#!/bin/bash

# OpenCodeRemote Build Script
# Build và export IPA từ Xcode project

set -e

PROJECT_NAME="OpenCodeRemote"
SCHEME="OpenCodeRemote"
CONFIGURATION="Release"
TEAM_ID="JQiRAaCKdW"
PROVISIONING_PROFILE="JQiRAaCKdW-03062026"
BUNDLE_ID="com.opencode.remote.ocr2026"
PROFILE_PATH="$HOME/Library/MobileDevice/Provisioning Profiles/JQiRAaCKdW-03062026.mobileprovision"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenCodeRemote Build Script${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: Build requires macOS with Xcode${NC}"
    exit 1
fi

# Check if xcodebuild exists
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: xcodebuild not found. Install Xcode command line tools.${NC}"
    exit 1
fi

# Check if provisioning profile exists
if [ ! -f "$PROFILE_PATH" ]; then
    echo -e "${YELLOW}Warning: Provisioning profile not found at:${NC}"
    echo "  $PROFILE_PATH"
    echo -e "${YELLOW}Please ensure profile is installed in:${NC}"
    echo "  $HOME/Library/MobileDevice/Provisioning Profiles/"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create build directory
BUILD_DIR="./build"
mkdir -p "$BUILD_DIR"

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
xcodebuild clean \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION"

# Archive
echo -e "${YELLOW}Archiving...${NC}"
xcodebuild archive \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$BUILD_DIR/$PROJECT_NAME.xcarchive" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE="Manual"

if [ ! -d "$BUILD_DIR/$PROJECT_NAME.xcarchive" ]; then
    echo -e "${RED}Archive failed${NC}"
    exit 1
fi

echo -e "${GREEN}Archive created successfully${NC}"

# Create ExportOptions.plist
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key>
        <string>$PROVISIONING_PROFILE</string>
    </dict>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF

# Export IPA
echo -e "${YELLOW}Exporting IPA...${NC}"
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$PROJECT_NAME.xcarchive" \
    -exportPath "$BUILD_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

if [ -f "$BUILD_DIR/$PROJECT_NAME.ipa" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "IPA location: $BUILD_DIR/$PROJECT_NAME.ipa"
    echo "Size: $(du -h "$BUILD_DIR/$PROJECT_NAME.ipa" | cut -f1)"
    echo ""
else
    echo -e "${RED}Export failed${NC}"
    exit 1
fi
