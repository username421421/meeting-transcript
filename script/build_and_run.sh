#!/usr/bin/env bash
set -euo pipefail

readonly MODE="${1:-run}"
readonly APP_NAME="Transcribe"
readonly SCHEME="MeetingTranscriber"
readonly PROJECT="MeetingTranscriber.xcodeproj"
readonly BUNDLE_ID="com.codex.MeetingTranscriber"

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_ROOT="$ROOT_DIR/.build"
readonly DERIVED_DATA="$BUILD_ROOT/DerivedData"
readonly PACKAGE_CACHE="$BUILD_ROOT/PackageCache"
readonly BUILD_HOME="$BUILD_ROOT/Home"
readonly CLONED_PACKAGES="$DERIVED_DATA/SourcePackages"
readonly APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
readonly APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

prepare_build_environment() {
  mkdir -p \
    "$DERIVED_DATA" \
    "$PACKAGE_CACHE" \
    "$BUILD_HOME/Library/Caches" \
    "$BUILD_HOME/Library/Logs" \
    "$BUILD_HOME/Library/Developer/Xcode"

  export CFFIXED_USER_HOME="$BUILD_HOME"
  export SWIFTPM_DISABLE_SANDBOX=1
  export SWIFT_BUILD_USE_SANDBOX=0
}

build_app() {
  prepare_build_environment

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$CLONED_PACKAGES" \
    -packageCachePath "$PACKAGE_CACHE" \
    -disablePackageRepositoryCache \
    -IDEPackageSupportDisableManifestSandbox=1 \
    -IDEPackageSupportDisablePackageSandbox=1 \
    OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
