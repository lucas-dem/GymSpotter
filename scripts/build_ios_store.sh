#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/build_ios_store.sh [--dry-run] <build-name x.y.z> <build-number> https://host/path/to/exact-release-source" >&2
  exit 1
}

# --dry-run prints the exact flutter command without building.
dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

if [[ $# -ne 3 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$2" =~ ^[1-9][0-9]*$ || ! "$3" =~ ^https:// ]]; then
  usage
fi
build_name="$1"
build_number="$2"
source_url="$3"

if [[ "$dry_run" == false && "$(uname -s)" != "Darwin" ]]; then
  echo "The App Store IPA must be built on macOS with Xcode." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "$dry_run" == false ]]; then
    echo "The working tree must be clean. Commit the exact release source first." >&2
    exit 1
  fi
  echo "Dry run: the working tree is not clean; a real build would stop here."
fi

revision="$(git rev-parse HEAD)"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# The same arguments as the Codemagic store build. APP_BUILD_NAME/APP_BUILD_NUMBER must match
# --build-name/--build-number: without them the app shows the pubspec version.
args=(
  build ipa --release
  "--build-name=$build_name"
  "--build-number=$build_number"
  "--dart-define=APP_BUILD_NAME=$build_name"
  "--dart-define=APP_BUILD_NUMBER=$build_number"
  "--dart-define=SOURCE_CODE_URL=$source_url"
  "--dart-define=SOURCE_REVISION=$revision"
  "--dart-define=BUILD_DATE=$build_date"
)

if [[ "$dry_run" == true ]]; then
  echo "flutter ${args[*]}"
  exit 0
fi

flutter "${args[@]}"
