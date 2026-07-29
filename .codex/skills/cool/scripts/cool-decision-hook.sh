#!/bin/bash
# cool-decision-hook.sh — PreToolUse hook for recommend-mode decision gates
#
# Matcher: AskUserQuestion. 仅 Claude Code 启用。
# 在 decision_mode=recommend 下，若 .cool.yaml 的 pending_decision 命中
# auto / auto-after-review(已 pass) → exit 2 阻止问询；block / agent-assess / 未 pass / 空 → exit 0 放行。
# agent-assess 档（context-compaction）允许询问——agent 自评决定是否问用户。
#
# Usage (called by harness, not directly):
#   PreToolUse matcher "AskUserQuestion" → this script
#   Stdin:  JSON  {"tool_name":"AskUserQuestion","tool_input":{...}}
#   Exit 0  = allow
#   Exit 2  = blocked (stderr message shown to user)

set -uo pipefail

# 复用 cool-state.sh 所在目录
COOL_STATE="${COOL_STATE:-}"
if [ -z "$COOL_STATE" ]; then
  # 自发现：与 hook 同目录的 cool-state.sh
  HOOK_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null || pwd)"
  if [ -f "$HOOK_DIR/cool-state.sh" ]; then
    COOL_STATE="$HOOK_DIR/cool-state.sh"
  fi
fi
COOL_BASH="${COOL_BASH:-${BASH:-bash}}"

# ── 解析 stdin JSON ──────────────────────────────────────────────

INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# 提取 tool_name
TOOL_NAME=$(printf '%s' "$INPUT" \
  | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
  | head -1 \
  | sed 's/^"tool_name"[[:space:]]*:[[:space:]]*"//' \
  | sed 's/"$//' \
  || true)

# 非 AskUserQuestion → 放行（本 hook 只拦决策点问询）
if [ "$TOOL_NAME" != "AskUserQuestion" ]; then
  exit 0
fi

# ── 找活跃 change ────────────────────────────────────────────────

YAML_FILE=""
if [ -d "openspec/changes" ]; then
  for dir in openspec/changes/*/; do
    [ -d "$dir" ] || continue
    case "$dir" in
      */archive/*) continue ;;
    esac
    if [ -f "${dir}.cool.yaml" ]; then
      YAML_FILE="${dir}.cool.yaml"
      break
    fi
  done
fi

# 无活跃 change → 放行
if [ -z "$YAML_FILE" ]; then
  exit 0
fi

# ── 读 decision_mode + pending_decision ──────────────────────────

yaml_field_local() {
  local field="$1"
  local file="$2"
  if [ -f "$file" ]; then
    local value
    value=$(grep "^${field}:" "$file" 2>/dev/null | sed "s/^${field}: *//" || true)
    # 去行内注释 + 去引号
    value=$(printf '%s' "$value" | sed 's/ *#.*$//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")
    printf '%s\n' "$value"
  fi
}

MODE=$(yaml_field_local "decision_mode" "$YAML_FILE")
[ -z "$MODE" ] && MODE="manual"

# 非 recommend → 放行（manual 模式所有点都问用户）
if [ "$MODE" != "recommend" ]; then
  exit 0
fi

PENDING=$(yaml_field_local "pending_decision" "$YAML_FILE")
# 空 / null → 放行（非 cool 决策点提问，如正常需求澄清）
if [ -z "$PENDING" ] || [ "$PENDING" = "null" ]; then
  exit 0
fi

# ── 调 cmd_decision 得档位 ───────────────────────────────────────

if [ -z "$COOL_STATE" ] || [ ! -f "$COOL_STATE" ]; then
  # 找不到 cool-state.sh → 保守放行（避免误拦）
  exit 0
fi

CHANGE_NAME=$(basename "$(dirname "$YAML_FILE")")
TIER=$("$COOL_BASH" "$COOL_STATE" decision "$CHANGE_NAME" "$PENDING" 2>/dev/null || true)

case "$TIER" in
  block)
    # 允许询问用户
    exit 0
    ;;
  agent-assess)
    # agent 自评决定是否询问；允许询问（不阻止）
    exit 0
    ;;
  auto)
    echo "[COOL-DECISION] blocked: point '$PENDING' is auto; do not ask, follow gate instruction." >&2
    exit 2
    ;;
  auto-after-review)
    # 查 review-log 最近一条 result
    LOG_FILE="openspec/changes/${CHANGE_NAME}/.cool/handoff/review-log.md"
    RESULT=""
    if [ -f "$LOG_FILE" ]; then
      RESULT=$(awk -v pt="$PENDING" '
        /^## [0-9]{4}-[0-9]{2}-[0-9]{2} / {
          split($0, a, " "); cur_pt=a[3]
          if (cur_pt == pt) { in_block=1; cur_result="" }
          else { in_block=0 }
          next
        }
        in_block && /^- 结果: / { cur_result=substr($0, index($0,":")+2) }
        END { print cur_result }
      ' "$LOG_FILE")
    fi
    case "$RESULT" in
      pass|minor)
        echo "[COOL-DECISION] blocked: point '$PENDING' auto-after-review passed; do not ask, follow gate instruction." >&2
        exit 2
        ;;
      *)
        # 未复核 / material / escalated → 允许问（需先复核或升级用户）
        exit 0
        ;;
    esac
    ;;
  *)
    # 未知档位 → 保守放行
    exit 0
    ;;
esac
