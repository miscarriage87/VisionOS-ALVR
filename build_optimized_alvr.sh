#!/bin/bash
set -eo pipefail # Exit on error, treat unset variables as an error, and propagate exit status

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR" # Assuming script is in repo root
PROJECT_NAME="ALVRClient"
# Correct path based on context's directory structure for the main app project
PROJECT_XCODEPROJ_PATH="$REPO_ROOT/$PROJECT_NAME/$PROJECT_NAME.xcodeproj" 
OPTIMIZED_SERVER_CONFIG_FILENAME="optimized_rtx_a4500_settings.json"
OPTIMIZED_SERVER_CONFIG_EXPECTED_LOCATION="$REPO_ROOT/config/$OPTIMIZED_SERVER_CONFIG_FILENAME"

# Build configurations
BUILD_TYPE="Debug" # Default
CLEAN_BUILD=false # Not directly passed to repack_alvr_client.sh, but could be used to clean derived data first
TARGET_SDK_DEVICE="xros" # VisionOS device SDK

# Output directories and files from repack_alvr_client.sh
# repack_alvr_client.sh outputs to the REPO_ROOT
FINAL_APP_LOCATION_DESCRIPTION="" # Will be set after build

# --- Helper Functions ---
log_info() {
    echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo "[WARN] $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $1" >&2
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 command not found. Please install it and ensure it's in your PATH."
    fi
}

usage() {
    echo "Usage: $0 [-b <Debug|Release|TestFlight>] [-c] [-h]"
    echo ""
    echo "Builds the ALVR VisionOS Client with optimizations for Cloud Gaming (Shadow PC + RTX A4500)."
    echo ""
    echo "Options:"
    echo "  -b, --build-type    Build type: Debug, Release, TestFlight (default: Debug)."
    echo "                      'TestFlight' uses a 'Release' configuration."
    echo "  -c, --clean           Perform a clean build by removing prior build artifacts."
    echo "                      (Deletes $REPO_ROOT/build and potentially previous zip outputs)."
    echo "  -h, --help            Show this help message."
    exit 0
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -b|--build-type)
            BUILD_TYPE="$2"
            if [[ ! "$BUILD_TYPE" =~ ^(Debug|Release|TestFlight)$ ]]; then
                log_error "Invalid build type: $BUILD_TYPE. Must be Debug, Release, or TestFlight."
            fi
            shift
            ;;
        -c|--clean) CLEAN_BUILD=true ;;
        -h|--help) usage ;;
        *) log_error "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# --- Pre-flight Checks ---
log_info "Starting ALVR VisionOS Client Optimized Build Script..."
log_info "Selected Build Type: $BUILD_TYPE"
log_info "Clean Build Requested: $CLEAN_BUILD"

check_command git
check_command xcodebuild # repack_alvr_client.sh uses xcrun xcodebuild

if [ ! -d "$PROJECT_XCODEPROJ_PATH" ]; then
    log_error "Xcode project not found at $PROJECT_XCODEPROJ_PATH. Make sure you are in the repository root."
fi

REPACK_SCRIPT="$REPO_ROOT/repack_alvr_client.sh"
if [ ! -f "$REPACK_SCRIPT" ]; then
    log_error "Build script $REPACK_SCRIPT not found. This script is essential for the build process."
fi
if [ ! -x "$REPACK_SCRIPT" ]; then
    log_warn "$REPACK_SCRIPT is not executable. Attempting to set execute permission."
    chmod +x "$REPACK_SCRIPT" || log_error "Failed to set execute permission on $REPACK_SCRIPT."
fi


# --- Main Build Process ---

# 0. Clean build artifacts if requested
if $CLEAN_BUILD; then
    log_info "Performing clean build: removing $REPO_ROOT/build and $REPO_ROOT/ALVRClient-*.zip..."
    rm -rf "$REPO_ROOT/build"
    rm -f "$REPO_ROOT/ALVRClient-Debug-$TARGET_SDK_DEVICE.zip"
    rm -f "$REPO_ROOT/ALVRClient-Release-$TARGET_SDK_DEVICE.zip"
    rm -f "$REPO_ROOT/ALVRClient-$TARGET_SDK_DEVICE.zip" # Fallback name from repack script
    log_info "Clean up complete."
