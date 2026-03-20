#!/bin/bash
set -euo pipefail

# Strip unsupported architectures from embedded frameworks (SmartView.framework in particular)
# Add this script as an Xcode Run Script phase after "Embed Frameworks".

APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

find "$APP_PATH" -name '*.framework' -type d | while read -r FRAMEWORK; do
  EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$FRAMEWORK/Info.plist" 2>/dev/null || true)
  if [[ -z "${EXECUTABLE_NAME}" ]]; then
    continue
  fi

  EXECUTABLE_PATH="$FRAMEWORK/$EXECUTABLE_NAME"
  if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    continue
  fi

  ARCH_LIST=$(lipo -info "$EXECUTABLE_PATH" | sed -n 's/.*are: //p')
  if [[ -z "$ARCH_LIST" ]]; then
    continue
  fi

  for ARCH in $ARCH_LIST; do
    if [[ "${VALID_ARCHS:-$ARCHS}" != *"$ARCH"* ]]; then
      lipo -remove "$ARCH" -output "$EXECUTABLE_PATH" "$EXECUTABLE_PATH" || true
    fi
  done
done
