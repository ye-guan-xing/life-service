#!/bin/bash
# cool-hook-guard.sh — PreToolUse hook for Cool phase enforcement
#
# Blocks file writes (Write/Edit) when the active Cool change is in
# a phase that does not allow source code modifications (open/design/archive).
#
# Usage (called by harness, not directly):
#   PreToolUse matcher "Write|Edit" → this script
#   Stdin:  JSON  {"tool_name":"Write|Edit","tool_input":{"file_path":"..."}}
#   Exit 0  = allow
#   Exit 2  = blocked (stderr message shown to user)
#
# Cross-platform: macOS / Linux / Windows Git Bash
# shellcheck disable=SC2329

set -euo pipefail

# ── Extract target file path ──────────────────────────────────────

TARGET=""

# Method 1: FILE_PATH environment variable (set by some harnesses)
if [ -n "${FILE_PATH:-}" ]; then
  TARGET="$FILE_PATH"
fi

# Method 2: Parse stdin JSON
if [ -z "$TARGET" ]; then
  INPUT=""
  if [ ! -t 0 ]; then
    INPUT=$(cat 2>/dev/null || true)
  fi
  if [ -n "$INPUT" ]; then
    # Extract file_path value — works for both Write and Edit tool inputs
    TARGET=$(printf '%s' "$INPUT" \
      | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
      | head -1 \
      | sed 's/^"file_path"[[:space:]]*:[[:space:]]*"//' \
      | sed 's/"$//' \
      || true)
  fi
fi

# No target found — allow (not a file-path-bearing operation)
if [ -z "$TARGET" ]; then
  echo "[COOL-HOOK] allowed: no file path in tool input" >&2
  exit 0
fi

# Normalize to forward slashes, collapse doubles from JSON escaping (\\ → //)
TARGET=$(printf '%s' "$TARGET" | sed 's|\\|/|g' | sed 's|///*|/|g')

# ── Find active Cool change ──────────────────────────────────────