fi

# 1. Setup Development Environment & Update Git Submodules
log_info "Ensuring development environment is up-to-date..."
log_info "Updating git submodules..."
if ! git submodule update --init --recursive; then
    log_error "Failed to update git submodules. Please check for errors."
fi
log_info "Git submodules updated successfully."

# 2. Build the ALVR client using repack_alvr_client.sh
log_info "Building VisionOS ALVR Client ($PROJECT_NAME) using $REPACK_SCRIPT..."

XCODE_BUILD_CONFIGURATION="Debug" # Default for repack_alvr_client.sh if -c is not given
if [ "$BUILD_TYPE" == "Release" ] || [ "$BUILD_TYPE" == "TestFlight" ]; then
    XCODE_BUILD_CONFIGURATION="Release"
fi
log_info "Using Xcode Configuration: $XCODE_BUILD_CONFIGURATION for the build."

# Determine expected output ZIP file name based on repack_alvr_client.sh logic
# repack_alvr_client.sh creates ALVRClient-${CONFIGURATION}-${SDK}.zip
# SDK defaults to "xros" in repack_alvr_client.sh if not specified with -s
EXPECTED_ZIP_OUTPUT_FILE="$REPO_ROOT/ALVRClient-$XCODE_BUILD_CONFIGURATION-$TARGET_SDK_DEVICE.zip"

# Clean previous specific zip if it exists (again, if not covered by global clean)
if [ -f "$EXPECTED_ZIP_OUTPUT_FILE" ]; then
    log_info "Removing existing $EXPECTED_ZIP_OUTPUT_FILE before build..."
    rm "$EXPECTED_ZIP_OUTPUT_FILE"
fi

# Ensure script is run from REPO_ROOT for repack_alvr_client.sh relative paths
cd "$REPO_ROOT" || log_error "Failed to change directory to $REPO_ROOT"

log_info "Executing: $REPACK_SCRIPT -c \"$XCODE_BUILD_CONFIGURATION\""
# The -s sdk defaults to xros in repack_alvr_client.sh which is what we want.
if "$REPACK_SCRIPT" -c "$XCODE_BUILD_CONFIGURATION"; then
    log_info "$REPACK_SCRIPT executed successfully."
else
    log_error "$REPACK_SCRIPT failed. Please check the output above for details."
fi

# Verify zip output
if [ ! -f "$EXPECTED_ZIP_OUTPUT_FILE" ]; then
    # repack_alvr_client.sh might have a slightly different naming if SDK is not part of default name in some versions
    ALTERNATIVE_ZIP_OUTPUT="$REPO_ROOT/ALVRClient-$XCODE_BUILD_CONFIGURATION.zip" # If SDK is omitted by script
    if [ -f "$ALTERNATIVE_ZIP_OUTPUT" ]; then
        EXPECTED_ZIP_OUTPUT_FILE="$ALTERNATIVE_ZIP_OUTPUT"
        log_warn "Output zip found at $EXPECTED_ZIP_OUTPUT_FILE (name pattern differs from primary expectation)."
    else
        log_error "Output zip file $EXPECTED_ZIP_OUTPUT_FILE (or alternative) not found after build. The build might have failed or the output name is unexpected."
    fi
fi

log_info "Build process completed. Output package: $EXPECTED_ZIP_OUTPUT_FILE"
FINAL_APP_LOCATION_DESCRIPTION="The ALVRClient.app is inside $EXPECTED_ZIP_OUTPUT_FILE (usually within a 'Payload' directory)."

