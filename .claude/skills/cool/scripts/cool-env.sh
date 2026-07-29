#!/bin/bash
# Cool script locator — source this file to export paths to bundled scripts.
#
# Usage:
#   . /path/to/cool/scripts/cool-env.sh
#
# This file is sourced by workflow snippets. Do not set global shell options here.

_cool_env_source="${BASH_SOURCE[0]:-$0}"
_cool_script_dir="$(cd "$(dirname "$_cool_env_source")" && pwd -P)"
_cool_env_sourced=0
(return 0 2>/dev/null) && _cool_env_sourced=1

export COOL_GUARD="${COOL_GUARD:-${_cool_script_dir}/cool-guard.sh}"
export COOL_STATE="${COOL_STATE:-${_cool_script_dir}/cool-state.sh}"
export COOL_HANDOFF="${COOL_HANDOFF:-${_cool_script_dir}/cool-handoff.sh}"
export COOL_ARCHIVE="${COOL_ARCHIVE:-${_cool_script_dir}/cool-archive.sh}"
export COOL_YAML_VALIDATE="${COOL_YAML_VALIDATE:-${_cool_script_dir}/cool-yaml-validate.sh}"
export COOL_NOTIFY="${COOL_NOTIFY:-${_cool_script_dir}/cool-notify.sh}"
export COOL_EXTENSION_SH="${COOL_EXTENSION_SH:-${_cool_script_dir}/cool-extension.sh}"

_cool_bash_is_usable() {
  local _cool_bash_candidate="$1"
  if [ -z "$_cool_bash_candidate" ]; then
    return 1
  fi
  case "$_cool_bash_candidate" in
    */Windows/System32/bash.exe|*/windows/system32/bash.exe|*\\Windows\\System32\\bash.exe|*\\windows\\system32\\bash.exe)
      return 1
      ;;
  esac
  "$_cool_bash_candidate" -lc 'printf cool-bash-ok' >/dev/null 2>&1
}

_cool_resolve_bash() {
  local _cool_bash_candidate

  if _cool_bash_is_usable "${COOL_BASH:-}"; then
    printf '%s\n' "$COOL_BASH"
    return 0
  fi

  if _cool_bash_is_usable "${BASH:-}"; then
    printf '%s\n' "$BASH"
    return 0
  fi

  _cool_bash_candidate="$(command -v sh 2>/dev/null | awk '{ sub(/\/sh(\.exe)?$/, "/bash.exe"); print }')"
  if _cool_bash_is_usable "$_cool_bash_candidate"; then
    printf '%s\n' "$_cool_bash_candidate"
    return 0
  fi

  _cool_bash_candidate="$(command -v bash 2>/dev/null || true)"
  if _cool_bash_is_usable "$_cool_bash_candidate"; then
    printf '%s\n' "$_cool_bash_candidate"
    return 0
  fi

  return 1
}

COOL_BASH="$(_cool_resolve_bash || true)"
export COOL_BASH

_cool_env_fail() {
  echo "ERROR: Cool scripts not found. Ensure the cool skill is installed completely." >&2
  echo "Expected path pattern: */cool/scripts/cool-*.sh under project or platform skill directories" >&2
}

_cool_bash_fail() {
  echo "ERROR: usable bash not found. Install Git Bash or set COOL_BASH to a working bash executable." >&2
  echo "Windows WSL launcher bash.exe is not supported for Cool scripts." >&2
}

_cool_env_abort() {
  local _cool_env_was_sourced="$_cool_env_sourced"
  unset _cool_env_source _cool_script_dir _cool_script _cool_env_missing _cool_env_sourced
  unset _cool_bash_candidate
  unset -f _cool_env_fail _cool_bash_fail _cool_bash_is_usable _cool_resolve_bash
  if [ "$_cool_env_was_sourced" -eq 1 ]; then
    unset -f _cool_env_abort
    return 1
  fi
  exit 1
}

_cool_env_missing=0
if [ -z "$COOL_BASH" ]; then
  _cool_bash_fail
  _cool_env_missing=1
fi
for _cool_script in \
  "$COOL_GUARD" \
  "$COOL_STATE" \
  "$COOL_HANDOFF" \
  "$COOL_ARCHIVE" \
  "$COOL_YAML_VALIDATE" \
  "$COOL_NOTIFY" \
  "$COOL_EXTENSION_SH"; do
  if [ ! -f "$_cool_script" ]; then
    _cool_env_fail
    _cool_env_missing=1
    break
  fi
done

if [ "$_cool_env_missing" -ne 0 ]; then
  _cool_env_abort
else
  unset _cool_env_source _cool_script_dir _cool_script _cool_env_missing _cool_env_sourced
  unset _cool_bash_candidate
  unset -f _cool_env_fail _cool_bash_fail _cool_bash_is_usable _cool_resolve_bash _cool_env_abort
fi
