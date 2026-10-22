#!/usr/bin/env bash
# quota-preflight.sh — refuse to launch a multi-agent fleet when the primary
# provider quota is too close to the next reset.
#
#
# Usage:
#   quota-preflight.sh PROVIDER [MIN_HEADROOM_SECONDS]
#
# PROVIDER ∈ { anthropic, openai-codex, both }
# MIN_HEADROOM_SECONDS default 7200 (2h).
#
# Exit codes:
#   0 — headroom OK or unknown (graceful fallback when API unreachable)
#   1 — headroom below threshold — DO NOT launch the fleet
#   2 — usage / configuration error (e.g. provider unset)
#
# Environment:
#   ANTHROPIC_API_KEY     — used for the anthropic probe
#   OPENAI_API_KEY        — used for the codex probe
#   QUOTA_PROBE_URL       — override base URL (for tests)
#   QUOTA_PROBE_DRY_RUN=1 — skip the network probe; print the planned call
#
# Implementation note: this is a STUB. Anthropic's 5h window reset time is
# carried on the `anthropic-ratelimit-tokens-reset` response header on any
# real API call. For now we fire a 1-token completion and parse that header;
# if probe fails we exit 0 (graceful) and log the reason so the operator can
# decide. Full implementation tracked in the carry-over learning file.

set -uo pipefail

PROVIDER="${1:-}"
MIN_HEADROOM_SECONDS="${2:-7200}"

if [[ -z "$PROVIDER" ]]; then
  echo "usage: quota-preflight.sh PROVIDER [MIN_HEADROOM_SECONDS]" >&2
  echo "  PROVIDER ∈ { anthropic, openai-codex, both }" >&2
  exit 2
fi

# Compute seconds-until-reset from an ISO-8601 timestamp. Returns empty on
# parse failure. Supports both GNU date (-d) and BSD date (-j -f) forms.
_seconds_until() {
  local iso="$1"
  [[ -z "$iso" ]] && return 0
  local target_epoch now
  if target_epoch=$(date -u -d "$iso" +%s 2>/dev/null); then
    :
  elif target_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${iso%.*Z}Z" +%s 2>/dev/null); then
    :
  else
    return 0
  fi
  now=$(date -u +%s)
  echo $(( target_epoch - now ))
}

# Probe Anthropic /v1/messages with the smallest possible request and parse
# the rate-limit headers. Echoes "OK <s>" / "LOW <s>" / "UNKNOWN <reason>"
# on stdout; never exits non-zero (caller decides).
_probe_anthropic() {
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "UNKNOWN no-ANTHROPIC_API_KEY-set"
    return 0
  fi
  local url="${QUOTA_PROBE_URL:-https://api.anthropic.com}/v1/messages"
  if [[ "${QUOTA_PROBE_DRY_RUN:-0}" = 1 ]]; then
    echo "UNKNOWN dry-run (would probe $url)"
    return 0
  fi
  local hdr_file body_file
  hdr_file=$(mktemp); body_file=$(mktemp)
  curl -sS -X POST "$url" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -D "$hdr_file" -o "$body_file" \
    --max-time 10 \
    --data '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"x"}]}' \
    >/dev/null 2>&1 || {
      echo "UNKNOWN curl-failed"
      rm -f "$hdr_file" "$body_file"
      return 0
    }
  local reset
  # Split on the FIRST colon — `awk '{print $2}'` would silently drop
  # the value if the server emits the header without a space after `:`,
  # which is valid per RFC 7230.
  reset=$(grep -i '^anthropic-ratelimit-tokens-reset:' "$hdr_file" | cut -d':' -f2- | tr -d ' \r')
  rm -f "$hdr_file" "$body_file"
  if [[ -z "$reset" ]]; then
    echo "UNKNOWN no-reset-header"
    return 0
  fi
  local seconds
  seconds=$(_seconds_until "$reset")
  if [[ -z "$seconds" ]]; then
    echo "UNKNOWN unparseable-reset=$reset"
    return 0
  fi
  if (( seconds >= MIN_HEADROOM_SECONDS )); then
    echo "OK ${seconds}s"
  else
    echo "LOW ${seconds}s (need ${MIN_HEADROOM_SECONDS}s)"
  fi
}

# Codex/OpenAI probe — codex CLI doesn't expose 5h-window state; we fire a
# minimal exec and check it succeeded. Full impl is carry-over.
_probe_codex() {
  if [[ -z "${OPENAI_API_KEY:-}" ]] && [[ ! -f "${CODEX_AUTH_FILE:-$HOME/.codex/auth.json}" ]]; then
    echo "UNKNOWN no-OPENAI_API_KEY-and-no-auth-file"
    return 0
  fi
  if [[ "${QUOTA_PROBE_DRY_RUN:-0}" = 1 ]]; then
    echo "UNKNOWN dry-run (would invoke codex exec)"
    return 0
  fi
  if ! command -v codex >/dev/null 2>&1; then
    echo "UNKNOWN codex-cli-not-installed"
    return 0
  fi
  # `timeout` is GNU coreutils — not in macOS/BSD base. If absent, run
  # without it so we don't falsely report LOW.
  if command -v timeout >/dev/null 2>&1; then
    if echo "ok" | timeout 15 codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox - >/dev/null 2>&1; then
      echo "OK reachable"
    else
      echo "LOW codex-probe-failed (rate-limited or down)"
    fi
  else
    if echo "ok" | codex exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox - >/dev/null 2>&1; then
      echo "OK reachable (no timeout(1) — install coreutils for hung-probe protection)"
    else
      echo "LOW codex-probe-failed (rate-limited or down)"
    fi
  fi
}

_main() {
  local rc=0
  case "$PROVIDER" in
    anthropic)
      local r; r=$(_probe_anthropic)
      echo "anthropic: $r"
      [[ "$r" == LOW* ]] && rc=1
      ;;
    openai-codex)
      local r; r=$(_probe_codex)
      echo "openai-codex: $r"
      [[ "$r" == LOW* ]] && rc=1
      ;;
    both)
      local ra rcx
      ra=$(_probe_anthropic);  echo "anthropic: $ra"
      rcx=$(_probe_codex);     echo "openai-codex: $rcx"
      [[ "$ra" == LOW* || "$rcx" == LOW* ]] && rc=1
      ;;
    *)
      echo "ERROR: unknown PROVIDER '$PROVIDER'" >&2
      exit 2
      ;;
  esac
  return $rc
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _main
fi
