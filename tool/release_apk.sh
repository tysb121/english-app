#!/usr/bin/env bash
# Build a release APK (when Flutter is available) and print / optionally run
# `gh release create` for tysb121/english-app. Safe defaults: never fails the
# surrounding feature work if Android build is unavailable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUBLISH=0
SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help)
      echo "Usage: $0 [--publish] [--skip-build]"
      exit 0
      ;;
  esac
done

if [[ ! -f pubspec.yaml ]]; then
  echo "error: pubspec.yaml not found in $ROOT" >&2
  exit 1
fi

# version: 1.2.3+4  →  name=1.2.3  build=4
VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -n1 | tr -d '[:space:]')"
VERSION_RAW="${VERSION_LINE#version:}"
VERSION_NAME="${VERSION_RAW%%+*}"
VERSION_BUILD=""
if [[ "$VERSION_RAW" == *"+"* ]]; then
  VERSION_BUILD="${VERSION_RAW#*+}"
fi
TAG="v${VERSION_NAME}"
APK_ASSET="english-app-${TAG}.apk"
DEFAULT_APK="build/app/outputs/flutter-apk/app-release.apk"

echo "==> pubspec version name=${VERSION_NAME} build=${VERSION_BUILD:-?} tag=${TAG}"

BUILD_OK=0
if [[ "$SKIP_BUILD" -eq 1 ]]; then
  echo "==> skip build (--skip-build)"
elif command -v flutter >/dev/null 2>&1; then
  echo "==> flutter build apk --release"
  if flutter build apk --release; then
    BUILD_OK=1
  else
    echo "warning: flutter build failed; continuing with command printout" >&2
  fi
else
  echo "warning: flutter not on PATH; skip build" >&2
fi

STAGED=""
if [[ -f "$DEFAULT_APK" ]]; then
  mkdir -p build/release
  STAGED="build/release/${APK_ASSET}"
  cp -f "$DEFAULT_APK" "$STAGED"
  echo "==> staged $STAGED"
else
  echo "warning: APK not found at $DEFAULT_APK" >&2
fi

GH_CMD=(gh release create "$TAG")
if [[ -n "$STAGED" ]]; then
  GH_CMD+=("${STAGED}#${APK_ASSET}")
fi
GH_CMD+=(--title "$TAG" --notes "Release ${TAG}")

echo
echo "==> suggested command:"
printf ' %q' "${GH_CMD[@]}"
echo
echo

if [[ "$PUBLISH" -eq 1 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh not installed; cannot --publish" >&2
    exit 1
  fi
  if [[ -z "$STAGED" ]]; then
    echo "error: no APK to upload; build first or place file at $DEFAULT_APK" >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "error: gh not authenticated; run gh auth login" >&2
    exit 1
  fi
  echo "==> creating GitHub release ${TAG}"
  "${GH_CMD[@]}"
else
  echo "Tip: re-run with --publish after gh auth login to create the release."
fi

if [[ "$BUILD_OK" -eq 0 && "$SKIP_BUILD" -eq 0 && ! -f "$DEFAULT_APK" ]]; then
  exit 0
fi
exit 0
