#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preview_cache="${OCU_PREVIEW_CACHE_DIR:-${HOME}/Library/Caches/open-computer-use-preview}"
preview_output="${OCU_PREVIEW_OUTPUT_DIR:-${preview_cache}/package}"
preview_identity="${OPEN_COMPUTER_USE_CODESIGN_IDENTITY:-}"
if [[ -z "${preview_identity}" ]]; then
  preview_identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
fi
if [[ -z "${preview_identity}" ]]; then
  echo "Set OPEN_COMPUTER_USE_CODESIGN_IDENTITY to a Developer ID Application identity." >&2
  exit 1
fi
preview_configuration="${OCU_PREVIEW_CONFIGURATION:-debug}"
mkdir -p "${preview_cache}" "${preview_output}"
cd "${repo_root}"
swift build --scratch-path "${preview_cache}/swift" -c "${preview_configuration}" --product OCUPreview
preview_bin="$(swift build --scratch-path "${preview_cache}/swift" -c "${preview_configuration}" --show-bin-path)"
preview_app="${preview_output}/Open Computer Use Preview.app"
mkdir -p "${preview_app}/Contents/MacOS" "${preview_app}/Contents/Resources"
cp "${preview_bin}/OCUPreview" "${preview_app}/Contents/MacOS/OCUPreview"
python3 - "${preview_app}/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'OCUPreview',
        'CFBundleIdentifier': 'com.ifuryst.opencomputeruse.preview',
        'CFBundleName': 'Open Computer Use Preview',
        'CFBundleDisplayName': 'Open Computer Use Preview',
        'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '1.0.0',
        'CFBundleVersion': '1',
        'LSMinimumSystemVersion': '14.0',
        'LSUIElement': True,
        'NSHighResolutionCapable': True,
        'NSPrincipalClass': 'NSApplication',
        'NSScreenCaptureUsageDescription': 'Read-only live preview of Open Computer Use virtual displays.',
    }, f)
PY
codesign --force --options runtime --timestamp --sign "${preview_identity}" "${preview_app}"
codesign --verify --strict --verbose=2 "${preview_app}"
printf '%s\n' "${preview_app}"
