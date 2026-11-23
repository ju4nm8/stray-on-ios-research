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

// IOKit on iOS: Mac system-power notifications and synthetic GPU IORegistry entry for UE4.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <dlfcn.h>

// ============================================================================
// MARK: Forward Declarations
// ============================================================================

mach_port_t IOIteratorNext(mach_port_t iterator);
kern_return_t IOObjectRelease(mach_port_t object);
kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort, CFDictionaryRef matching, mach_port_t *existing);

// ============================================================================
// MARK: System Power Notification Stubs (Unity / Engine compatibility)
// ============================================================================

typedef struct IONotificationPort *IONotificationPortRef;
typedef void (*IOServiceInterestCallback)(void *refcon, mach_port_t service, uint32_t type, void *arg);

static struct { int unused; } gDummyPort;
static IONotificationPortRef const kDummyPort = (IONotificationPortRef)&gDummyPort;

static CFRunLoopSourceRef DummySource(void) {
    static CFRunLoopSourceRef source;
    if (!source) {
        CFRunLoopSourceContext ctx = {0};
        source = CFRunLoopSourceCreate(NULL, 0, &ctx);
    }
    return source;
}

__attribute__((visibility("default")))
mach_port_t IORegisterForSystemPower(void *refcon, IONotificationPortRef *port, IOServiceInterestCallback cb, mach_port_t *notifier) {
    NSLog(@"SHIM IORegisterForSystemPower -> dummy port");
    if (port) *port = kDummyPort;
    if (notifier) *notifier = 1;
    return 1;  // nonzero = success
}

__attribute__((visibility("default"))) kern_return_t IODeregisterForSystemPower(mach_port_t *notifier) { return KERN_SUCCESS; }
__attribute__((visibility("default"))) kern_return_t IOAllowPowerChange(mach_port_t kernelPort, intptr_t id) { return KERN_SUCCESS; }
__attribute__((visibility("default"))) kern_return_t IOCancelPowerChange(mach_port_t kernelPort, intptr_t id) { return KERN_SUCCESS; }

__attribute__((visibility("default"))) CFRunLoopSourceRef IONotificationPortGetRunLoopSource(IONotificationPortRef port) {
    if (port == kDummyPort || !port) return DummySource();
    static CFRunLoopSourceRef (*real)(IONotificationPortRef);
    if (!real) real = dlsym(dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY), "IONotificationPortGetRunLoopSource");
    return real ? real(port) : DummySource();
}

__attribute__((visibility("default"))) void IONotificationPortDestroy(IONotificationPortRef port) {
    if (port == kDummyPort || !port) return;
    static void (*real)(IONotificationPortRef);
    if (!real) real = dlsym(dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY), "IONotificationPortDestroy");
    if (real) real(port);
}

// Missing symbols that iOS IOKit lacks entirely
__attribute__((visibility("default"))) CFDictionaryRef IODisplayCreateInfoDictionary(mach_port_t framebuffer, uint32_t options) { return NULL; }
__attribute__((visibility("default"))) CFDictionaryRef KextManagerCopyLoadedKextInfo(CFArrayRef kextIdentifiers, CFArrayRef keysToInclude) { return NULL; }
__attribute__((visibility("default"))) CFURLRef KextManagerCreateURLForBundleIdentifier(CFAllocatorRef allocator, CFStringRef bundleIdentifier) { return NULL; }

// ============================================================================
// MARK: Synthetic Apple Silicon GPU IORegistry Adapter for UE4 (FMacPlatformGPUManager)
// ============================================================================

enum {
    kShimIOIterSGX    = 0x53484940u,
    kShimIOEntrySGX   = 0x53484941u,
    kShimIOIterAccel  = 0x53484942u,
    kShimIOEntryAccel = 0x53484943u,
};

static int gShimSGXIterYielded = 0;
static int gShimAccelIterYielded = 0;

static void *RealIOKit(const char *name) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY);
    return h ? dlsym(h, name) : NULL;
}

static NSString *ShimMetalDeviceModel(void) {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    NSString *name = dev ? dev.name : nil;
    return (name && name.length > 0) ? name : @"Apple GPU";
}

static NSString *ShimMetalPluginName(void) {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    const char *img = dev ? class_getImageName(object_getClass(dev)) : NULL;
    if (img && *img) {
        NSString *base = @(img).lastPathComponent.stringByDeletingPathExtension;
        if (base && base.length > 0) return base;
    }
    return @"AGXMetal";
}

static CFMutableDictionaryRef CreateShimSGXCFDictionary(void) {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    const UInt8 sgxBytes[4] = { 's', 'g', 'x', 0 };
    CFDataRef devType = CFDataCreate(kCFAllocatorDefault, sgxBytes, sizeof(sgxBytes));
    const UInt8 vendorBytes[4] = { 0x6b, 0x10, 0x00, 0x00 };  // 0x0000106b LE (Apple)
    CFDataRef vendorData = CFDataCreate(kCFAllocatorDefault, vendorBytes, sizeof(vendorBytes));
    NSString *model = ShimMetalDeviceModel();
    CFDictionarySetValue(dict, CFSTR("device_type"), devType);
    CFDictionarySetValue(dict, CFSTR("vendor-id"), vendorData);
    CFDictionarySetValue(dict, CFSTR("model"), (__bridge CFStringRef)model);
    CFRelease(devType);
    CFRelease(vendorData);
    return dict;
}

