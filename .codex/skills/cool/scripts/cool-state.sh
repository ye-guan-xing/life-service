#!/bin/bash
# Cool State — unified interface for .cool.yaml state management
# Usage: cool-state.sh <subcommand> <change-name> [args...]
#
# Subcommands:
#   init <change-name> <workflow>  — Initialize .cool.yaml with workflow defaults
#   get <change-name> <field>       — Read a field value from .cool.yaml
#   set <change-name> <field> <val> — Update a field value
#   transition <change-name> <event> — Apply a validated state transition
#   check <change-name> <phase>    — Verify entry requirements for a phase
#   check <change-name> <phase> --recover — Output structured recovery context for compaction resume
#   scale <change-name>             — Assess and set verification mode based on metrics
#
# Workflows: full, hotfix, tweak
# Phases for check: open, design, build, review, verify, archive

set -euo pipefail

# --- Color output helpers ---

red() { echo -e "\033[31m$1\033[0m" >&2; }
green() { echo -e "\033[32m$1\033[0m" >&2; }
yellow() { echo -e "\033[33m$1\033[0m" >&2; }

# --- Script location ---

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Input validation ---

validate_change_name() {
  local name="$1"
  # Reject empty names
  if [ -z "$name" ]; then
    red "ERROR: Change name cannot be empty" >&2
    exit 1
  fi
  # Only allow alphanumeric, hyphens, and underscores
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    red "ERROR: Invalid change name: '$name'" >&2
    red "Valid characters: a-z, A-Z, 0-9, -, _" >&2
    exit 1
  fi
  # Reject path traversal attempts
  if [[ "$name" =~ \.\. ]]; then
    red "ERROR: Change name cannot contain '..' (path traversal not allowed)" >&2
    exit 1
  fi
}

validate_enum() {
  local value="$1"
  shift
  local valid_values=("$@")

  for valid in "${valid_values[@]}"; do
    if [ "$value" = "$valid" ]; then
      return 0
    fi
  done

  red "ERROR: Invalid value: '$value'" >&2
  red "Valid values: ${valid_values[*]}" >&2
  exit 1
}

validate_path_field() {
  local value="$1"
  local field="$2"
  # null and empty are acceptable (means "not set")
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    return 0
  fi
  # Reject absolute paths and home-directory references
  case "$value" in
    /*|~*|[A-Za-z]:*|\\*)
      red "ERROR: $field must be a relative path within the repo: '$value'" >&2
      exit 1
      ;;
  esac
  if [[ "$value" =~ \.\. ]]; then
    red "ERROR: $field cannot contain '..' (path traversal not allowed): '$value'" >&2
    exit 1
  fi
}

# --- Helper functions ---

yaml_field() {
  local field="$1"
  local yaml_file="$2"
  if [ -f "$yaml_file" ]; then
    local value
    value=$(grep "^${field}:" "$yaml_file" 2>/dev/null | sed "s/^${field}: *//" || true)
    value=$(strip_inline_comment "$value")
    strip_wrapping_quotes "$value"
  fi
}

strip_inline_comment() {
  local value="$1"
  printf '%s\n' "$value" | awk -v squote="'" '
    {
      out = ""
      quote = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (quote == "") {
          if (c == "\"" || c == squote) {
            quote = c
          } else if (c == "#" && (i == 1 || substr($0, i - 1, 1) ~ /[[:space:]]/)) {
            sub(/[[:space:]]+$/, "", out)
            print out
            next
          }
        } else if (c == quote) {
          quote = ""
        }
        out = out c
      }
      print out
    }
  '
}

strip_wrapping_quotes() {
  local value="$1"
  case "$value" in
    \"*\")
      printf '%s\n' "${value:1:${#value}-2}"
      ;;
    \'*\')
      printf '%s\n' "${value:1:${#value}-2}"
      ;;
    *)
      printf '%s\n' "$value"
      ;;
  esac
}

replace_yaml_field() {
  local yaml_file="$1"
  local field="$2"
  local value="$3"
  local tmp_file

  tmp_file=$(mktemp)
  chmod 600 "$tmp_file"
  # Replace the target field, then deduplicate all fields keeping only the
  # last occurrence of each key. Prevents stale earlier values from
  # persisting when a field is set multiple times.
  awk -v field="$field" -v value="$value" '
    index($0, field ":") == 1 { $0 = field ": " value }
    { buf[NR] = $0; keys[NR] = $0; sub(/:.*$/, "", keys[NR]); n = NR }
    END {
      for (i = 1; i <= n; i++) last[keys[i]] = i
      for (i = 1; i <= n; i++) if (last[keys[i]] == i) print buf[i]
    }
  ' "$yaml_file" > "$tmp_file"
  mv "$tmp_file" "$yaml_file"
}

file_nonempty() {
  [ -f "$1" ] && [ -s "$1" ]
}

change_dir_for() {
  local change_name="$1"
  if [ -d "openspec/changes/$change_name" ]; then
    echo "openspec/changes/$change_name"
  elif [ -d "openspec/changes/archive/$change_name" ]; then
    echo "openspec/changes/archive/$change_name"
  else
    echo "openspec/changes/$change_name"
  fi
}

yaml_file_for() {
  local change_name="$1"
  local change_dir
  change_dir=$(change_dir_for "$change_name")
  echo "$change_dir/.cool.yaml"
}

project_context_compression() {
  local value="off"
  local source="default"
  if [ -n "${COOL_CONTEXT_COMPRESSION:-}" ]; then
    value="$COOL_CONTEXT_COMPRESSION"
    source="COOL_CONTEXT_COMPRESSION"
  elif [ -f ".cool/config.yaml" ]; then
    value=$(yaml_field "context_compression" ".cool/config.yaml")
    value="${value:-off}"
    source=".cool/config.yaml"
  fi

  case "$value" in
    off|beta)
      printf '%s\n' "$value"
      ;;
    *)
      red "ERROR: Invalid context_compression from ${source}: '$value'" >&2
      red "Valid values: off, beta" >&2
      exit 1
      ;;
  esac
}

project_auto_transition_default() {
  local value="true"
  local source="default"
  if [ -n "${COOL_AUTO_TRANSITION:-}" ]; then
    value="$COOL_AUTO_TRANSITION"
    source="COOL_AUTO_TRANSITION"
  elif [ -f ".cool/config.yaml" ]; then
    local raw
    raw=$(yaml_field "auto_transition" ".cool/config.yaml" 2>/dev/null || true)
    if [ -n "$raw" ]; then
      value="$raw"
      source=".cool/config.yaml"
    fi
  fi

  case "$value" in
    true|false)
      printf '%s\n' "$value"
      ;;
    *)
      red "ERROR: Invalid auto_transition from ${source}: '$value'" >&2
      red "Valid values: true, false" >&2
      exit 1
      ;;
  esac
}

project_decision_mode_default() {
  local value="manual"
  local source="default"
  if [ -n "${COOL_DECISION_MODE:-}" ]; then
    value="$COOL_DECISION_MODE"
    source="COOL_DECISION_MODE"
  elif [ -f ".cool/config.yaml" ]; then
    local raw
    raw=$(yaml_field "decision_mode" ".cool/config.yaml" 2>/dev/null || true)
    if [ -n "$raw" ]; then
      value="$raw"
      source=".cool/config.yaml"
    fi
  fi
  case "$value" in
    manual|recommend)
      printf '%s\n' "$value"
      ;;
    *)
      red "ERROR: Invalid decision_mode from ${source}: '$value'" >&2
      red "Valid values: manual, recommend" >&2
      exit 1
      ;;
  esac
}

# --- Subcommands ---

