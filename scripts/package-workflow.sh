#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DEFAULT_OUTPUT_DIR="$REPO_ROOT/release"
DEFAULT_NAME="YoudaoTranslator"
DEFAULT_BUNDLE_ID="Youdao.Translator"
DEFAULT_WORKFLOWS_DIR="$HOME/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows"
DEFAULT_TEMPLATE_DIR="$REPO_ROOT/workflow"
DEFAULT_DIST_DIR="$REPO_ROOT/dist"

TEMP_DIR=""

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT INT TERM

usage() {
  cat <<'EOF'
Usage: ./scripts/package-workflow.sh [options]

Options:
  -v, --version VERSION   Release version. Defaults to version in package.json.
  -s, --source DIR        Alfred workflow source directory to package.
  -o, --output DIR        Output directory. Defaults to ./release
  -n, --name NAME         Output filename prefix. Defaults to YoudaoTranslator
  -h, --help              Show this help message.
EOF
}

resolve_version() {
  sed -n 's/.*"version": "\(.*\)".*/\1/p' "$REPO_ROOT/package.json" | head -n 1
}

find_workflow_dir() {
  if [ ! -d "$DEFAULT_WORKFLOWS_DIR" ]; then
    echo "Alfred workflows directory not found: $DEFAULT_WORKFLOWS_DIR" >&2
    exit 1
  fi

  latest_dir=""
  latest_mtime=0

  for info_plist in "$DEFAULT_WORKFLOWS_DIR"/*/info.plist; do
    [ -f "$info_plist" ] || continue
    bundle_id=$(plutil -extract bundleid raw -o - "$info_plist" 2>/dev/null || true)
    [ "$bundle_id" = "$DEFAULT_BUNDLE_ID" ] || continue

    workflow_dir=$(dirname "$info_plist")
    mtime=$(stat -f %m "$workflow_dir")

    if [ "$mtime" -gt "$latest_mtime" ]; then
      latest_mtime=$mtime
      latest_dir=$workflow_dir
    fi
  done

  if [ -z "$latest_dir" ]; then
    echo "No installed Alfred workflow found for bundle id $DEFAULT_BUNDLE_ID" >&2
    echo "Use --source to specify a workflow directory manually." >&2
    exit 1
  fi

  printf '%s\n' "$latest_dir"
}

assemble_repo_workflow() {
  if [ ! -d "$DEFAULT_TEMPLATE_DIR" ]; then
    echo "Workflow template directory not found: $DEFAULT_TEMPLATE_DIR" >&2
    exit 1
  fi

  if [ ! -f "$DEFAULT_DIST_DIR/index.js" ]; then
    echo "Missing build output: $DEFAULT_DIST_DIR/index.js" >&2
    echo "Run 'pnpm build' first, or pass --source to package an existing workflow directory." >&2
    exit 1
  fi

  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/youdao-workflow.XXXXXX")

  cp -R "$DEFAULT_TEMPLATE_DIR/." "$TEMP_DIR/"
  cp -R "$REPO_ROOT/assets" "$TEMP_DIR/assets"
  cp -R "$REPO_ROOT/runtime" "$TEMP_DIR/runtime"
  cp "$DEFAULT_DIST_DIR/index.js" "$TEMP_DIR/index.js"

  printf '%s\n' "$TEMP_DIR"
}

VERSION=""
SOURCE_DIR=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
NAME="$DEFAULT_NAME"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--version)
      VERSION=${2-}
      shift 2
      ;;
    -s|--source)
      SOURCE_DIR=${2-}
      shift 2
      ;;
    -o|--output)
      OUTPUT_DIR=${2-}
      shift 2
      ;;
    -n|--name)
      NAME=${2-}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION=$(resolve_version)
fi

if [ -z "$VERSION" ]; then
  echo "Unable to resolve version from package.json. Use --version." >&2
  exit 1
fi

if [ -z "$SOURCE_DIR" ]; then
  if [ -d "$DEFAULT_TEMPLATE_DIR" ]; then
    SOURCE_DIR=$(assemble_repo_workflow)
  else
    SOURCE_DIR=$(find_workflow_dir)
  fi
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Workflow source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

if [ ! -f "$SOURCE_DIR/info.plist" ]; then
  echo "Workflow source directory is missing info.plist: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
ARCHIVE_BASENAME="$NAME-$VERSION"
ZIP_PATH="$OUTPUT_DIR/$ARCHIVE_BASENAME.zip"
WORKFLOW_PATH="$OUTPUT_DIR/$ARCHIVE_BASENAME.alfredworkflow"

rm -f "$ZIP_PATH" "$WORKFLOW_PATH"

(
  cd "$SOURCE_DIR"
  zip -r "$ZIP_PATH" . \
    -x "*.DS_Store" \
    -x "runtime/txiki.bak.*" \
    -x "__MACOSX/*" >/dev/null
)

mv "$ZIP_PATH" "$WORKFLOW_PATH"

echo "Packaged workflow:"
echo "  source: $SOURCE_DIR"
echo "  output: $WORKFLOW_PATH"
