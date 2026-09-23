#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The App Store IPA must be built on macOS with Xcode." >&2
  exit 1
fi

if [[ $# -ne 1 || ! "$1" =~ ^https:// ]]; then
  echo "Usage: scripts/build_ios_store.sh https://host/path/to/exact-release-source" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree must be clean. Commit the exact release source first." >&2
  exit 1
fi

revision="$(git rev-parse HEAD)"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

flutter build ipa --release \
  --dart-define="SOURCE_CODE_URL=$1" \
  --dart-define="SOURCE_REVISION=$revision" \
  --dart-define="BUILD_DATE=$build_date"