cmd_init() {
  local change_name="$1"
  local workflow="$2"

  validate_change_name "$change_name"
  validate_enum "$workflow" "full" "hotfix" "tweak"

  local change_dir yaml_file
  change_dir=$(change_dir_for "$change_name")
  yaml_file=$(yaml_file_for "$change_name")

  # Check if .cool.yaml already exists
  if [ -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml already exists at $yaml_file"
    exit 1
  fi

  # Create change directory if it doesn't exist
  mkdir -p "$change_dir"

  # Set workflow-appropriate defaults
  local phase build_mode isolation verify_mode review_mode context_compression auto_transition
  phase="open"
  context_compression=$(project_context_compression)
  auto_transition="$(project_auto_transition_default)"

  case "$workflow" in
    full)
      build_mode="null"
      tdd_mode="null"
      isolation="null"
      verify_mode="null"
      review_mode="full"
      ;;
    hotfix)
      build_mode="direct"
      tdd_mode="direct"
      isolation="branch"
      verify_mode="light"
      review_mode="light"
      ;;
    tweak)
      build_mode="direct"
      tdd_mode="direct"
      isolation="branch"
      verify_mode="light"
      review_mode="skip"
      ;;
  esac

  # Write .cool.yaml
  # Record current HEAD as base_ref for scale assessment fallback
  local base_ref="null"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    base_ref=$(git rev-parse HEAD 2>/dev/null || echo "null")
  fi

  cat > "$yaml_file" <<EOF
workflow: $workflow
phase: $phase
context_compression: $context_compression
build_mode: $build_mode
build_pause: null
subagent_dispatch: null
tdd_mode: $tdd_mode
isolation: $isolation
verify_mode: $verify_mode
review_mode: $review_mode
review_result: pending
review_report: null
review_fail_count: 0
auto_transition: $auto_transition
decision_mode: manual
base_branch: null
open_branch: null
base_ref: $base_ref
design_doc: null
plan: null
verify_result: pending
verification_report: null
branch_status: pending
created_at: $(date -u +%Y-%m-%d)
verified_at: null
archived: false
EOF

  green "Initialized: $yaml_file (workflow=$workflow)"
}

cmd_get() {
  local change_name="$1"
  local field="$2"

  validate_change_name "$change_name"

  local yaml_file
  yaml_file=$(yaml_file_for "$change_name")

  # Check if .cool.yaml exists
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  # Read and output the field value
  local value
  value=$(yaml_field "$field" "$yaml_file")
  if [ "$field" = "auto_transition" ] && { [ -z "$value" ] || [ "$value" = "null" ]; }; then
    value="$(project_auto_transition_default)"
  fi
  echo "${value:-}"
}

cmd_set() {
  local change_name="$1"
  local field="$2"
  local value="$3"

  validate_change_name "$change_name"

  local yaml_file
  yaml_file=$(yaml_file_for "$change_name")

  # Check if .cool.yaml exists
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  # Validate field name
  case "$field" in
    phase)
      yellow "WARNING: Setting 'phase' directly bypasses state machine constraints." >&2
      yellow "  Consider using: cool-state.sh transition <change-name> <event>" >&2
      ;;
    workflow|context_compression|build_mode|build_pause|subagent_dispatch|tdd_mode|isolation|verify_mode|auto_transition|verify_result|verification_report|branch_status|archived|design_doc|plan|verified_at|created_at|direct_override|build_command|verify_command|handoff_context|handoff_hash|base_ref|review_mode|review_result|review_report|review_fail_count|decision_mode|base_branch|open_branch|pending_decision)
      # Valid field
      ;;
    *)
      red "ERROR: Unknown field: '$field'" >&2
      red "Valid fields:" >&2
      red "  workflow, phase, context_compression, design_doc, plan, build_mode, build_pause, subagent_dispatch, tdd_mode, isolation," >&2
      red "  verify_mode, auto_transition, verify_result, verification_report, branch_status," >&2
      red "  verified_at, created_at, archived, base_ref, direct_override," >&2
      red "  build_command, verify_command, handoff_context, handoff_hash," >&2
      red "  review_mode, review_result, review_report, review_fail_count, open_branch, pending_decision" >&2
      exit 1
      ;;
  esac

  # Validate enum values
  case "$field" in
    workflow)
      validate_enum "$value" "full" "hotfix" "tweak"
      ;;
    context_compression)
      validate_enum "$value" "off" "beta"
      ;;
    phase)
      validate_enum "$value" "open" "design" "build" "review" "verify" "archive"
      ;;
    build_mode)
      validate_enum "$value" "subagent-driven-development" "executing-plans" "direct"
      ;;
    build_pause)
      validate_enum "$value" "null" "plan-ready"
      ;;
    subagent_dispatch)
      validate_enum "$value" "null" "confirmed"
      ;;
    tdd_mode)
      validate_enum "$value" "tdd" "direct"
      ;;
    isolation)
      validate_enum "$value" "branch" "worktree"
      ;;
    verify_mode)
      validate_enum "$value" "light" "full"
      ;;
    auto_transition)
      validate_enum "$value" "true" "false"
      ;;
    decision_mode)
      validate_enum "$value" "manual" "recommend"
      ;;
    verify_result)
      validate_enum "$value" "pending" "pass" "fail"
      ;;
    review_mode)
      validate_enum "$value" "full" "light" "skip"
      ;;
    review_result)
      validate_enum "$value" "pending" "pass" "fail"
      ;;
    branch_status)
      validate_enum "$value" "pending" "handled"
      ;;
    pending_decision)
      # null 或任意已命名 point；非空值须为 cmd_decision 已命名点
      if [ "$value" != "null" ] && [ -n "$value" ]; then
        case "$value" in
          archive|discard|verify-critical|verify-fail-limit|spec-contradiction|context-compaction|\
          clarify-review|open-review|design-review|plan-ready|plan-review|build-config|scope-split-review|\
          verify-drift-review|verify-fail-decision|tweak-upgrade|hotfix-upgrade|\
          intent|branch-name|change-name|finishing-branch|subagent-dispatch|platform-capability)
            ;;
          *)
            red "ERROR: pending_decision='$value' is not a known decision point" >&2
            exit 1
            ;;
        esac
      fi
      ;;
    archived)
      validate_enum "$value" "true" "false"
      ;;
    direct_override)
      validate_enum "$value" "true" "false"
      ;;
    design_doc|plan|verification_report|handoff_context|handoff_hash|review_report)
      validate_path_field "$value" "$field"
      ;;
    verified_at|created_at|build_command|verify_command|review_fail_count)
      # No validation for date fields, project command strings, or counters
      ;;
  esac

  # Write or update the field
  if grep -q "^${field}:" "$yaml_file"; then
    replace_yaml_field "$yaml_file" "$field" "$value"
  else
    # Field doesn't exist, append it
    echo "${field}: ${value}" >> "$yaml_file"
  fi

  green "[SET] ${field}=${value}"
}

require_phase() {
  local change_name="$1"
  local expected="$2"
  local actual
  actual=$(cmd_get "$change_name" "phase")
  if [ "$actual" != "$expected" ]; then
    red "ERROR: Cannot transition '$change_name': expected phase ${expected}, got ${actual}" >&2
    exit 1
  fi
}

require_verification_evidence() {
  local change_name="$1"
  local report branch_status
  report=$(cmd_get "$change_name" "verification_report")
  branch_status=$(cmd_get "$change_name" "branch_status")

  if [ -z "$report" ] || [ "$report" = "null" ] || [ ! -f "$report" ]; then
    red "ERROR: Cannot transition '$change_name': verification_report must point to an existing report file" >&2
    exit 1
  fi

  if [ "$branch_status" != "handled" ]; then
    red "ERROR: Cannot transition '$change_name': branch_status must be handled" >&2
    exit 1
  fi
}

