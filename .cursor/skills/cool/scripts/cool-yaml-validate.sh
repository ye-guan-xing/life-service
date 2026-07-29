#!/bin/bash
# Cool YAML Schema Validator — validates .cool.yaml structure
# Usage: cool-yaml-validate.sh <change-name>
# Exit 0 = valid, exit 1 = errors found (printed to stderr)

set -euo pipefail

red()   { echo -e "\033[31m$1\033[0m" >&2; }
green() { echo -e "\033[32m$1\033[0m" >&2; }
warn()  { echo -e "\033[33m$1\033[0m" >&2; }

# Input validation - prevent path traversal
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

validate_change_name "$1"

CHANGE="$1"
CHANGE_DIR="openspec/changes/$CHANGE"
if [ ! -d "$CHANGE_DIR" ] && [ -d "openspec/changes/archive/$CHANGE" ]; then
  CHANGE_DIR="openspec/changes/archive/$CHANGE"
fi
YAML="$CHANGE_DIR/.cool.yaml"

ERRORS=0
WARNINGS=0

# Helper: get value of a top-level field (handles null, empty, quoted)
field_value() {
  local value
  value=$(grep "^${1}:" "$YAML" 2>/dev/null | sed "s/^${1}: *//" || true)
  value=$(strip_inline_comment "$value")
  strip_wrapping_quotes "$value"
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

fail()  { red "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn_msg() { warn "  WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

echo "[VALIDATE] $YAML" >&2

# --- Required fields ---
REQUIRED_FIELDS="workflow phase design_doc plan build_mode isolation verify_mode verify_result verified_at archived review_mode review_result"
for field in $REQUIRED_FIELDS; do
  if ! grep -q "^${field}:" "$YAML" 2>/dev/null; then
    fail "missing required field '$field'"
  fi
done

# --- Enum validation ---
validate_enum() {
  local field="$1" value="$2"
  shift 2
  local valid_values="$*"

  # null or empty is always acceptable
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    return 0
  fi

  for v in $valid_values; do
    if [ "$value" = "$v" ]; then
      return 0
    fi
  done
  fail "$field='$value' is not valid. Expected: $valid_values"
}

validate_required_enum() {
  local field="$1" value="$2"
  shift 2
  local valid_values="$*"

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    fail "$field='${value:-}' is not valid. Expected: $valid_values"
    return 0
  fi

  validate_enum "$field" "$value" "$@"
}

workflow=$(field_value "workflow")
phase=$(field_value "phase")
context_compression=$(field_value "context_compression")
build_mode=$(field_value "build_mode")
build_pause=$(field_value "build_pause")
subagent_dispatch=$(field_value "subagent_dispatch")
tdd_mode=$(field_value "tdd_mode")
isolation=$(field_value "isolation")
verify_mode=$(field_value "verify_mode")
auto_transition=$(field_value "auto_transition")
verify_result=$(field_value "verify_result")
branch_status=$(field_value "branch_status")
archived=$(field_value "archived")
direct_override=$(field_value "direct_override")
design_doc=$(field_value "design_doc")
plan=$(field_value "plan")
handoff_context=$(field_value "handoff_context")
handoff_hash=$(field_value "handoff_hash")

validate_enum "workflow"      "$workflow"      "full hotfix tweak"
validate_enum "phase"         "$phase"          "open design build review verify archive"
validate_enum "context_compression" "$context_compression" "off beta"
validate_enum "build_mode"    "$build_mode"     "subagent-driven-development executing-plans direct"
validate_enum "build_pause"   "$build_pause"     "null plan-ready"
validate_enum "subagent_dispatch" "$subagent_dispatch" "null confirmed"
validate_enum "tdd_mode"      "$tdd_mode"       "tdd direct null"
validate_enum "isolation"     "$isolation"      "branch worktree"
validate_enum "verify_mode"   "$verify_mode"    "light full"
if grep -q "^auto_transition:" "$YAML" 2>/dev/null; then
  validate_required_enum "auto_transition" "$auto_transition" "true false"
fi
if grep -q "^decision_mode:" "$YAML" 2>/dev/null; then
  validate_required_enum "decision_mode" "$(field_value "decision_mode")" "manual recommend"
fi
validate_enum "verify_result" "$verify_result"  "pending pass fail"

review_mode=$(field_value "review_mode")
review_result=$(field_value "review_result")

validate_enum "review_mode" "$review_mode"    "full light skip"
validate_enum "review_result" "$review_result" "pending pass fail"

validate_enum "branch_status" "$branch_status"  "pending handled"
validate_enum "archived"      "$archived"       "true false"
validate_enum "direct_override" "$direct_override" "true false"

# pending_decision: null 或已命名 decision point
if grep -q "^pending_decision:" "$YAML" 2>/dev/null; then
  pd="$(field_value "pending_decision")"
  if [ -n "$pd" ] && [ "$pd" != "null" ]; then
    case "$pd" in
      archive|discard|verify-critical|verify-fail-limit|spec-contradiction|context-compaction|\
      clarify-review|open-review|design-review|plan-ready|plan-review|build-config|scope-split-review|\
      verify-drift-review|verify-fail-decision|tweak-upgrade|hotfix-upgrade|\
      intent|branch-name|change-name|finishing-branch|subagent-dispatch|platform-capability)
        ;;
      *)
        fail "pending_decision='$pd' is not a known decision point"
        ;;
    esac
  fi
