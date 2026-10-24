#!/usr/bin/env bash
set -e

# ==============================================================================
# FLUTTER APK & IPA BUILD SCRIPT (macOS / Linux)
# ==============================================================================

echo "=============================================="
echo "Building Expense Tracker Release APK & IPA"
echo "=============================================="

# Ensure flutter is available in PATH
if ! command -v flutter &> /dev/null; then
    echo "Error: 'flutter' command not found in PATH."
    echo "Please ensure Flutter SDK is installed and added to PATH."
    exit 1
fi

cd finance_app

echo "Fetching dependencies..."
flutter pub get

# 1. Build Android APK
echo "----------------------------------------------"
echo "Building Android Release APK..."
echo "----------------------------------------------"
flutter build apk --release

mkdir -p ../builds
cp build/app/outputs/flutter-apk/app-release.apk ../builds/expense_tracker_latest.apk
echo ">> APK copied to builds/expense_tracker_latest.apk"

# 2. Build iOS IPA if on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "----------------------------------------------"
    echo "Building iOS Release Bundle & Packaging IPA..."
    echo "----------------------------------------------"
    flutter build ios --release --no-codesign

    mkdir -p build/ios/ipa/Payload
    cp -r build/ios/iphoneos/Runner.app build/ios/ipa/Payload/
    (cd build/ios/ipa && zip -r -q ../../../builds/expense_tracker_latest.ipa Payload)
    echo ">> IPA packaged to builds/expense_tracker_latest.ipa"
fi

echo "=============================================="
echo "Build complete! Check the builds/ directory."
echo "=============================================="