require_build_decisions() {
  local change_name="$1"
  local workflow build_mode isolation direct_override subagent_dispatch tdd_mode
  workflow=$(cmd_get "$change_name" "workflow")
  build_mode=$(cmd_get "$change_name" "build_mode")
  isolation=$(cmd_get "$change_name" "isolation")
  direct_override=$(cmd_get "$change_name" "direct_override" 2>/dev/null || true)
  subagent_dispatch=$(cmd_get "$change_name" "subagent_dispatch" 2>/dev/null || true)
  tdd_mode=$(cmd_get "$change_name" "tdd_mode" 2>/dev/null || true)

  case "$isolation" in
    branch|worktree) ;;
    *)
      red "ERROR: Cannot transition '$change_name': isolation must be branch or worktree, got '${isolation:-null}'" >&2
      exit 1
      ;;
  esac

  case "$build_mode" in
    subagent-driven-development|executing-plans|direct) ;;
    *)
      red "ERROR: Cannot transition '$change_name': build_mode must be selected before leaving build, got '${build_mode:-null}'" >&2
      exit 1
      ;;
  esac

  if [ "$build_mode" = "direct" ] && [ "$workflow" != "hotfix" ] && [ "$workflow" != "tweak" ] && [ "$direct_override" != "true" ]; then
    red "ERROR: Cannot transition '$change_name': build_mode=direct is only allowed for hotfix/tweak unless direct_override=true" >&2
    exit 1
  fi

  if [ "$build_mode" = "subagent-driven-development" ] && [ "$subagent_dispatch" != "confirmed" ]; then
    red "ERROR: Cannot transition '$change_name': subagent_dispatch must be confirmed before using build_mode=subagent-driven-development" >&2
    exit 1
  fi

  if [ "$workflow" = "full" ] && { [ "$tdd_mode" = "null" ] || [ -z "$tdd_mode" ]; }; then
    red "ERROR: Cannot transition '$change_name': tdd_mode must be selected before leaving build (full workflow)" >&2
    exit 1
  fi
}

cmd_transition() {
  local change_name="$1"
  local event="$2"

  validate_change_name "$change_name"
  validate_enum "$event" "open-complete" "design-complete" "build-complete" "review-pass" "review-fail" "verify-pass" "verify-fail" "archive-reopen" "archived"

  case "$event" in
    open-complete)
      require_phase "$change_name" "open"
      local workflow
      workflow=$(cmd_get "$change_name" "workflow")
      if [ "$workflow" = "full" ]; then
        cmd_set "$change_name" phase design
      else
        cmd_set "$change_name" phase build
      fi
      ;;
    design-complete)
      require_phase "$change_name" "design"
      cmd_set "$change_name" phase build
      ;;
    build-complete)
      require_phase "$change_name" "build"
      require_build_decisions "$change_name"
      local current_verify_result review_mode
      current_verify_result=$(cmd_get "$change_name" "verify_result")
      review_mode=$(cmd_get "$change_name" "review_mode")

      if [ "$review_mode" = "skip" ]; then
        # tweak：跳过 review，直接进入 verify
        cmd_set "$change_name" phase verify
        cmd_set "$change_name" verify_result pending
        if [ "$current_verify_result" != "fail" ]; then
          cmd_set "$change_name" verification_report null
          cmd_set "$change_name" branch_status pending
        fi
      else
        # full/light：进入 review 阶段
        cmd_set "$change_name" phase review
        cmd_set "$change_name" review_result pending
      fi
      ;;
    review-pass)
      require_phase "$change_name" "review"
      cmd_set "$change_name" review_result pass
      cmd_set "$change_name" review_fail_count 0
      cmd_set "$change_name" phase verify
      cmd_set "$change_name" verify_result pending
      cmd_set "$change_name" verification_report null
      cmd_set "$change_name" branch_status pending
      ;;
    review-fail)
      require_phase "$change_name" "review"
      local current_fail_count
      current_fail_count=$(cmd_get "$change_name" "review_fail_count" 2>/dev/null || echo "0")
      [ "$current_fail_count" = "null" ] && current_fail_count=0
      cmd_set "$change_name" review_result fail
      cmd_set "$change_name" review_fail_count $((current_fail_count + 1))
      cmd_set "$change_name" phase build
      ;;
    verify-pass)
      require_phase "$change_name" "verify"
      require_verification_evidence "$change_name"
      cmd_set "$change_name" verify_result pass
      cmd_set "$change_name" phase archive
      cmd_set "$change_name" verified_at "$(date -u +%Y-%m-%d)"
      ;;
    verify-fail)
      require_phase "$change_name" "verify"
      cmd_set "$change_name" verify_result fail
      cmd_set "$change_name" phase build
      # Preserve branch_status so re-verify doesn't require re-handling branches
      ;;
    archive-reopen)
      require_phase "$change_name" "archive"
      local archived
      archived=$(cmd_get "$change_name" "archived")
      if [ "$archived" = "true" ]; then
        red "ERROR: Cannot transition '$change_name': already archived" >&2
        exit 1
      fi
      cmd_set "$change_name" verify_result pending
      cmd_set "$change_name" phase verify
      cmd_set "$change_name" verified_at null
      ;;
    archived)
      require_phase "$change_name" "archive"
      cmd_set "$change_name" archived true
      ;;
  esac

  green "[TRANSITION] ${event}"
}

# --- Check helpers for entry verification ---

CHECK_BLOCK=0

check_pass() {
  local msg="$1"
  echo "  $(green "[PASS]") $msg"
}

check_fail() {
  local msg="$1"
  echo "  $(red "[FAIL]") $msg"
  CHECK_BLOCK=1
}

check_nonempty() {
  local desc="$1"
  local path="$2"
  if file_nonempty "$path"; then
    check_pass "$desc non-empty"
  else
    check_fail "$desc missing or empty"
  fi
}

check_yaml_is() {
  local field="$1"
  local expected="$2"
  local change_name="$3"
  local actual
  actual=$(cmd_get "$change_name" "$field")
  if [ "$actual" = "$expected" ]; then
    check_pass "${field}=${actual} (expected: ${expected})"
  else
    check_fail "${field}=${actual} (expected: ${expected})"
  fi
}

check_yaml_empty() {
  local field="$1"
  local change_name="$2"
  local value
  value=$(cmd_get "$change_name" "$field")
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    check_pass "${field} is empty/null"
  else
    check_fail "${field}=${value} (expected: empty/null)"
  fi
}

check_file_not_exists() {
  local desc="$1"
  local path="$2"
  if [ ! -f "$path" ]; then
    check_pass "$desc does not exist"
  else
    check_fail "$desc exists (should not exist)"
  fi
}

cmd_check() {
  local change_name="$1"
  local phase="$2"

  validate_change_name "$change_name"
  validate_enum "$phase" "open" "design" "build" "review" "verify" "archive"

  local change_dir="openspec/changes/$change_name"
  local yaml_file="$change_dir/.cool.yaml"
  local proposal_file="$change_dir/proposal.md"
  local design_file="$change_dir/design.md"
  local tasks_file="$change_dir/tasks.md"

  echo "=== Entry Check: cool-${phase} ==="

  # .cool.yaml must exist for all phases (state machine core)
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  # Phase-specific checks
  case "$phase" in
    open)
      check_pass ".cool.yaml exists"
      check_yaml_is "phase" "open" "$change_name"
      ;;
    design)
      check_pass ".cool.yaml exists"
      check_yaml_is "phase" "design" "$change_name"
      check_yaml_is "workflow" "full" "$change_name"
      check_yaml_empty "design_doc" "$change_name"
      check_nonempty "proposal.md" "$proposal_file"
      check_nonempty "design.md" "$design_file"
      check_nonempty "tasks.md" "$tasks_file"
      ;;
    build)
      check_pass ".cool.yaml exists"
      check_yaml_is "phase" "build" "$change_name"
      # design_doc required for full workflow only
      local workflow
      workflow=$(cmd_get "$change_name" "workflow")
      if [ "$workflow" = "full" ]; then
        local design_doc
        design_doc=$(cmd_get "$change_name" "design_doc")
        if [ -n "$design_doc" ] && [ "$design_doc" != "null" ] && [ -f "$design_doc" ]; then
          check_pass "design_doc=${design_doc} (file exists)"
        else
          check_fail "design_doc=${design_doc} (expected: non-null and file exists)"
        fi
      else
        check_pass "workflow=${workflow} (design_doc not required)"
      fi
      check_nonempty "proposal.md" "$proposal_file"
      check_nonempty "tasks.md" "$tasks_file"
      ;;
    review)
      check_pass ".cool.yaml exists"
      check_yaml_is "phase" "review" "$change_name"
      check_nonempty "proposal.md" "$proposal_file"
      check_nonempty "tasks.md" "$tasks_file"
      ;;
    verify)
      check_pass ".cool.yaml exists"
      check_yaml_is "phase" "verify" "$change_name"
      # Check verify_result is pending or null
      local verify_result
      verify_result=$(cmd_get "$change_name" "verify_result")
      if [ "$verify_result" = "pending" ] || [ -z "$verify_result" ] || [ "$verify_result" = "null" ]; then
        check_pass "verify_result=${verify_result} (expected: pending or null)"
      else
        check_fail "verify_result=${verify_result} (expected: pending or null)"
      fi
      ;;
    archive)
      check_pass ".cool.yaml exists"
      check_yaml_is "phase" "archive" "$change_name"
      check_yaml_is "verify_result" "pass" "$change_name"
      # Check archived is NOT true
      local archived
      archived=$(cmd_get "$change_name" "archived")
      if [ "$archived" != "true" ]; then
        check_pass "archived=${archived} (expected: not true)"
      else
        check_fail "archived=${archived} (expected: not true)"
      fi
      ;;
    *)
      red "ERROR: Unknown phase for check: $phase"
      exit 1
      ;;
  esac

  echo ""
  if [ "$CHECK_BLOCK" -eq 1 ]; then
    red "BLOCKED — fix failing checks before proceeding"
    exit 1
  else
    green "ALL CHECKS PASSED — ready to proceed"
    exit 0
  fi
}