fi

# --- Path validation ---

if [ -n "$design_doc" ] && [ "$design_doc" != "null" ]; then
  if [ ! -f "$design_doc" ]; then
    fail "design_doc='$design_doc' does not exist on disk"
  fi
fi

if [ -n "$plan" ] && [ "$plan" != "null" ]; then
  if [ ! -f "$plan" ]; then
    fail "plan='$plan' does not exist on disk"
  fi
fi

if [ -n "$handoff_context" ] && [ "$handoff_context" != "null" ]; then
  if [ ! -f "$handoff_context" ]; then
    fail "handoff_context='$handoff_context' does not exist on disk"
  fi
fi

if [ -n "$handoff_hash" ] && [ "$handoff_hash" != "null" ]; then
  if [[ ! "$handoff_hash" =~ ^[a-f0-9]{64}$ ]]; then
    fail "handoff_hash='$handoff_hash' is not a sha256 hex digest"
  fi
fi

# --- extensions section boundary guard ---
# extensions 节属 project 级 .cool/config.yaml，不应出现在 per-change .cool.yaml。
# 字段级校验由 cool-extension validate（运行时）承担；此处仅守边界。
if grep -q "^extensions:" "$YAML" 2>/dev/null; then
  warn_msg "extensions section belongs in .cool/config.yaml, not per-change .cool.yaml"
fi

# --- Unknown keys check ---
KNOWN_KEYS="workflow phase context_compression design_doc plan build_mode build_pause subagent_dispatch tdd_mode isolation verify_mode auto_transition verify_result verification_report branch_status verified_at created_at archived direct_override build_command verify_command handoff_context handoff_hash base_ref review_mode review_result review_report review_fail_count decision_mode base_branch pending_decision"
while IFS=: read -r key _; do
  key="${key// /}"
  [ -z "$key" ] && continue
  found=0
  for known in $KNOWN_KEYS; do
    [ "$key" = "$known" ] && found=1 && break
  done
  if [ "$found" -eq 0 ]; then
    warn_msg "unknown field '$key' found"
  fi
done < "$YAML"

# --- Summary ---
echo "" >&2
if [ "$ERRORS" -gt 0 ]; then
  red "$ERRORS error(s), $WARNINGS warning(s) — validation FAILED"
  exit 1
else
  green "0 errors, $WARNINGS warning(s) — validation PASSED"
  exit 0
fi