YAML_FILE=""
if [ -d "openspec/changes" ]; then
  for dir in openspec/changes/*/; do
    [ -d "$dir" ] || continue
    # Skip archived changes
    case "$dir" in
      */archive/*) continue ;;
    esac
    if [ -f "${dir}.cool.yaml" ]; then
      YAML_FILE="${dir}.cool.yaml"
      break
    fi
  done
fi

# No active change — allow all writes
if [ -z "$YAML_FILE" ]; then
  echo "[COOL-HOOK] allowed: no active cool change" >&2
  exit 0
fi

# ── Read current phase ───────────────────────────────────────────

PHASE=$(grep "^phase:" "$YAML_FILE" 2>/dev/null \
  | awk '{print $2}' \
  | tr -d '[:space:][:cntrl:]' \
  || true)

if [ -z "$PHASE" ]; then
  echo "[COOL-HOOK] allowed: no phase in .cool.yaml" >&2
  exit 0
fi

# ── Resolve to project-relative path ─────────────────────────────

# Normalize helper: forward slashes only
norm() { printf '%s' "$1" | sed 's|\\|/|g'; }

RELPATH=$(norm "$TARGET")

# If already relative, use as-is
case "$RELPATH" in
  /*|[A-Za-z]:/*)
    # Absolute — try stripping CWD prefixes
    CWD_UNIX=$(norm "$(pwd)")
    CWD_PHYS=$(norm "$(pwd -P 2>/dev/null || pwd)")

    # Try: TARGET as-is vs CWD logical
    if [ "${RELPATH#"$CWD_UNIX"/}" != "$RELPATH" ]; then
      RELPATH="${RELPATH#"$CWD_UNIX"/}"
    # Try: TARGET as-is vs CWD physical (macOS /var → /private/var)
    elif [ "${RELPATH#"$CWD_PHYS"/}" != "$RELPATH" ]; then
      RELPATH="${RELPATH#"$CWD_PHYS"/}"
    else
      # Resolve TARGET's parent through filesystem (handles symlinked TARGET path)
      _PDIR=$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd -P 2>/dev/null || true)
      if [ -n "$_PDIR" ]; then
        _TRESOLVED=$(norm "${_PDIR}/$(basename "$TARGET")")
        if [ "${_TRESOLVED#"$CWD_UNIX"/}" != "$_TRESOLVED" ]; then
          RELPATH="${_TRESOLVED#"$CWD_UNIX"/}"
        elif [ "${_TRESOLVED#"$CWD_PHYS"/}" != "$_TRESOLVED" ]; then
          RELPATH="${_TRESOLVED#"$CWD_PHYS"/}"
        fi
      fi
    fi
    ;;
esac

# ── Whitelist: phase-aware allowed paths ─────────────────────────

case "$RELPATH" in
  openspec/*)
    # OpenSpec artifacts — phase-aware sub-check
    case "$PHASE" in
      open)
        # 状态/配置/规格文件：无条件放行（非产物）
        case "$RELPATH" in
          */.openspec.yaml|*/.cool.yaml|*/.cool/*|*/specs/*)
            echo "[COOL-HOOK] allowed: $RELPATH (phase: open, openspec state/spec)" >&2
            exit 0
            ;;
        esac
        # 产物三件套：写前校验（clarify-review pass + 产物顺序链）
        case "$RELPATH" in
          */proposal.md|*/design.md|*/tasks.md)
            # CHANGE_NAME 优先从被写目标 RELPATH 解析（多 change 健壮性），
            # 回退到 YAML_FILE（openspec/changes/<name>/.cool.yaml）
            CHANGE_NAME=$(printf '%s' "$RELPATH" \
              | sed -n 's|^openspec/changes/\([^/]*\)/.*|\1|p')
            [ -n "$CHANGE_NAME" ] || CHANGE_NAME=$(basename "$(dirname "$YAML_FILE")")
            LOG_FILE="openspec/changes/${CHANGE_NAME}/.cool/handoff/review-log.md"
            # 1. 校验 clarify-review pass 记录
            #    review-log 是多行块格式（cool-state.sh 写入）：
            #      ## <date> clarify-review (review:...) round: N
            #      - 结果: pass
            #    grep 行级匹配无法跨行，改用 awk 取最近 clarify-review 块的 result。
            #    pass|minor 均算通过（与 cool-decision-hook.sh auto-after-review 语义对齐）。
            REVIEW_RESULT=$(awk -v pt="clarify-review" '
              /^## [0-9]{4}-[0-9]{2}-[0-9]{2} / {
                split($0, a, " "); cur_pt=a[3]
                if (cur_pt == pt) { in_block=1; cur_result="" }
                else { in_block=0 }
                next
              }
              in_block && /^- 结果: / { cur_result=substr($0, index($0,":")+2) }
              END { print cur_result }
            ' "$LOG_FILE" 2>/dev/null || true)
            case "$REVIEW_RESULT" in
              pass|minor) ;;
              *)
                echo "" >&2
                echo "╔══════════════════════════════════════════╗" >&2
                echo "║   COOL OPEN PRE-WRITE GUARD — BLOCKED    ║" >&2
                echo "╚══════════════════════════════════════════╝" >&2
                echo "  目标: $RELPATH" >&2
                echo "  ❌ 未通过 clarify-review，禁止写 open 产物" >&2
                echo "  💡 先完成需求澄清并取得 clarify-review pass" >&2
                exit 2
                ;;
            esac
            # 2. 链式产物顺序校验（design 需 proposal 存在 / tasks 需 design 存在）
            case "$RELPATH" in
              */design.md|*/tasks.md)
                [ -f "openspec/changes/${CHANGE_NAME}/proposal.md" ] || {
                  echo "[COOL-HOOK] blocked: $RELPATH — proposal.md missing" >&2
                  exit 2
                } ;;
            esac
            case "$RELPATH" in
              */tasks.md)
                [ -f "openspec/changes/${CHANGE_NAME}/design.md" ] || {
                  echo "[COOL-HOOK] blocked: $RELPATH — design.md missing" >&2
                  exit 2
                } ;;
            esac
            echo "[COOL-HOOK] allowed: $RELPATH (phase: open, post-clarify)" >&2
            exit 0 ;;
        esac
        ;;
      design)
        # design: allow handoff, delta spec (Spec Patch), proposal/design/tasks (minor refinements), .cool.yaml
        case "$RELPATH" in
          */proposal.md|*/design.md|*/tasks.md|*/.cool/*|*/specs/*|*/.cool.yaml|*/.openspec.yaml)
            echo "[COOL-HOOK] allowed: $RELPATH (phase: design, handoff/spec)" >&2
            exit 0
            ;;
        esac
        ;;
      build)
        # build: allow delta spec (incremental update), tasks, .cool.yaml
        case "$RELPATH" in
          */specs/*|*/tasks.md|*/.cool.yaml|*/.openspec.yaml)
            echo "[COOL-HOOK] allowed: $RELPATH (phase: build, spec/tasks)" >&2
            exit 0
            ;;
        esac
        ;;
      review)
        # review: 允许写入审查报告和状态文件
        case "$RELPATH" in
          */review-report.md|*/.cool.yaml|*/.openspec.yaml)
            echo "[COOL-HOOK] allowed: $RELPATH (phase: review, review artifacts)" >&2
            exit 0
            ;;
        esac
        ;;
      verify)
        # verify: allow tasks (post-check), .cool.yaml
        case "$RELPATH" in
          */tasks.md|*/.cool.yaml|*/.openspec.yaml)
            echo "[COOL-HOOK] allowed: $RELPATH (phase: verify, tasks/state)" >&2
            exit 0
            ;;
        esac
        ;;
      archive)
        # archive: allow .cool.yaml state updates only
        case "$RELPATH" in
          */.cool.yaml|*/.openspec.yaml)
            echo "[COOL-HOOK] allowed: $RELPATH (phase: archive, state)" >&2
            exit 0
            ;;
        esac
        ;;
    esac
    ;;
  docs/superpowers/*)
    # Superpowers artifacts — phase-aware sub-check
    case "$PHASE" in
      design)
        echo "[COOL-HOOK] allowed: $RELPATH (phase: design, superpowers)" >&2
        exit 0
        ;;
      build)
        echo "[COOL-HOOK] allowed: $RELPATH (phase: build, superpowers)" >&2
        exit 0
        ;;
      verify)
        echo "[COOL-HOOK] allowed: $RELPATH (phase: verify, superpowers)" >&2
        exit 0
        ;;
    esac
    # open/archive: block docs/superpowers writes
    ;;
  .superpowers/*|*/.superpowers/*)
    # Superpowers runtime workspace (SDD progress/diffs, debug reports) — not source code.
    # design: brainstorming; review: systematic-debugging / code review.
    # build/verify already permit all writes; open/archive remain blocked.
    case "$PHASE" in
      design|review)
        echo "[COOL-HOOK] allowed: $RELPATH (phase: $PHASE, superpowers workspace)" >&2
        exit 0
        ;;
    esac
    ;;
  .cool/*|*/.cool/*)
    # Cool config
    echo "[COOL-HOOK] allowed: $RELPATH (whitelist: cool config)" >&2
    exit 0
    ;;
  .claude/*)
    # Claude settings/rules
    echo "[COOL-HOOK] allowed: $RELPATH (whitelist: claude config)" >&2
    exit 0
    ;;
  CLAUDE.md|CHANGELOG.md|README.md|*.md)
    # Root-level markdown files
    case "$RELPATH" in
      */*) ;; # subdirectory .md — NOT whitelisted, fall through
      *)
        echo "[COOL-HOOK] allowed: $RELPATH (whitelist: root markdown)" >&2
        exit 0
        ;;
    esac
    ;;
  .cool.yaml|cool.yaml|.cool.yml|cool.yml)
    # Project-level cool config
    echo "[COOL-HOOK] allowed: $RELPATH (whitelist: cool config)" >&2
    exit 0
    ;;
