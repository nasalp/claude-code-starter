#!/usr/bin/env bash
set -uo pipefail

_usage() {
  echo "usage: verify-screenshot-not-blank.sh [--repo PATH] IMAGE_PATH" >&2
}

_image_is_real() {
  local image="$1"
  file "$image" 2>/dev/null | grep -qi 'image data'
}

_vision_verdict() {
  local image="$1"
  [[ "${AUDIT_DISABLE_VISION:-}" == "1" ]] && return 2
  command -v claude >/dev/null 2>&1 || return 2

  local prompt
  prompt=$(cat <<EOF
Inspect this screenshot file: $image

Answer with exactly one word:
- POPULATED if it shows a populated UI or chart with meaningful visual content.
- BLANK if it is empty, near-empty, or only contains axes/placeholders.
EOF
)
  local output
  output=$(printf '%s\n' "$prompt" | claude --print --model haiku --tools default 2>/dev/null)
  case "$output" in
    *BLANK*|*blank*) return 1 ;;
    *POPULATED*|*populated*) return 0 ;;
    *) return 2 ;;
  esac
}

_unique_color_count() {
  local image="$1"
  command -v magick >/dev/null 2>&1 || return 2

  local count
  count=$(magick "$image" -format '%k' info: 2>/dev/null)
  if [[ "$count" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$count"
    return 0
  fi

  count=$(magick "$image" -unique-colors txt:- 2>/dev/null | awk 'NR > 1 { n++ } END { print n + 0 }')
  [[ "$count" =~ ^[0-9]+$ ]] || return 2
  printf '%s\n' "$count"
}

verify_screenshot_main() {
  local repo_arg="" image=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo_arg="$2"
        shift 2
        ;;
      --proof-dir|--run-dir)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        shift 2
        ;;
      --help|-h)
        _usage
        return 0
        ;;
      --*)
        echo "unknown flag: $1" >&2
        return 2
        ;;
      *)
        image="$1"
        shift
        ;;
    esac
  done
  : "${repo_arg:=}"

  if [[ -z "$image" ]]; then
    _usage
    return 2
  fi
  if [[ ! -f "$image" ]]; then
    echo "ERROR: image not found: $image" >&2
    return 2
  fi
  if ! _image_is_real "$image"; then
    echo "WARN proof-blank: $image is not recognized as image data"
    return 0
  fi

  _vision_verdict "$image"
  local vision_rc=$?
  case "$vision_rc" in
    0) return 0 ;;
    1)
      echo "WARN proof-blank: $image appears blank by vision inspection"
      return 0
      ;;
  esac

  local colors
  colors=$(_unique_color_count "$image")
  local color_rc=$?
  if [[ "$color_rc" -ne 0 ]]; then
    return 0
  fi
  if (( colors < 5 )); then
    echo "WARN proof-blank: $image has $colors unique colors"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_screenshot_main "$@"
fi