# --- Recovery context for compaction resume ---

field_status() {
  # Args: field_name value [file_path]
  # Prints: "field_name: DONE (value)" or "field_name: PENDING"
  local field="$1"
  local value="$2"
  local file_path="${3:-}"

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "  - ${field}: PENDING"
  elif [ -n "$file_path" ] && [ ! -f "$file_path" ]; then
    echo "  - ${field}: BROKEN (path ${value} does not exist)"
  else
    echo "  - ${field}: DONE (${value})"
  fi
}

cmd_recover() {
  local change_name="$1"

  validate_change_name "$change_name"

  local change_dir="openspec/changes/$change_name"
  local yaml_file="$change_dir/.cool.yaml"

  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  local phase workflow
  phase=$(cmd_get "$change_name" "phase")
  workflow=$(cmd_get "$change_name" "workflow")

  echo "=== Recovery Context: ${change_name} ==="
  echo "Phase: ${phase}"
  echo "Workflow: ${workflow}"
  echo ""

  # Read all relevant fields
  local design_doc plan verify_result verify_mode verification_report
  local branch_status handoff_context handoff_hash isolation build_mode build_pause subagent_dispatch tdd_mode direct_override
  design_doc=$(cmd_get "$change_name" "design_doc")
  plan=$(cmd_get "$change_name" "plan")
  verify_result=$(cmd_get "$change_name" "verify_result")
  verify_mode=$(cmd_get "$change_name" "verify_mode")
  verification_report=$(cmd_get "$change_name" "verification_report")
  branch_status=$(cmd_get "$change_name" "branch_status")
  handoff_context=$(cmd_get "$change_name" "handoff_context")
  handoff_hash=$(cmd_get "$change_name" "handoff_hash")
  isolation=$(cmd_get "$change_name" "isolation")
  build_mode=$(cmd_get "$change_name" "build_mode")
  build_pause=$(cmd_get "$change_name" "build_pause" 2>/dev/null || true)
  subagent_dispatch=$(cmd_get "$change_name" "subagent_dispatch" 2>/dev/null || true)
  tdd_mode=$(cmd_get "$change_name" "tdd_mode" 2>/dev/null || true)
  direct_override=$(cmd_get "$change_name" "direct_override" 2>/dev/null || true)

  echo "State fields:"

  # Phase-specific field reporting
  case "$phase" in
    open)
      echo "  Artifacts:"
      local artifacts_done=0
      for f in proposal.md design.md tasks.md; do
        if file_nonempty "$change_dir/$f"; then
          echo "  - ${f}: DONE"
          artifacts_done=$((artifacts_done + 1))
        else
          echo "  - ${f}: PENDING"
        fi
      done
      echo ""
      if [ "$artifacts_done" -eq 3 ]; then
        echo "Recovery action: All artifacts complete. Run /cool-open user confirmation, then guard to transition."
      elif [ "$artifacts_done" -eq 0 ]; then
        echo "Recovery action: No artifacts created yet. Start from /cool-open Step 1 (explore and clarify)."
      else
        echo "Recovery action: Some artifacts incomplete. Resume /cool-open from the first missing artifact."
      fi
      ;;
    design)
      echo "  Artifacts:"
      for f in proposal.md design.md tasks.md; do
        if file_nonempty "$change_dir/$f"; then
          echo "  - ${f}: DONE"
        else
          echo "  - ${f}: MISSING (unexpected in design phase)"
        fi
      done
      echo ""
      echo "  Design progress:"
      field_status "handoff_context" "$handoff_context" "$handoff_context"
      field_status "handoff_hash" "$handoff_hash"
      field_status "design_doc" "$design_doc" "$design_doc"
      echo ""
      if [ -n "$design_doc" ] && [ "$design_doc" != "null" ] && [ -f "$design_doc" ]; then
        echo "Recovery action: Design Doc already created and linked. Run guard to transition to build."
      elif [ -n "$handoff_context" ] && [ "$handoff_context" != "null" ] && [ -f "$handoff_context" ]; then
        echo "Recovery action: Handoff generated but Design Doc not yet created. Resume from brainstorming confirmation (Step 1c)."
      else
        echo "Recovery action: No handoff generated yet. Start from Step 1a (generate handoff package)."
      fi
      ;;
    build)
      echo "  Build decisions:"
      field_status "isolation" "$isolation"
      field_status "build_mode" "$build_mode"
      field_status "build_pause" "$build_pause"
      field_status "tdd_mode" "$tdd_mode"
      if [ "$build_mode" = "subagent-driven-development" ] || { [ -n "$subagent_dispatch" ] && [ "$subagent_dispatch" != "null" ]; }; then
        field_status "subagent_dispatch" "$subagent_dispatch"
      fi
      if [ "$build_mode" = "direct" ] && [ "$workflow" != "hotfix" ] && [ "$workflow" != "tweak" ]; then
        field_status "direct_override" "$direct_override"
      fi
      echo ""
      echo "  Plan:"
      field_status "plan" "$plan" "$plan"
      echo ""
      # Count completed vs pending tasks
      local tasks_file="$change_dir/tasks.md"
      local total=0 done=0 pending=0
      local plan_total=0 plan_done=0 plan_pending=0
      if [ -f "$tasks_file" ]; then
        total=$(grep -c '^[[:space:]]*- \[' "$tasks_file" 2>/dev/null || true)
        done=$(grep -c '^[[:space:]]*- \[x\]' "$tasks_file" 2>/dev/null || true)
        total="${total:-0}"
        done="${done:-0}"
        pending=$((total - done))
        echo "  Tasks: ${done}/${total} done, ${pending} pending"
      else
        echo "  Tasks: tasks.md MISSING"
      fi
      if [ -n "$plan" ] && [ "$plan" != "null" ] && [ -f "$plan" ]; then
        plan_total=$(grep -c '^[[:space:]]*- \[' "$plan" 2>/dev/null || true)
        plan_done=$(grep -c '^[[:space:]]*- \[x\]' "$plan" 2>/dev/null || true)
        plan_total="${plan_total:-0}"
        plan_done="${plan_done:-0}"
        plan_pending=$((plan_total - plan_done))
        if [ "$plan_total" -gt 0 ]; then
          echo "  Plan tasks: ${plan_done}/${plan_total} done, ${plan_pending} pending"
        fi
      fi
      echo ""
      if [ "$build_pause" = "plan-ready" ] && [ -n "$plan" ] && [ "$plan" != "null" ] && [ -f "$plan" ] && { [ "$isolation" = "null" ] || [ -z "$isolation" ] || [ "$build_mode" = "null" ] || [ -z "$build_mode" ]; }; then
        echo "Recovery action: Plan-ready pause detected. Ask the user whether to continue, then choose isolation and build mode without regenerating the plan."
      elif [ "$build_pause" = "plan-ready" ] && { [ -z "$plan" ] || [ "$plan" = "null" ] || [ ! -f "$plan" ]; }; then
        echo "Recovery action: Plan-ready pause is recorded, but the plan file is missing. Restore the plan file or rerun writing-plans before choosing execution."
      elif [ "$build_pause" = "plan-ready" ]; then
        if [ "$build_mode" = "subagent-driven-development" ] && { [ "$pending" -gt 0 ] || [ "$plan_pending" -gt 0 ]; }; then
          if [ "$subagent_dispatch" = "confirmed" ]; then
            echo "Recovery action: Plan-ready pause is stale because build decisions are already selected. Clear build_pause to null, then inspect the first unchecked task (OpenSpec or plan additions) against recent git history/diff. If implemented, check it off; otherwise dispatch a real background subagent. Do not execute the pending task directly in the main window."
          else
            echo "Recovery action: Plan-ready pause is stale and subagent dispatch is not confirmed. Confirm a real background subagent/Task/multi-agent dispatcher and set subagent_dispatch to confirmed, or set build_mode to executing-plans before continuing."
          fi
        elif [ "$pending" -gt 0 ] || [ "$plan_pending" -gt 0 ]; then
          echo "Recovery action: Plan-ready pause is stale because build decisions are already selected. Clear build_pause to null, then continue from the first unchecked task."
        else
          echo "Recovery action: Plan-ready pause is stale and all tasks are done. Clear build_pause to null, then run guard to transition to verify."
        fi
      elif [ "$isolation" = "null" ] || [ -z "$isolation" ]; then
        echo "Recovery action: Isolation not selected. Use the current platform's user confirmation mechanism to ask user for branch/worktree choice."
      elif [ "$build_mode" = "null" ] || [ -z "$build_mode" ]; then
        echo "Recovery action: Build mode not selected. Use the current platform's user confirmation mechanism to ask user for execution method."
      elif [ -z "$tdd_mode" ] || [ "$tdd_mode" = "null" ]; then
        echo "Recovery action: TDD mode not selected. Use the current platform's user confirmation mechanism to ask user for tdd or direct."
      elif [ ! -f "$tasks_file" ]; then
        echo "Recovery action: tasks.md missing. Verify change directory integrity."
      elif [ "$pending" -gt 0 ]; then
        if [ "$build_mode" = "subagent-driven-development" ]; then
          if [ "$subagent_dispatch" = "confirmed" ]; then
            echo "Recovery action: Read tasks.md and the Superpowers plan (which may include additions beyond OpenSpec), then inspect the first unchecked task against recent git history/diff. If implemented, check it off; otherwise dispatch a real background subagent. Do not execute the pending task directly in the main window."
          else
            echo "Recovery action: Subagent dispatch is not confirmed. Confirm a real background subagent/Task/multi-agent dispatcher and set subagent_dispatch to confirmed, or set build_mode to executing-plans before continuing."
          fi
        else
          echo "Recovery action: Read tasks.md and continue from first unchecked task."
        fi
      elif [ "$plan_pending" -gt 0 ]; then
        if [ "$build_mode" = "subagent-driven-development" ]; then
          if [ "$subagent_dispatch" = "confirmed" ]; then
            echo "Recovery action: Read the Superpowers plan, then inspect the first unchecked Superpowers plan task against recent git history/diff. If implemented, check it off; otherwise dispatch a real background subagent. Do not execute the pending task directly in the main window."
          else
            echo "Recovery action: Subagent dispatch is not confirmed. Confirm a real background subagent/Task/multi-agent dispatcher and set subagent_dispatch to confirmed, or set build_mode to executing-plans before continuing."
          fi
        else
          echo "Recovery action: Read the Superpowers plan and continue from the first unchecked plan task."
        fi
      else
        echo "Recovery action: All tasks done. Run guard to transition to verify."
      fi
      ;;
    verify)
      echo "  Verification:"
      field_status "verify_result" "$verify_result"
      field_status "verify_mode" "$verify_mode"
      field_status "verification_report" "$verification_report" "$verification_report"
      field_status "branch_status" "$branch_status"
      echo ""
      if [ "$verify_result" = "pass" ] && [ "$branch_status" = "handled" ]; then
        echo "Recovery action: Verification complete. Run guard to transition to archive."
      elif [ "$verify_result" = "pass" ]; then
        echo "Recovery action: Verification passed but branch not yet handled. Complete branch handling and set branch_status to handled."
      elif [ "$verify_result" = "fail" ]; then
        echo "Recovery action: Verification failed and rolled back to build. Resume from /cool-build."
      else
        echo "Recovery action: Verification not yet started or in progress. Run scale assessment then verify."
      fi
      ;;
    archive)
      echo "  Archive:"
      field_status "verify_result" "$verify_result"
      field_status "archived" "$(cmd_get "$change_name" "archived")"
      echo ""
      echo "Recovery action: Run /cool-archive to complete archiving."
      ;;
    *)
      red "ERROR: Unknown phase: $phase"
      exit 1
      ;;
  esac

  echo ""
  echo "=== End Recovery Context ==="
}

