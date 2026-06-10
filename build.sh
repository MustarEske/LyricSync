#!/bin/bash
set -e

# LyricSync Build Script
# Builds the LyricSync macOS app using swiftc

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/LyricSync.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building LyricSync..."

# Clean and create directories
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Collect all Swift files
SWIFT_FILES=(
    "$SCRIPT_DIR/LyricSync/LyricSyncApp.swift"
    "$SCRIPT_DIR/LyricSync/Models/SongDocument.swift"
    "$SCRIPT_DIR/LyricSync/ViewModels/LyricSyncViewModel.swift"
    "$SCRIPT_DIR/LyricSync/Utilities/AudioEngine.swift"
    "$SCRIPT_DIR/LyricSync/Utilities/AudioMetadataWriter.swift"
    "$SCRIPT_DIR/LyricSync/Views/ContentView.swift"
    "$SCRIPT_DIR/LyricSync/Views/WaveformView.swift"
    "$SCRIPT_DIR/LyricSync/Views/LyricListView.swift"
    "$SCRIPT_DIR/LyricSync/Views/TransportBar.swift"
    "$SCRIPT_DIR/LyricSync/Views/TapToSetOverlay.swift"
    "$SCRIPT_DIR/LyricSync/Views/SeekBarView.swift"
)

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
TARGET="arm64-apple-macos14.0"

# Compile
echo "📦 Compiling Swift files..."
swiftc \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework AppKit \
    -framework Foundation \
    -framework CoreGraphics \
    -parse-as-library \
    -o "$MACOS_DIR/LyricSync" \
    "${SWIFT_FILES[@]}"

# Copy Info.plist
cp "$SCRIPT_DIR/LyricSync/Info.plist" "$CONTENTS_DIR/Info.plist"

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✅ Build complete!"
echo "📱 App located at: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo "  or"
echo "  $MACOS_DIR/LyricSync"
