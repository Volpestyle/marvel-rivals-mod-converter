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
  --project-name <name>       Unreal project folder name used for staging (default: Marvel)
  --retarget-from <id>        Optional cooked-ID string to replace in paths and package metadata
  --retarget-to <id>          Replacement for --retarget-from (must be same length)
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
PROJECT_NAME="Marvel"
RETARGET_FROM=""
RETARGET_TO=""
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
    --project-name)
      [[ $# -ge 2 ]] || err "--project-name requires a value"
      PROJECT_NAME="$2"
      shift 2
      ;;
    --retarget-from)
      [[ $# -ge 2 ]] || err "--retarget-from requires a value"
      RETARGET_FROM="$2"
      shift 2
      ;;
    --retarget-to)
      [[ $# -ge 2 ]] || err "--retarget-to requires a value"
      RETARGET_TO="$2"
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

if [[ -n "$RETARGET_FROM" || -n "$RETARGET_TO" ]]; then
  [[ -n "$RETARGET_FROM" && -n "$RETARGET_TO" ]] || err "Use --retarget-from and --retarget-to together."
  [[ "${#RETARGET_FROM}" -eq "${#RETARGET_TO}" ]] || err "--retarget-from and --retarget-to must have equal length."
fi

if [[ ! -e "$INPUT_PATH" ]]; then
  err "Input does not exist: $INPUT_PATH"
fi

TMP_DIR=""
STAGE_DIR=""
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
  if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
    rm -rf "$STAGE_DIR"
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

CONTENT_SRC=""
if [[ -d "$WORK_INPUT/Content" ]]; then
  CONTENT_SRC="$WORK_INPUT/Content"
elif [[ "$(basename "$WORK_INPUT")" == "Content" && -d "$WORK_INPUT" ]]; then
  CONTENT_SRC="$WORK_INPUT"
else
  # Accept one nested project folder like <root>/<ProjectName>/Content
  CANDIDATE="$(find "$WORK_INPUT" -mindepth 2 -maxdepth 2 -type d -name Content | head -n 1 || true)"
  if [[ -n "$CANDIDATE" ]]; then
    CONTENT_SRC="$CANDIDATE"
  fi
fi

[[ -n "$CONTENT_SRC" && -d "$CONTENT_SRC" ]] || err "Could not locate a Content folder under: $WORK_INPUT"

RETOC_PATH="$(find_retoc "$RETOC_PATH")"

if [[ -z "$MOD_NAME" ]]; then
  MOD_NAME="$(basename "${INPUT_PATH%/}")"
fi
MOD_NAME="$(sanitize_name "$MOD_NAME")"

mkdir -p "$OUTPUT_DIR"

OUT_UTOC="$OUTPUT_DIR/${MOD_NAME}.utoc"
OUT_UCAS="$OUTPUT_DIR/${MOD_NAME}.ucas"
OUT_PAK="$OUTPUT_DIR/${MOD_NAME}.pak"

# Stage into <ProjectName>/Content so output filename paths match typical game layout.
STAGE_DIR="$(mktemp -d)"
mkdir -p "$STAGE_DIR/$PROJECT_NAME"
cp -r "$CONTENT_SRC" "$STAGE_DIR/$PROJECT_NAME/Content"

if [[ -n "$RETARGET_FROM" ]]; then
  RETARGET_ROOT="$STAGE_DIR/$PROJECT_NAME/Content"
  echo "Retargeting IDs in staged content:"
  echo "  from: $RETARGET_FROM"
  echo "  to:   $RETARGET_TO"

  # 1) Move files to rewritten paths (handles both folder and file name retargeting).
  RENAME_COUNT=0
  while IFS= read -r F; do
    NEW_F="${F//$RETARGET_FROM/$RETARGET_TO}"
    if [[ "$F" != "$NEW_F" ]]; then
      mkdir -p "$(dirname "$NEW_F")"
      mv "$F" "$NEW_F"
      RENAME_COUNT=$((RENAME_COUNT + 1))
    fi
  done < <(find "$RETARGET_ROOT" -type f)

  # Remove any empty directories left after file moves.
  find "$RETARGET_ROOT" -type d -empty -delete

  # 2) Replace token inside cooked metadata files.
  PATCH_COUNT=0
  while IFS= read -r F; do
    TMP_F="${F}.tmp"
    perl -0777 -pe "s/\\Q$RETARGET_FROM\\E/$RETARGET_TO/g" "$F" > "$TMP_F"
    mv "$TMP_F" "$F"
    PATCH_COUNT=$((PATCH_COUNT + 1))
  done < <(find "$RETARGET_ROOT" -type f \( -iname '*.uasset' -o -iname '*.uexp' \))

  echo "  renamed paths: $RENAME_COUNT"
  echo "  patched files: $PATCH_COUNT"
fi

WORK_INPUT_W="$(wslpath -w "$STAGE_DIR")"
OUT_UTOC_W="$(wslpath -w "$OUT_UTOC")"

echo "Converting with retoc..."
echo "  input:   $WORK_INPUT"
echo "  staged:  $STAGE_DIR/$PROJECT_NAME/Content"
echo "  output:  $OUT_UTOC"
echo "  version: $ENGINE_VERSION"
echo "  project: $PROJECT_NAME"
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
