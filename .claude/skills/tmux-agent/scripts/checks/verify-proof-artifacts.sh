#!/usr/bin/env bash
set -uo pipefail

PROOF_TMPDIR=""

_cleanup_tmpdir() {
  [[ -n "$PROOF_TMPDIR" ]] && rm -rf "$PROOF_TMPDIR"
}

_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

_usage() {
  echo "usage: verify-proof-artifacts.sh [--repo PATH] [--proof-dir PATH]" >&2
}

_git_toplevel() {
  git rev-parse --show-toplevel 2>/dev/null
}

_mktemp_dir() {
  local parent="${TMPDIR:-/tmp}"
  mkdir -p "$parent" || return 1
  mktemp -d "${parent%/}/verify-proof-artifacts.XXXXXX"
}

_resolve_proof_dir() {
  local repo="$1" proof_dir="$2"
  case "$proof_dir" in
    /*) printf '%s\n' "$proof_dir" ;;
    *) printf '%s/%s\n' "$repo" "$proof_dir" ;;
  esac
}

_extract_urls() {
  local proof_dir="$1"
  [[ -d "$proof_dir" ]] || return 0
  find "$proof_dir" -maxdepth 1 -type f -name '*.md' -print | sort | while IFS= read -r md; do
    awk '
      {
        while (match($0, /https?:\/\/[^][()<>[:space:]"'"'"']+/)) {
          url = substr($0, RSTART, RLENGTH)
          gsub(/[),.;]+$/, "", url)
          if (url ~ /\.(png|jpg|jpeg|gif|webp)(\?|$)/ ||
              url ~ /user-attachments\/assets\// ||
              url ~ /releases\/download\// ||
              url ~ /gist/) {
            print url
          }
          $0 = substr($0, RSTART + RLENGTH)
        }
      }
    ' "$md"
  done
}

_url_basename() {
  local url="$1"
  local clean="${url%%\?*}"
  clean="${clean%/}"
  clean="${clean##*/}"
  [[ -n "$clean" ]] || clean="proof-image"
  printf '%s\n' "$clean"
}

_download_release_url() {
  local url="$1" dest_dir="$2"
  [[ "$url" == https://github.com/*/releases/download/* ]] || return 1

  local path owner repo tag asset
  path="${url#https://github.com/}"
  owner="${path%%/*}"
  path="${path#*/}"
  repo="${path%%/*}"
  path="${path#*/releases/download/}"
  tag="${path%%/*}"
  asset="${path#*/}"
  asset="${asset%%\?*}"
  [[ -n "$owner" && -n "$repo" && -n "$tag" && -n "$asset" ]] || return 1

  gh release download "$tag" --repo "$owner/$repo" --pattern "$asset" --dir "$dest_dir" >/dev/null 2>&1
}

_download_url() {
  local url="$1" dest="$2" tmp="$3"
  case "$url" in
    file://*)
      cp "${url#file://}" "$dest" 2>/dev/null
      return $?
      ;;
  esac

  local release_dir="$tmp/release-download"
  mkdir -p "$release_dir" || return 1
  if _download_release_url "$url" "$release_dir"; then
    local downloaded
    downloaded=$(find "$release_dir" -type f -maxdepth 1 -print | head -1)
    if [[ -n "$downloaded" && -f "$downloaded" ]]; then
      cp "$downloaded" "$dest" 2>/dev/null
      return $?
    fi
  fi

  command -v gh >/dev/null 2>&1 || return 1
  gh api "$url" > "$dest" 2>/dev/null
}

_image_is_real() {
  local path="$1"
  file "$path" 2>/dev/null | grep -qi 'image data'
}

verify_proof_artifacts_main() {
  local repo="" proof_dir="docs/proof"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        repo="$2"
        shift 2
        ;;
      --proof-dir)
        [[ $# -ge 2 ]] || { _usage; return 2; }
        proof_dir="$2"
        shift 2
        ;;
      --run-dir)
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
        _usage
        return 2
        ;;
    esac
  done

  if [[ -z "$repo" ]]; then
    repo=$(_git_toplevel)
  fi
  if [[ -z "$repo" || ! -d "$repo" ]]; then
    echo "ERROR: repo not found" >&2
    return 2
  fi

  local resolved_proof_dir
  resolved_proof_dir=$(_resolve_proof_dir "$repo" "$proof_dir")
  [[ -d "$resolved_proof_dir" ]] || return 0

  local tmp
  tmp=$(_mktemp_dir) || {
    echo "ERROR: failed to create temporary proof directory" >&2
    return 1
  }
  PROOF_TMPDIR="$tmp"
  trap _cleanup_tmpdir EXIT

  local script_dir
  script_dir=$(_script_dir)

  local url filename dest blank_output
  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    filename=$(_url_basename "$url")
    dest="$tmp/$filename"
    if ! _download_url "$url" "$dest" "$tmp"; then
      echo "WARN proof-404: $url could not be downloaded"
      continue
    fi
    if [[ ! -s "$dest" ]] || ! _image_is_real "$dest"; then
      echo "WARN proof-404: $url did not download as real image data"
      continue
    fi
    blank_output=$(bash "$script_dir/verify-screenshot-not-blank.sh" "$dest")
    if [[ -n "$blank_output" ]]; then
      printf '%s\n' "$blank_output"
    fi
  done < <(_extract_urls "$resolved_proof_dir")

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_proof_artifacts_main "$@"
fi
