#!/bin/bash

set -e

cd "$(dirname "$0")"

WORKING_LOCATION="$(pwd)"
APPLICATION_NAME=Geranium
CONFIGURATION=Debug

rm -rf build
if [ ! -d "build" ]; then
    mkdir build
fi

cd build

if [ -e "$APPLICATION_NAME.tipa" ]; then
rm $APPLICATION_NAME.tipa
fi

# Build .app
xcodebuild -project "$WORKING_LOCATION/$APPLICATION_NAME.xcodeproj" \
    -scheme Geranium \
    -configuration Debug \
    -derivedDataPath "$WORKING_LOCATION/build/DerivedData" \
    -destination 'generic/platform=iOS' \
    ONLY_ACTIVE_ARCH="NO" \
    CODE_SIGNING_ALLOWED="NO" \
    
# Build helper
# xcodebuild -project "$WORKING_LOCATION/$APPLICATION_NAME.xcodeproj" \
#     -scheme RootHelper \
#     -configuration Debug \
#     -derivedDataPath "$WORKING_LOCATION/build/DerivedData" \
#     -destination 'generic/platform=iOS' \
#     ONLY_ACTIVE_ARCH="NO" \
#     CODE_SIGNING_ALLOWED="NO" \

DD_APP_PATH="$WORKING_LOCATION/build/DerivedData/Build/Products/$CONFIGURATION-iphoneos/$APPLICATION_NAME.app"
TARGET_APP="$WORKING_LOCATION/build/$APPLICATION_NAME.app"
cp -r "$DD_APP_PATH" "$TARGET_APP"

# Remove signature
codesign --remove "$TARGET_APP"
if [ -e "$TARGET_APP/_CodeSignature" ]; then
    rm -rf "$TARGET_APP/_CodeSignature"
fi
if [ -e "$TARGET_APP/embedded.mobileprovision" ]; then
    rm -rf "$TARGET_APP/embedded.mobileprovision"
fi

# Ensure we're in the repository root for submodule operations
cd "$WORKING_LOCATION"

# RootHelper is a pinned git submodule. Never replace it with an unpinned clone.
if [ ! -e "$WORKING_LOCATION/RootHelper/.git" ]; then
    echo "Initializing the pinned RootHelper submodule..."
    git submodule update --init --recursive
fi

if [ ! -e "$WORKING_LOCATION/RootHelper/.git" ]; then
    echo "Error: the pinned RootHelper submodule could not be initialized."
    exit 1
fi

EXPECTED_ROOT_HELPER=$(git rev-parse :RootHelper)
ACTUAL_ROOT_HELPER=$(git -C "$WORKING_LOCATION/RootHelper" rev-parse HEAD)
if [ "$EXPECTED_ROOT_HELPER" != "$ACTUAL_ROOT_HELPER" ]; then
    echo "Error: RootHelper is not at the pinned commit."
    echo "Expected: $EXPECTED_ROOT_HELPER"
    echo "Actual:   $ACTUAL_ROOT_HELPER"
    exit 1
fi

# Return to build directory
cd "$WORKING_LOCATION/build"

cd $WORKING_LOCATION/RootHelper
make clean
make
cp $WORKING_LOCATION/RootHelper/.theos/obj/debug/GeraniumRootHelper $WORKING_LOCATION/build/Geranium.app/GeraniumRootHelper
cd -

#cp $WORKING_LOCATION/build/DerivedData/Build/Products/$CONFIGURATION-iphoneos/RootHelper $WORKING_LOCATION/build/Geranium.app/RootHelper

# Is ldid installed ?
if command -v ldid &> /dev/null; then
    echo "ldid is already installed."
else
    # Install ldid using Homebrew
    if command -v brew &> /dev/null; then
        echo "Installing ldid with Homebrew..."
        brew install ldid
        echo "ldid has been installed."
    else
        echo "Homebrew is not installed. Please install Homebrew first."
    fi
fi

# Add entitlements
echo "Adding entitlements"
ldid -S"$WORKING_LOCATION/entitlements.plist" "$TARGET_APP/$APPLICATION_NAME"
# Inject into the Maps thingy
ldid -S"$WORKING_LOCATION/Bookmark Location in Geranium/entitlements.plist" "$TARGET_APP/PlugIns/Bookmark Location in Geranium.appex/Bookmark Location in Geranium"
# idk if this is usefull but uhm
# ldid -S"$WORKING_LOCATION/Bookmark Location in Geranium/entitlements.plist" "$TARGET_APP/PlugIns/Bookmark Location in Geranium.appex/Bookmark Location in Geranium.debug.dylib"
# ldid -S"$WORKING_LOCATION/entitlements.plist" "$TARGET_APP/RootHelper"

# Package .ipa
rm -rf Payload
mkdir Payload
cp -r $APPLICATION_NAME.app Payload/$APPLICATION_NAME.app
zip -vr $APPLICATION_NAME.tipa Payload
rm -rf $APPLICATION_NAME.app
rm -rf Payload