esac

# ── Phase-based enforcement ──────────────────────────────────────

case "$PHASE" in
  build|verify)
    # Code writes allowed in build and verify
    echo "[COOL-HOOK] allowed: $RELPATH (phase: $PHASE)" >&2
    exit 0
    ;;
  open|design|review|archive)
    echo "" >&2
    echo "╔══════════════════════════════════════════╗" >&2
    echo "║      COOL PHASE GUARD — WRITE BLOCKED    ║" >&2
    echo "╚══════════════════════════════════════════╝" >&2
    echo "" >&2
    echo "  当前阶段: $PHASE" >&2
    echo "  目标文件: $RELPATH" >&2
    echo "" >&2
    case "$PHASE" in
      open)
        echo "  ❌ open 阶段不允许写源代码" >&2
        echo "  ✅ 允许: 创建 proposal/design/tasks, 运行 guard" >&2
        echo "  💡 完成需求澄清和 artifact 创建后运行 guard --apply" >&2
        ;;
      design)
        echo "  ❌ design 阶段不允许写源代码" >&2
        echo "  ✅ 允许: brainstorming, 创建 Design Doc, 运行 guard" >&2
        echo "  💡 完成 Design Doc 后运行 cool-guard design --apply 进入 build" >&2
        ;;
      review)
        echo "  ❌ review 阶段不允许写源代码" >&2
        echo "  ✅ 允许: 写 review-report.md, 运行 guard" >&2
        echo "  💡 完成代码审查后运行 cool-guard review --apply 进入 verify" >&2
        ;;
      archive)
        echo "  ❌ archive 阶段不允许写源代码" >&2
        echo "  ✅ 允许: 确认归档, 运行归档脚本" >&2
        ;;
    esac
    echo "" >&2
    exit 2
    ;;
esac

echo "[COOL-HOOK] allowed: $RELPATH (phase: $PHASE)" >&2
exit 0