static CFMutableDictionaryRef CreateShimAccelCFDictionary(void) {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    const UInt8 vendorBytes[4] = { 0x6b, 0x10, 0x00, 0x00 };  // 0x0000106b LE (Apple)
    CFDataRef vendorData = CFDataCreate(kCFAllocatorDefault, vendorBytes, sizeof(vendorBytes));
    NSString *model = ShimMetalDeviceModel();
    NSString *pluginName = ShimMetalPluginName();
    CFDictionarySetValue(dict, CFSTR("IOMatchCategory"), CFSTR("IOAccelerator"));
    CFDictionarySetValue(dict, CFSTR("IOClass"), CFSTR("AGXAccelerator"));
    CFDictionarySetValue(dict, CFSTR("CFBundleIdentifier"), CFSTR("com.apple.AGXMetal"));
    CFDictionarySetValue(dict, CFSTR("MetalPluginName"), (__bridge CFStringRef)pluginName);
    CFDictionarySetValue(dict, CFSTR("IOGLBundleName"), CFSTR("AppleMetalGLRenderer"));
    CFDictionarySetValue(dict, CFSTR("model"), (__bridge CFStringRef)model);
    CFDictionarySetValue(dict, CFSTR("vendor-id"), vendorData);
    CFRelease(vendorData);
    return dict;
}

__attribute__((visibility("default")))
CFMutableDictionaryRef IOServiceMatching(const char *name) {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if (name) {
        CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
        if (str) {
            CFDictionarySetValue(dict, CFSTR("IOProviderClass"), str);
            CFRelease(str);
        }
    }
    return dict;
}

__attribute__((visibility("default")))
kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort, CFDictionaryRef matching, mach_port_t *existing) {
    if (matching && CFGetTypeID(matching) == CFDictionaryGetTypeID()) {
        CFTypeRef cls = CFDictionaryGetValue(matching, CFSTR("IOProviderClass"));
        if (cls && CFGetTypeID(cls) == CFStringGetTypeID() &&
            CFEqual(cls, CFSTR("AppleARMIODevice"))) {
            CFRelease(matching);  // Standard Apple IOKit: consumes 1 reference to matching
            gShimSGXIterYielded = 0;
            if (existing) *existing = kShimIOIterSGX;
            NSLog(@"SHIM IOKit: IOServiceGetMatchingServices(AppleARMIODevice) -> iter=0x%x", kShimIOIterSGX);
            return KERN_SUCCESS;
        }
    }
    static kern_return_t (*real)(mach_port_t, CFDictionaryRef, mach_port_t *);
    if (!real) real = RealIOKit("IOServiceGetMatchingServices");
    if (!real) {
        if (matching) CFRelease(matching);
        return KERN_FAILURE;
    }
    return real(mainPort, matching, existing);
}

__attribute__((visibility("default")))
mach_port_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching) {
    mach_port_t iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(mainPort, matching, &iter);
    if (kr != KERN_SUCCESS || !iter) return 0;
    mach_port_t entry = IOIteratorNext(iter);
    IOObjectRelease(iter);
    return entry;
}

__attribute__((visibility("default")))
kern_return_t IOServiceOpen(mach_port_t service, mach_port_t owningTask, uint32_t type, mach_port_t *connect) {
    if (service == kShimIOEntrySGX || service == kShimIOEntryAccel) {
        if (connect) *connect = 1;
        return KERN_SUCCESS;
    }
    static kern_return_t (*real)(mach_port_t, mach_port_t, uint32_t, mach_port_t *);
    if (!real) real = RealIOKit("IOServiceOpen");
    return real ? real(service, owningTask, type, connect) : KERN_FAILURE;
}

__attribute__((visibility("default")))
mach_port_t IOIteratorNext(mach_port_t iterator) {
    if (iterator == kShimIOIterSGX) {
        if (!gShimSGXIterYielded) {
            gShimSGXIterYielded = 1;
            NSLog(@"SHIM IOKit: IOIteratorNext(sgxIter=0x%x) -> entry=0x%x", iterator, kShimIOEntrySGX);
            return kShimIOEntrySGX;
        }
        return 0;
    }
    if (iterator == kShimIOIterAccel) {
        if (!gShimAccelIterYielded) {
            gShimAccelIterYielded = 1;
            NSLog(@"SHIM IOKit: IOIteratorNext(accelIter=0x%x) -> child=0x%x", iterator, kShimIOEntryAccel);
            return kShimIOEntryAccel;
        }
        return 0;
    }
    static mach_port_t (*real)(mach_port_t);
    if (!real) real = RealIOKit("IOIteratorNext");
    return real ? real(iterator) : 0;
}