# 3. Configuration Guidance for Cloud Gaming + RTX A4500 Setup
log_info ""
log_info "--- Configuration for Optimized Cloud Gaming Setup (Shadow PC + RTX A4500) ---"
log_info "The ALVR client has been built with embedded optimizations for your specific setup."
log_info "For the server-side configuration on your Shadow PC:"
if [ -f "$OPTIMIZED_SERVER_CONFIG_EXPECTED_LOCATION" ]; then
    log_info "1. An optimized server configuration template is available at:"
    log_info "   $OPTIMIZED_SERVER_CONFIG_EXPECTED_LOCATION"
    log_info "2. Transfer this file ('$OPTIMIZED_SERVER_CONFIG_FILENAME') to your Shadow PC."
    log_info "3. On the ALVR Server Dashboard (on Shadow PC), navigate to Settings -> Installation (or a similar section)."
    log_info "4. Use the 'Import settings from file' or 'Load preset' option to apply the '$OPTIMIZED_SERVER_CONFIG_FILENAME'."
    log_info "5. Restart the ALVR server if prompted or if settings don't apply immediately."
else
    log_warn "Optimized server configuration template ($OPTIMIZED_SERVER_CONFIG_EXPECTED_LOCATION) was not found."
    log_warn "Please ensure you manually create or obtain the correct server-side JSON settings tailored for your RTX A4500, H.265 10-bit streaming, and other cloud optimizations."
fi
log_info "For comprehensive setup details, network tuning, and troubleshooting, refer to the 'RTX_A4500_OPTIMIZATION_GUIDE.md' document."

# 4. Next Steps for Deployment
log_info ""
log_info "--- Next Steps for Deploying to Apple Vision Pro ---"
log_info "The built application is packaged in: $EXPECTED_ZIP_OUTPUT_FILE"
log_info "To deploy the '$PROJECT_NAME.app' found inside the zip archive:"

if [ "$BUILD_TYPE" == "Debug" ]; then
    log_info "For Debug builds (recommended for development):"
    log_info "  a. Unzip $EXPECTED_ZIP_OUTPUT_FILE."
    log_info "  b. Locate the '$PROJECT_NAME.app' (likely in a 'Payload' folder)."
    log_info "  c. Connect your Apple Vision Pro to your Mac."
    log_info "  d. Open the '$PROJECT_XCODEPROJ_PATH' in Xcode."
    log_info "  e. Select your Vision Pro as the run destination device."
    log_info "  f. In Xcode, go to 'Window' -> 'Devices and Simulators'."
    log_info "  g. Select your Vision Pro, then under 'Installed Apps', click '+' and choose the '$PROJECT_NAME.app' you extracted."
    log_info "     Alternatively, drag and drop the .app bundle onto your device in this window."
    log_info "  h. You can also run directly from Xcode by selecting your device and pressing the Run button."
elif [ "$BUILD_TYPE" == "Release" ] || [ "$BUILD_TYPE" == "TestFlight" ]; then
    log_info "For Release or TestFlight distribution:"
    log_info "  The recommended method is to use Xcode's archiving and distribution features:"
    log_info "  a. Open '$PROJECT_XCODEPROJ_PATH' in Xcode."
    log_info "  b. Ensure your project's signing and capabilities are correctly configured for your Apple Developer account."
    log_info "  c. Select 'Any visionOS Device (arm64)' as the build destination (top of Xcode window)."
    log_info "  d. Go to 'Product' -> 'Archive'."
    log_info "  e. Once archiving is complete, the Xcode Organizer window will appear."
    log_info "  f. From the Organizer, you can 'Distribute App' to App Store Connect for TestFlight or official release."
    log_info "     You can also export a signed .ipa for ad-hoc distribution if your provisioning profile allows."
fi

log_info ""
log_info "After deployment:"
log_info "1. Ensure your ALVR server is running on the Shadow PC with the imported '$OPTIMIZED_SERVER_CONFIG_FILENAME'."
log_info "2. Launch the '$PROJECT_NAME' app on your Apple Vision Pro."
log_info "3. The client should discover and allow connection to your ALVR server."
log_info "Enjoy your optimized PC VR experience on Apple Vision Pro!"
log_info ""
log_info "Build script finished successfully."

exit 0