cmd_scale() {
  local change_name="$1"

  validate_change_name "$change_name"

  local change_dir="openspec/changes/$change_name"
  local yaml_file="$change_dir/.cool.yaml"

  # Verify .cool.yaml exists
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  # Read metrics
  # 1. Task count: count lines matching `- [` in tasks.md
  local tasks_file="$change_dir/tasks.md"
  local task_count=0
  if [ -f "$tasks_file" ]; then
    task_count=$(grep -c '^\- \[' "$tasks_file" 2>/dev/null || echo "0")
  fi

  # 2. Delta spec count: count files named spec.md under specs/*/spec.md
  local delta_spec_count=0
  if [ -d "$change_dir/specs" ]; then
    delta_spec_count=$(find "$change_dir/specs" -name "spec.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  fi

  # 3. Changed files: prefer plan base-ref, then .cool.yaml base_ref, fall back to worktree diff.
  # A1+D2: 文件列表统一经 substantive_changed_files_list 过滤，排除工作流产物偏置。
  local changed_files=0
  if git rev-parse --git-dir > /dev/null 2>&1; then
    local plan_file base_ref="" diff_files
    plan_file=$(cmd_get "$change_name" "plan" 2>/dev/null || true)
    if [ -n "$plan_file" ] && [ "$plan_file" != "null" ] && [ -f "$plan_file" ]; then
      base_ref=$(grep '^base-ref:' "$plan_file" 2>/dev/null | head -1 | sed 's/^base-ref: *//' || true)
    fi
    # Fallback to base_ref stored in .cool.yaml (set during init)
    if [ -z "$base_ref" ] || [ "$base_ref" = "null" ]; then
      base_ref=$(cmd_get "$change_name" "base_ref" 2>/dev/null || true)
    fi

    if [ -n "${base_ref:-}" ] && [ "$base_ref" != "null" ] && git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
      diff_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || true)
    else
      diff_files=$(git diff --name-only HEAD 2>/dev/null || true)
    fi
    changed_files=$(substantive_changed_files_list "$diff_files" | wc -l | tr -d ' ')
  fi

  # Decision rules
  local result="light"
  if [ "$task_count" -gt 3 ] || [ "$delta_spec_count" -gt 1 ] || [ "$changed_files" -gt 4 ]; then
    result="full"
  fi

  # Output assessment to stderr
  echo "=== Scale Assessment: $change_name ===" >&2
  echo "  Tasks: $task_count (threshold: 3)" >&2
  echo "  Delta specs: $delta_spec_count capabilities (threshold: 1)" >&2
  echo "  Changed files: $changed_files (threshold: 4)" >&2
  echo "  → Result: $result" >&2

  # Update verify_mode in .cool.yaml
  replace_yaml_field "$yaml_file" "verify_mode" "$result"

  green "[SCALE] verify_mode=$result"
}