__attribute__((visibility("default")))
kern_return_t IOObjectRelease(mach_port_t object) {
    if (object == kShimIOIterSGX || object == kShimIOEntrySGX ||
        object == kShimIOIterAccel || object == kShimIOEntryAccel) {
        return KERN_SUCCESS;
    }
    static kern_return_t (*real)(mach_port_t);
    if (!real) real = RealIOKit("IOObjectRelease");
    return real ? real(object) : KERN_SUCCESS;
}

__attribute__((visibility("default")))
kern_return_t IORegistryEntryCreateCFProperties(mach_port_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options) {
    if (entry == kShimIOEntrySGX) {
        CFMutableDictionaryRef dict = CreateShimSGXCFDictionary();
        if (properties) *properties = dict;
        else CFRelease(dict);
        NSLog(@"SHIM IOKit: IORegistryEntryCreateCFProperties(SGX=0x%x) -> device_type=sgx", entry);
        return KERN_SUCCESS;
    }
    if (entry == kShimIOEntryAccel) {
        CFMutableDictionaryRef dict = CreateShimAccelCFDictionary();
        if (properties) *properties = dict;
        else CFRelease(dict);
        NSLog(@"SHIM IOKit: IORegistryEntryCreateCFProperties(IOAccelerator=0x%x) -> model=%@ plugin=%@",
              entry, ShimMetalDeviceModel(), ShimMetalPluginName());
        return KERN_SUCCESS;
    }
    static kern_return_t (*real)(mach_port_t, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
    if (!real) real = RealIOKit("IORegistryEntryCreateCFProperties");
    return real ? real(entry, properties, allocator, options) : KERN_FAILURE;
}

__attribute__((visibility("default")))
kern_return_t IORegistryEntryGetChildIterator(mach_port_t entry, const char *plane, mach_port_t *iterator) {
    if (entry == kShimIOEntrySGX) {
        gShimAccelIterYielded = 0;
        if (iterator) *iterator = kShimIOIterAccel;
        NSLog(@"SHIM IOKit: IORegistryEntryGetChildIterator(SGX=0x%x, plane=%s) -> iter=0x%x",
              entry, plane ?: "?", kShimIOIterAccel);
        return KERN_SUCCESS;
    }
    static kern_return_t (*real)(mach_port_t, const char *, mach_port_t *);
    if (!real) real = RealIOKit("IORegistryEntryGetChildIterator");
    return real ? real(entry, plane, iterator) : KERN_FAILURE;
}

__attribute__((visibility("default")))
CFTypeRef IORegistryEntryCreateCFProperty(mach_port_t entry, CFStringRef key, CFAllocatorRef allocator, uint32_t options) {
    if ((entry == kShimIOEntrySGX || entry == kShimIOEntryAccel) && key) {
        CFMutableDictionaryRef dict = (entry == kShimIOEntrySGX) ? CreateShimSGXCFDictionary() : CreateShimAccelCFDictionary();
        CFTypeRef val = CFDictionaryGetValue(dict, key);
        if (val) CFRetain(val);
        CFRelease(dict);
        return val;
    }
    static CFTypeRef (*real)(mach_port_t, CFStringRef, CFAllocatorRef, uint32_t);
    if (!real) real = RealIOKit("IORegistryEntryCreateCFProperty");
    return real ? real(entry, key, allocator, options) : NULL;
}

__attribute__((visibility("default")))
CFTypeRef IORegistryEntrySearchCFProperty(mach_port_t entry, const char *plane, CFStringRef key, CFAllocatorRef allocator, uint32_t options) {
    if ((entry == kShimIOEntrySGX || entry == kShimIOEntryAccel) && key) {
        CFMutableDictionaryRef accelDict = CreateShimAccelCFDictionary();
        CFTypeRef val = CFDictionaryGetValue(accelDict, key);
        if (val) {
            CFRetain(val);
            CFRelease(accelDict);
            return val;
        }
        CFRelease(accelDict);
        CFMutableDictionaryRef sgxDict = CreateShimSGXCFDictionary();
        val = CFDictionaryGetValue(sgxDict, key);
        if (val) CFRetain(val);
        CFRelease(sgxDict);
        return val;
    }
    static CFTypeRef (*real)(mach_port_t, const char *, CFStringRef, CFAllocatorRef, uint32_t);
    if (!real) real = RealIOKit("IORegistryEntrySearchCFProperty");
    return real ? real(entry, plane, key, allocator, options) : NULL;
}

__attribute__((visibility("default")))
kern_return_t IORegistryEntryGetRegistryEntryID(mach_port_t entry, uint64_t *entryID) {
    if (entry == kShimIOEntryAccel || entry == kShimIOEntrySGX) {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        uint64_t regID = dev ? dev.registryID : 1ULL;
        if (!regID) regID = 1ULL;
        if (entryID) *entryID = regID;
        NSLog(@"SHIM IOKit: GPU descriptor initialized (model=%@, plugin=%@, registryID=0x%llx, vendor=0x106b)",
              ShimMetalDeviceModel(), ShimMetalPluginName(), (unsigned long long)regID);
        return KERN_SUCCESS;
    }
    static kern_return_t (*real)(mach_port_t, uint64_t *);
    if (!real) real = RealIOKit("IORegistryEntryGetRegistryEntryID");
    return real ? real(entry, entryID) : KERN_FAILURE;
}
