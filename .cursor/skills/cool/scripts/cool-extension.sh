#!/bin/bash
# Cool Extension Runner — executes phase-boundary hooks declared in .cool/config.yaml
# Usage:
#   cool-extension.sh run <change> <phase> <slot>   # slot: pre|post
#   cool-extension.sh validate <change>
# Exit 0 = all pass/warn/no-op; exit 1 = block-level failure (or invalid config)
set -euo pipefail

COOL_BASH="${COOL_BASH:-${BASH:-bash}}"

red()    { echo -e "\033[31m$1\033[0m" >&2; }
green()  { echo -e "\033[32m$1\033[0m" >&2; }
warn()   { echo -e "\033[33m$1\033[0m" >&2; }

validate_change_name() {
  local name="$1"
  if [ -z "$name" ]; then
    red "ERROR: Change name cannot be empty" >&2; exit 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    red "ERROR: Invalid change name: '$name'" >&2; exit 1
  fi
  if [[ "$name" =~ \.\. ]]; then
    red "ERROR: Change name cannot contain '..'" >&2; exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
PROJECT_DIR="$(pwd -P)"

# strip_inline_comment / strip_wrapping_quotes 复用 guard 风格
strip_inline_comment() {
  local value="$1"
  printf '%s\n' "$value" | awk -v squote="'" '
    {
      out = ""; quote = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (quote == "") {
          if (c == "\"" || c == squote) { quote = c }
          else if (c == "#" && (i == 1 || substr($0, i - 1, 1) ~ /[[:space:]]/)) {
            sub(/[[:space:]]+$/, "", out); print out; next
          }
        } else if (c == quote) { quote = "" }
        out = out c
      }
      print out
    }
  '
}