# Resolve the next workflow step after a guard --apply phase advance.
# Reads the (already advanced) phase, workflow, and auto_transition, then emits
# a deterministic next-step contract so skills don't hardcode the next skill name.
#
# Output contract (stdout):
#   NEXT: auto|manual|done
#   SKILL: <skill-name>      (omitted when NEXT=done)
#   HINT: <message>          (only when NEXT=manual)
cmd_next() {
  local change_name="$1"
  validate_change_name "$change_name"

  local change_dir="openspec/changes/$change_name"
  local yaml_file="$change_dir/.cool.yaml"
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file" >&2
    exit 1
  fi

  local phase workflow auto_transition archived
  phase=$(cmd_get "$change_name" "phase" 2>/dev/null || true)
  workflow=$(cmd_get "$change_name" "workflow" 2>/dev/null || true)
  auto_transition=$(cmd_get "$change_name" "auto_transition" 2>/dev/null || true)
  archived=$(cmd_get "$change_name" "archived" 2>/dev/null || true)

  # Change-level auto_transition overrides project-level; fall back to project default
  if [ -z "$auto_transition" ] || [ "$auto_transition" = "null" ]; then
    auto_transition="$(project_auto_transition_default)"
  fi

  # Terminal state: archived change has no next step.
  if [ "$archived" = "true" ]; then
    echo "NEXT: done"
    return 0
  fi

  # Map the current (post-advance) phase to the skill that owns it.
  local skill=""
  case "$phase" in
    open)
      skill="cool-open"
      ;;
    design)
      skill="cool-design"
      ;;
    build)
      case "$workflow" in
        hotfix) skill="cool-hotfix" ;;
        tweak)  skill="cool-tweak" ;;
        *)      skill="cool-build" ;;
      esac
      ;;
    review)
      skill="cool-review"
      ;;
    verify)
      skill="cool-verify"
      ;;
    archive)
      skill="cool-archive"
      ;;
    *)
      red "ERROR: Cannot resolve next step for '$change_name': unknown phase '${phase:-null}'" >&2
      exit 1
      ;;
  esac

  # auto_transition=false pauses the next skill invocation only; phase is already advanced.
  if [ "$auto_transition" = "false" ]; then
    echo "NEXT: manual"
    echo "SKILL: $skill"
    echo "HINT: phase is '$phase'; run /$skill manually to continue"
  else
    echo "NEXT: auto"
    echo "SKILL: $skill"
  fi
}

