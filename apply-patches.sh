#!/bin/bash
set -e

echo "=========================================="
echo "Frida iOS 14 + Taurine Compatibility Patches"
echo "=========================================="
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "ERROR: This script must be run from the root of the Frida git repository"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Get the directory where the patches are
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Patch directory: $PATCH_DIR"
echo "Frida repository: $(pwd)"
echo ""

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "WARNING: You have uncommitted changes in your repository"
    echo "Please commit or stash them before applying patches"
    exit 1
fi

# Apply patches
echo "Applying patches..."
echo ""

for patch in "$PATCH_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        echo "Applying: $(basename "$patch")"
        if git am --3way "$patch"; then
            echo "✓ Success"
        else
            echo "✗ Failed to apply $(basename "$patch")"
            echo ""
            echo "You can try:"
            echo "  1. Resolve conflicts manually"
            echo "  2. Run: git am --continue"
            echo "  3. Or abort: git am --abort"
            exit 1
        fi
        echo ""
    fi
done

echo "=========================================="
echo "All patches applied successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Set your iOS code signing certificate:"
echo "     export IOS_CERTID=\"Apple Development: your@email.com (XXXXXXXXXX)\""
echo ""
echo "  2. Configure for iOS:"
echo "     ./configure --host=ios-arm64"
echo ""
echo "  3. Build:"
echo "     make"
echo ""
echo "  4. Install:"
echo "     make install"
echo ""
