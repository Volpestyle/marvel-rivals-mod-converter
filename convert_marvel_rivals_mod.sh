#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Convert a legacy Marvel Rivals mod (loose Content assets) to new ~mods IoStore format.

Usage:
  ./convert_marvel_rivals_mod.sh <input_path> [options]

Required:
  <input_path>                Legacy mod folder or .zip (must contain Content/... files)

Options:
  --output-dir <dir>          Output directory (default: ./converted_mods)
  --name <mod_name>           Base name for output files (default: derived from input)
  --retoc <path>              Path to retoc.exe (default: auto-detect)
  --version <ue_version>      retoc engine version (default: UE5_3)
  --install                   Copy output files into game ~mods folder after convert
  --mods-dir <path>           Override install folder for --install
  -h, --help                  Show this help

Examples:
  ./convert_marvel_rivals_mod.sh old_mod
  ./convert_marvel_rivals_mod.sh old_mod.zip --name MySkin --install
  ./convert_marvel_rivals_mod.sh old_mod --retoc "/mnt/c/Users/me/Downloads/retoc-x86_64-pc-windows-msvc/retoc.exe"
EOF
}

err() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing required command: $1"
}

to_wsl_path_if_windows() {
  local p="$1"
  if [[ "$p" =~ ^[A-Za-z]:[\\/].* ]]; then
    wslpath -u "$p"
  else
    echo "$p"
  fi
}

find_retoc() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    [[ -f "$explicit" ]] || err "retoc.exe not found at: $explicit"
    echo "$explicit"
    return 0
  fi

  local candidates=(
    "$PWD/retoc.exe"
    "$HOME/Downloads/retoc-x86_64-pc-windows-msvc/retoc.exe"
    "/mnt/c/Users/${USER}/Downloads/retoc-x86_64-pc-windows-msvc/retoc.exe"
    "/mnt/c/Users/volpe/Downloads/retoc-x86_64-pc-windows-msvc/retoc.exe"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done

  if command -v retoc.exe >/dev/null 2>&1; then
    command -v retoc.exe
    return 0
  fi

  err "Could not locate retoc.exe. Pass it explicitly with --retoc."
}

sanitize_name() {
  local n="$1"
  n="${n%.zip}"
  n="${n%.utoc}"
  n="${n%.ucas}"
  n="${n%.pak}"
  n="${n%_9999999_P}"
  n="${n%_9999999}"
  n="${n%_P}"
  # Keep only safe filename characters.
  n="$(echo "$n" | tr -cs '[:alnum:]_.-' '_')"
  n="${n##_}"
  n="${n%%_}"
  [[ -n "$n" ]] || err "Could not derive a valid mod name. Pass --name explicitly."
  echo "${n}_9999999_P"
}

INPUT_PATH=""
OUTPUT_DIR="$PWD/converted_mods"
MOD_NAME=""
RETOC_PATH=""
ENGINE_VERSION="UE5_3"
INSTALL="false"
MODS_DIR="/mnt/c/Program Files (x86)/Steam/steamapps/common/MarvelRivals/MarvelGame/Marvel/Content/Paks/~mods"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || err "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || err "--name requires a value"
      MOD_NAME="$2"
      shift 2
      ;;
    --retoc)
      [[ $# -ge 2 ]] || err "--retoc requires a value"
      RETOC_PATH="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || err "--version requires a value"
      ENGINE_VERSION="$2"
      shift 2
      ;;
    --install)
      INSTALL="true"
      shift
      ;;
    --mods-dir)
      [[ $# -ge 2 ]] || err "--mods-dir requires a value"
      MODS_DIR="$2"
      shift 2
      ;;
    --*)
      err "Unknown option: $1"
      ;;
    *)
      if [[ -z "$INPUT_PATH" ]]; then
        INPUT_PATH="$1"
        shift
      else
        err "Unexpected argument: $1"
      fi
      ;;
  esac
