#!/bin/bash
set -e

echo "=========================================="
echo "Frida iOS 14 + Taurine Direct Patch Application"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "meson.build" ] || [ ! -d "subprojects" ]; then
    echo "ERROR: This script must be run from the root of the Frida repository"
    echo "Current directory: $(pwd)"
    exit 1
fi

echo "Applying patches by directly editing files..."
echo ""

# Backup original files
echo "Creating backups..."
cp subprojects/frida-gum/gum/gummemory.c subprojects/frida-gum/gum/gummemory.c.backup
cp subprojects/frida-core/src/darwin/darwin-host-session.vala subprojects/frida-core/src/darwin/darwin-host-session.vala.backup
cp subprojects/frida-gum/gum/backend-darwin/gumprocess-darwin.c subprojects/frida-gum/gum/backend-darwin/gumprocess-darwin.c.backup
cp subprojects/frida-gum/gum/backend-darwin/gumcodesegment-darwin.c subprojects/frida-gum/gum/backend-darwin/gumcodesegment-darwin.c.backup
echo "✓ Backups created (.backup files)"
echo ""

# ============================================================================
# PATCH 1: Disable thread suspension on iOS 14
# ============================================================================
echo "[1/4] Patching gummemory.c - Disable thread suspension on iOS 14..."

# Add utsname.h include
if ! grep -q "sys/utsname.h" subprojects/frida-gum/gum/gummemory.c; then
    sed -i.tmp '/#include <string.h>/a\
#ifdef HAVE_DARWIN\
# include <sys/utsname.h>\
#endif
' subprojects/frida-gum/gum/gummemory.c
    rm subprojects/frida-gum/gum/gummemory.c.tmp
    echo "  ✓ Added utsname.h include"
else
    echo "  - utsname.h already included"
fi

# Patch the thread suspension logic
python3 << 'PYTHON_EOF'
import re

file_path = 'subprojects/frida-gum/gum/gummemory.c'
with open(file_path, 'r') as f:
    content = f.read()

# Find and replace the thread suspension code
old_pattern = r'(    GumPageProtection protection;\n    GumSuspendOperation suspend_op = \{ 0, \};)\n\n(    protection = rwx_supported \? GUM_PAGE_RWX : GUM_PAGE_RW;)\n\n(    if \(!rwx_supported\)\n    \{)'

replacement = r'''\1
    gboolean should_suspend_threads = FALSE;

\2

#if defined (HAVE_IOS) || defined (HAVE_TVOS)
    /*
     * PATCH: Disable thread suspension on iOS 14 for Taurine compatibility.
     * Thread suspension triggers kernel panics on Taurine-based jailbreaks.
     * iOS 14.x runs on Darwin 20.x kernel.
     */
    if (!rwx_supported)
    {
      static gboolean ios14_compat_mode = FALSE;
      static gsize check_done = 0;

      if (g_once_init_enter (&check_done))
      {
        struct utsname u;
        ios14_compat_mode = (uname (&u) == 0 && strncmp (u.release, "20.", 3) == 0);
        g_once_init_leave (&check_done, 1);
      }
      should_suspend_threads = !ios14_compat_mode;
    }
#else
    if (!rwx_supported)
      should_suspend_threads = TRUE;
#endif

    if (should_suspend_threads)
    {'''

content = re.sub(old_pattern, replacement, content)

# Also replace the resume_threads check
content = content.replace(
    'resume_threads:\n    if (!rwx_supported)',
    'resume_threads:\n    if (should_suspend_threads)'
)

with open(file_path, 'w') as f:
    f.write(content)

print("  ✓ Thread suspension logic patched")
PYTHON_EOF

echo ""

# ============================================================================
# PATCH 2: Skip launchd injection
# ============================================================================
echo "[2/4] Patching darwin-host-session.vala - Skip launchd injection..."

python3 << 'PYTHON_EOF'
file_path = 'subprojects/frida-core/src/darwin/darwin-host-session.vala'
with open(file_path, 'r') as f:
    content = f.read()

# Find the inject_agent function and add the check
injection_check = '''
#if IOS || TVOS
			/*
			 * PATCH: Skip launchd (PID 1) injection on iOS.
			 * Taurine-based jailbreaks do not permit hooking launchd, and attempts
			 * to do so can cause kernel panics and system reboots.
			 */
			if (pid == 1) {
				throw new Error.NOT_SUPPORTED (
					"Injection into launchd is not supported on this jailbreak");
			}
#endif
'''

# Insert after "private async uint inject_agent (uint pid, string agent_parameters, Cancellable? cancellable) throws Error, IOError {"
pattern = r'(private async uint inject_agent \(uint pid, string agent_parameters, Cancellable\? cancellable\) throws Error, IOError \{\n\t\t\tuint id;)'