strip_wrapping_quotes() {
  local value="$1"
  case "$value" in
    \"*\") printf '%s\n' "${value:1:${#value}-2}" ;;
    \'*\") printf '%s\n' "${value:1:${#value}-2}" ;;
    *)    printf '%s\n' "$value" ;;
  esac
}

# escape_json_str — 转义 \ 和 "，保证字符串可安全嵌入 JSON 字符串字面量
# 用于 stdin JSON 的所有字符串字段（command/change_dir/project_dir/cool_yaml 值等），
# 与 args 的转义保持一致，避免字段含引号/反斜杠时 JSON 畸形。
escape_json_str() {
  local s="$1"
  s="${s//\\/\\\\}"   # \ → \\
  s="${s//\"/\\\"}"   # " → \"
  printf '%s' "$s"
}

# load_extensions_config <change>
# 回声一行 "enabled|default-timeout|default-on-failure"（无配置 → "false|30|warn"）
# 返回 0 总是（无配置 = no-op，不报错）
# 用 awk 限定 extensions 节边界，避免误读其他节的 enabled/timeout/on-failure（W1）。
load_extensions_config() {
  local change="$1"
  local cfg=".cool/config.yaml"
  local enabled="false" dtimeout="30" dfail="warn"
  if [ -f "$cfg" ] && grep -q "^extensions:" "$cfg" 2>/dev/null; then
    local ext_section
    ext_section=$(awk '
      /^extensions:[[:space:]]*$/ { in_ext=1; next }
      in_ext && /^[^[:space:]]/ { in_ext=0 }
      in_ext { print }
    ' "$cfg" 2>/dev/null || true)
    local val
    val=$(printf '%s\n' "$ext_section" | grep "^  enabled:" | sed 's/^  enabled: *//' || true)
    val=$(strip_inline_comment "$val"); val=$(strip_wrapping_quotes "$val")
    [ -n "$val" ] && [ "$val" != "null" ] && enabled="$val"
    val=$(printf '%s\n' "$ext_section" | grep "^  default-timeout:" | sed 's/^  default-timeout: *//' || true)
    val=$(strip_inline_comment "$val"); val=$(strip_wrapping_quotes "$val")
    [ -n "$val" ] && [ "$val" != "null" ] && dtimeout="$val"
    val=$(printf '%s\n' "$ext_section" | grep "^  default-on-failure:" | sed 's/^  default-on-failure: *//' || true)
    val=$(strip_inline_comment "$val"); val=$(strip_wrapping_quotes "$val")
    [ -n "$val" ] && [ "$val" != "null" ] && dfail="$val"
  fi
  printf '%s|%s|%s\n' "$enabled" "$dtimeout" "$dfail"
}

# 占位：后续 Task 填充
# hook_field <line> <fieldnum>（1-based）— 用 awk -F'\t' 拆分，保留空字段
# （bash `read` 用 tab 作 IFS 会折叠连续 tab，吞掉空 args 字段，故用 awk）
hook_field() {
  printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'
}

# parse_hooks_section <file> <phase> <slot>
# 输出匹配记录，每行: command \t args \t on-failure \t timeout \t env
# args 为逗号分隔原始串（占位符未替换）；timeout 空=用默认
# env 为 inline 格式 KEY=val;KEY=val（空=无额外 env）
# 缩进无关：靠 `extensions:` 节边界 + `- phase:` 项标记 + 字段名识别。
parse_hooks_section() {
  local file="$1" phase="$2" slot="$3"
  [ -f "$file" ] || return 0
  awk -v want_phase="$phase" -v want_slot="$slot" '
    function flush() {
      if (in_hook && cur_phase == want_phase && cur_slot == want_slot) {
        printf "%s\t%s\t%s\t%s\t%s\n", cur_command, cur_args, cur_onfail, cur_timeout, cur_env
      }
      in_hook=0; cur_phase=""; cur_slot=""; cur_command=""; cur_args=""; cur_onfail=""; cur_timeout=""; cur_env=""
    }
    function fieldval(line) {
      v = substr(line, index(line, ":") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub(/["'\'']/, "", v)
      return v
    }
    /^extensions:[[:space:]]*$/ { in_ext=1; next }
    in_ext && /^[^[:space:]]/ { flush(); in_ext=0; next }
    in_ext && /^[[:space:]]*#/ { next }
    in_ext && /^[[:space:]]+-[[:space:]]*phase:/ {
      flush(); in_hook=1
      cur_phase=fieldval($0); next
    }
    in_hook && /^[[:space:]]+slot:/        { cur_slot=fieldval($0); next }
    in_hook && /^[[:space:]]+command:/     { cur_command=fieldval($0); next }
    in_hook && /^[[:space:]]+args:/ {
      cur_args=fieldval($0)
      sub(/^\[/, "", cur_args); sub(/\][[:space:]]*$/, "", cur_args)
      next
    }
    in_hook && /^[[:space:]]+on-failure:/  { cur_onfail=fieldval($0); next }
    in_hook && /^[[:space:]]+timeout:/     { cur_timeout=fieldval($0); next }
    in_hook && /^[[:space:]]+env:/         { cur_env=fieldval($0); next }
    END { flush() }
  ' "$file"
}
substitute_placeholders() {
  local s="$1" change="$2" phase="$3" slot="$4"
  local change_dir project_dir
  project_dir="$(pwd -P)"
  # {change-dir} 始终为绝对路径（目录不存在时也基于 project_dir 推导）
  if [ -d "openspec/changes/$change" ]; then
    change_dir="$(cd "openspec/changes/$change" && pwd -P)"
  else
    change_dir="$project_dir/openspec/changes/$change"
  fi
  s="${s//\{change\}/$change}"
  s="${s//\{phase\}/$phase}"
  s="${s//\{slot\}/$slot}"
  s="${s//\{change-dir\}/$change_dir}"
  s="${s//\{project-dir\}/$project_dir}"
  printf '%s' "$s"
}
# cool_timeout <secs> <cmd> <args...>
# 超时 → return 124；否则透传子进程退出码。macOS 无 timeout 命令，自实现。
# 直接后台子进程 + kill -0 轮询，避免 watcher subshell 的 pid 竞态。
cool_timeout() {
  local secs="$1"; shift
  if ! [[ "$secs" =~ ^[0-9]+$ ]] || [ "$secs" -le 0 ] 2>/dev/null; then secs=30; fi
  "$@" &
  local pid=$!
  local elapsed=0
  while [ "$elapsed" -lt "$secs" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if wait "$pid"; then return 0; else return $?; fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  # 超时：TERM → 等 1s → KILL
  kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 124
}

# build_cool_yaml_json <change>
# 透传 .cool.yaml 关键字段为 JSON 对象（design §5.1 cool_yaml 契约，C2）。
# 字段值经 escape_json_str 转义，保证 JSON 合法。字段缺失 → "null"。
build_cool_yaml_json() {
  local change="$1"
  local yf="openspec/changes/$change/.cool.yaml"
  [ -f "$yf" ] || { printf '{}'; return; }
  local k v pairs="" first=1
  for k in workflow phase review_mode verify_mode build_mode isolation context_compression auto_transition decision_mode; do
    v=$(grep "^$k:" "$yf" 2>/dev/null | head -1 | sed "s/^$k: *//")
    v=$(strip_inline_comment "$v"); v=$(strip_wrapping_quotes "$v")
    [ -z "$v" ] && v="null"
    v=$(escape_json_str "$v")
    [ "$first" -eq 1 ] || pairs+=","
    pairs+="\"$k\":\"$v\""
    first=0
  done
  printf '{%s}' "$pairs"
}

# run_hook <change> <phase> <slot> <index> <command> <args> <on-failure> <timeout> <env> <prev_out>
# 返回 hook 退出码（124=超时）。落盘 stdout JSON 与 stderr 日志（均含 index，W4）。
# 数组执行（禁 eval）防注入。env（KEY=val;KEY=val）导出给子进程（C3）。
# prev_out 为上一个 hook 的 stdout 路径，通过 COOL_PREV_HOOK_OUTPUT 传递（C4 inter-hook）。
run_hook() {
  local change="$1" phase="$2" slot="$3" index="$4"
  local command="$5" args_raw="$6" onfail="$7" timeout="$8" env_raw="${9:-}" prev_out="${10:-}"

  local change_dir project_dir
  project_dir="$(pwd -P)"
  if [ -d "openspec/changes/$change" ]; then
    change_dir="$(cd "openspec/changes/$change" && pwd -P)"
  else
    change_dir="$project_dir/openspec/changes/$change"
  fi

  # 解析 args（逗号分隔）+ 占位符替换 → 数组
  local args_array=()
  if [ -n "$args_raw" ]; then
    local raw_parts
    IFS=',' read -r -a raw_parts <<< "$args_raw"
    unset IFS
    local part
    for part in "${raw_parts[@]}"; do
      part="${part# }"; part="${part% }"
      args_array+=("$(substitute_placeholders "$part" "$change" "$phase" "$slot")")
    done
  fi

  # 解析 command（路径 or PATH）。含 / 的路径校验存在性 + 可执行性（W6 健壮性）。
  local resolved_cmd
  if [[ "$command" == */* ]]; then
    if [ ! -f "$command" ]; then
      red "hook $phase/$slot[$index]: command file not found: $command"
      return 1
    fi
    if [ ! -x "$command" ]; then
      red "hook $phase/$slot[$index]: command not executable: $command"
      return 1
    fi
    resolved_cmd="$command"
  else
    resolved_cmd="$(command -v "$command" 2>/dev/null || true)"
    if [ -z "$resolved_cmd" ]; then
      red "hook $phase/$slot[$index]: command not found: $command"
      return 1
    fi
  fi

  mkdir -p .cool/extensions
  local log=".cool/extensions/${phase}-${slot}-${index}.log"
  local out=".cool/extensions/${phase}-${slot}-${index}.json"

  # 解析 env（KEY=val;KEY=val）→ 导出给子进程；记录 key 以便事后 unset（C3）
  local env_keys=()
  if [ -n "$env_raw" ]; then
    local ep
    IFS=';' read -r -a env_parts <<< "$env_raw"
    unset IFS
    for ep in "${env_parts[@]}"; do
      [ -z "$ep" ] && continue
      local ek="${ep%%=*}"
      local ev="${ep#*=}"
      if [ -n "$ek" ] && [[ "$ek" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        export "$ek=$ev"
        env_keys+=("$ek")
      fi
    done
  fi

  # stdin JSON 构造：所有字符串字段经 escape_json_str 转义（C1）；含 cool_yaml（C2）。
  local args_json="" ai escaped
  for ((ai=0; ai<${#args_array[@]}; ai++)); do
    [ "$ai" -gt 0 ] && args_json+='","'
    escaped="${args_array[$ai]//\\/\\\\}"   # \ → \\
    escaped="${escaped//\"/\\\"}"           # " → \"
    args_json+="$escaped"
  done

  local cool_yaml
  cool_yaml=$(build_cool_yaml_json "$change")

  local stdin_json
  stdin_json=$(printf '{"change":"%s","phase":"%s","slot":"%s","change_dir":"%s","project_dir":"%s","cool_yaml":%s,"hook":{"command":"%s","args":["%s"],"on-failure":"%s","timeout":%s,"index":%s}}' \
    "$(escape_json_str "$change")" "$(escape_json_str "$phase")" "$(escape_json_str "$slot")" \
    "$(escape_json_str "$change_dir")" "$(escape_json_str "$project_dir")" \
    "$cool_yaml" \
    "$(escape_json_str "$command")" "$args_json" "$(escape_json_str "${onfail:-warn}")" \
    "${timeout:-30}" "$index")

  # env + 数组执行（禁 eval）。用 cmd_array 始终含 resolved_cmd，避免 bash 3.2 set -u 空数组报错。
  local cmd_array=("$resolved_cmd")
  if [ "${#args_array[@]}" -gt 0 ]; then
    cmd_array+=("${args_array[@]}")
  fi
  local rc=0
  COOL_CHANGE="$change" COOL_PHASE="$phase" COOL_PHASE_SLOT="$slot" \
  COOL_CHANGE_DIR="$change_dir" COOL_PROJECT_DIR="$project_dir" COOL_HOOK_INDEX="$index" \
  COOL_PREV_HOOK_OUTPUT="$prev_out" \
  cool_timeout "$timeout" "${cmd_array[@]}" \
    < <(printf '%s' "$stdin_json") >"$out.tmp" 2>>"$log" || rc=$?

  # 清理本次导出的 env，避免污染同进程后续 hook
  local ek
  for ek in "${env_keys[@]:-}"; do [ -n "$ek" ] && unset "$ek"; done

  if [ "$rc" -eq 0 ] && [ -s "$out.tmp" ]; then
    mv "$out.tmp" "$out"
  else
    rm -f "$out.tmp"
  fi
  return "$rc"
}
# run_hook_chain <change> <phase> <slot>
# 返回 0=全 pass/warn；1=有 block 级失败。用 hook_field 拆字段（避免 tab 折叠）。
# 维护 prev_out（上一个 hook 的 stdout 路径）传给下一个 hook（C4 inter-hook 传递）。
run_hook_chain() {
  local change="$1" phase="$2" slot="$3"
  local cfg
  cfg=$(load_extensions_config "$change")
  local enabled dtimeout dfail rest
  enabled="${cfg%%|*}"; rest="${cfg#*|}"
  dtimeout="${rest%%|*}"; dfail="${rest#*|}"
  [ "$enabled" = "true" ] || return 0

  local idx=0 line command args onfail timeout henv rc prev_out=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    command=$(hook_field "$line" 1)
    args=$(hook_field "$line" 2)
    onfail=$(hook_field "$line" 3)
    timeout=$(hook_field "$line" 4)
    henv=$(hook_field "$line" 5)
    [ -z "$command" ] && continue
    [ -z "$onfail" ] && onfail="$dfail"
    [ -z "$timeout" ] && timeout="$dtimeout"
    rc=0
    run_hook "$change" "$phase" "$slot" "$idx" "$command" "$args" "$onfail" "$timeout" "$henv" "$prev_out" || rc=$?
    # 记录本次 hook 的 stdout 路径，供下一个 hook 读取
    local out_file=".cool/extensions/${phase}-${slot}-${idx}.json"
    if [ "$rc" -eq 0 ] && [ -s "$out_file" ]; then
      prev_out="$out_file"
    else
      prev_out=""
    fi
    if [ "$rc" -ne 0 ]; then
      if [ "$onfail" = "block" ]; then
        red "hook $phase/$slot[$idx] BLOCKED (exit $rc): $command (log: .cool/extensions/${phase}-${slot}-${idx}.log)"
        return 1
      else
        warn "hook $phase/$slot[$idx] warn (exit $rc): $command (log: .cool/extensions/${phase}-${slot}-${idx}.log)"
      fi
    fi
    idx=$((idx + 1))
  done < <(parse_hooks_section ".cool/config.yaml" "$phase" "$slot")
  return 0
}

cmd_run() {
  local change="$1" phase="$2" slot="$3"
  validate_change_name "$change"
  case "$phase" in open|design|build|review|verify|archive) ;; *)
    red "ERROR: invalid phase '$phase'"; exit 1 ;; esac
  case "$slot" in pre|post) ;; *)
    red "ERROR: invalid slot '$slot'"; exit 1 ;; esac

  local cfg
  cfg=$(load_extensions_config "$change")
  local enabled="${cfg%%|*}"
  if [ "$enabled" != "true" ]; then
    exit 0
  fi
  if run_hook_chain "$change" "$phase" "$slot"; then
    exit 0
  else
    exit 1
  fi
}

cmd_validate() {
  local change="$1"
  validate_change_name "$change"
  local cfg=".cool/config.yaml"
  if [ ! -f "$cfg" ] || ! grep -q "^extensions:" "$cfg" 2>/dev/null; then
    green "extensions: no config (no-op)"
    exit 0
  fi
  local errors=0
  local ext_section
  ext_section=$(awk '
    /^extensions:[[:space:]]*$/ { in_ext=1; next }
    in_ext && /^[^[:space:]]/ { in_ext=0 }
    in_ext { print }
  ' "$cfg" 2>/dev/null || true)
  local enabled dtimeout dfail
  enabled=$(printf '%s\n' "$ext_section" | grep "^  enabled:" | sed 's/^  enabled: *//' || true)
  enabled=$(strip_inline_comment "$enabled"); enabled=$(strip_wrapping_quotes "$enabled")
  case "$enabled" in true|false|"") ;; *) red "extensions.enabled '$enabled' must be true|false"; errors=$((errors+1)) ;; esac
  dtimeout=$(printf '%s\n' "$ext_section" | grep "^  default-timeout:" | sed 's/^  default-timeout: *//' || true)
  dtimeout=$(strip_inline_comment "$dtimeout"); dtimeout=$(strip_wrapping_quotes "$dtimeout")
  if [ -n "$dtimeout" ] && [ "$dtimeout" != "null" ]; then
    if ! { [[ "$dtimeout" =~ ^[0-9]+$ ]] && [ "$dtimeout" -gt 0 ]; }; then
      red "default-timeout must be positive int: '$dtimeout'"; errors=$((errors+1))
    fi
  fi
  dfail=$(printf '%s\n' "$ext_section" | grep "^  default-on-failure:" | sed 's/^  default-on-failure: *//' || true)
  dfail=$(strip_inline_comment "$dfail"); dfail=$(strip_wrapping_quotes "$dfail")
  case "$dfail" in block|warn|"") ;; *) red "default-on-failure '$dfail' must be block|warn"; errors=$((errors+1)) ;; esac

  # 逐 hook 记录校验（process substitution 避免 subshell 计数丢失）
  local all_phases="open design build review verify archive"
  local phase slot line hcmd honfail hto henv
  for phase in $all_phases; do
    for slot in pre post; do
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        hcmd=$(hook_field "$line" 1)
        honfail=$(hook_field "$line" 3)
        hto=$(hook_field "$line" 4)
        henv=$(hook_field "$line" 5)
        [ -z "$hcmd" ] && { red "hook $phase/$slot missing command"; errors=$((errors+1)); continue; }
        case "$honfail" in block|warn|"") ;; *) red "hook $phase/$slot on-failure '$honfail' must be block|warn"; errors=$((errors+1)) ;; esac
        if [ -n "$hto" ]; then
          if ! { [[ "$hto" =~ ^[0-9]+$ ]] && [ "$hto" -gt 0 ]; }; then
            red "hook $phase/$slot timeout must be positive int: '$hto'"; errors=$((errors+1))
          fi
        fi
        # env 格式校验：KEY=val;KEY=val（KEY 须为合法 env 变量名）
        if [ -n "$henv" ]; then
          local ep
          IFS=';' read -r -a _env_parts <<< "$henv"
          unset IFS
          for ep in "${_env_parts[@]}"; do
            [ -z "$ep" ] && continue
            local ek="${ep%%=*}"
            if ! [[ "$ek" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
              red "hook $phase/$slot env key '$ek' invalid (must be [A-Za-z_][A-Za-z0-9_]*)"; errors=$((errors+1))
            fi
          done
        fi
      done < <(parse_hooks_section "$cfg" "$phase" "$slot")
    done
  done

  if [ "$errors" -gt 0 ]; then
    red "extensions validation FAILED ($errors error(s))"
    exit 1
  fi
  green "extensions validation PASSED"
  exit 0
}

if [ "${COOL_EXTENSION_SOURCE_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null
  red "ERROR: COOL_EXTENSION_SOURCE_ONLY=1 is only for sourcing" >&2; exit 1
fi

case "${1:-}" in
  run)      shift; cmd_run "$@" ;;
  validate) shift; cmd_validate "$@" ;;
  *)
    red "Usage: cool-extension.sh run <change> <phase> <slot>|validate <change>"
    exit 1 ;;
esac