done

[[ -n "$INPUT_PATH" ]] || {
  usage
  exit 1
}

require_cmd wslpath
require_cmd unzip

INPUT_PATH="$(to_wsl_path_if_windows "$INPUT_PATH")"
OUTPUT_DIR="$(to_wsl_path_if_windows "$OUTPUT_DIR")"
MODS_DIR="$(to_wsl_path_if_windows "$MODS_DIR")"
if [[ -n "$RETOC_PATH" ]]; then
  RETOC_PATH="$(to_wsl_path_if_windows "$RETOC_PATH")"
fi

if [[ ! -e "$INPUT_PATH" ]]; then
  err "Input does not exist: $INPUT_PATH"
fi

TMP_DIR=""
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

WORK_INPUT="$INPUT_PATH"
if [[ -f "$INPUT_PATH" ]]; then
  case "${INPUT_PATH,,}" in
    *.zip)
      TMP_DIR="$(mktemp -d)"
      unzip -q -o "$INPUT_PATH" -d "$TMP_DIR"
      WORK_INPUT="$TMP_DIR"
      ;;
    *)
      err "Input file must be a .zip, or provide a directory."
      ;;
  esac
fi

[[ -d "$WORK_INPUT" ]] || err "Input is not a directory after extraction: $WORK_INPUT"

# Normalize expected legacy layout:
#  - If user passes .../Content, move up one level.
#  - If user passes root with Content/, keep root.
if [[ "$(basename "$WORK_INPUT")" == "Content" ]]; then
  WORK_INPUT="$(dirname "$WORK_INPUT")"
fi

if ! find "$WORK_INPUT" -type f \( -iname '*.uasset' -o -iname '*.uexp' -o -iname '*.ubulk' \) -print -quit | grep -q .; then
  err "No .uasset/.uexp/.ubulk files found under: $WORK_INPUT"
fi

RETOC_PATH="$(find_retoc "$RETOC_PATH")"

if [[ -z "$MOD_NAME" ]]; then
  MOD_NAME="$(basename "${INPUT_PATH%/}")"
fi
MOD_NAME="$(sanitize_name "$MOD_NAME")"

mkdir -p "$OUTPUT_DIR"

OUT_UTOC="$OUTPUT_DIR/${MOD_NAME}.utoc"
OUT_UCAS="$OUTPUT_DIR/${MOD_NAME}.ucas"
OUT_PAK="$OUTPUT_DIR/${MOD_NAME}.pak"

WORK_INPUT_W="$(wslpath -w "$WORK_INPUT")"
OUT_UTOC_W="$(wslpath -w "$OUT_UTOC")"

echo "Converting with retoc..."
echo "  input:   $WORK_INPUT"
echo "  output:  $OUT_UTOC"
echo "  version: $ENGINE_VERSION"
echo "  retoc:   $RETOC_PATH"

"$RETOC_PATH" to-zen --version "$ENGINE_VERSION" "$WORK_INPUT_W" "$OUT_UTOC_W"

[[ -s "$OUT_UTOC" ]] || err "Missing output: $OUT_UTOC"
[[ -s "$OUT_UCAS" ]] || err "Missing output: $OUT_UCAS"
[[ -s "$OUT_PAK" ]] || err "Missing output: $OUT_PAK"

echo
echo "Created:"
echo "  $OUT_PAK"
echo "  $OUT_UCAS"
echo "  $OUT_UTOC"
echo

if [[ "$INSTALL" == "true" ]]; then
  mkdir -p "$MODS_DIR"
  cp -f "$OUT_PAK" "$OUT_UCAS" "$OUT_UTOC" "$MODS_DIR"/
  echo "Installed to:"
  echo "  $MODS_DIR"
  echo
fi

echo "Container info:"
"$RETOC_PATH" info "$(wslpath -w "$OUT_UTOC")" | sed -n '1,20p'

echo
echo "Done."