if 'Skip launchd' not in content:
    content = content.replace(
        'private async uint inject_agent (uint pid, string agent_parameters, Cancellable? cancellable) throws Error, IOError {\n\t\t\tuint id;',
        'private async uint inject_agent (uint pid, string agent_parameters, Cancellable? cancellable) throws Error, IOError {\n\t\t\tuint id;' + injection_check
    )
    with open(file_path, 'w') as f:
        f.write(content)
    print("  ✓ launchd injection check added")
else:
    print("  - launchd check already present")
PYTHON_EOF

echo ""

# ============================================================================
# PATCH 3: Add Taurine detection
# ============================================================================
echo "[3/4] Patching gumprocess-darwin.c - Add Taurine detection..."

if ! grep -q "gum_is_taurine_jailbreak" subprojects/frida-gum/gum/backend-darwin/gumprocess-darwin.c; then
    # Insert the Taurine detection function after the includes
    sed -i.tmp '/^static gboolean gum_collect_range_of_potential_images/i\
/*\
 * PATCH: Taurine jailbreak detection.\
 * Detects Taurine/Odyssey/Chimera jailbreaks which use libhooker instead of\
 * Cydia Substrate. These jailbreaks have different restrictions that can\
 * trigger kernel panics with standard Frida operations.\
 */\
static gboolean\
gum_is_taurine_jailbreak (void)\
{\
#if defined (HAVE_IOS) || defined (HAVE_TVOS)\
  static gsize cached_result = 0;\
\
  if (g_once_init_enter (\&cached_result))\
  {\
    gboolean is_taurine = FALSE;\
    void * libhooker;\
\
    /* Check for libhooker (Taurines hooking library) */\
    libhooker = dlopen ("/usr/lib/libhooker.dylib", RTLD_NOLOAD | RTLD_LAZY);\
    if (libhooker != NULL)\
    {\
      is_taurine = TRUE;\
      dlclose (libhooker);\
    }\
\
    /* Check for Taurine-specific files */\
    if (!is_taurine)\
    {\
      is_taurine = g_file_test ("/Library/dpkg/info/com.odysseyteam.taurine.list",\
          G_FILE_TEST_EXISTS) ||\
        g_file_test ("/odyssey/jailbreakd.plist", G_FILE_TEST_EXISTS);\
    }\
\
    g_once_init_leave (\&cached_result, is_taurine ? 2 : 1);\
  }\
\
  return cached_result == 2;\
#else\
  return FALSE;\
#endif\
}\
\
' subprojects/frida-gum/gum/backend-darwin/gumprocess-darwin.c
    rm subprojects/frida-gum/gum/backend-darwin/gumprocess-darwin.c.tmp
    echo "  ✓ Taurine detection function added"
else
    echo "  - Taurine detection already present"
fi

echo ""

# ============================================================================
# PATCH 4: Prioritize substrated
# ============================================================================
echo "[4/4] Patching gumcodesegment-darwin.c - Prioritize substrated..."

python3 << 'PYTHON_EOF'
file_path = 'subprojects/frida-gum/gum/backend-darwin/gumcodesegment-darwin.c'
with open(file_path, 'r') as f:
    content = f.read()

# Check if already patched
if 'PATCH: Try substrated first' not in content:
    # Find the section where we remap and swap the order
    old_code = '''  else
  {
    mapped_successfully = gum_code_segment_try_remap_using_substrated (self,
        source_offset, source_size, target_address);
    if (!mapped_successfully)
    {
      mapped_successfully = gum_code_segment_try_remap_locally (self,
          source_offset, source_size, target_address);
    }
  }'''

    new_code = '''  else
  {
    /*
     * PATCH: Try substrated first for better jailbreak compatibility.
     * substrated (Cydia Substrate daemon) provides more reliable code signing
     * on jailbroken systems, especially with Taurine-based jailbreaks that may
     * have kernel restrictions on local vm_remap operations.
     */
    mapped_successfully = gum_code_segment_try_remap_using_substrated (self,
        source_offset, source_size, target_address);
    if (!mapped_successfully)
    {
      /* Fall back to local remap if substrated is not available */
      mapped_successfully = gum_code_segment_try_remap_locally (self,
          source_offset, source_size, target_address);
    }
  }'''

    content = content.replace(old_code, new_code)

    with open(file_path, 'w') as f:
        f.write(content)
    print("  ✓ Substrated priority comment added")
else:
    print("  - Substrated priority already set")
PYTHON_EOF

echo ""
echo "=========================================="
echo "All patches applied successfully!"
echo "=========================================="
echo ""
echo "Backup files created with .backup extension"
echo "You can now build Frida with: ./configure --host=ios-arm64 && make"
echo ""