cmd_abspath() {
  local path="${1:-}"
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$root" ]; then
    root="$(pwd -P)"
  fi
  if [ -z "$path" ]; then
    printf '%s\n' "$root"
    return 0
  fi
  # 绝对路径原样返回
  case "$path" in
    /*) printf '%s\n' "$path"; return 0 ;;
  esac
  # 去掉前导 ./
  path="${path#./}"
  printf '%s/%s\n' "$root" "$path"
}

cmd_decision() {
  local change_name="$1"
  local point="$2"
  local mode
  mode=$(yaml_field "decision_mode" "$(yaml_file_for "$change_name")" 2>/dev/null || true)
  if [ -z "$mode" ] || [ "$mode" = "null" ]; then
    mode="$(project_decision_mode_default)"
  fi

  if [ "$mode" != "recommend" ]; then
    printf 'block\n'
    return 0
  fi

  # recommend 模式档位表（D1 全量命名）。
  # 未知点一律 block（保守询问，避免新点静默放行）。
  case "$point" in
    # ── block：硬拦点（与 decision_mode 无关，此处 recommend 亦停）──
    archive|discard|verify-critical|verify-fail-limit|spec-contradiction)
      printf 'block\n'
      ;;
    # ── agent-assess：agent 自评档（recommend 独有；manual 顶部早返回 block）──
    # context-compaction 的 block 本质是「能力限制」（/compact 须手动）非「不可逆决策」，
    # 故 recommend 下交 agent 自评：充足则继续，紧张且无法触发则问用户。
    context-compaction)
      printf 'agent-assess\n'
      ;;
    # ── auto-after-review：产物质量点（先预决策复核再放行）──
    # 注：plan-review 旧名保留为 plan-ready 的别名；verify-fail-decision 为
    # verify-drift-review 的别名——均做冗余安全，防 `*`→block 误伤。
    clarify-review|open-review|design-review|plan-ready|plan-review|build-config|scope-split-review|verify-drift-review|verify-fail-decision|tweak-upgrade|hotfix-upgrade)
      printf 'auto-after-review\n'
      ;;
    # ── auto：机械点 / 可逆点（直接放行）──
    intent|branch-name|change-name|finishing-branch|subagent-dispatch|platform-capability)
      printf 'auto\n'
      ;;
    # ── `*`→block：未审计的新点保守询问 ──
    *)
      printf 'block\n'
      ;;
  esac
}

# gate <change-name> <point>
# 调 cmd_decision 得档位；auto-after-review 时读 review-log 最近一条 result。
# stdout 三态（机器可解析前缀 + 人类可读）；写 pending_decision 供 hook 校验。
cmd_gate() {
  local change_name="$1"
  local point="$2"

  validate_change_name "$change_name"

  # point 须为已命名决策点（与 cmd_set pending_decision 校验一致，防 yaml 污染）
  case "$point" in
    archive|discard|verify-critical|verify-fail-limit|spec-contradiction|context-compaction|\
    clarify-review|open-review|design-review|plan-ready|plan-review|build-config|scope-split-review|\
    verify-drift-review|verify-fail-decision|tweak-upgrade|hotfix-upgrade|\
    intent|branch-name|change-name|finishing-branch|subagent-dispatch|platform-capability) ;;
    *)
      red "ERROR: unknown decision point '$point'" >&2
      exit 1
      ;;
  esac

  local yaml_file
  yaml_file=$(yaml_file_for "$change_name")
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  local tier
  tier=$(cmd_decision "$change_name" "$point")

  # 写 pending_decision（任何档位都写，供 hook 校验当前点）
  if grep -q "^pending_decision:" "$yaml_file"; then
    replace_yaml_field "$yaml_file" "pending_decision" "$point"
  else
    echo "pending_decision: $point" >> "$yaml_file"
  fi

  case "$tier" in
    auto)
      printf 'PROCEED: %s auto-advance. DO NOT ask the user.\n' "$point"
      ;;
    agent-assess)
      printf 'ASSESS: %s agent-self-assess. Assess context budget; if sufficient, continue without asking; if tight and the platform cannot trigger compaction programmatically, stop and ask the user to run /compact manually (retained block path).\n' "$point"
      ;;
    block)
      printf 'BLOCK: ask the user for %s.\n' "$point"
      ;;
    auto-after-review)
      # 读 review-log 最近一条该 point 的 result
      local log_file result
      log_file="openspec/changes/${change_name}/.cool/handoff/review-log.md"
      result=""
      if [ -f "$log_file" ]; then
        # 标题格式: ## DATE <point> (review:by) round: N
        # 取最后一个匹配 point 的 block 之后紧跟的 - 结果: 行
        result=$(awk -v pt="$point" '
          /^## [0-9]{4}-[0-9]{2}-[0-9]{2} / {
            split($0, a, " "); cur_pt=a[3]
            # 仅进入匹配 point 的 block 时 reset cur_result（准备接收该 block 结果）；
            # 非匹配 block 不动 cur_result，确保混合 point 序列下取目标 point 最近一条。
            if (cur_pt == pt) { in_block=1; cur_result="" }
            else { in_block=0 }
            next
          }
          in_block && /^- 结果: / { cur_result=substr($0, index($0,":")+2) }
          END { print cur_result }
        ' "$log_file")
      fi
      case "$result" in
        pass|minor)
          printf 'PROCEED: %s auto-advance. DO NOT ask the user.\n' "$point"
          ;;
        material|escalated|"")
          printf 'REVIEW: run predecision review for %s; on pass re-run gate; on material escalate to user.\n' "$point"
          ;;
      esac
      ;;
  esac
}

# review-log <change-name> <point> <round> <result> [issue]
# Append one review record to openspec/changes/<name>/.cool/handoff/review-log.md
# Env: COOL_REVIEW_BY=subagent|self (default: subagent)
# result ∈ {pass, minor, material, escalated}
cmd_review_log() {
  local change_name="$1"
  local point="$2"
  local round="$3"
  local result="$4"
  local issue="${5:-}"
  local by="${COOL_REVIEW_BY:-subagent}"

  validate_change_name "$change_name"

  local log_dir log_file
  log_dir="openspec/changes/${change_name}/.cool/handoff"
  log_file="${log_dir}/review-log.md"
  mkdir -p "$log_dir"

  local date_str decision
  date_str="$(date +%Y-%m-%d 2>/dev/null || echo YYYY-MM-DD)"
  case "$result" in
    pass|minor) decision="auto-advanced" ;;
    material|escalated) decision="escalated-to-user" ;;
    *) decision="recorded" ;;
  esac

  {
    printf '## %s %s (review:%s) round: %s\n' "$date_str" "$point" "$by" "$round"
    printf -- '- 结果: %s\n' "$result"
    if [ -n "$issue" ]; then
      printf -- '- 问题: %s\n' "$issue"
    else
      printf -- '- 问题: (无)\n'
    fi
    printf -- '- 决策: %s\n' "$decision"
    printf '\n'
  } >> "$log_file"

  printf 'appended: %s\n' "$log_file"
}

# --- Level detection: substantive changed files (A1+D2) ---
#
# 统一排除集，供 count-upgrade-files 与 cmd_scale 共用，防止两处规则漂移。
# 排除：openspec 产物、Superpowers 产物、.cool 目录、根级 .cool.yaml/.openspec.yaml、
# docs/guide 同步文档；构建产物目录（dist/build/out）；机器生成文件（lock/min/sourcemap）。
# 另 assets/skills/ 与 assets/skills-zh/ 同名 SKILL.md/rules/reference 视为一份
# （en/zh 同步对，由 substantive_changed_files_list 内联去重实现，不在此 glob 集合中）。
# glob 风格与 openspec/* 一致：bash case 中 * 匹配含 / 的任意字符，故 dist/* 匹配 dist/ 下任意深度。
LEVEL_DETECTION_DEFAULT_EXCLUDE_GLOBS="openspec/* docs/superpowers/* .cool/* docs/guide/* .cool.yaml .openspec.yaml dist/* build/* out/* *.lock *-lock.json *-lock.yaml *.min.js *.min.css *.map"

# level_detection_exclude_globs
# 读取可选 .cool/config.yaml: level_detection.exclude_globs 嵌套列表，
# 返回空格分隔的 glob 字符串（缺省空，不影响内置排除集）。
level_detection_exclude_globs() {
  local cfg=".cool/config.yaml"
  [ -f "$cfg" ] || return 0
  awk '
    /^level_detection:/ { in_ld=1; next }
    in_ld && /^[^[:space:]]/ { in_ld=0 }
    in_ld && /^[[:space:]]+exclude_globs:/ { in_eg=1; next }
    in_ld && in_eg && /^[[:space:]]+-[[:space:]]/ {
      line=$0
      sub(/^[[:space:]]+-[[:space:]]+/, "", line)
      gsub(/^["'"'"']|["'"'"']$/, "", line)
      printf "%s ", line
      next
    }
    in_ld && in_eg { in_eg=0 }
  ' "$cfg"
}

# substantive_changed_files_list <files-newline-text>
# 对给定的换行分隔文件列表应用统一排除集（内置 + 可选 config 追加）+
# en/zh SKILL.md/rules/reference 同步对去重，输出过滤后的文件列表（每行一个路径）。
substantive_changed_files_list() {
  local files="$1"
  local extra_globs
  extra_globs="$(level_detection_exclude_globs)"

  local f rel key seen=""
  set -f
  local -a all_globs=($LEVEL_DETECTION_DEFAULT_EXCLUDE_GLOBS $extra_globs)
  set +f

  while IFS= read -r f; do
    [ -z "$f" ] && continue

    local excluded=0 g
    for g in "${all_globs[@]}"; do
      [ -z "$g" ] && continue
      case "$f" in
        $g) excluded=1; break ;;
      esac
    done
    [ "$excluded" -eq 1 ] && continue

    rel=""
    case "$f" in
      assets/skills/*)    rel="${f#assets/skills/}" ;;
      assets/skills-zh/*) rel="${f#assets/skills-zh/}" ;;
    esac
    if [ -n "$rel" ]; then
      case "$rel" in
        */SKILL.md|*/rules/*|*/reference/*)
          key="skills::$rel"
          case "$seen" in
            *"$key"*) continue ;;
          esac
          seen="$seen $key"
          printf '%s\n' "$f"
          continue
          ;;
      esac
    fi
    printf '%s\n' "$f"
  done <<EOF
$files
EOF
}

# count-upgrade-files <change-name>
# 统计 change 涉及的「实质」文件数：调用统一 helper substantive_changed_files_list
# （排除 openspec/**、docs/superpowers/**、.cool/**、根级 .cool.yaml/.openspec.yaml、
# docs/guide/**，以及 assets/skills/ 与 assets/skills-zh/ 同名文件的 en/zh 同步对去重）。
# 统计来源：git diff --name-only <base_ref> HEAD（若 base_ref 缺失/无效，回退 git status --short）
cmd_count_upgrade_files() {
  local change_name="$1"
  validate_change_name "$change_name"

  local yaml_file base_ref
  yaml_file=$(yaml_file_for "$change_name")
  base_ref=$(yaml_field "base_ref" "$yaml_file" 2>/dev/null || true)

  local files
  if [ -n "$base_ref" ] && [ "$base_ref" != "null" ] && git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    files=$(git diff --name-only "$base_ref" HEAD 2>/dev/null || true)
  else
    files=$(git status --short 2>/dev/null | sed 's/^...//' || true)
  fi

  substantive_changed_files_list "$files" | wc -l | tr -d ' '
}

protected_branches_list() {
  local raw=""
  if [ -f ".cool/config.yaml" ]; then
    raw=$(yaml_field "protected_branches" ".cool/config.yaml" 2>/dev/null || true)
  fi
  if [ -z "$raw" ]; then
    raw="main master"
  fi
  # 支持 [a, b] 与 "a b" 两种写法
  raw="${raw#[}"
  raw="${raw%]}"
  raw="${raw//,/ }"
  printf '%s\n' "$raw"
}

cmd_branch_recommend() {
  local change_name="$1"
  local base target action
  base=$(yaml_field "base_branch" "$(yaml_file_for "$change_name")" 2>/dev/null || true)
  if [ -z "$base" ] || [ "$base" = "null" ]; then
    base=""
  fi

  local protected
  protected="$(protected_branches_list)"

  is_protected() {
    local b="$1"
    case " $protected " in
      *" $b "*) return 0 ;;
    esac
    return 1
  }

  if [ -n "$base" ]; then
    target="$base"
    if is_protected "$base"; then
      action="pr"
    else
      action="merge-local"
    fi
  else
    # base 缺失（open 阶段沿用非保护主分支）：推荐 keep 当前分支
    target="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    action="keep"
  fi

  printf 'target: %s\n' "$target"
  printf 'action: %s\n' "$action"
}

# Validate a user-supplied branch name: reject leading dash (git arg injection),
# empty, and disallowed characters.
validate_branch_name() {
  local b="$1"
  if [ -z "$b" ]; then
    red "ERROR: branch name is empty" >&2
    exit 1
  fi
  case "$b" in
    -*) red "ERROR: branch name must not start with '-': '$b'" >&2; exit 1 ;;
  esac
  if ! printf '%s' "$b" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9/_.-]*$'; then
    red "ERROR: invalid branch name '$b' (allowed: [A-Za-z0-9][A-Za-z0-9/_.-]*)" >&2
    exit 1
  fi
}

# open-branch <change-name> [--branch <name>]
# Called by cool-open before creating artifacts. Detects protected branch,
# records base_branch/open_branch, switches to a feature branch when on a
# protected branch, or reuses the current non-protected branch. Idempotent.
cmd_open_branch() {
  local change_name="$1"
  shift || true
  validate_change_name "$change_name"

  local yaml_file
  yaml_file=$(yaml_file_for "$change_name")
  if [ ! -f "$yaml_file" ]; then
    red "ERROR: .cool.yaml not found at $yaml_file"
    exit 1
  fi

  # Idempotent: open_branch already recorded
  local existing
  existing=$(yaml_field "open_branch" "$yaml_file" 2>/dev/null || true)
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    printf 'ACTION: skip (already branched: %s)\n' "$existing"
    return 0
  fi

  # Parse --branch <name>
  local branch_name=""
  local got_branch=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)
        shift
        if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
          red "ERROR: --branch requires a value" >&2
          exit 1
        fi
        branch_name="$1"
        got_branch=1
        ;;
      *)
        red "ERROR: unknown argument: $1" >&2
        exit 1
        ;;
    esac
    shift || true
  done

  # Require git workspace with a checked-out branch
  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    red "ERROR: not a git repo (or no HEAD). /cool-open requires a git workspace." >&2
    exit 1
  fi
  local cur
  cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ -z "$cur" ] || [ "$cur" = "HEAD" ]; then
    red "ERROR: detached HEAD. Please checkout a branch before /cool-open." >&2
    exit 1
  fi

  # Protected branch detection (reuse shared helper)
  local protected
  protected="$(protected_branches_list)"
  is_protected() {
    local b="$1"
    case " $protected " in
      *" $b "*) return 0 ;;
    esac
    return 1
  }

  if is_protected "$cur"; then
    # On a protected branch: must switch to a new feature branch
    if [ -z "$branch_name" ]; then
      red "ERROR: current branch '$cur' is protected. --branch <name> is required." >&2
      exit 1
    fi
    validate_branch_name "$branch_name"
    # Switch FIRST; only record state after checkout succeeds (avoids recording
    # a non-existent branch and idempotent-reentry deadlock on checkout failure).
    if ! git checkout -b "$branch_name" >/dev/null 2>&1; then
      red "ERROR: git checkout -b '$branch_name' failed (state unchanged)" >&2
      exit 1
    fi
    cmd_set "$change_name" base_branch "$cur"
    cmd_set "$change_name" open_branch "$branch_name"
    printf 'ACTION: created\nBRANCH: %s\nBASE: %s\n' "$branch_name" "$cur"
  else
    # Already on a non-protected branch: reuse it
    if [ "$got_branch" = "1" ]; then
      yellow "WARNING: --branch '$branch_name' ignored (current branch '$cur' is not protected; reusing)" >&2
    fi
    cmd_set "$change_name" base_branch null
    cmd_set "$change_name" open_branch "$cur"
    printf 'ACTION: reuse\nBRANCH: %s\n' "$cur"
  fi
}

# --- Main ---

SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
  init)
    if [ $# -lt 2 ]; then
      red "Usage: cool-state.sh init <change-name> <workflow>" >&2
      red "Workflows: full, hotfix, tweak" >&2
      exit 1
    fi
    cmd_init "$@"
    ;;
  get)
    if [ $# -lt 2 ]; then
      red "Usage: cool-state.sh get <change-name> <field>" >&2
      exit 1
    fi
    cmd_get "$@"
    ;;
  set)
    if [ $# -lt 3 ]; then
      red "Usage: cool-state.sh set <change-name> <field> <value>" >&2
      exit 1
    fi
    cmd_set "$@"
    ;;
  transition)
    if [ $# -lt 2 ]; then
      red "Usage: cool-state.sh transition <change-name> <event>" >&2
      red "Events: open-complete, design-complete, build-complete, verify-pass, verify-fail, archive-reopen, archived" >&2
      exit 1
    fi
    cmd_transition "$@"
    ;;
  check)
    if [ $# -lt 2 ]; then
      red "Usage: cool-state.sh check <change-name> <phase> [--recover]" >&2
      red "Phases: open, design, build, verify, archive" >&2
      exit 1
    fi
    # Detect --recover flag (3rd argument)
    if [ "${3:-}" = "--recover" ]; then
      cmd_recover "$1"
    else
      cmd_check "$@"
    fi
    ;;
  scale)
    if [ $# -lt 1 ]; then
      red "Usage: cool-state.sh scale <change-name>" >&2
      exit 1
    fi
    cmd_scale "$@"
    ;;
  next)
    if [ $# -lt 1 ]; then
      red "Usage: cool-state.sh next <change-name>" >&2
      exit 1
    fi
    cmd_next "$@"
    ;;
  abspath)
    cmd_abspath "$@"
    ;;
  decision)
    if [ $# -lt 2 ]; then
      red "Usage: cool-state.sh decision <change-name> <point>" >&2
      exit 1
    fi
    cmd_decision "$@"
    ;;
  gate)
    if [ $# -lt 2 ]; then
      red "Usage: cool-state.sh gate <change-name> <point>" >&2
      exit 1
    fi
    cmd_gate "$@"
    ;;
  count-upgrade-files)
    if [ $# -lt 1 ]; then
      red "Usage: cool-state.sh count-upgrade-files <change-name>" >&2
      exit 1
    fi
    cmd_count_upgrade_files "$@"
    ;;
  __internal-list-substantive)
    substantive_changed_files_list "$(cat)"
    ;;
  review-log)
    if [ $# -lt 4 ]; then
      red "Usage: cool-state.sh review-log <change-name> <point> <round> <result> [issue]" >&2
      exit 1
    fi
    cmd_review_log "$@"
    ;;
  branch-recommend)
    if [ $# -lt 1 ]; then
      red "Usage: cool-state.sh branch-recommend <change-name>" >&2
      exit 1
    fi
    cmd_branch_recommend "$@"
    ;;
  open-branch)
    if [ $# -lt 1 ]; then
      red "Usage: cool-state.sh open-branch <change-name> [--branch <name>]" >&2
      exit 1
    fi
    cmd_open_branch "$@"
    ;;
  *)
    red "Unknown subcommand: $SUBCOMMAND" >&2
    echo "" >&2
    echo "Usage: cool-state.sh <subcommand> <change-name> [args...]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  init <change-name> <workflow>  — Initialize .cool.yaml with workflow defaults" >&2
    echo "  get <change-name> <field>       — Read a field value from .cool.yaml" >&2
    echo "  set <change-name> <field> <val> — Update a field value in .cool.yaml" >&2
    echo "  transition <change-name> <event> — Apply a validated state transition" >&2
    echo "  check <change-name> <phase>    — Verify entry requirements for a phase" >&2
    echo "  scale <change-name>             — Assess and set verification mode based on metrics" >&2
    echo "  next <change-name>              — Resolve the next workflow step (auto/manual/done)" >&2
    echo "  abspath [path]               — Resolve a path to absolute (repo root based)" >&2
    echo "  decision <change-name> <point>  — auto|block under current decision_mode" >&2
    echo "  gate <change-name> <point>       — Output PROCEED/REVIEW/BLOCK + write pending_decision" >&2
    echo "  count-upgrade-files <change-name> — Count substantive changed files (D5: excludes en/zh sync pairs + docs/guide)" >&2
    echo "  review-log <change-name> <point> <round> <result> [issue] — Append a review record to .cool/handoff/review-log.md" >&2
    echo "  branch-recommend <change-name> — Emit target+action for branch handling" >&2
    echo "  open-branch <change-name> [--branch <name>] — Detect protected branch, record base/open_branch, switch or reuse" >&2
    echo "" >&2
    echo "Workflows: full, hotfix, tweak" >&2
    echo "Phases for check: open, design, build, verify, archive" >&2
    exit 1
    ;;
esac
