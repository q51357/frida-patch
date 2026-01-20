# Frida Patches for iOS 14.7.1 + Taurine Jailbreak Compatibility

Patches to fix kernel panic/reboot issues when using Frida on iOS 14.7.1 devices jailbroken with Taurine.

## Problem

Running Frida commands like `frida` or `frida-ps -Ua` on iOS 14.7.1 with Taurine jailbreak causes the device to reboot immediately, requiring re-jailbreaking.

## Root Cause

1. **Thread Suspension** (introduced in Frida 16.0.3): Frida suspends all threads when modifying memory pages on W^X systems. Taurine's kernel protections treat this as hostile and trigger kernel panic.
2. **launchd Hooking**: Frida attempts to hook launchd (PID 1), which Taurine-based jailbreaks specifically block.
3. **Memory Protection**: Taurine uses libhooker instead of Cydia Substrate, with different kernel-level restrictions.

## Patches Included

This repository contains 4 patches that must be applied to the Frida source code:

### Patch 1: Disable Thread Suspension on iOS 14 - CRITICAL
- **File**: `subprojects/frida-gum/gum/gummemory.c`
- **Effect**: Detects iOS 14 (Darwin 20.x) and skips thread suspension
- **This is the primary fix for the reboot issue**

### Patch 2: Skip launchd Injection
- **File**: `subprojects/frida-core/src/darwin/darwin-host-session.vala`
- **Effect**: Prevents injection attempts into launchd (PID 1)

### Patch 3: Add Taurine Detection
- **File**: `subprojects/frida-gum/gum/backend-darwin/gumprocess-darwin.c`
- **Effect**: Runtime detection of Taurine jailbreak

### Patch 4: Prioritize Substrated
- **File**: `subprojects/frida-gum/gum/backend-darwin/gumcodesegment-darwin.c`
- **Effect**: Use substrated daemon preferentially for code signing

## Installation

### Step 1: Clone Frida

```bash
git clone --recurse-submodules https://github.com/frida/frida.git
cd frida
```

### Step 2: Checkout Specific Version

These patches are tested against Frida 17.5.2:

```bash
git checkout 17.5.2
git submodule update --init --recursive
```

### Step 3: Clone This Patch Repository

```bash
cd ..
git clone https://github.com/jwalker/frida-patch.git
```

### Step 4: Apply Patches

Run the apply-patches script from within your Frida repository:

```bash
cd frida
../frida-patch/apply-patches.sh
```

The script will:
- Verify you're in a clean git repository
- Apply all 4 patches using `git am`
- Provide next steps for building

### Step 5: Configure Code Signing

Find your iOS development certificate:

```bash
security find-identity -v -p codesigning | grep "Apple Development"
```

Export the certificate ID:

```bash
export IOS_CERTID="Apple Development: your@email.com (XXXXXXXXXX)"
```

### Step 6: Configure and Build

```bash
# Configure for iOS ARM64
./configure --host=ios-arm64

# Build Frida
make

# The build will produce:
# - build/frida-ios-arm64/bin/frida-server
# - Frida tools and libraries
```

### Step 7: Deploy to iOS Device

```bash
# SSH into your jailbroken iOS device
ssh root@YOUR_DEVICE_IP

# On the device, stop any running frida-server
killall frida-server

# Exit SSH and copy the patched frida-server from your Mac:
scp build/frida-ios-arm64/bin/frida-server root@YOUR_DEVICE_IP:/usr/sbin/frida-server

# SSH back in and start the patched frida-server
ssh root@YOUR_DEVICE_IP
chmod +x /usr/sbin/frida-server
/usr/sbin/frida-server --version
frida-server &
```

### Step 8: Test

```bash
# From your Mac, test the connection:
frida-ps -Ua

# If successful, your device should NOT reboot!
```

## Tested Configurations

- ✅ iOS 14.7.1 + Taurine jailbreak + Frida 17.5.2 (patched)
- ✅ iPad mini 5th generation (iOS 14.7.1)

## Troubleshooting

### Patches Fail to Apply

If patches fail with conflicts:

1. Ensure you're on Frida 17.5.2: `git describe --tags`
2. Check for uncommitted changes: `git status`
3. Try 3-way merge: The script uses `git am --3way` automatically
4. Manual resolution: `git am --abort` then apply patches manually

### Device Still Reboots

1. Verify patch 1 was applied: Check `subprojects/frida-gum/gum/gummemory.c` for iOS 14 detection
2. Ensure you deployed the patched frida-server, not the stock one
3. Check iOS version: `uname -a` should show Darwin 20.x for iOS 14
4. Verify Taurine jailbreak is active

### Code Signing Issues

```bash
# List available certificates
security find-identity -v -p codesigning

# If no certificates, create a self-signed certificate:
# (Follow instructions in INSTALL.txt for certificate creation)
```

## Alternative: Direct Script Method

If you prefer to apply patches without git am:

```bash
cd frida
../frida-patch/apply-edits-directly.sh
```

This script directly modifies source files but doesn't create git commits.

## Last resort

Apply the patches directly one by one


## Documentation

- **INSTALL.txt** - Simple installation walkthrough

Patches developed through analysis of Frida source code and Taurine jailbreak behavior on iOS 14.7.1.

## License

These patches are provided as-is for compatibility purposes. Frida itself is licensed under the wxWindows Library Licence, Version 3.1.

## Contributing

Issues and improvements welcome! Please test thoroughly before submitting patches for additional iOS versions or jailbreaks.

## Supported Frida Version

- **Recommended**: Frida 17.5.2
- **May work with**: Frida 16.x  (untested, may require patch adjustments)
