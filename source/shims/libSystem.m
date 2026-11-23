/*
 * Part of the Stray on iOS Compatibility Research Project.
 * Based on / extending macos-on-ios-public (https://github.com/zorrobyte/macos-on-ios-public).
 *
 * Copyright (c) 2026 Ross Fisher
 * Copyright (c) 2026 Stray on iOS Research Contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// libSystem on iOS: path redirects, case-insensitive paths, crash-site logging.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dirent.h>
#import <fcntl.h>
#import <stdarg.h>
#import <stdio.h>
#import <sys/stat.h>
#import <signal.h>
#import <objc/runtime.h>
#import <sys/ucontext.h>
#import <unistd.h>
#import <execinfo.h>
#import <mach/mach.h>
#import <pthread.h>

// MARK: Path redirects (Info.plist SHIMPathRedirects: {"/Resources/Packages": "Documents/packages"})
// Big game data lives in the app's Documents (pushed once, survives reinstalls) instead of
// the bundle. Any path containing a key (case-insensitive) is rewritten from that point to
// <home>/<value>. Covers the libc file calls Mac games use.

static NSDictionary<NSString *, NSString *> *Redirects(void) {
    static NSDictionary *r;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ r = NSBundle.mainBundle.infoDictionary[@"SHIMPathRedirects"] ?: @{}; });
    return r;
}

static const char *FixCase(const char *path, char *buf, size_t size);

// Returns path itself, or a rewritten copy in buf (redirects, then case-insensitive matching).
static const char *RedirectOnly(const char *path, char *buf, size_t size);
static const char *Redirect(const char *path, char *buf, size_t size) {
    if (!path) return path;
    char tmp[PATH_MAX];
    const char *p = RedirectOnly(path, tmp, sizeof tmp);
    const char *f = FixCase(p, buf, size);
    if (f == p && p == tmp) { strlcpy(buf, tmp, size); return buf; }
    return f;
}
// Info.plist SHIMAppParentRedirect = "Documents/<game>": games that keep data next to their .app
// (Cyberpunk: archive/, engine/, r6/) see the iOS install folder there, which is read-only and
// changes per install. Paths in the app's parent folder (other than the app) go to <home>/<value>.
// Textual absolute form of a relative path under `base` ("."/".." removed). No Foundation calls: this
// runs inside the hooked libc entry points.
static bool AbsoluteNormalized(const char *base, const char *rel, char *out, size_t size) {
    char joined[PATH_MAX * 2], work[PATH_MAX * 2];
    if (snprintf(joined, sizeof joined, "%s/%s", base, rel) >= (int)sizeof joined) return false;
    strlcpy(work, joined, sizeof work);
    char *parts[PATH_MAX / 2];
    size_t n = 0;
    char *save = NULL;
    for (char *tok = strtok_r(work, "/", &save); tok; tok = strtok_r(NULL, "/", &save)) {
        if (!strcmp(tok, ".")) continue;
        if (!strcmp(tok, "..")) { if (n) n--; continue; }
        if (n >= PATH_MAX / 2) return false;
        parts[n++] = tok;
    }
    size_t len = 0;
    out[0] = '\0';
    for (size_t i = 0; i < n; i++) {
        int w = snprintf(out + len, size - len, "/%s", parts[i]);
        if (w < 0 || (size_t)w >= size - len) return false;
        len += (size_t)w;
    }
    if (!len) return strlcpy(out, "/", size) < size;
    return true;
}

static const char *AppParentRedirect(const char *path, char *buf, size_t size) {
    static char parent[PATH_MAX], privParent[PATH_MAX], app[NAME_MAX + 1], macRoot[PATH_MAX];
    static size_t parentLen, privLen;
    static NSString *target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        target = NSBundle.mainBundle.infoDictionary[@"SHIMAppParentRedirect"];
        char exe[PATH_MAX];
        // Real image path (bundle root). _NSGetExecutablePath is overridden below to report the
        // Mac layout (<app>/Mac/Contents/MacOS), which would put the parent inside Mac/.
        const char *img = _dyld_get_image_name(0);
        if (!target || !img || strlcpy(exe, img, sizeof exe) >= sizeof exe) return;
        NSString *appPath = @(exe).stringByDeletingLastPathComponent;            // .../<UUID>/X.app
        strlcpy(app, appPath.lastPathComponent.fileSystemRepresentation, sizeof app);
        strlcpy(parent, appPath.stringByDeletingLastPathComponent.fileSystemRepresentation, sizeof parent);
        if (!strncmp(parent, "/private/", 9)) strlcpy(privParent, parent + 8, sizeof privParent);
        else snprintf(privParent, sizeof privParent, "/private%s", parent);
        parentLen = strlen(parent); privLen = strlen(privParent);
        strlcpy(macRoot, NSBundle.mainBundle.bundlePath.fileSystemRepresentation, sizeof macRoot);
    });
    if (!target || !parentLen || !path) return path;
    // Relative paths (e.g. "../../../<UUID>/X" from the shim's chdir) resolve against the cwd first.
    const char *abs = path;
    char absBuf[PATH_MAX];
    if (path[0] != '/') {
        if (!AbsoluteNormalized(macRoot, path, absBuf, sizeof absBuf)) return path;
        abs = absBuf;
    }
    const char *rest = NULL;
    if (!strncmp(abs, parent, parentLen) && abs[parentLen] == '/') rest = abs + parentLen + 1;
    else if (!strncmp(abs, privParent, privLen) && abs[privLen] == '/') rest = abs + privLen + 1;
    if (!rest || (!strncmp(rest, app, strlen(app)) && (rest[strlen(app)] == '/' || !rest[strlen(app)]))) return path;
    snprintf(buf, size, "%s/%s/%s", NSHomeDirectory().fileSystemRepresentation, target.UTF8String, rest);
    return buf;
}

static const char *RedirectOnly(const char *path, char *buf, size_t size) {
    const char *a = AppParentRedirect(path, buf, size);
    if (a != path) return a;
    if (!path || !Redirects().count) return path;
    for (NSString *key in Redirects()) {
        const char *hit = strcasestr(path, key.UTF8String);
        if (!hit) continue;
        snprintf(buf, size, "%s/%s%s", NSHomeDirectory().fileSystemRepresentation, Redirects()[key].UTF8String, hit + key.length);
        return buf;
    }
    return path;
}

static void *RealLibc(const char *name);

// Mac file systems ignore case and Mac games rely on it (Crimson Desert lowercases its whole
// save path). For paths inside the app container, match each component case-insensitively
// against the disk, like macOS. Only runs when the exact path doesn't exist.
static const char *FixCase(const char *path, char *buf, size_t size) {
    static char home[PATH_MAX], privHome[PATH_MAX];
    static size_t homeLen, privLen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        strlcpy(home, NSHomeDirectory().fileSystemRepresentation, sizeof home);  // /private/var/mobile/... or /var/...
        if (!strncmp(home, "/private/", 9)) strlcpy(privHome, home + 8, sizeof privHome);       // /var/...
        else snprintf(privHome, sizeof privHome, "/private%s", home);
        homeLen = strlen(home); privLen = strlen(privHome);
    });
    size_t prefix = 0;
    if (!strncasecmp(path, home, homeLen)) prefix = homeLen;
    else if (!strncasecmp(path, privHome, privLen)) prefix = privLen;
    else return path;
    static int (*realAccess)(const char *, int);
    if (!realAccess) realAccess = RealLibc("access");
    if (realAccess(path, F_OK) == 0) return path;
    static DIR *(*realOpendir)(const char *);
    if (!realOpendir) realOpendir = RealLibc("opendir");
    char out[PATH_MAX];
    strlcpy(out, home, sizeof out);
    const char *rest = path + prefix;
    while (*rest == '/') rest++;
    while (*rest) {
        const char *slash = strchr(rest, '/');
        size_t len = slash ? (size_t)(slash - rest) : strlen(rest);
        char comp[NAME_MAX + 1];
        snprintf(comp, sizeof comp, "%.*s", (int)len, rest);
        char probe[PATH_MAX];
        snprintf(probe, sizeof probe, "%s/%s", out, comp);
        if (realAccess(probe, F_OK) != 0) {
            DIR *d = realOpendir(out);
            struct dirent *e;
            while (d && (e = readdir(d))) if (!strcasecmp(e->d_name, comp)) { strlcpy(comp, e->d_name, sizeof comp); break; }
            if (d) closedir(d);
        }
        strlcat(out, "/", sizeof out);
        strlcat(out, comp, sizeof out);
        rest += len;
        while (*rest == '/') rest++;
    }
    strlcpy(buf, out, size);
    return buf;
}

static void *RealLibc(const char *name) {
    static void *h;
    if (!h) h = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
    return dlsym(h, name);
}

#define REAL(ret, name, ...) static ret (*real)(__VA_ARGS__); if (!real) real = RealLibc(name)

// First 1000 distinct paths the app looks for and doesn't find (where does it expect its data?).
static void LogMissing(const char *call, const char *path, int r) {
    if (r != -1 || errno != ENOENT || !path) return;
    static NSMutableSet *seen; static int n;
    @synchronized (NSNull.null) {
        if (n >= 1000) return;
        if (!seen) seen = [NSMutableSet new];
        NSString *k = @(path);
        if ([seen containsObject:k]) return;
        [seen addObject:k]; n++;
    }
    int e = errno;
    NSLog(@"SHIM missing file (%s): %s", call, path);
    errno = e;
}
#define EXPORT __attribute__((visibility("default")))

static void ProbeShaderAccess(const char *call, const char *orig, const char *redirected, int ret, int err) {
    if (orig && (strcasestr(orig, "shader") || strcasestr(orig, "global") || strstr(orig, "SF_") || strcasestr(orig, ".bin") || strcasestr(orig, "pak") || strcasestr(orig, "TargetSettings") || strcasestr(orig, "TargetedRHI") || strcasestr(orig, "BaseEngine") || strcasestr(orig, "MacEngine"))) {
        NSLog(@"SHIM PROBE (%s): orig='%s' -> redir='%s' ret=%d errno=%d", call, orig, (redirected ? redirected : "none"), ret, err);
    }
}

EXPORT int open(const char *path, int flags, ...) {
    REAL(int, "open", const char *, int, ...);
    int mode = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
    char buf[PATH_MAX];
    const char *p = Redirect(path, buf, sizeof buf);
    int r = real(p, flags, mode);
    int e = errno;
    ProbeShaderAccess("open", path, p, r, e);
    errno = e;
    LogMissing("open", path, r);
    return r;
}
EXPORT FILE *fopen(const char *path, const char *m) {
    REAL(FILE *, "fopen", const char *, const char *);
    char buf[PATH_MAX];
    const char *p = Redirect(path, buf, sizeof buf);
    FILE *f = real(p, m);
    int e = errno;
    ProbeShaderAccess("fopen", path, p, f ? 0 : -1, e);
    errno = e;
    return f;
}
EXPORT int stat(const char *path, struct stat *st) {
    REAL(int, "stat", const char *, struct stat *);
    char buf[PATH_MAX];
    const char *p = Redirect(path, buf, sizeof buf);
    int r = real(p, st);
    int e = errno;
    ProbeShaderAccess("stat", path, p, r, e);
    errno = e;
    LogMissing("stat", path, r);
    return r;
}
EXPORT int access(const char *path, int m) {
    REAL(int, "access", const char *, int);
    char buf[PATH_MAX];
    const char *p = Redirect(path, buf, sizeof buf);
    int r = real(p, m);
    int e = errno;
    ProbeShaderAccess("access", path, p, r, e);
    errno = e;
    LogMissing("access", path, r);
    return r;
}
// Case-insensitive resolution for any absolute path (the read-only bundle included, which
// FixCase's data-container prefix check excludes). POSIX only (real access/opendir), so it is
// safe inside the dlopen interposer. Only walks when the exact path does not exist.
static const char *FixCaseAbs(const char *path, char *buf, size_t size) {
    static int (*realAccess)(const char *, int);
    if (!realAccess) realAccess = RealLibc("access");
    if (realAccess(path, F_OK) == 0) return path;
    static DIR *(*realOpendir)(const char *);
    if (!realOpendir) realOpendir = RealLibc("opendir");
    char out[PATH_MAX];
    out[0] = '\0';
    const char *rest = path;
    while (*rest == '/') rest++;
    while (*rest) {
        const char *slash = strchr(rest, '/');
        size_t len = slash ? (size_t)(slash - rest) : strlen(rest);
        char comp[NAME_MAX + 1];
        snprintf(comp, sizeof comp, "%.*s", (int)len, rest);
        char probe[PATH_MAX];
        snprintf(probe, sizeof probe, "%s/%s", out, comp);
        if (realAccess(probe, F_OK) != 0) {
            DIR *d = realOpendir(out);
            struct dirent *e;
            while (d && (e = readdir(d))) if (!strcasecmp(e->d_name, comp)) { strlcpy(comp, e->d_name, sizeof comp); break; }
            if (d) closedir(d);
        }
        strlcat(out, "/", sizeof out);
        strlcat(out, comp, sizeof out);
        rest += len;
        while (*rest == '/') rest++;
    }
    strlcpy(buf, out, size);
    return buf;
}
// dyld resolves dlopen paths case-sensitively on iOS (its lookup bypasses the hooked open/stat).
// Mac binaries rely on case-insensitive resolution: UE asks for "libAPEXFramework.dylib" but the
// file ships as "libApexFramework.dylib", so InitGamePhys fails and PreInit exits. Apply the same
// case fallback used for open/stat, but only when the exact path fails to load.
EXPORT void *dlopen(const char *path, int mode) {
    static void *(*real_dlopen)(const char *, int);
    if (!real_dlopen) {
        void *p = dlsym(RTLD_DEFAULT, "dlopen");
        if (p == (void *)dlopen) p = dlsym(RTLD_NEXT, "dlopen");
        real_dlopen = (void *(*)(const char *, int))p;
    }
    if (!real_dlopen) return NULL;
    static _Thread_local int inside;
    if (inside || !path) return real_dlopen(path, mode);
    inside = 1;
    void *h = real_dlopen(path, mode);
    if (!h) {
        char abs[PATH_MAX];
        const char *base = path;
        if (path[0] != '/') {
            char cwd[PATH_MAX];
            if (getcwd(cwd, sizeof cwd) && AbsoluteNormalized(cwd, path, abs, sizeof abs)) base = abs;
        }
        if (base[0] == '/') {
            char fixed[PATH_MAX];
            const char *f = FixCaseAbs(base, fixed, sizeof fixed);
            if (f != base) h = real_dlopen(f, mode);
        }
    }
    inside = 0;
    return h;
}
EXPORT DIR *opendir(const char *path) { REAL(DIR *, "opendir", const char *); char buf[PATH_MAX]; return real(Redirect(path, buf, sizeof buf)); }
EXPORT int mkdir(const char *path, mode_t m) { REAL(int, "mkdir", const char *, mode_t); char buf[PATH_MAX]; return real(Redirect(path, buf, sizeof buf), m); }
EXPORT int rmdir(const char *path) { REAL(int, "rmdir", const char *); char buf[PATH_MAX]; return real(Redirect(path, buf, sizeof buf)); }
EXPORT int unlink(const char *path) { REAL(int, "unlink", const char *); char buf[PATH_MAX]; return real(Redirect(path, buf, sizeof buf)); }
EXPORT int remove(const char *path) { REAL(int, "remove", const char *); char buf[PATH_MAX]; return real(Redirect(path, buf, sizeof buf)); }
// Info.plist SHIMWorkingDirectory = "Contents/UE4/Hk_project/Binaries/Mac" (convert_app.py --working-dir):
// the game's own cwd on macOS. Relative engine paths ("../../../Engine/...") resolve from there.
static const char *WorkingDirOverride(const char *path, char *buf, size_t size) {
    static NSString *sub, *root, *macRoot;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sub = NSBundle.mainBundle.infoDictionary[@"SHIMWorkingDirectory"];
        root = NSBundle.mainBundle.bundlePath;
        NSString *mr = NSBundle.mainBundle.infoDictionary[@"SHIMMacRoot"] ?: @"Mac";
        macRoot = [root stringByAppendingPathComponent:mr];
    });
    if (!sub || !root || !path) return path;
    size_t n = strlen(path);
    while (n > 1 && path[n - 1] == '/') n--;
    const char *rootC = root.fileSystemRepresentation;
    if (strlen(rootC) == n && !strncmp(path, rootC, n)) {
        snprintf(buf, size, "%s/%s", rootC, sub.UTF8String);
        return buf;
    }
    if (macRoot) {
        const char *macRootC = macRoot.fileSystemRepresentation;
        if (strlen(macRootC) == n && !strncmp(path, macRootC, n)) {
            snprintf(buf, size, "%s/%s", macRootC, sub.UTF8String);
            NSLog(@"SHIM chdir auto-corrected Mac root \"%s\" -> \"%s\"", path, buf);
            return buf;
        }
    }
    return path;
}

EXPORT int chdir(const char *path) {
    REAL(int, "chdir", const char *);
    char buf[PATH_MAX], wd[PATH_MAX];
    const char *p = Redirect(path, buf, sizeof buf);
    p = WorkingDirOverride(p, wd, sizeof wd);
    int r = real(p);
    NSLog(@"SHIM chdir \"%s\" (as %s) -> %d", path, p, r);
    return r;
}
// Mac games derive their folders from the executable path; report the Mac layout like
// -[NSBundle executablePath] does (the real binary sits at the bundle root, see convert_app.py).
EXPORT int _NSGetExecutablePath(char *out, uint32_t *size) {
    REAL(int, "_NSGetExecutablePath", char *, uint32_t *);
    char exe[PATH_MAX]; uint32_t n = sizeof exe;
    if (real(exe, &n) != 0) return real(out, size);
    NSString *root = NSBundle.mainBundle.infoDictionary[@"SHIMMacRoot"];
    NSString *path = @(exe);
    if (root) path = [NSString stringWithFormat:@"%@/%@/Contents/MacOS/%@",
                      path.stringByDeletingLastPathComponent, root, path.lastPathComponent];
    const char *c = path.fileSystemRepresentation;
    if (strlen(c) + 1 > *size) { *size = (uint32_t)strlen(c) + 1; return -1; }
    strlcpy(out, c, *size);
    return 0;
}
// Foundation's chdir doesn't come through the export above (No Man's Sky: changeCurrentDirectoryPath:
// <bundle>/Contents/Resources/GAMEDATA, then opens gpu.cfg relative to it).
static BOOL ShimChangeDir(id self, SEL _cmd, NSString *path) { return chdir(path.fileSystemRepresentation) == 0; }
// Same for existence checks (No Man's Sky tests Contents/Resources/GAMEDATA before changing into it).
static BOOL ShimExistsDir(id self, SEL _cmd, NSString *path, BOOL *isDir) {
    struct stat st;
    if (!path || stat(path.fileSystemRepresentation, &st) != 0) return NO;  // our stat redirects
    if (isDir) *isDir = S_ISDIR(st.st_mode);
    return YES;
}
static BOOL ShimExists(id self, SEL _cmd, NSString *path) { return ShimExistsDir(self, _cmd, path, NULL); }
__attribute__((constructor)) static void HookChangeDir(void) {
    class_replaceMethod(NSFileManager.class, @selector(changeCurrentDirectoryPath:), (IMP)ShimChangeDir, "c@:@");
    class_replaceMethod(NSFileManager.class, @selector(fileExistsAtPath:), (IMP)ShimExists, "c@:@");
    class_replaceMethod(NSFileManager.class, @selector(fileExistsAtPath:isDirectory:), (IMP)ShimExistsDir, "c@:@^c");
}
EXPORT int rename(const char *a, const char *b) {
    REAL(int, "rename", const char *, const char *);
    char b1[PATH_MAX], b2[PATH_MAX]; return real(Redirect(a, b1, sizeof b1), Redirect(b, b2, sizeof b2));
}
EXPORT char *shim_realpath(const char *path, char *out) __asm__("_realpath$DARWIN_EXTSN");
char *shim_realpath(const char *path, char *out) {
    REAL(char *, "realpath$DARWIN_EXTSN", const char *, char *); char buf[PATH_MAX]; return real(Redirect(path, buf, sizeof buf), out);
}

// MARK: reported RAM (Info.plist SHIMReportedMemoryGB). Some engines size their address-space
// reservations from RAM; a constrained device may need to report less.
// NSProcessInfo.physicalMemory is handled in RuntimeHooks.
#import <sys/sysctl.h>
uint64_t ShimReportedMemory(void) {
    static uint64_t v = UINT64_MAX;
    if (v == UINT64_MAX) {
        NSNumber *gb = NSBundle.mainBundle.infoDictionary[@"SHIMReportedMemoryGB"];
        v = gb ? (uint64_t)(gb.doubleValue * 1073741824.0) : 0;
    }
    return v;
}
EXPORT int sysctlbyname(const char *name, void *old, size_t *oldlen, void *newp, size_t newlen) {
    REAL(int, "sysctlbyname", const char *, void *, size_t *, void *, size_t);
    if (name && !strcmp(name, "hw.model")) {
        const char *fakeModel = "Mac16,12";
        size_t fakeLen = strlen(fakeModel) + 1;
        if (oldlen) {
            if (old) {
                size_t copyLen = (*oldlen < fakeLen) ? *oldlen : fakeLen;
                memcpy(old, fakeModel, copyLen);
            }
            *oldlen = fakeLen;
        }
        NSLog(@"SHIM SYSCTL hw.model = %s", fakeModel);
        return 0;
    }
    if (name && !strcmp(name, "hw.machine")) {
        const char *fakeMachine = "arm64";
        size_t fakeLen = strlen(fakeMachine) + 1;
        if (oldlen) {
            if (old) {
                size_t copyLen = (*oldlen < fakeLen) ? *oldlen : fakeLen;
                memcpy(old, fakeMachine, copyLen);
            }
            *oldlen = fakeLen;
        }
        NSLog(@"SHIM SYSCTL hw.machine = %s", fakeMachine);
        return 0;
    }
    int r = real(name, old, oldlen, newp, newlen);
    if (r == 0 && name && ShimReportedMemory() && (!strcmp(name, "hw.memsize") || !strcmp(name, "hw.physmem"))
        && old && oldlen && *oldlen >= sizeof(uint64_t)) {
        *(uint64_t *)old = ShimReportedMemory();
        NSLog(@"SHIM sysctl %s -> %.0f GB", name, ShimReportedMemory() / 1073741824.0);
    }
    return r;
}
EXPORT int sysctl(int *mib, u_int n, void *old, size_t *oldlen, void *newp, size_t newlen) {
    REAL(int, "sysctl", int *, u_int, void *, size_t *, void *, size_t);
    if (n >= 2 && mib[0] == CTL_HW && mib[1] == HW_MODEL) {
        const char *fakeModel = "Mac16,12";
        size_t fakeLen = strlen(fakeModel) + 1;
        if (oldlen) {
            if (old) {
                size_t copyLen = (*oldlen < fakeLen) ? *oldlen : fakeLen;
                memcpy(old, fakeModel, copyLen);
            }
            *oldlen = fakeLen;
        }
        NSLog(@"SHIM SYSCTL hw.model (mib) = %s", fakeModel);
        return 0;
    }
    if (n >= 2 && mib[0] == CTL_HW && mib[1] == HW_MACHINE) {
        const char *fakeMachine = "arm64";
        size_t fakeLen = strlen(fakeMachine) + 1;
        if (oldlen) {
            if (old) {
                size_t copyLen = (*oldlen < fakeLen) ? *oldlen : fakeLen;
                memcpy(old, fakeMachine, copyLen);
            }
            *oldlen = fakeLen;
        }
        NSLog(@"SHIM SYSCTL hw.machine (mib) = %s", fakeMachine);
        return 0;
    }
    int r = real(mib, n, old, oldlen, newp, newlen);
    if (r == 0 && n >= 2 && mib[0] == CTL_HW && mib[1] == HW_MEMSIZE && ShimReportedMemory() && old && oldlen && *oldlen >= 8) {
        *(uint64_t *)old = ShimReportedMemory();
        NSLog(@"SHIM sysctl hw.memsize (mib) -> %.0f GB", ShimReportedMemory() / 1073741824.0);
    }
    return r;
}

EXPORT void exit(int code) {
    static int inside;
    if (!inside++) {
        void *callers[64];
        int count = backtrace(callers, 64);
        char **symbols = backtrace_symbols(callers, count);
        NSLog(@"SHIM INTERCEPTED exit(%d)! Backtrace (%d frames):", code, count);
        for (int i = 0; i < count; i++) {
            NSLog(@"  frame #%d: %s", i, symbols ? symbols[i] : "?");
        }
    }
    REAL(void, "exit", int);
    real(code);
}

EXPORT void _exit(int code) {
    static int inside;
    if (!inside++) {
        void *callers[64];
        int count = backtrace(callers, 64);
        char **symbols = backtrace_symbols(callers, count);
        NSLog(@"SHIM INTERCEPTED _exit(%d)! Backtrace (%d frames):", code, count);
        for (int i = 0; i < count; i++) {
            NSLog(@"  frame #%d: %s", i, symbols ? symbols[i] : "?");
        }
    }
    REAL(void, "_exit", int);
    real(code);
}

EXPORT void _Exit(int code) {
    static int inside;
    if (!inside++) {
        void *callers[64];
        int count = backtrace(callers, 64);
        char **symbols = backtrace_symbols(callers, count);
        NSLog(@"SHIM INTERCEPTED _Exit(%d)! Backtrace (%d frames):", code, count);
        for (int i = 0; i < count; i++) {
            NSLog(@"  frame #%d: %s", i, symbols ? symbols[i] : "?");
        }
        intptr_t slide = _dyld_get_image_vmaddr_slide(0);
        const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
        if (mh && mh->magic == MH_MAGIC_64) {
            uint8_t *pReqExit = (uint8_t *)((uintptr_t)slide + 0x1053c5717ULL);
            int32_t *pFeatureLevel = (int32_t *)((uintptr_t)slide + 0x10507737cULL);
            uint8_t *pAppleMetal = (uint8_t *)((uintptr_t)slide + 0x105077378ULL);
            int32_t featLevel = pFeatureLevel ? *pFeatureLevel : -1;
            int32_t shaderPlatform = -1;
            if (featLevel >= 0 && featLevel <= 7) {
                int32_t *pShaderPlatform = (int32_t *)((uintptr_t)slide + 0x1050773e4ULL + (featLevel * 4));
                shaderPlatform = pShaderPlatform ? *pShaderPlatform : -1;
            }
            int32_t *pMaxShaderPlatform = (int32_t *)((uintptr_t)slide + 0x1053eceb0ULL);
            void **pGDynamicRHI = (void **)((uintptr_t)slide + 0x1053ec758ULL);
            uint8_t *pIsRHIInit = (uint8_t *)((uintptr_t)slide + 0x1053efb44ULL);
            uint8_t *pIsMetalInit = (uint8_t *)((uintptr_t)slide + 0x1053431c0ULL);
            uint8_t *pIsCritErr = (uint8_t *)((uintptr_t)slide + 0x1053c570fULL);
            const unichar *pErrorHist = (const unichar *)((uintptr_t)slide + 0x1053bb648ULL);
            const unichar *pDesc = (const unichar *)((uintptr_t)slide + 0x1053c3648ULL);

            NSString *errHistStr = @"";
            if (pErrorHist && pErrorHist[0]) {
                size_t l = 0; while (pErrorHist[l] && l < 1024) l++;
                errHistStr = [NSString stringWithCharacters:pErrorHist length:l];
            }
            NSString *descStr = @"";
            if (pDesc && pDesc[0]) {
                size_t l = 0; while (pDesc[l] && l < 1024) l++;
                descStr = [NSString stringWithCharacters:pDesc length:l];
            }

            NSLog(@"SHIM UE STATE AT _Exit: slide=0x%lx GIsRequestingExit=%d GMaxRHIFeatureLevel=%d GShaderPlatformForFeatureLevel=%d GMaxRHIShaderPlatform=%d GAppleMetalEnabled=%d GDynamicRHI=%p GIsRHIInitialized=%d GIsMetalInitialized=%d GIsCriticalError=%d",
                  (unsigned long)slide, pReqExit ? *pReqExit : -1, featLevel, shaderPlatform,
                  pMaxShaderPlatform ? *pMaxShaderPlatform : -1, pAppleMetal ? *pAppleMetal : -1,
                  pGDynamicRHI ? *pGDynamicRHI : NULL, pIsRHIInit ? *pIsRHIInit : -1,
                  pIsMetalInit ? *pIsMetalInit : -1, pIsCritErr ? *pIsCritErr : -1);
            if (errHistStr.length > 0) NSLog(@"SHIM UE GErrorHist: \"%@\"", errHistStr);
            if (descStr.length > 0) NSLog(@"SHIM UE GErrorExceptionDescription: \"%@\"", descStr);

            uintptr_t pGLog = (uintptr_t)slide + 0x10521a490ULL;
            int32_t numLines = *(int32_t *)(pGLog + 0x298);
            NSLog(@"SHIM UE GLog: pGLog=0x%lx numLines=%d", (unsigned long)pGLog, numLines);
            if (numLines > 0 && numLines < 5000) {
                void *dataPtr = *(void **)(pGLog + 0x290);
                if (!dataPtr) dataPtr = (void *)(pGLog + 0x10);
                for (int i = 0; i < numLines && i < 200; i++) {
                    uintptr_t entry = (uintptr_t)dataPtr + (i * 40);
                    const unichar *lineChars = *(const unichar **)entry;
                    uint8_t verbosity = *(uint8_t *)(entry + 0x20);
                    if (lineChars && (uintptr_t)lineChars > 0x10000) {
                        size_t l = 0;
                        while (lineChars[l] && l < 2048) l++;
                        if (l > 0) {
                            NSString *s = [NSString stringWithCharacters:lineChars length:l];
                            NSLog(@"[UE_BUFFERED #%d v=%u] %@", i, (unsigned)verbosity, s);
                        }
                    }
                }
            }
        }
        fflush(stdout);
        fflush(stderr);
    }
    REAL(void, "_Exit", int);
    real(code);
}

EXPORT void abort(void) {
    static int inside;
    if (!inside++) {
        void *callers[64];
        int count = backtrace(callers, 64);
        char **symbols = backtrace_symbols(callers, count);
        NSLog(@"SHIM INTERCEPTED abort()! Backtrace (%d frames):", count);
        for (int i = 0; i < count; i++) {
            NSLog(@"  frame #%d: %s", i, symbols ? symbols[i] : "?");
        }
    }
    REAL(void, "abort", void);
    real();
}

// MARK: Crash handlers
// Games install their own SIGSEGV/SIGBUS handlers, which swallow crashes (no iOS crash report;
// No Man's Sky prints "Caught SIGSEGV" and spins). Log where the fault is, then run theirs.
static struct sigaction gGameAction[NSIG];

static void ShimLogAddr(const char *what, uintptr_t a) {
    Dl_info d = {0};
    char line[400];
    if (dladdr((void *)a, &d) && d.dli_fname) {
        const char *base = strrchr(d.dli_fname, '/');
        snprintf(line, sizeof line, "SHIM FAULT %s 0x%lx = %s+0x%lx (%s)\n", what, (unsigned long)a,
                 base ? base + 1 : d.dli_fname, (unsigned long)(a - (uintptr_t)d.dli_fbase), d.dli_sname ?: "?");
    } else {
        snprintf(line, sizeof line, "SHIM FAULT %s 0x%lx\n", what, (unsigned long)a);
    }
    write(2, line, strlen(line));
}

static void ShimFault(int sig, siginfo_t *si, void *ctx) {
    static int logged;
    if (logged++ < 3) {
        ucontext_t *uc = ctx;
        char line[120];
        snprintf(line, sizeof line, "SHIM FAULT signal %d address 0x%lx\n", sig, (unsigned long)si->si_addr);
        write(2, line, strlen(line));
        ShimLogAddr("pc", (uintptr_t)arm_thread_state64_get_pc(uc->uc_mcontext->__ss));
        ShimLogAddr("lr", (uintptr_t)arm_thread_state64_get_lr(uc->uc_mcontext->__ss));
    }
    struct sigaction *g = &gGameAction[sig];
    if (g->sa_flags & SA_SIGINFO) g->sa_sigaction(sig, si, ctx);
    else if (g->sa_handler != SIG_DFL && g->sa_handler != SIG_IGN) g->sa_handler(sig);
    else signal(sig, SIG_DFL);  // returns and re-faults with the default action
}

EXPORT int sigaction(int sig, const struct sigaction *act, struct sigaction *old) {
    REAL(int, "sigaction", int, const struct sigaction *, struct sigaction *);
    BOOL fault = sig == SIGSEGV || sig == SIGBUS || sig == SIGILL || sig == SIGABRT;
    if (!fault || !act || act->sa_handler == SIG_DFL || act->sa_handler == SIG_IGN) return real(sig, act, old);
    struct sigaction prev = gGameAction[sig], mine = *act;
    mine.sa_sigaction = ShimFault;
    mine.sa_flags |= SA_SIGINFO;
    int r = real(sig, &mine, old);
    if (r == 0) {
        if (old && old->sa_sigaction == ShimFault) *old = prev;
        gGameAction[sig] = *act;
    }
    return r;
}

EXPORT void (*signal(int sig, void (*h)(int)))(int) {
    struct sigaction act = {0}, old = {0};
    act.sa_handler = h;
    sigemptyset(&act.sa_mask);
    return sigaction(sig, &act, &old) == 0 ? old.sa_handler : SIG_ERR;
}

// MARK: diagnostics (ShimTrace). Every 200 us, samples UE's RHI and exit globals (link addresses from
// nm of Stray-Mac-Shipping). On each change it logs every thread's call stack as link-time addresses
// (pc - slide). A thread is suspended only while its registers and frame records are copied.
struct ShimTraceState {
    uint8_t reqExit, rhiInit, metalInit, appleMetal, critErr;
    int32_t featLevel, maxShaderPlatform;
    void *dynRHI;
    uint16_t errHist0;
};

static int ShimTraceDumps;
static mach_port_t ShimTraceGameThread = MACH_PORT_NULL;
static int ShimTraceSamplesPrinted;
static int ShimTraceProbed;
#define ShimTraceKeep 2000
static uint64_t ShimTraceSamples[ShimTraceKeep][6];
static int ShimTraceSampleCount;

// Link-time range of GuardedMain (its return addresses identify the game thread).
static BOOL ShimTraceInGuardedMain(const uint64_t *f, int n, uintptr_t slide) {
    for (int k = 0; k < n; k++) {
        uint64_t a = f[k] - slide;
        if (a >= 0x10066a598ULL && a < 0x10066c7b8ULL) return YES;
    }
    return NO;
}

static void ShimTraceDump(uintptr_t slide, const struct ShimTraceState *s) {
    enum { kThreads = 128, kFrames = 24 };
    static uint64_t frames[kThreads][kFrames];
    static int counts[kThreads];
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t total = 0;
    if (task_threads(mach_task_self(), &threads, &total) != KERN_SUCCESS) return;
    mach_msg_type_number_t count = total < kThreads ? total : kThreads;
    mach_port_t me = mach_thread_self();
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        counts[i] = 0;
        if (threads[i] == me || thread_suspend(threads[i]) != KERN_SUCCESS) continue;
        arm_thread_state64_t st;
        mach_msg_type_number_t sc = ARM_THREAD_STATE64_COUNT;
        if (thread_get_state(threads[i], ARM_THREAD_STATE64, (thread_state_t)&st, &sc) == KERN_SUCCESS) {
            frames[i][counts[i]++] = st.__pc;
            if (st.__lr) frames[i][counts[i]++] = st.__lr;
            uint64_t fp = st.__fp;
            while (counts[i] < kFrames && fp && !(fp & 7)) {
                uint64_t rec[2];
                vm_size_t got = 0;
                if (vm_read_overwrite(mach_task_self(), (vm_address_t)fp, sizeof rec, (vm_address_t)rec, &got) != KERN_SUCCESS || got != sizeof rec) break;
                if (rec[1]) frames[i][counts[i]++] = rec[1];
                if (rec[0] <= fp) break;
                fp = rec[0];
            }
        }
        thread_resume(threads[i]);
    }
    for (mach_msg_type_number_t i = 0; i < total; i++) {
        if (i < count && ShimTraceGameThread == MACH_PORT_NULL && threads[i] != me && ShimTraceInGuardedMain(frames[i], counts[i], slide)) {
            ShimTraceGameThread = threads[i];
            continue;
        }
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, total * sizeof(thread_t));
    mach_port_deallocate(mach_task_self(), me);

    ShimTraceDumps++;
    fprintf(stderr, "SHIM TRACE #%d reqExit=%u featLevel=%d maxShaderPlatform=%d dynRHI=%p rhiInit=%u metalInit=%u appleMetal=%u critErr=%u errHist0=0x%x threads=%u\n",
            ShimTraceDumps, (unsigned)s->reqExit, s->featLevel, s->maxShaderPlatform, s->dynRHI, (unsigned)s->rhiInit,
            (unsigned)s->metalInit, (unsigned)s->appleMetal, (unsigned)s->critErr, (unsigned)s->errHist0, (unsigned)total);
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        if (!counts[i]) continue;
        fprintf(stderr, "SHIM TRACE #%d thread %u:", ShimTraceDumps, (unsigned)i);
        for (int k = 0; k < counts[i]; k++) fprintf(stderr, " %llx", (unsigned long long)(frames[i][k] - slide));
        fprintf(stderr, "\n");
    }
    fflush(stderr);
}

static void ShimTraceSample(uintptr_t slide) {
    arm_thread_state64_t st;
    mach_msg_type_number_t sc = ARM_THREAD_STATE64_COUNT;
    uint64_t pcs[6] = {0};
    int n = 0;
    if (thread_suspend(ShimTraceGameThread) != KERN_SUCCESS) return;
    if (thread_get_state(ShimTraceGameThread, ARM_THREAD_STATE64, (thread_state_t)&st, &sc) == KERN_SUCCESS) {
        pcs[n++] = st.__pc;
        uint64_t fp = st.__fp;
        while (n < 6 && fp && !(fp & 7)) {
            uint64_t rec[2];
            vm_size_t got = 0;
            if (vm_read_overwrite(mach_task_self(), (vm_address_t)fp, sizeof rec, (vm_address_t)rec, &got) != KERN_SUCCESS || got != sizeof rec) break;
            pcs[n++] = rec[1];
            if (rec[0] <= fp) break;
            fp = rec[0];
        }
    }
    thread_resume(ShimTraceGameThread);
    memcpy(ShimTraceSamples[ShimTraceSampleCount % ShimTraceKeep], pcs, sizeof pcs);
    ShimTraceSampleCount++;
}

static void ShimTracePrintSamples(uintptr_t slide) {
    int kept = ShimTraceSampleCount < 400 ? ShimTraceSampleCount : 400;
    int first = ShimTraceSampleCount - kept;
    fprintf(stderr, "SHIM SAMPLES total=%d kept=%d (oldest first; link addresses, pc then return addresses)\n", ShimTraceSampleCount, kept);
    for (int k = 0; k < kept; k++) {
        uint64_t *s = ShimTraceSamples[(first + k) % ShimTraceKeep];
        fprintf(stderr, "SHIM S%d:", first + k);
        for (int j = 0; j < 6 && s[j]; j++) fprintf(stderr, " %llx", (unsigned long long)(s[j] - slide));
        fprintf(stderr, "\n");
    }
    fflush(stderr);
}

typedef void *(*ShimUEGetDllHandleFn)(const unichar *);

static void ShimProbePhysX(void) {
    char cwd[PATH_MAX] = {0};
    fprintf(stderr, "SHIM PROBE cwd=%s\n", getcwd(cwd, sizeof cwd) ? cwd : "?");
    fprintf(stderr, "SHIM PROBE dlsym dlopen RTLD_DEFAULT=%p RTLD_NEXT=%p self=%p\n", dlsym(RTLD_DEFAULT, "dlopen"), dlsym(RTLD_NEXT, "dlopen"), (void *)dlopen);
    uintptr_t slide = (uintptr_t)_dyld_get_image_vmaddr_slide(0);
    volatile int64_t *ver = (volatile int64_t *)(slide + 0x10520c590ULL);
    fprintf(stderr, "SHIM PROBE GMacAppInfo OS version = %lld.%lld.%lld\n", (long long)ver[0], (long long)ver[1], (long long)ver[2]);
    ShimUEGetDllHandleFn ueGetDllHandle = (ShimUEGetDllHandleFn)(slide + 0x10136eacc);
    NSArray *ueLibs = @[@"libPxFoundation", @"libPhysX3Common", @"libPxPvdSDK", @"libPhysX3", @"libPhysX3Cooking", @"libAPEXFramework", @"libAPEX_Legacy", @"libAPEX_Clothing"];
    for (NSString *name in ueLibs) {
        NSString *p = [@"../../../Engine/Binaries/ThirdParty/PhysX3/Mac/" stringByAppendingFormat:@"%@.dylib", name];
        unichar buf[256] = {0};
        [p getCharacters:buf range:NSMakeRange(0, MIN(p.length, 255))];
        void *h = ueGetDllHandle(buf);
        fprintf(stderr, "SHIM PROBE UE GetDllHandle %s -> %p\n", p.UTF8String, h);
    }
    fflush(stderr);
    NSArray *libs = @[@"libPxFoundation.dylib", @"libPhysX3Common.dylib", @"libPxPvdSDK.dylib", @"libPhysX3.dylib", @"libPhysX3Cooking.dylib"];
    NSString *rel = @"../../../Engine/Binaries/ThirdParty/PhysX3/Mac";
    for (NSString *lib in libs) {
        NSString *p = [rel stringByAppendingPathComponent:lib];
        void *h = dlopen(p.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
        fprintf(stderr, "SHIM PROBE rel dlopen %s -> %s\n", p.UTF8String, h ? "OK" : dlerror());
    }
    NSString *base = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/UE4/Engine/Binaries/ThirdParty/PhysX3/Mac"];
    for (NSString *lib in libs) {
        NSString *p = [base stringByAppendingPathComponent:lib];
        void *h = dlopen(p.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
        fprintf(stderr, "SHIM PROBE abs dlopen %s -> %s\n", lib.UTF8String, h ? "OK" : dlerror());
    }
    void *hc = dlopen("../../../Engine/Binaries/ThirdParty/PhysX3/Mac/libAPEXFramework.dylib", RTLD_LAZY | RTLD_LOCAL);
    fprintf(stderr, "SHIM PROBE dlopen UPPERCASE libAPEXFramework rel -> %s\n", hc ? "OK" : dlerror());
    void *he = dlopen("../../../Engine/Binaries/ThirdParty/PhysX3/Mac/libApexFramework.dylib", RTLD_LAZY | RTLD_LOCAL);
    fprintf(stderr, "SHIM PROBE dlopen exactcase libApexFramework rel -> %s\n", he ? "OK" : dlerror());
    fflush(stderr);
}

static void *ShimTraceLoop(void *arg) {
    uintptr_t slide = (uintptr_t)_dyld_get_image_vmaddr_slide(0);
    volatile uint8_t *reqExit = (volatile uint8_t *)(slide + 0x1053c5717ULL);
    volatile int32_t *featLevel = (volatile int32_t *)(slide + 0x10507737cULL);
    volatile int32_t *maxShaderPlatform = (volatile int32_t *)(slide + 0x1053eceb0ULL);
    void *volatile *dynRHI = (void *volatile *)(slide + 0x1053ec758ULL);
    volatile uint8_t *rhiInit = (volatile uint8_t *)(slide + 0x1053efb44ULL);
    volatile uint8_t *metalInit = (volatile uint8_t *)(slide + 0x1053431c0ULL);
    volatile uint8_t *appleMetal = (volatile uint8_t *)(slide + 0x105077378ULL);
    volatile uint8_t *critErr = (volatile uint8_t *)(slide + 0x1053c570fULL);
    volatile uint16_t *errHist = (volatile uint16_t *)(slide + 0x1053bb648ULL);
    fprintf(stderr, "SHIM TRACE armed: slide=0x%lx\n", (unsigned long)slide);
    struct ShimTraceState prev, cur;
    memset(&prev, 0, sizeof prev);
    int have = 0;
    for (;;) {
        memset(&cur, 0, sizeof cur);
        cur.reqExit = *reqExit;
        cur.featLevel = *featLevel;
        cur.maxShaderPlatform = *maxShaderPlatform;
        cur.dynRHI = *dynRHI;
        cur.rhiInit = *rhiInit;
        cur.metalInit = *metalInit;
        cur.appleMetal = *appleMetal;
        cur.critErr = *critErr;
        cur.errHist0 = *errHist;
        if (ShimTraceGameThread != MACH_PORT_NULL && !ShimTraceProbed) {
            ShimTraceProbed = 1;
            ShimProbePhysX();
        }
        if (ShimTraceGameThread != MACH_PORT_NULL && !ShimTraceSamplesPrinted) {
            if (cur.reqExit) {
                ShimTracePrintSamples(slide);
                ShimTraceSamplesPrinted = 1;
            } else {
                ShimTraceSample(slide);
            }
        }
        if (!have || memcmp(&cur, &prev, sizeof cur) != 0) {
            if (ShimTraceDumps < 300) ShimTraceDump(slide, &cur);
            prev = cur;
            have = 1;
        }
        usleep(ShimTraceGameThread != MACH_PORT_NULL ? 20 : 200);
    }
    return NULL;
}

__attribute__((constructor)) static void ShimTraceInit(void) {
    pthread_t t;
    if (pthread_create(&t, NULL, ShimTraceLoop, NULL) == 0) pthread_detach(t);
}
