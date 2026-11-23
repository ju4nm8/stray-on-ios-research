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

// Minimal AppKit implemented on UIKit, upgraded for Stray on iOS (Phase I.2):
// - Priority 1 (100% Fullscreen 16:9 Viewport): Unifies AppKit/CoreGraphics logical display dimensions
//   (1536x864 with 1.0 backingScaleFactor) with FMetalViewport::Resize and UIKit's CAMetalLayer
//   (768x432 pt container at 2.0x contentsScale = 1536x864 drawableSize), eliminating the 2x HiDPI
//   division that previously shrunk the game into the top-left 384x216 pt (1/4) quadrant. Also sanitizes
//   GameUserSettings.ini on launch and blocks any portrait drawable resize.
// - Priority 2 (Immediate SWindow Focus & Save Slot Start): Schedules asynchronous windowDidBecomeMain: /
//   windowDidBecomeKey: / NSApplicationDidBecomeActiveNotification callbacks after FCocoaWindow registration
//   in FMacApplication::Windows so FMacApplication::OnWindowActivationChanged activates the SWindow on frame 1
//   without requiring a screen tap.
// - Priority 3 (Precision Multi-Touch & Zero Overlap HUD): Pure virtual GCExtendedGamepad dispatch without
//   duplicate Keyboard/Mouse event collisions, fixed-center left analog joystick with 0.15 deadzone and
//   instant zero reset, sequence-guarded right-side camera drag, and zero-overlap A/B/X/Y diamond (abSize=46,
//   abStep=52 -> overlaps=0).
// - Priority 4 (DualShock 4 Priority): Exclusive PlayerIndex=0 ownership and automatic touch HUD hiding.
// - Priority 5 (FMallocBinned2 Crash Fix): Allocates GSavedCommandLine.Data via Unreal's own FMemory::Realloc
//   (0x1012b9928) instead of system calloc(), preventing the 0x113a30000 canary panic when returning to menu.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <sys/mman.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <crt_externs.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <unistd.h>
#import <math.h>

@class NSWindow, NSView, NSViewController, ShimTouchOverlayView, ShimVirtualGCController;

__attribute__((visibility("default"))) id NSApp = nil;
__attribute__((visibility("default"))) NSString *const NSApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
__attribute__((visibility("default"))) NSString *const NSApplicationWillFinishLaunchingNotification = @"NSApplicationWillFinishLaunchingNotification";

static NSMutableArray<NSWindow *> *gWindows;
static UIViewController *gRootVC;
static ShimTouchOverlayView *gTouchOverlay;
static NSUInteger gPressedMouseButtons = 0;

typedef NS_ENUM(NSInteger, ShimAspectMode) {
    ShimAspectMode16x9 = 0,       // Exact 16:9 fitted inside safe area (default: zero distortion, clears Dynamic Island)
    ShimAspectModeSafeArea = 1,   // Full horizontal/vertical safe area
    ShimAspectModeFullScreen = 2, // Full screen bounds
};

typedef NS_ENUM(NSInteger, ShimInputMode) {
    ShimInputModeHybrid = 0,      // Virtual GCExtendedGamepad primary + Keyboard/Mouse fallback if unpolled (default)
    ShimInputModeGamepadOnly = 1, // Virtual GCExtendedGamepad only
    ShimInputModeKeyMouseOnly = 2 // Synthetic NSEvent Keyboard + Mouse only
};

static ShimAspectMode gAspectMode = ShimAspectMode16x9;
static ShimInputMode gInputMode = ShimInputModeHybrid;
static CGFloat gLookSensitivity = 1.0;
static CGFloat gHudOpacity = 0.78;
static BOOL gMetalHudEnabled = NO;
static CGRect gCurrentViewportContainerRect = {94, 4, 768, 432};
static CGSize gCurrentViewportPoints = {1536, 864};
static CGFloat gCurrentViewportScale = 1.0;
static CGFloat gCurrentLayerContentsScale = 2.0;
static BOOL gUnrealPolledVirtualGamepad = NO;
static BOOL gUnrealPolledRealGamepad = NO;

static id ShimMissing(id self, SEL _cmd, ...) { return nil; }
static id ShimMissingInit(id self, SEL _cmd, ...) { return self; }

static BOOL ShimResolve(Class cls, SEL sel, BOOL isClass) {
    NSLog(@"SHIM MISSING %c[%@ %@]", isClass ? '+' : '-', NSStringFromClass(cls), NSStringFromSelector(sel));
    BOOL init = !isClass && [NSStringFromSelector(sel) hasPrefix:@"init"];
    class_addMethod(isClass ? object_getClass(cls) : cls, sel, (IMP)(init ? ShimMissingInit : ShimMissing), "@@:");
    return YES;
}

#define SHIM_RESOLVE \
    + (BOOL)resolveInstanceMethod:(SEL)sel { return [super resolveInstanceMethod:sel] || ShimResolve(self, sel, NO); } \
    + (BOOL)resolveClassMethod:(SEL)sel { return [super resolveClassMethod:sel] || ShimResolve(self, sel, YES); }

// MARK: Priority 1 — Viewport & Display Metrics Calculation (1:1 Logical-to-Drawable for Unreal)

static void ShimSaveViewportMetricsToDefaults(CGSize pts, CGFloat scale) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setDouble:pts.width forKey:@"SHIMActiveViewportPointsW"];
    [ud setDouble:pts.height forKey:@"SHIMActiveViewportPointsH"];
    [ud setDouble:scale forKey:@"SHIMActiveViewportScale"];
    [ud setInteger:gAspectMode forKey:@"SHIMAspectMode"];
}

static void ShimComputeViewportMetrics(CGRect containerBounds, UIEdgeInsets safeInsets, CGRect *outFrameInContainer, CGSize *outPoints, CGFloat *outScale) {
    CGFloat rawW = containerBounds.size.width;
    CGFloat rawH = containerBounds.size.height;
    if (rawW <= 0 || rawH <= 0) {
        CGSize sb = UIScreen.mainScreen.bounds.size;
        rawW = MAX(sb.width, sb.height);
        rawH = MIN(sb.width, sb.height);
        if (rawW <= 0 || rawH <= 0) { rawW = 956; rawH = 440; }
    }
    // Always compute landscape dimensions even if queried before UIKit finishes rotating the window scene
    CGFloat landW = MAX(rawW, rawH);
    CGFloat landH = MIN(rawW, rawH);

    CGFloat sideInset = MAX(safeInsets.left, safeInsets.right);
    if (sideInset <= 0 && landW > 800) sideInset = 62.0; // iPhone 17 Pro Max Dynamic Island fallback
    CGFloat safeW = MAX(320.0, landW - sideInset * 2.0);
    CGFloat safeH = landH;

    CGFloat vpW = landW;
    CGFloat vpH = landH;

    if (gAspectMode == ShimAspectMode16x9) {
        // Fit exact 16:9 inside landscape height (768x432 UIKit points -> 1536x864 render pixels)
        vpH = floor(landH / 9.0) * 9.0;
        vpW = (vpH / 9.0) * 16.0;
        if (vpW > safeW + 32.0) {
            vpW = floor(safeW / 16.0) * 16.0;
            vpH = (vpW / 16.0) * 9.0;
        }
    } else if (gAspectMode == ShimAspectModeSafeArea) {
        vpW = floor(safeW / 2.0) * 2.0;
        vpH = floor(safeH / 2.0) * 2.0;
    } else {
        vpW = floor(landW / 2.0) * 2.0;
        vpH = floor(landH / 2.0) * 2.0;
    }

    CGFloat ox = round((landW - vpW) * 0.5);
    CGFloat oy = round((landH - vpH) * 0.5);
    if (outFrameInContainer) *outFrameInContainer = CGRectMake(ox, oy, vpW, vpH);
    // Expose full target render pixel dimensions (e.g. 1536x864) with scale=1.0 to AppKit/CoreGraphics
    // so Unreal never divides the window or viewport size by 2.0!
    if (outPoints) *outPoints = CGSizeMake(round(vpW * gCurrentLayerContentsScale),
                                           round(vpH * gCurrentLayerContentsScale));
    if (outScale) *outScale = 1.0;
}

static void ShimInitializeDefaultViewportMetrics(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        if ([ud objectForKey:@"SHIMAspectMode"]) {
            gAspectMode = (ShimAspectMode)[ud integerForKey:@"SHIMAspectMode"];
        }
        NSNumber *plistHud = NSBundle.mainBundle.infoDictionary[@"MetalHudEnabled"];
        gMetalHudEnabled = plistHud ? plistHud.boolValue : NO;
        CGRect f; CGSize pts; CGFloat sc;
        ShimComputeViewportMetrics(CGRectZero, UIEdgeInsetsZero, &f, &pts, &sc);
        gCurrentViewportContainerRect = f;
        gCurrentViewportPoints = pts;
        gCurrentViewportScale = sc;
        ShimSaveViewportMetricsToDefaults(pts, sc);
    });
}

// MARK: NSEvent

typedef NS_ENUM(NSUInteger, NSEventType) {
    NSEventTypeLeftMouseDown = 1,
    NSEventTypeLeftMouseUp = 2,
    NSEventTypeRightMouseDown = 3,
    NSEventTypeRightMouseUp = 4,
    NSEventTypeMouseMoved = 5,
    NSEventTypeLeftMouseDragged = 6,
    NSEventTypeRightMouseDragged = 7,
    NSEventTypeMouseEntered = 8,
    NSEventTypeMouseExited = 9,
    NSEventTypeKeyDown = 10,
    NSEventTypeKeyUp = 11,
    NSEventTypeFlagsChanged = 12,
    NSEventTypeScrollWheel = 22,
    NSEventTypeOtherMouseDown = 25,
    NSEventTypeOtherMouseUp = 26,
    NSEventTypeOtherMouseDragged = 27,
};

@interface NSEvent : NSObject
@property NSEventType type;
@property CGPoint locationInWindow;
@property NSTimeInterval timestamp;
@property (weak) NSWindow *window;
@property NSInteger clickCount, buttonNumber;
@property NSUInteger modifierFlags;
@property unsigned short keyCode;
@property (copy) NSString *characters, *charactersIgnoringModifiers;
@property BOOL isARepeat, hasPreciseScrollingDeltas;
@property CGFloat scrollingDeltaX, scrollingDeltaY, deltaX, deltaY;
@property NSUInteger phase, momentumPhase;
@end

static NSMutableArray *gMonitors;  // {mask, handler}
static NSUInteger gModifiers;
static CGPoint gMouse = {768.0, 432.0};

static NSWindow *ShimActiveGameWindow(void);

@protocol ShimWindowEarlyAccess <NSObject>
- (NSInteger)windowNumber;
- (NSView *)contentView;
@end

@implementation NSEvent
SHIM_RESOLVE
+ (id)addLocalMonitorForEventsMatchingMask:(uint64_t)mask handler:(NSEvent *(^)(NSEvent *))handler {
    if (!gMonitors) gMonitors = [NSMutableArray new];
    id token = @[@(mask), [handler copy]];
    [gMonitors addObject:token];
    NSLog(@"SHIM NSEvent addLocalMonitorForEventsMatchingMask:0x%llx (monitors=%lu)",
          (unsigned long long)mask, (unsigned long)gMonitors.count);
    return token;
}
+ (id)addGlobalMonitorForEventsMatchingMask:(uint64_t)mask handler:(id)handler { return [NSObject new]; }
+ (void)removeMonitor:(id)token { [gMonitors removeObject:token]; }
+ (void)setMouseCoalescingEnabled:(BOOL)flag {}
+ (BOOL)isMouseCoalescingEnabled { return YES; }
+ (NSUInteger)modifierFlags { return gModifiers; }
+ (CGPoint)mouseLocation { return gMouse; }
+ (NSUInteger)pressedMouseButtons { return gPressedMouseButtons; }
+ (NSTimeInterval)doubleClickInterval { return 0.5; }
+ (NSTimeInterval)keyRepeatDelay { return 0.4; }
+ (NSTimeInterval)keyRepeatInterval { return 0.08; }
- (NSInteger)windowNumber {
    NSWindow *w = self.window ?: ShimActiveGameWindow();
    return w ? [(id<ShimWindowEarlyAccess>)w windowNumber] : 1;
}
- (CGFloat)deltaZ { return 0; }
- (id)subtype { return nil; }
- (NSUInteger)subtype_ { return 0; }
- (BOOL)isDirectionInvertedFromDevice { return NO; }
@end

// MARK: NSWorkspace / NSRunningApplication

__attribute__((visibility("default"))) NSString *const NSWorkspaceDidActivateApplicationNotification = @"NSWorkspaceDidActivateApplicationNotification";
__attribute__((visibility("default"))) NSString *const NSWorkspaceDidDeactivateApplicationNotification = @"NSWorkspaceDidDeactivateApplicationNotification";
__attribute__((visibility("default"))) NSString *const NSWorkspaceApplicationKey = @"NSWorkspaceApplicationKey";

@interface NSRunningApplication : NSObject
@end
@implementation NSRunningApplication
SHIM_RESOLVE
+ (instancetype)currentApplication { static id app; static dispatch_once_t once; dispatch_once(&once, ^{ app = [self new]; }); return app; }
- (pid_t)processIdentifier { return getpid(); }
- (NSString *)bundleIdentifier { return NSBundle.mainBundle.bundleIdentifier; }
- (NSString *)localizedName { return NSProcessInfo.processInfo.processName; }
- (BOOL)isActive { return UIApplication.sharedApplication.applicationState == UIApplicationStateActive; }
- (BOOL)isHidden { return UIApplication.sharedApplication.applicationState == UIApplicationStateBackground; }
- (BOOL)activateWithOptions:(NSUInteger)options { return YES; }
@end

@interface NSWorkspace : NSObject
@end
@implementation NSWorkspace
SHIM_RESOLVE
+ (instancetype)sharedWorkspace { static id ws; static dispatch_once_t once; dispatch_once(&once, ^{ ws = [self new]; }); return ws; }
- (NSNotificationCenter *)notificationCenter { static NSNotificationCenter *c; static dispatch_once_t once; dispatch_once(&once, ^{ c = [NSNotificationCenter new]; }); return c; }
- (NSRunningApplication *)frontmostApplication { return NSRunningApplication.currentApplication; }
- (NSArray *)runningApplications { return @[NSRunningApplication.currentApplication]; }
- (BOOL)isVoiceOverEnabled { return NO; }
- (BOOL)voiceOverEnabled { return NO; }
- (void)setVoiceOverEnabled:(BOOL)v {}
@end

static void ShimWorkspaceActivation(BOOL active) {
    [NSWorkspace.sharedWorkspace.notificationCenter
        postNotificationName:active ? NSWorkspaceDidActivateApplicationNotification : NSWorkspaceDidDeactivateApplicationNotification
                      object:NSWorkspace.sharedWorkspace
                    userInfo:@{NSWorkspaceApplicationKey: NSRunningApplication.currentApplication}];
}

// MARK: late observers
static IMP gAddObserver;
static void ShimAddObserver(NSNotificationCenter *self, SEL _cmd, id observer, SEL sel, NSString *name, id object) {
    ((void (*)(id, SEL, id, SEL, id, id))gAddObserver)(self, _cmd, observer, sel, name, object);
    if (self != NSNotificationCenter.defaultCenter || !name || !gWindows.count) return;
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) return;
    NSWindow *w = ShimActiveGameWindow();
    id sender = nil;
    if ([name isEqualToString:@"NSWindowDidBecomeKeyNotification"] || [name isEqualToString:@"NSWindowDidBecomeMainNotification"]) sender = w;
    else if ([name isEqualToString:@"NSApplicationDidBecomeActiveNotification"]) sender = NSApp;
    if (!sender || (object && object != sender)) return;
    NSLog(@"SHIM late observer for %@: delivering current state to %@", name, NSStringFromClass([observer class]));
    __weak id weakObserver = observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        id o = weakObserver;
        if (o) ((void (*)(id, SEL, id))objc_msgSend)(o, sel, [NSNotification notificationWithName:name object:sender]);
    });
}
__attribute__((constructor)) static void HookLateObservers(void) {
    gAddObserver = method_setImplementation(class_getInstanceMethod(NSNotificationCenter.class, @selector(addObserver:selector:name:object:)), (IMP)ShimAddObserver);
}

// MARK: NSResponder / NSView

@interface NSResponder : NSObject
@property (nonatomic, weak) NSResponder *nextResponder;
@end
@implementation NSResponder
SHIM_RESOLVE
#define SHIM_FORWARD(sel) - (void)sel(NSEvent *)e { [self.nextResponder sel e]; }
SHIM_FORWARD(mouseDown:) SHIM_FORWARD(mouseUp:) SHIM_FORWARD(mouseDragged:) SHIM_FORWARD(mouseMoved:)
SHIM_FORWARD(scrollWheel:) SHIM_FORWARD(keyDown:) SHIM_FORWARD(keyUp:) SHIM_FORWARD(flagsChanged:)
SHIM_FORWARD(rightMouseDown:) SHIM_FORWARD(rightMouseUp:)
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { return YES; }
- (BOOL)resignFirstResponder { return YES; }
@end

static void ShimDispatch(NSEvent *e);
static void ShimSyncWindowAndViewGeometry(NSWindow *w, BOOL notifyResize);
static void ShimApplyMetalHudSetting(void);

@interface ShimHostView : UIView
@property (weak) NSView *nsView;
@property BOOL pointerInside;
@property CGPoint lastTouchPoint;
@property BOOL hasLastTouchPoint;
@end

@interface NSView : NSResponder
@property (nonatomic) CGRect frame;
@property (nonatomic) BOOL wantsLayer;
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, readonly) ShimHostView *hostView;
@property (nonatomic, weak) NSView *superview;
@property (nonatomic, readonly) NSMutableArray<NSView *> *shimSubviews;
@property (nonatomic) BOOL postsFrameChangedNotifications;
@property (nonatomic) BOOL postsBoundsChangedNotifications;
@end

static IMP gOrigSetDrawableSize;
static void ShimSetDrawableSize(CAMetalLayer *self, SEL _cmd, CGSize size) {
    // Allow internal 16x16 dummy probe layer in ShimPacingLogInit without clamping or seeding lastLogged
    if (!self.superlayer && size.width <= 32.0 && size.height <= 32.0) {
        ((void (*)(id, SEL, CGSize))gOrigSetDrawableSize)(self, _cmd, size);
        return;
    }
    ShimInitializeDefaultViewportMetrics();
    CGSize target = gCurrentViewportPoints;
    if (size.height > size.width || size.width < 640.0 || size.height < 360.0) {
        NSLog(@"SHIM CAMetalLayer setDrawableSize: clamping invalid/portrait %.0fx%.0f -> %.0fx%.0f",
              size.width, size.height, target.width, target.height);
        size = target;
    }
    static CGSize lastLogged = {0, 0};
    if (fabs(size.width - lastLogged.width) > 0.5 || fabs(size.height - lastLogged.height) > 0.5) {
        lastLogged = size;
        NSLog(@"SHIM CAMetalLayer setDrawableSize: %.0fx%.0f (layer=%p superlayer=%p layerBounds=%.0fx%.0f contentsScale=%.1f)",
              size.width, size.height, self, self.superlayer, self.bounds.size.width, self.bounds.size.height, self.contentsScale);
    }
    ((void (*)(id, SEL, CGSize))gOrigSetDrawableSize)(self, _cmd, size);
}

__attribute__((constructor)) static void HookCAMetalLayerDrawableSize(void) {
    Method m = class_getInstanceMethod(CAMetalLayer.class, @selector(setDrawableSize:));
    if (m) gOrigSetDrawableSize = method_setImplementation(m, (IMP)ShimSetDrawableSize);
}

@implementation NSView
SHIM_RESOLVE
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super init])) {
        ShimInitializeDefaultViewportMetrics();
        CGRect logicalRect = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
        CGRect uikitRect = CGRectMake(0, 0, gCurrentViewportContainerRect.size.width, gCurrentViewportContainerRect.size.height);
        _frame = logicalRect;
        _hostView = [[ShimHostView alloc] initWithFrame:uikitRect];
        _hostView.nsView = self;
        _hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _postsFrameChangedNotifications = YES;
        _postsBoundsChangedNotifications = YES;
    }
    return self;
}
- (instancetype)init {
    ShimInitializeDefaultViewportMetrics();
    return [self initWithFrame:CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height)];
}
- (void)setFrame:(CGRect)frame {
    ShimInitializeDefaultViewportMetrics();
    _frame = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
    if (_hostView && _superview) {
        _hostView.frame = _superview.hostView.bounds;
    }
    if (_layer) {
        _layer.frame = _hostView.bounds;
        _layer.contentsScale = gCurrentLayerContentsScale;
        if ([_layer isKindOfClass:CAMetalLayer.class]) {
            _layer.contentsGravity = kCAGravityResizeAspect;
        }
    }
}
- (void)setFrameSize:(CGSize)newSize {
    [self setFrame:CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height)];
}
- (CGRect)bounds { return CGRectMake(0, 0, _frame.size.width, _frame.size.height); }
- (CGRect)convertRectToBacking:(CGRect)r { return r; }
- (CGRect)convertRectFromBacking:(CGRect)r { return r; }
- (CGSize)convertSizeToBacking:(CGSize)sz { return sz; }
- (CGSize)convertSizeFromBacking:(CGSize)sz { return sz; }
- (CGPoint)convertPointToBacking:(CGPoint)pt { return pt; }
- (CGPoint)convertPointFromBacking:(CGPoint)pt { return pt; }
- (void)setLayer:(CALayer *)layer {
    [_layer removeFromSuperlayer];
    _layer = layer;
    layer.frame = _hostView.bounds;
    layer.contentsScale = gCurrentLayerContentsScale;
    if ([layer isKindOfClass:CAMetalLayer.class]) {
        layer.opaque = YES;
        layer.contentsGravity = kCAGravityResizeAspect;
        CAMetalLayer *ml = (CAMetalLayer *)layer;
        if (ml.drawableSize.width <= 0 || ml.drawableSize.height <= 0) {
            ml.drawableSize = gCurrentViewportPoints;
        }
        ml.developerHUDProperties = gMetalHudEnabled ? @{@"mode": @"default"} : nil;
        NSLog(@"SHIM NSView setLayer CAMetalLayer on %@: hostBounds=%.0fx%.0f nsBounds=%.0fx%.0f drawable=%.0fx%.0f contentsScale=%.1f metalHud=%d",
              NSStringFromClass([self class]),
              _hostView.bounds.size.width, _hostView.bounds.size.height,
              _frame.size.width, _frame.size.height,
              ml.drawableSize.width, ml.drawableSize.height, layer.contentsScale, gMetalHudEnabled);
    }
    [_hostView.layer addSublayer:layer];
}
- (void)setWantsLayer:(BOOL)flag {
    _wantsLayer = flag;
    if (flag && !_layer)
        self.layer = [self respondsToSelector:@selector(makeBackingLayer)]
            ? ((CALayer *(*)(id, SEL))objc_msgSend)(self, @selector(makeBackingLayer)) : [CALayer layer];
}
- (CGPoint)convertPoint:(CGPoint)p fromView:(NSView *)view { return p; }
- (CGPoint)convertPoint:(CGPoint)p toView:(NSView *)view { return p; }
- (CGRect)convertRect:(CGRect)r fromView:(NSView *)view { return r; }
- (CGRect)convertRect:(CGRect)r toView:(NSView *)view { return r; }
- (NSArray<NSView *> *)subviews { return _shimSubviews ? [_shimSubviews copy] : @[]; }
- (void)addSubview:(NSView *)v {
    if (!v) return;
    if (!_shimSubviews) _shimSubviews = [NSMutableArray new];
    [v removeFromSuperview];
    [_shimSubviews addObject:v];
    v.superview = self;
    v.frame = self.bounds;
    v.hostView.frame = _hostView.bounds;
    v.hostView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.hostView.userInteractionEnabled = NO;
    [_hostView addSubview:v.hostView];
}
- (void)removeFromSuperview {
    [_superview.shimSubviews removeObject:self];
    _superview = nil;
    [_hostView removeFromSuperview];
}
- (NSWindow *)window { return _window ?: _superview.window; }
- (NSResponder *)nextResponder { return [super nextResponder] ?: (_superview ?: (NSResponder *)self.window); }
- (void)setAutoresizesSubviews:(BOOL)flag {}
- (BOOL)isHidden { return _hostView.hidden; }
- (void)setHidden:(BOOL)h { _hostView.hidden = h; }
- (NSView *)hitTest:(CGPoint)p {
    if (!CGRectContainsPoint(self.bounds, p) || self.isHidden) return nil;
    for (NSView *v in _shimSubviews.reverseObjectEnumerator) {
        NSView *h = [v hitTest:CGPointMake(p.x - v.frame.origin.x, p.y - v.frame.origin.y)];
        if (h) return h;
    }
    return self;
}
- (void)setNeedsDisplay:(BOOL)flag {}
- (void)setLayerContentsRedrawPolicy:(NSInteger)policy {}
- (CALayer *)makeBackingLayer { return [CALayer layer]; }
- (void)setAutoresizingMask:(NSUInteger)mask {}
- (void)addTrackingArea:(id)area {}
- (void)removeTrackingArea:(id)area {}
- (NSArray *)trackingAreas { return @[]; }
- (BOOL)isFlipped { return NO; }
@end

@interface NSViewController : NSResponder
@property (nonatomic, strong) NSView *view;
@end

@implementation NSViewController
SHIM_RESOLVE
- (NSView *)view {
    if (!_view) {
        [self loadView];
        if (!_view) _view = [NSView new];
        if ([self respondsToSelector:@selector(viewDidLoad)]) [self performSelector:@selector(viewDidLoad)];
    }
    return _view;
}
- (void)loadView {}
@end

@implementation ShimHostView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return;
    CGRect logicalBounds = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
    self.nsView.frame = logicalBounds;
    for (NSView *sub in self.nsView.shimSubviews) {
        sub.frame = logicalBounds;
        sub.hostView.frame = b;
        for (CALayer *sl in sub.hostView.layer.sublayers) {
            sl.frame = b;
            sl.contentsScale = gCurrentLayerContentsScale;
            if ([sl isKindOfClass:CAMetalLayer.class]) {
                sl.contentsGravity = kCAGravityResizeAspect;
            }
        }
    }
    for (CALayer *l in self.layer.sublayers) {
        if ([l.delegate isKindOfClass:UIView.class]) continue; // skip subview backing layers
        l.frame = b;
        l.contentsScale = gCurrentLayerContentsScale;
        if ([l isKindOfClass:CAMetalLayer.class]) {
            l.contentsGravity = kCAGravityResizeAspect;
        }
    }
    if (self.nsView.window && self.nsView == [(id<ShimWindowEarlyAccess>)self.nsView.window contentView]) {
        ShimSyncWindowAndViewGeometry(self.nsView.window, YES);
    }
}
- (NSEvent *)eventOfType:(NSEventType)type at:(CGPoint)p delta:(CGPoint)delta {
    NSEvent *e = [NSEvent new];
    e.type = type;
    CGFloat w = self.bounds.size.width > 0 ? self.bounds.size.width : gCurrentViewportContainerRect.size.width;
    CGFloat h = self.bounds.size.height > 0 ? self.bounds.size.height : gCurrentViewportContainerRect.size.height;
    CGFloat scaleX = (w > 0) ? (gCurrentViewportPoints.width / w) : 2.0;
    CGFloat scaleY = (h > 0) ? (gCurrentViewportPoints.height / h) : 2.0;
    e.locationInWindow = CGPointMake(p.x * scaleX, (h - p.y) * scaleY); // AppKit origin is bottom-left in 1536x864 window space
    gMouse = e.locationInWindow;
    e.deltaX = delta.x * scaleX;
    e.deltaY = delta.y * scaleY;
    e.timestamp = NSProcessInfo.processInfo.systemUptime;
    e.window = self.nsView.window ?: ShimActiveGameWindow();
    e.modifierFlags = gModifiers;
    return e;
}
- (void)send:(SEL)sel type:(NSEventType)type touches:(NSSet<UITouch *> *)touches {
    UITouch *t = touches.anyObject;
    if (!t) return;
    CGPoint p = [t locationInView:self];
    CGPoint delta = CGPointZero;
    if (type == NSEventTypeLeftMouseDown) {
        gPressedMouseButtons |= (1 << 0);
        self.lastTouchPoint = p;
        self.hasLastTouchPoint = YES;
        if (!self.pointerInside) {
            self.pointerInside = YES;
            NSEvent *enter = [self eventOfType:NSEventTypeMouseEntered at:p delta:CGPointZero];
            if ([self.nsView respondsToSelector:@selector(mouseEntered:)])
                [self.nsView performSelector:@selector(mouseEntered:) withObject:enter];
        }
        ShimDispatch([self eventOfType:NSEventTypeMouseMoved at:p delta:CGPointZero]);
    } else if (type == NSEventTypeLeftMouseDragged) {
        if (self.hasLastTouchPoint) {
            delta = CGPointMake(p.x - self.lastTouchPoint.x, p.y - self.lastTouchPoint.y);
        }
        self.lastTouchPoint = p;
        self.hasLastTouchPoint = YES;
    } else if (type == NSEventTypeLeftMouseUp) {
        gPressedMouseButtons &= ~(1UL << 0);
        self.hasLastTouchPoint = NO;
    }
    NSEvent *e = [self eventOfType:type at:p delta:delta];
    e.clickCount = MAX(1, t.tapCount);
    ShimDispatch(e);
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    static int n;
    if (n++ < 5) {
        CGPoint p = [t.anyObject locationInView:self];
        NSLog(@"SHIM direct viewport touch began (#%d) at (%.1f, %.1f) in bounds %.0fx%.0f",
              n, p.x, p.y, self.bounds.size.width, self.bounds.size.height);
    }
    [self send:@selector(mouseDown:) type:NSEventTypeLeftMouseDown touches:t];
}
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self send:@selector(mouseDragged:) type:NSEventTypeLeftMouseDragged touches:t]; }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self send:@selector(mouseUp:) type:NSEventTypeLeftMouseUp touches:t]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self send:@selector(mouseUp:) type:NSEventTypeLeftMouseUp touches:t]; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.gestureRecognizers.count) return;
    UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scroll:)];
    scroll.minimumNumberOfTouches = 2;
    scroll.allowedScrollTypesMask = UIScrollTypeMaskAll;
    scroll.cancelsTouchesInView = NO;
    [self addGestureRecognizer:scroll];
    [self addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)]];
}
- (void)scroll:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    NSEvent *e = [self eventOfType:NSEventTypeScrollWheel at:[g locationInView:self] delta:CGPointZero];
    e.scrollingDeltaX = e.deltaX = d.x / 4;
    e.scrollingDeltaY = e.deltaY = d.y / 4;
    e.hasPreciseScrollingDeltas = YES;
    ShimDispatch(e);
}
- (void)hover:(UIHoverGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    CGPoint delta = self.hasLastTouchPoint ? CGPointMake(p.x - self.lastTouchPoint.x, p.y - self.lastTouchPoint.y) : CGPointZero;
    self.lastTouchPoint = p;
    self.hasLastTouchPoint = YES;
    ShimDispatch([self eventOfType:NSEventTypeMouseMoved at:p delta:delta]);
}
@end

// MARK: NSWindow / NSScreen

typedef struct { CGFloat top, left, bottom, right; } NSEdgeInsets_;

@interface NSScreen : NSObject
+ (instancetype)mainScreen;
@end

@interface NSWindow : NSResponder
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSViewController *contentViewController;
@property (nonatomic, weak) id windowController;
@property (nonatomic, weak) id delegate;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) CGRect frame;
@property (nonatomic) BOOL acceptsMouseMovedEvents;
@property (nonatomic) BOOL movable;
@property (nonatomic) BOOL movableByWindowBackground;
@property (nonatomic) BOOL hidesOnDeactivate;
@property (nonatomic) BOOL ignoresMouseEvents;
@property (nonatomic) NSInteger level;
@property (nonatomic) CGFloat alphaValue;
@property (nonatomic, strong) id backgroundColor;
@property (nonatomic) NSUInteger collectionBehavior, styleMask;
@property (nonatomic, weak) id shimFirstResponder;
@property (nonatomic, readonly) NSInteger windowNumber;
@property (nonatomic) CGSize lastNotifiedSize;
@end

static NSInteger gNextWindowNumber = 1;

static NSWindow *ShimActiveGameWindow(void) {
    Class cocoaWinCls = NSClassFromString(@"FCocoaWindow");
    if (cocoaWinCls) {
        for (NSWindow *w in gWindows.reverseObjectEnumerator) {
            if ([w isKindOfClass:cocoaWinCls]) return w;
        }
    }
    return gWindows.lastObject;
}

static void ShimApplyMetalHudSetting(void) {
    NSDictionary *props = gMetalHudEnabled ? @{@"mode": @"default"} : nil;
    for (NSWindow *w in gWindows) {
        if (!w.contentView) continue;
        for (CALayer *l in w.contentView.hostView.layer.sublayers) {
            if ([l isKindOfClass:CAMetalLayer.class]) {
                ((CAMetalLayer *)l).developerHUDProperties = props;
            }
        }
        for (NSView *sub in w.contentView.shimSubviews) {
            for (CALayer *l in sub.hostView.layer.sublayers) {
                if ([l isKindOfClass:CAMetalLayer.class]) {
                    ((CAMetalLayer *)l).developerHUDProperties = props;
                }
            }
        }
    }
}

static void ShimNotify(NSWindow *w, NSString *name) {
    if (!w) return;
    SEL sel = NSSelectorFromString([NSString stringWithFormat:@"window%@:", name]);
    NSNotification *n = [NSNotification notificationWithName:[NSString stringWithFormat:@"NSWindow%@Notification", name] object:w];
    if ([w.delegate respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(w.delegate, sel, n);
    [NSNotificationCenter.defaultCenter postNotification:n];
}

@interface NSObject (ShimFCocoaWindowAccess)
- (void)setAcceptsInput:(BOOL)accept;
@end

static void ShimSyncWindowAndViewGeometry(NSWindow *w, BOOL notifyResize) {
    if (!w || !w.contentView) return;
    ShimInitializeDefaultViewportMetrics();
    if (gRootVC && gRootVC.view) {
        CGRect vRect; CGSize pts; CGFloat sc;
        ShimComputeViewportMetrics(gRootVC.view.bounds, gRootVC.view.safeAreaInsets, &vRect, &pts, &sc);
        gCurrentViewportContainerRect = vRect;
        gCurrentViewportPoints = pts;
        gCurrentViewportScale = sc;
        ShimSaveViewportMetricsToDefaults(pts, sc);
    }

    CGRect logicalBounds = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
    CGRect uikitLocalBounds = CGRectMake(0, 0, gCurrentViewportContainerRect.size.width, gCurrentViewportContainerRect.size.height);
    UIView *hv = w.contentView.hostView;
    if (hv.superview == gRootVC.view && !CGRectEqualToRect(hv.frame, gCurrentViewportContainerRect)) {
        hv.frame = gCurrentViewportContainerRect;
    }
    w.frame = logicalBounds;
    w.contentView.frame = logicalBounds;
    for (NSView *sub in w.contentView.shimSubviews) {
        sub.frame = logicalBounds;
        sub.hostView.frame = uikitLocalBounds;
    }

    CGSize targetDrawable = gCurrentViewportPoints;
    for (CALayer *l in w.contentView.hostView.layer.sublayers) {
        if ([l.delegate isKindOfClass:UIView.class]) continue;
        l.frame = uikitLocalBounds;
        l.contentsScale = gCurrentLayerContentsScale;
        if ([l isKindOfClass:CAMetalLayer.class]) {
            CAMetalLayer *ml = (CAMetalLayer *)l;
            ml.contentsGravity = kCAGravityResizeAspect;
            ml.developerHUDProperties = gMetalHudEnabled ? @{@"mode": @"default"} : nil;
            if (fabs(ml.drawableSize.width - targetDrawable.width) > 1.0 ||
                fabs(ml.drawableSize.height - targetDrawable.height) > 1.0) {
                ml.drawableSize = targetDrawable;
            }
        }
    }
    for (NSView *sub in w.contentView.shimSubviews) {
        for (CALayer *l in sub.hostView.layer.sublayers) {
            l.frame = uikitLocalBounds;
            l.contentsScale = gCurrentLayerContentsScale;
            if ([l isKindOfClass:CAMetalLayer.class]) {
                CAMetalLayer *ml = (CAMetalLayer *)l;
                ml.contentsGravity = kCAGravityResizeAspect;
                ml.developerHUDProperties = gMetalHudEnabled ? @{@"mode": @"default"} : nil;
                if (fabs(ml.drawableSize.width - targetDrawable.width) > 1.0 ||
                    fabs(ml.drawableSize.height - targetDrawable.height) > 1.0) {
                    ml.drawableSize = targetDrawable;
                }
            }
        }
    }

    if ([w respondsToSelector:@selector(setAcceptsInput:)]) {
        [(id)w setAcceptsInput:YES];
    }

    BOOL sizeChanged = fabs(w.lastNotifiedSize.width - logicalBounds.size.width) > 0.5 ||
                       fabs(w.lastNotifiedSize.height - logicalBounds.size.height) > 0.5;
    if (notifyResize && sizeChanged) {
        CGSize prev = w.lastNotifiedSize;
        w.lastNotifiedSize = logicalBounds.size;
        static const char *const kModeNames[] = {"16:9", "SAFE_AREA", "FULLSCREEN"};
        CGRect rootBounds = gRootVC ? gRootVC.view.bounds : CGRectZero;
        UIEdgeInsets insets = gRootVC ? gRootVC.view.safeAreaInsets : UIEdgeInsetsZero;
        NSLog(@"SHIM VIEWPORT METRICS [%s]: screen=%.0fx%.0f safeInsets=(T:%.0f,L:%.0f,B:%.0f,R:%.0f) containerFrame=(%.0f,%.0f,%.0fx%.0f) windowPt=%.0fx%.0f (prev=%.0fx%.0f) drawablePx=%.0fx%.0f scale=%.1f",
              kModeNames[gAspectMode % 3],
              rootBounds.size.width, rootBounds.size.height,
              insets.top, insets.left, insets.bottom, insets.right,
              gCurrentViewportContainerRect.origin.x, gCurrentViewportContainerRect.origin.y,
              gCurrentViewportContainerRect.size.width, gCurrentViewportContainerRect.size.height,
              logicalBounds.size.width, logicalBounds.size.height,
              prev.width, prev.height,
              targetDrawable.width, targetDrawable.height,
              gCurrentViewportScale);
        ShimNotify(w, @"DidResize");
        [NSNotificationCenter.defaultCenter postNotificationName:@"NSViewFrameDidChangeNotification" object:w.contentView];
        [NSNotificationCenter.defaultCenter postNotificationName:@"NSViewBoundsDidChangeNotification" object:w.contentView];
        for (NSView *sub in w.contentView.shimSubviews) {
            [NSNotificationCenter.defaultCenter postNotificationName:@"NSViewFrameDidChangeNotification" object:sub];
            [NSNotificationCenter.defaultCenter postNotificationName:@"NSViewBoundsDidChangeNotification" object:sub];
        }
    }
}

static void ShimEnsureTouchOverlayOnTop(void);

// Priority 2 (Deadlock-Free Non-Blocking Window Activation):
// Disassembly of -[FCocoaWindow windowDidBecomeMain:] (0x10167d61c) proved two critical facts:
// 1. It calls [self orderFrontAndMakeMain:NO andKey:NO] (0x10167d670) -> [self orderFront:nil] (0x10167c410)
//    synchronously on the Main Thread, AND then calls GameThreadCall(block, @[NSDefaultRunLoopMode], bWait=true)
//    (0x10167d718). When GameThread enters FMacWindow::ApplySizeAndModeChanges (0x101690fdc) and waits for
//    MainThread in UE4NilEventMode, calling windowDidBecomeMain: on MainThread causes an instant deadlock!
// 2. By contrast, FMacApplication::OnApplicationDidBecomeActive (0x101680c00, observer of
//    NSApplicationDidBecomeActiveNotification) calls GameThreadCall(block, @[NSDefaultRunLoopMode], bWait=false)
//    (0x101680d98: mov w2, #0x0). Its GameThread block (0x101689180) calls OnApplicationActivationChanged(true),
//    looks up [NSApp keyWindow] via FindWindowByNSWindow (0x1016891d4), and calls
//    MessageHandler->OnWindowActivationChanged(Window, EWindowActivation::Activate) (0x101689228) WITHOUT
//    ever blocking MainThread or recursing into orderFront:!
static void ShimActivateGameWindowNonBlocking(NSWindow *w, NSString *reason) {
    if (!w) w = ShimActiveGameWindow();
    if (!w) return;
    if ([w respondsToSelector:@selector(setAcceptsInput:)]) {
        [(id)w setAcceptsInput:YES];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:@"NSApplicationWillBecomeActiveNotification" object:NSApp];
    [NSNotificationCenter.defaultCenter postNotificationName:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
    ShimWorkspaceActivation(YES);
    NSLog(@"SHIM WINDOW ACTIVATION NON-BLOCKING (%@): win=%@ (%ld) contentView=%@ size=%.0fx%.0f",
          reason, NSStringFromClass([w class]), (long)w.windowNumber,
          NSStringFromClass([w.contentView class]), w.frame.size.width, w.frame.size.height);
}

static void ShimActivateGameWindowNow(NSWindow *w, NSString *reason) {
    ShimActivateGameWindowNonBlocking(w, reason);
}

static void ShimUpdateWindowHostViewsVisibility(void) {
    if (!gRootVC || !gRootVC.view) return;
    NSWindow *activeGameWin = ShimActiveGameWindow();
    Class splashCls = NSClassFromString(@"FSplashWindow");
    for (NSWindow *win in gWindows) {
        if (!win.contentView || !win.contentView.hostView) continue;
        if (splashCls && [win isKindOfClass:splashCls] && activeGameWin && activeGameWin != win) {
            win.contentView.hostView.hidden = YES;
        } else if (win == activeGameWin) {
            win.contentView.hostView.hidden = NO;
            if (win.contentView.hostView.superview == gRootVC.view) {
                [gRootVC.view bringSubviewToFront:win.contentView.hostView];
            }
        }
    }
    ShimEnsureTouchOverlayOnTop();
}

static void ShimAttach(NSWindow *w) {
    if (!gRootVC || !w.contentView || ![gWindows containsObject:w]) return;
    UIView *v = w.contentView.hostView;
    BOOL newlyAdded = (v.superview != gRootVC.view);
    if (newlyAdded) {
        v.autoresizingMask = UIViewAutoresizingNone;
        [gRootVC.view addSubview:v];
        NSLog(@"SHIM ShimAttach added hostView=%p for win=%@ (%ld) contentView=%@ (%p) layer=%@",
              v, NSStringFromClass([w class]), (long)w.windowNumber,
              NSStringFromClass([w.contentView class]), w.contentView,
              NSStringFromClass([w.contentView.layer class]));
    }
    ShimSyncWindowAndViewGeometry(w, YES);
    ShimUpdateWindowHostViewsVisibility();

    Class cocoaWinCls = NSClassFromString(@"FCocoaWindow");
    if (newlyAdded && (!cocoaWinCls || [w isKindOfClass:cocoaWinCls])) {
        ShimActivateGameWindowNonBlocking(w, @"ShimAttach");
        // Schedule non-blocking activation notifications after FMacApplication::Windows registers FCocoaWindow
        // and after FEngineLoop::Init finishes setting up Slate focus.
        __weak NSWindow *weakW = w;
        const double delays[] = {0.25, 0.90, 2.00};
        for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
            double d = delays[i];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSWindow *strongW = weakW ?: ShimActiveGameWindow();
                if (strongW && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
                    ShimUpdateWindowHostViewsVisibility();
                    ShimActivateGameWindowNonBlocking(strongW, [NSString stringWithFormat:@"PostAttach+%.2fs", d]);
                }
            });
        }
    }
}

@implementation NSWindow
SHIM_RESOLVE
+ (NSInteger)windowNumberAtPoint:(CGPoint)point belowWindowWithWindowNumber:(NSInteger)below {
    NSWindow *w = ShimActiveGameWindow();
    return w ? w.windowNumber : 1;
}
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer {
    if ((self = [super init])) {
        _windowNumber = gNextWindowNumber++;
        _alphaValue = 1.0;
        ShimInitializeDefaultViewportMetrics();
        CGRect targetRect = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
        _frame = targetRect;
        _styleMask = style;
        self.contentView = [[NSView alloc] initWithFrame:targetRect];
        NSLog(@"SHIM NSWindow init (%@, num=%ld): requested=%.0fx%.0f style=0x%lx -> viewport=%.0fx%.0f",
              NSStringFromClass([self class]), (long)_windowNumber,
              rect.size.width, rect.size.height, (unsigned long)style,
              targetRect.size.width, targetRect.size.height);
    }
    return self;
}
- (void)setContentView:(NSView *)v {
    if (_contentView && _contentView != v) {
        [_contentView.hostView removeFromSuperview];
        if (_contentView.window == self) _contentView.window = nil;
    }
    _contentView = v;
    v.window = self;
    NSLog(@"SHIM NSWindow setContentView on %@ (num=%ld): newView=%@ (%p) layer=%@",
          NSStringFromClass([self class]), (long)_windowNumber,
          NSStringFromClass([v class]), v, NSStringFromClass([v.layer class]));
    ShimAttach(self);
}
- (void)setContentViewController:(NSViewController *)vc { _contentViewController = vc; self.contentView = vc.view; }
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer screen:(id)screen {
    return [self initWithContentRect:rect styleMask:style backing:backing defer:defer];
}
- (CGRect)contentLayoutRect { return CGRectMake(0, 0, _frame.size.width, _frame.size.height); }
- (void)setContentAspectRatio:(CGSize)ratio {}
- (void)setContentMinSize:(CGSize)size {}
- (void)setContentMaxSize:(CGSize)size {}
- (void)setMinSize:(CGSize)size {}
- (void)setFrameOrigin:(CGPoint)origin {}
- (void)center {}
@synthesize movable = _movable;
@synthesize movableByWindowBackground = _movableByWindowBackground;
@synthesize hidesOnDeactivate = _hidesOnDeactivate;
@synthesize ignoresMouseEvents = _ignoresMouseEvents;
@synthesize level = _level;
@synthesize alphaValue = _alphaValue;
@synthesize backgroundColor = _backgroundColor;
- (BOOL)isMovable { return _movable; }
- (BOOL)isMovableByWindowBackground { return _movableByWindowBackground; }
- (BOOL)isMiniaturized { return NO; }
- (BOOL)isZoomed { return YES; }
- (BOOL)isOnActiveSpace { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
- (void)orderWindow:(NSInteger)place relativeTo:(NSInteger)otherWin {
    if (place == 0) {
        [self orderOut:nil];
    } else {
        if (![gWindows containsObject:self]) [gWindows addObject:self];
        ShimAttach(self);
    }
}
- (void)toggleFullScreen:(id)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        ShimNotify(self, @"WillEnterFullScreen");
        ShimNotify(self, @"DidEnterFullScreen");
        ShimSyncWindowAndViewGeometry(self, YES);
    });
}
- (void)setIsVisible:(BOOL)v { if (v) [self makeKeyAndOrderFront:nil]; else [self orderOut:nil]; }
- (void)makeMainWindow {
    if (![gWindows containsObject:self]) [gWindows addObject:self];
    ShimAttach(self);
    ShimNotify(self, @"DidBecomeMain");
}
- (CGPoint)convertPointToScreen:(CGPoint)p { return p; }
- (CGPoint)convertPointFromScreen:(CGPoint)p { return p; }
- (CGRect)convertRectToScreen:(CGRect)r { return r; }
- (CGRect)convertRectFromScreen:(CGRect)r { return r; }
- (CGRect)convertRectToBacking:(CGRect)r { return r; }
- (CGRect)convertRectFromBacking:(CGRect)r { return r; }
- (void)invalidateCursorRectsForView:(id)view {}
// Clear bit 8 (NSWindowStyleMaskTexturedBackground = 1 << 8) so -[FCocoaWindow openGLView] (0x10167c1a8)
// and -[FCocoaWindow openGLFrame] (0x10167c0e8) always return [self contentView] (FMetalView) directly!
- (NSUInteger)styleMask { return (_styleMask & ~(1UL << 8)) | (1UL << 14); }
- (CGFloat)titlebarHeight { return 0; }
- (void)setFrame:(CGRect)frame display:(BOOL)display {
    _frame = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
}
- (void)setFrame:(CGRect)frame display:(BOOL)display animate:(BOOL)animate { [self setFrame:frame display:display]; }
- (void)setContentSize:(CGSize)size {
    _frame = CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
}
- (CGRect)contentRectForFrameRect:(CGRect)r { return CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height); }
- (CGRect)frameRectForContentRect:(CGRect)r { return CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height); }
- (BOOL)isKeyWindow { return [gWindows containsObject:self]; }
- (BOOL)isMainWindow { return [gWindows containsObject:self]; }
- (void)setDelegate:(id)d {
    _delegate = d;
    if (d && gRootVC && self.contentView.hostView.superview) {
        ShimSyncWindowAndViewGeometry(self, YES);
        ShimActivateGameWindowNonBlocking(self, @"setDelegate");
    }
}
- (BOOL)isVisible { return [gWindows containsObject:self]; }
- (NSScreen *)screen { return [NSScreen mainScreen]; }
- (void)makeKeyWindow {
    if (![gWindows containsObject:self]) [gWindows addObject:self];
    ShimAttach(self);
    ShimNotify(self, @"DidBecomeKey");
}
- (BOOL)makeFirstResponder:(id)r { _shimFirstResponder = r; return YES; }
- (id)firstResponder { return _shimFirstResponder ?: self.contentView; }
- (void)sendEvent:(NSEvent *)e {
    id target = (e.type == NSEventTypeKeyDown || e.type == NSEventTypeKeyUp || e.type == NSEventTypeFlagsChanged)
        ? [self firstResponder] : ([self.contentView hitTest:e.locationInWindow] ?: self.contentView);
    SEL sel = NULL;
    switch (e.type) {
        case NSEventTypeLeftMouseDown: sel = @selector(mouseDown:); break;
        case NSEventTypeLeftMouseUp: sel = @selector(mouseUp:); break;
        case NSEventTypeRightMouseDown: sel = @selector(rightMouseDown:); break;
        case NSEventTypeRightMouseUp: sel = @selector(rightMouseUp:); break;
        case NSEventTypeLeftMouseDragged: sel = @selector(mouseDragged:); break;
        case NSEventTypeRightMouseDragged: sel = @selector(rightMouseDragged:); break;
        case NSEventTypeMouseMoved: sel = @selector(mouseMoved:); break;
        case NSEventTypeScrollWheel: sel = @selector(scrollWheel:); break;
        case NSEventTypeKeyDown: sel = @selector(keyDown:); break;
        case NSEventTypeKeyUp: sel = @selector(keyUp:); break;
        case NSEventTypeFlagsChanged: sel = @selector(flagsChanged:); break;
        case NSEventTypeOtherMouseDown: sel = @selector(otherMouseDown:); break;
        case NSEventTypeOtherMouseUp: sel = @selector(otherMouseUp:); break;
        default: break;
    }
    if (sel && [target respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(target, sel, e);
}
- (void)makeKeyAndOrderFront:(id)sender {
    if (![gWindows containsObject:self]) [gWindows addObject:self];
    ShimAttach(self);
    ShimNotify(self, @"DidBecomeMain");
    ShimNotify(self, @"DidBecomeKey");
}
// CRITICAL: -[FCocoaWindow windowDidBecomeMain:] (0x10167d61c) calls [self orderFrontAndMakeMain:NO andKey:NO]
// -> [self orderFront:nil]. orderFront: MUST NOT call makeKeyAndOrderFront: or post DidBecomeMain,
// otherwise windowDidBecomeMain: recurses into itself!
- (void)orderFront:(id)sender {
    if (![gWindows containsObject:self]) [gWindows addObject:self];
    ShimAttach(self);
}
- (void)orderFrontRegardless {
    if (![gWindows containsObject:self]) [gWindows addObject:self];
    ShimAttach(self);
}
- (CGFloat)backingScaleFactor { return 1.0; }
- (void)close { [self orderOut:nil]; }
- (void)orderOut:(id)sender {
    [self.contentView.hostView removeFromSuperview];
    [gWindows removeObject:self];
    ShimUpdateWindowHostViewsVisibility();
}
@end

@implementation NSScreen
SHIM_RESOLVE
+ (instancetype)mainScreen { static NSScreen *s; if (!s) s = [NSScreen new]; return s; }
+ (NSArray *)screens { return @[[self mainScreen]]; }
- (CGRect)frame {
    ShimInitializeDefaultViewportMetrics();
    return CGRectMake(0, 0, gCurrentViewportPoints.width, gCurrentViewportPoints.height);
}
- (CGRect)visibleFrame { return [self frame]; }
- (CGRect)convertRectToBacking:(CGRect)r { return r; }
- (CGRect)convertRectFromBacking:(CGRect)r { return r; }
- (NSDictionary *)deviceDescription {
    return @{
        @"NSScreenNumber": @1,
        @"NSDeviceSize": [NSValue valueWithCGSize:[self frame].size],
        @"NSDeviceResolution": [NSValue valueWithCGSize:CGSizeMake(72.0, 72.0)]
    };
}
- (NSString *)localizedName { return @"iPhone Landscape Display"; }
- (NSInteger)maximumFramesPerSecond { return UIScreen.mainScreen.maximumFramesPerSecond ?: 60; }
- (CGFloat)maximumExtendedDynamicRangeColorComponentValue { return 1.0; }
- (CGFloat)maximumPotentialExtendedDynamicRangeColorComponentValue { return 1.0; }
- (NSTimeInterval)minimumRefreshInterval { return 1.0 / (UIScreen.mainScreen.maximumFramesPerSecond ?: 60); }
- (NSTimeInterval)maximumRefreshInterval { return 1.0 / 24; }
- (NSTimeInterval)displayUpdateGranularity { return 0; }
- (CGFloat)maximumReferenceExtendedDynamicRangeColorComponentValue { return 0; }
- (NSEdgeInsets_)safeAreaInsets { return (NSEdgeInsets_){0, 0, 0, 0}; }
- (CGFloat)backingScaleFactor { return 1.0; }
@end

// MARK: NSWindowController / NSApplication

@interface NSWindowController : NSResponder
@property (nonatomic, strong) NSWindow *window;
@end

@implementation NSWindowController
SHIM_RESOLVE
- (instancetype)initWithWindow:(NSWindow *)w { if ((self = [super init])) { _window = w; w.windowController = self; } return self; }
- (instancetype)init { return [self initWithWindow:nil]; }
- (void)setWindow:(NSWindow *)w { _window = w; w.windowController = self; }
- (void)showWindow:(id)sender { [_window makeKeyAndOrderFront:sender]; }
- (void)close { [_window close]; }
- (BOOL)isWindowLoaded { return _window != nil; }
- (void)loadWindow {}
- (void)windowDidLoad {}
- (void)windowWillLoad {}
@end

@interface NSApplication : NSResponder
@property (nonatomic, weak) id delegate;
@end

typedef struct { uint64_t x19_x30[12], sp, d8_d15[8]; } ShimContext;
void ShimContextSwitch(ShimContext *save, const ShimContext *load);
__asm__(".text\n.p2align 2\n.private_extern _ShimContextSwitch\n_ShimContextSwitch:\n"
        "stp x19, x20, [x0, #0]\n stp x21, x22, [x0, #16]\n stp x23, x24, [x0, #32]\n"
        "stp x25, x26, [x0, #48]\n stp x27, x28, [x0, #64]\n stp x29, x30, [x0, #80]\n"
        "mov x9, sp\n str x9, [x0, #96]\n"
        "stp d8, d9, [x0, #104]\n stp d10, d11, [x0, #120]\n stp d12, d13, [x0, #136]\n stp d14, d15, [x0, #152]\n"
        "ldp x19, x20, [x1, #0]\n ldp x21, x22, [x1, #16]\n ldp x23, x24, [x1, #32]\n"
        "ldp x25, x26, [x1, #48]\n ldp x27, x28, [x1, #64]\n ldp x29, x30, [x1, #80]\n"
        "ldr x9, [x1, #96]\n mov sp, x9\n"
        "ldp d8, d9, [x1, #104]\n ldp d10, d11, [x1, #120]\n ldp d12, d13, [x1, #136]\n ldp d14, d15, [x1, #152]\n"
        "ret\n");

static ShimContext gGameContext, gUIKitContext;
static BOOL gPolling;
static NSMutableArray<NSEvent *> *gEventQueue;
static BOOL gUIKitStarted, gUIKitOnFiber;
static NSEvent *gCurrentEvent;
static NSUInteger gPresentationOptions;

// MARK: Priority 1 & Priority 5 — Autonomous Launch + GameUserSettings.ini Sanitization + FMemory::Realloc

static char *gSafeUIKitArgv[2] = { NULL, NULL };
static NSArray<NSString *> *gSynthesizedArguments = nil;
static IMP gOrigProcessInfoArguments = NULL;

static NSArray<NSString *> *ShimProcessInfoArguments(NSProcessInfo *self, SEL _cmd) {
    if (gSynthesizedArguments.count) return gSynthesizedArguments;
    return ((NSArray<NSString *> *(*)(id, SEL))gOrigProcessInfoArguments)(self, _cmd);
}

__attribute__((constructor)) static void HookProcessInfoArguments(void) {
    Method m = class_getInstanceMethod(NSProcessInfo.class, @selector(arguments));
    if (m) gOrigProcessInfoArguments = method_setImplementation(m, (IMP)ShimProcessInfoArguments);
}

// Priority 1: Ensure Library/Preferences/Stray/MacNoEditor/GameUserSettings.ini never forces
// portrait (1320x2868) or quarter-screen (768x432) resolution.
static void ShimSanitizeGameUserSettingsIni(void) {
    ShimInitializeDefaultViewportMetrics();
    int targetW = (int)round(gCurrentViewportPoints.width);
    int targetH = (int)round(gCurrentViewportPoints.height);
    if (targetW < 640 || targetH < 360) {
        targetW = 1536;
        targetH = 864;
    }

    NSString *prefsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/Stray/MacNoEditor"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:prefsDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *iniPath = [prefsDir stringByAppendingPathComponent:@"GameUserSettings.ini"];

    NSString *existing = [NSString stringWithContentsOfFile:iniPath encoding:NSUTF8StringEncoding error:nil];
    if (!existing || existing.length == 0) {
        NSString *fresh = [NSString stringWithFormat:
            @"[/Script/Hk_project.HKGameUserSettings]\n"
            @"ResolutionSizeX=%d\n"
            @"ResolutionSizeY=%d\n"
            @"LastUserConfirmedResolutionSizeX=%d\n"
            @"LastUserConfirmedResolutionSizeY=%d\n"
            @"DesiredScreenWidth=%d\n"
            @"DesiredScreenHeight=%d\n"
            @"LastUserConfirmedDesiredScreenWidth=%d\n"
            @"LastUserConfirmedDesiredScreenHeight=%d\n"
            @"FullscreenMode=0\n"
            @"LastConfirmedFullscreenMode=0\n"
            @"PreferredFullscreenMode=0\n"
            @"bUseDynamicResolution=False\n\n"
            @"[/Script/Engine.GameUserSettings]\n"
            @"ResolutionSizeX=%d\n"
            @"ResolutionSizeY=%d\n"
            @"LastUserConfirmedResolutionSizeX=%d\n"
            @"LastUserConfirmedResolutionSizeY=%d\n"
            @"DesiredScreenWidth=%d\n"
            @"DesiredScreenHeight=%d\n"
            @"LastUserConfirmedDesiredScreenWidth=%d\n"
            @"LastUserConfirmedDesiredScreenHeight=%d\n"
            @"FullscreenMode=0\n"
            @"LastConfirmedFullscreenMode=0\n"
            @"PreferredFullscreenMode=0\n"
            @"bUseDynamicResolution=False\n",
            targetW, targetH, targetW, targetH, targetW, targetH, targetW, targetH,
            targetW, targetH, targetW, targetH, targetW, targetH, targetW, targetH];
        [fresh writeToFile:iniPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SHIM GameUserSettings.ini initialized at %@ with %dx%d (FullscreenMode=0)", iniPath, targetW, targetH);
        return;
    }

    NSMutableArray<NSString *> *lines = [[existing componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] mutableCopy];
    BOOL modified = NO;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        if ([line hasPrefix:@"ResolutionSizeX="] ||
            [line hasPrefix:@"LastUserConfirmedResolutionSizeX="] ||
            [line hasPrefix:@"DesiredScreenWidth="] ||
            [line hasPrefix:@"LastUserConfirmedDesiredScreenWidth="]) {
            NSString *key = [[line componentsSeparatedByString:@"="] firstObject];
            NSString *rep = [NSString stringWithFormat:@"%@=%d", key, targetW];
            if (![line isEqualToString:rep]) { lines[i] = rep; modified = YES; }
        } else if ([line hasPrefix:@"ResolutionSizeY="] ||
                   [line hasPrefix:@"LastUserConfirmedResolutionSizeY="] ||
                   [line hasPrefix:@"DesiredScreenHeight="] ||
                   [line hasPrefix:@"LastUserConfirmedDesiredScreenHeight="]) {
            NSString *key = [[line componentsSeparatedByString:@"="] firstObject];
            NSString *rep = [NSString stringWithFormat:@"%@=%d", key, targetH];
            if (![line isEqualToString:rep]) { lines[i] = rep; modified = YES; }
        } else if ([line hasPrefix:@"FullscreenMode="] ||
                   [line hasPrefix:@"LastConfirmedFullscreenMode="] ||
                   [line hasPrefix:@"PreferredFullscreenMode="]) {
            NSString *key = [[line componentsSeparatedByString:@"="] firstObject];
            NSString *rep = [NSString stringWithFormat:@"%@=0", key];
            if (![line isEqualToString:rep]) { lines[i] = rep; modified = YES; }
        } else if ([line hasPrefix:@"ScalingSolution="]) {
            NSString *rep = @"ScalingSolution=BuiltIn";
            if (![line isEqualToString:rep]) { lines[i] = rep; modified = YES; }
        } else if ([line hasPrefix:@"sg.TextureQuality="] ||
                   [line hasPrefix:@"sg.EffectsQuality="] ||
                   [line hasPrefix:@"sg.ShadowQuality="] ||
                   [line hasPrefix:@"sg.FoliageQuality="] ||
                   [line hasPrefix:@"sg.ViewDistanceQuality="] ||
                   [line hasPrefix:@"sg.PostProcessQuality="] ||
                   [line hasPrefix:@"sg.ShadingQuality="]) {
            NSString *key = [[line componentsSeparatedByString:@"="] firstObject];
            NSString *rep = [NSString stringWithFormat:@"%@=3", key];
            if (![line isEqualToString:rep]) { lines[i] = rep; modified = YES; }
        }
    }
    if (modified) {
        NSString *outText = [lines componentsJoinedByString:@"\n"];
        [outText writeToFile:iniPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SHIM GameUserSettings.ini sanitized to %dx%d (FullscreenMode=0, BuiltIn scaling, TextureQuality=3)", targetW, targetH);
    } else {
        NSLog(@"SHIM GameUserSettings.ini already matches %dx%d", targetW, targetH);
    }

    NSString *engineIniPath = [prefsDir stringByAppendingPathComponent:@"Engine.ini"];
    NSString *existingEngine = [NSString stringWithContentsOfFile:engineIniPath encoding:NSUTF8StringEncoding error:nil];

    // Core content paths required by Stray and its cooked plugins
    NSArray<NSString *> *corePaths = @[
        @"../../../Engine/Content",
        @"%GAMEDIR%Content",
        @"../../../Hk_project/Plugins/UE_ScreenLogger/Content",
        @"../../../Hk_project/Plugins/JoyLibrary/Content",
        @"../../../Engine/Plugins/Runtime/SoundUtilities/Content",
        @"../../../Engine/Plugins/Runtime/Synthesis/Content",
        @"../../../Engine/Plugins/Runtime/AudioSynesthesia/Content",
        @"../../../Hk_project/Plugins/GFurPRO/Content",
        @"../../../Hk_project/Plugins/PrefabTool/Content",
        @"../../../Hk_project/Plugins/MeshTool/Content",
        @"../../../Engine/Plugins/Experimental/GeometryProcessing/Content",
        @"../../../Engine/Plugins/Experimental/PythonScriptPlugin/Content",
        @"../../../Engine/Plugins/MetalFX4UE/Content",
        @"../../../Engine/Plugins/Developer/AnimationSharing/Content",
        @"../../../Hk_project/Plugins/ToyoTool/Content",
        @"../../../Engine/Plugins/Editor/GeometryMode/Content",
        @"../../../Engine/Plugins/Editor/SpeedTreeImporter/Content",
        @"../../../Engine/Plugins/Enterprise/DatasmithContent/Content",
        @"../../../Engine/Plugins/Experimental/ChaosClothEditor/Content",
        @"../../../Engine/Plugins/Experimental/GeometryCollectionPlugin/Content",
        @"../../../Engine/Plugins/Experimental/ChaosSolverPlugin/Content",
        @"../../../Engine/Plugins/Experimental/ChaosNiagara/Content",
        @"../../../Engine/Plugins/FX/Niagara/Content",
        @"../../../Engine/Plugins/Experimental/MotoSynth/Content"
    ];

    // Enforced baseline settings per section (non-destructive merge)
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *enforcedSettings = @{
        @"[/Script/EngineSettings.GameMapsSettings]": @{
            @"GameDefaultMap": @"/Game/Map/_MainGame/HK_Project_Intro.HK_Project_Intro"
        },
        @"[/Script/Engine.RendererSettings]": @{
            @"r.MobileHDR": @"True",
            @"r.AllowOcclusionQueries": @"False",
            @"r.HZBOcclusion": @"0",
            @"bDefaultFeatureAutoExposure": @"True",
            @"DefaultFeatureAutoExposure": @"1",
            @"DefaultFeatureAutoExposureBias": @"1.6",
            @"bDefaultFeatureAmbientOcclusion": @"True",
            @"r.DetailMode": @"2",
            @"r.TextureStreaming": @"True",
            @"r.AllowStaticLighting": @"True",
            @"r.CustomDepth": @"3",
            @"r.DefaultFeature.Bloom": @"True",
            @"r.DefaultFeature.MotionBlur": @"False",
            @"r.DefaultFeature.AntiAliasing": @"2",
            @"r.EarlyZPass": @"1",
            @"r.EarlyZPassMovable": @"False",
            @"r.EarlyZPassOnlyMaterialMasking": @"False",
            @"r.DBuffer": @"True",
            @"r.StencilForLODDither": @"False",
            @"r.VirtualTextures": @"True",
            @"r.VirtualTexturedLightmaps": @"True"
        },
        @"[SystemSettings]": @{
            @"r.DetailMode": @"2",
            @"foliage.DensityScale": @"1.0",
            @"r.AllowOcclusionQueries": @"0",
            @"r.HZBOcclusion": @"0",
            @"r.EarlyZPass": @"1",
            @"r.EarlyZPassMovable": @"0",
            @"r.EarlyZPassOnlyMaterialMasking": @"0",
            @"r.StencilForLODDither": @"0",
            @"r.SkinCache.Mode": @"0",
            @"r.SkeletalMeshLODBias": @"0",
            @"r.ForceLOD": @"0",
            @"showflag.SkeletalMeshes": @"1",
            @"r.SubsurfaceScattering": @"1",
            @"r.SSS.Quality": @"1",
            @"r.SSS.Scale": @"1",
            @"r.DistanceFieldShadowing": @"0",
            @"r.DistanceFieldAO": @"0",
            @"r.ShadowQuality": @"3",
            @"r.Shadow.CSM.MaxCascades": @"4",
            @"r.Shadow.MaxResolution": @"2048",
            @"r.DefaultFeature.AmbientOcclusion": @"1",
            @"r.AmbientOcclusionLevels": @"2",
            @"r.AmbientOcclusionRadiusScale": @"1.2",
            @"r.TextureStreaming": @"1",
            @"r.Streaming.PoolSize": @"2048",
            @"r.Streaming.LimitPoolSizeToVRAM": @"0",
            @"r.Streaming.HLODStrategy": @"2",
            @"r.Streaming.MaxNumTexturesToStreamPerFrame": @"10",
            @"r.Streaming.Boost": @"1.5",
            @"r.EyeAdaptationQuality": @"2",
            @"r.EyeAdaptation.ExposureBias": @"1.6",
            @"r.EyeAdaptation.MinAverageLuminance": @"0.03",
            @"r.TonemapperFilm": @"1",
            @"r.Tonemapper.Quality": @"3",
            @"r.SSGI.Enable": @"0",
            @"r.SkyAtmosphere.AerialPerspectiveLUT.FastApplyOnOpaque": @"1",
            @"r.SkyAtmosphere.FastSkyLUT": @"1",
            @"r.SkyAtmosphere.TransmittanceLUT.UseSmallFormat": @"0",
            @"r.SkyLight.RealTimeReflectionCapture": @"1"
        }
    };

    NSMutableArray<NSString *> *sectionOrder = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *sectionData = [NSMutableDictionary new];
    NSString *currentSec = nil;

    if (existingEngine.length > 0) {
        NSArray<NSString *> *rawLines = [existingEngine componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *rawLine in rawLines) {
            NSString *trimmed = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
                currentSec = trimmed;
                if (!sectionData[currentSec]) {
                    [sectionOrder addObject:currentSec];
                    sectionData[currentSec] = [NSMutableArray new];
                }
            } else if (currentSec && trimmed.length > 0) {
                [sectionData[currentSec] addObject:trimmed];
            }
        }
    }

    // Ensure enforced sections exist in order
    for (NSString *sec in enforcedSettings) {
        if (!sectionData[sec]) {
            [sectionOrder addObject:sec];
            sectionData[sec] = [NSMutableArray new];
        }
    }

    // Apply enforced key-value settings without erasing existing custom keys
    for (NSString *sec in enforcedSettings) {
        NSDictionary<NSString *, NSString *> *kvs = enforcedSettings[sec];
        NSMutableArray<NSString *> *lines = sectionData[sec];
        for (NSString *key in kvs) {
            NSString *val = kvs[key];
            NSString *prefix = [key stringByAppendingString:@"="];
            NSInteger foundIdx = -1;
            for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
                NSString *l = lines[i];
                if ([l.lowercaseString hasPrefix:prefix.lowercaseString]) {
                    foundIdx = i;
                    break;
                }
            }
            NSString *newLine = [NSString stringWithFormat:@"%@=%@", key, val];
            if (foundIdx >= 0) {
                lines[foundIdx] = newLine;
            } else {
                [lines addObject:newLine];
            }
        }
    }

    // Ensure [Core.System] section exists and preserves all required content paths
    NSString *coreSec = @"[Core.System]";
    if (!sectionData[coreSec]) {
        [sectionOrder addObject:coreSec];
        sectionData[coreSec] = [NSMutableArray new];
    }
    NSMutableArray<NSString *> *coreLines = sectionData[coreSec];
    NSMutableSet<NSString *> *existingPaths = [NSMutableSet new];
    for (NSString *l in coreLines) {
        if ([l.lowercaseString hasPrefix:@"paths="]) {
            NSString *p = [l substringFromIndex:6];
            [existingPaths addObject:p];
        }
    }
    for (NSString *cp in corePaths) {
        if (![existingPaths containsObject:cp]) {
            [coreLines addObject:[NSString stringWithFormat:@"Paths=%@", cp]];
            [existingPaths addObject:cp];
        }
    }

    // Deterministically reassemble sanitized Engine.ini
    NSMutableArray<NSString *> *outputLines = [NSMutableArray new];
    for (NSString *sec in sectionOrder) {
        [outputLines addObject:sec];
        for (NSString *l in sectionData[sec]) {
            [outputLines addObject:l];
        }
        [outputLines addObject:@""];
    }
    NSString *sanitizedContent = [[outputLines componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    sanitizedContent = [sanitizedContent stringByAppendingString:@"\n"];

    if (![sanitizedContent isEqualToString:existingEngine]) {
        [sanitizedContent writeToFile:engineIniPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SHIM Engine.ini sanitized and merged at %@ (preserved sections=%lu, corePaths=%lu)",
              engineIniPath, (unsigned long)sectionOrder.count, (unsigned long)coreLines.count);
    } else {
        NSLog(@"SHIM Engine.ini verified at %@ (all renderer & core path settings already valid)", engineIniPath);
    }
}

// Priority 5: Allocate GSavedCommandLine.Data using Unreal's own FMemory::Realloc (0x1012b9928)
// instead of system calloc(), preventing FMallocBinned2::GetAllocationSizeExternal panic (0x113a30000)
// when Unreal reallocates or frees GSavedCommandLine during map transitions (e.g. QUIT TO MAIN MENU).
typedef void *(*UnrealFMemoryReallocFn)(void *Original, size_t Count, uint32_t Alignment);

static void *ShimUnrealMalloc(size_t bytes) {
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (mh && mh->magic == MH_MAGIC_64) {
        uintptr_t reallocAddr = (uintptr_t)slide + 0x1012b9928ULL;
        const uint32_t *fnInsns = (const uint32_t *)reallocAddr;
        // Verify prologue of FMemory::Realloc(void*, unsigned long, unsigned int) at 0x1012b9928:
        //   1012b9928: a9bd57f6  stp x22, x21, [sp, #-0x30]!
        if (fnInsns[0] == 0xa9bd57f6) {
            UnrealFMemoryReallocFn fn = (UnrealFMemoryReallocFn)reallocAddr;
            void *ptr = fn(NULL, bytes, 0);
            if (ptr) {
                memset(ptr, 0, bytes);
                return ptr;
            }
        }
    }
    return calloc(1, bytes);
}


// MARK: Unreal Engine Log Interceptor (ShimOutputDevice)

static void ShimOutputDevice_dtor1(void *self) {}
static void ShimOutputDevice_dtor2(void *self) {}
static void ShimOutputDevice_Serialize(void *self, const unsigned short *V, uint8_t Verbosity, const void *Category) {
    if (!V) return;
    size_t len = 0;
    while (V[len]) len++;
    while (len > 0 && (V[len - 1] == '\n' || V[len - 1] == '\r')) len--;
    if (len == 0) return;
    NSString *msg = [[NSString alloc] initWithCharacters:(const unichar *)V length:len];
    NSLog(@"[UE4_LOG v=%u] %@", (unsigned)Verbosity, msg);
}
static void ShimOutputDevice_SerializeTime(void *self, const unsigned short *V, uint8_t Verbosity, const void *Category, double Time) {
    ShimOutputDevice_Serialize(self, V, Verbosity, Category);
}
static void ShimOutputDevice_Flush(void *self) {}
static void ShimOutputDevice_TearDown(void *self) {}
static void ShimOutputDevice_Dump(void *self, void *Ar) {}
static int ShimOutputDevice_IsMemoryOnly(void *self) { return 0; }
static int ShimOutputDevice_CanBeUsedOnAnyThread(void *self) { return 1; }
static int ShimOutputDevice_CanBeUsedOnMultipleThreads(void *self) { return 1; }

static void *sShimOutputDeviceVTable[10] = {
    (void *)ShimOutputDevice_dtor1,
    (void *)ShimOutputDevice_dtor2,
    (void *)ShimOutputDevice_Serialize,
    (void *)ShimOutputDevice_SerializeTime,
    (void *)ShimOutputDevice_Flush,
    (void *)ShimOutputDevice_TearDown,
    (void *)ShimOutputDevice_Dump,
    (void *)ShimOutputDevice_IsMemoryOnly,
    (void *)ShimOutputDevice_CanBeUsedOnAnyThread,
    (void *)ShimOutputDevice_CanBeUsedOnMultipleThreads
};

struct ShimOutputDeviceStruct {
    void *vptr;
    bool bSuppressEventTag;
    bool bAutoEmitLineTerminator;
    uint8_t VerbosityThreshold;
    uint8_t pad[5];
};

static struct ShimOutputDeviceStruct sShimOutputDevice = {
    .vptr = sShimOutputDeviceVTable,
    .bSuppressEventTag = false,
    .bAutoEmitLineTerminator = true,
    .VerbosityThreshold = 0xff,
    .pad = {0}
};

static void ShimInstallOutputDevice(void) {
    static BOOL installed;
    if (installed) return;
    installed = YES;

    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!mh || mh->magic != MH_MAGIC_64) return;

    const uint32_t *getInsns = (const uint32_t *)((uintptr_t)slide + 0x1013cbda0ULL);
    if (getInsns[0] != 0xa9be4ff4 || getInsns[1] != 0xa9017bfd || getInsns[2] != 0x910043fd) {
        NSLog(@"SHIM: FOutputDeviceRedirector::Get signature mismatch: %08x %08x %08x", getInsns[0], getInsns[1], getInsns[2]);
        return;
    }

    const uint32_t *addInsns = (const uint32_t *)((uintptr_t)slide + 0x1013cbe48ULL);
    if (addInsns[0] != 0xd10183ff || addInsns[1] != 0xa90167fa || addInsns[2] != 0xa9025ff8) {
        NSLog(@"SHIM: FOutputDeviceRedirector::AddOutputDevice signature mismatch: %08x %08x %08x", addInsns[0], addInsns[1], addInsns[2]);
        return;
    }

    typedef void *(*FOutputDeviceRedirectorGetFn)(void);
    FOutputDeviceRedirectorGetFn getFn = (FOutputDeviceRedirectorGetFn)getInsns;

    typedef void (*FOutputDeviceRedirectorAddOutputDeviceFn)(void *self, void *device);
    FOutputDeviceRedirectorAddOutputDeviceFn addFn = (FOutputDeviceRedirectorAddOutputDeviceFn)addInsns;

    void *redirector = getFn();
    NSLog(@"SHIM: FOutputDeviceRedirector::Get() = %p, registering ShimOutputDevice %p", redirector, &sShimOutputDevice);
    if (redirector) {
        addFn(redirector, &sShimOutputDevice);
        NSLog(@"SHIM: ShimOutputDevice successfully hooked into Unreal Engine log pipeline!");
    }
}

static void ShimSyncUnrealGSavedCommandLine(NSString *ueBaseDir, BOOL hasExternalArgs) {
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
    if (!mh || mh->magic != MH_MAGIC_64) return;

    // Verify the exact instruction sequence in -[UE4AppDelegate runGameThread:] (0x100675e78..0x100675e84):
    //   100675e78: 900256b4  adrp x20, 0x105149000
    //   100675e7c: 91187294  add  x20, x20, #0x61c
    //   100675e80: b943de88  ldr  w8, [x20, #0x3dc]
    const uint32_t *insns = (const uint32_t *)((uintptr_t)mh + 0x675e78);
    if (insns[0] != 0x900256b4 || insns[1] != 0x91187294 || insns[2] != 0xb943de88) {
        return;
    }

    uintptr_t fstrAddr = (uintptr_t)slide + 0x1051499f0ULL;
    unichar **pData = (unichar **)fstrAddr;
    int32_t *pNum = (int32_t *)(fstrAddr + 8);
    int32_t *pMax = (int32_t *)(fstrAddr + 12);

    NSString *existingCmd = @"";
    if (*pData && *pNum > 1) {
        existingCmd = [NSString stringWithCharacters:*pData length:(NSUInteger)(*pNum - 1)];
    }

    BOOL cmdHasProject = ([existingCmd rangeOfString:@".uproject" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL cmdHasBaseDir = ([existingCmd rangeOfString:@"-basedir=" options:NSCaseInsensitiveSearch].location != NSNotFound);
    BOOL cmdHasMetal   = ([existingCmd rangeOfString:@"-metalsm5" options:NSCaseInsensitiveSearch].location != NSNotFound);

    if (cmdHasProject && cmdHasBaseDir && cmdHasMetal) {
        NSLog(@"SHIM GSavedCommandLine already complete (len=%d, external=%d): \"%@\"",
              *pNum, hasExternalArgs, existingCmd);
        return;
    }

    int targetW = (int)round(gCurrentViewportPoints.width);
    int targetH = (int)round(gCurrentViewportPoints.height);
    if (targetW < 640 || targetH < 360) { targetW = 1536; targetH = 864; }

    NSString *targetCmd = [NSString stringWithFormat:@" \"../../../Hk_project/Hk_project.uproject\" \"-basedir=%@\" -SaveToUserDir -ResX=%d -ResY=%d -sm5 -metalsm5 -metal -log",
                           ueBaseDir, targetW, targetH];
    NSUInteger charLen = targetCmd.length;
    size_t allocBytes = (charLen + 1) * sizeof(unichar);
    unichar *newBuf = (unichar *)ShimUnrealMalloc(allocBytes);
    if (!newBuf) return;
    [targetCmd getCharacters:newBuf range:NSMakeRange(0, charLen)];
    newBuf[charLen] = 0;

    *pData = newBuf;
    *pNum = (int32_t)(charLen + 1);
    *pMax = (int32_t)(charLen + 1);

    NSLog(@"SHIM AUTONOMOUS LAUNCH: updated GSavedCommandLine via FMemory::Realloc (prev=\"%@\") -> \"%@\" (ArrayNum=%d ptr=%p)",
          existingCmd, targetCmd, *pNum, newBuf);
}

static void ShimPrepareAutonomousLaunchEnvironment(const char *stage) {
    ShimInstallOutputDevice();
    ShimSanitizeGameUserSettingsIni();

    int *pArgc = _NSGetArgc();
    char ***pArgv = _NSGetArgv();
    int origArgc = (pArgc && *pArgc > 0) ? *pArgc : 1;
    char **origArgv = (pArgv && *pArgv) ? *pArgv : NULL;

    if (origArgv && origArgv[0] && !gSafeUIKitArgv[0]) {
        gSafeUIKitArgv[0] = strdup(origArgv[0]);
        gSafeUIKitArgv[1] = NULL;
    }

    NSString *macBundlePath = NSBundle.mainBundle.bundlePath; // reported as <AppBundle>/Mac by RuntimeHooks
    if (![macBundlePath.lastPathComponent isEqualToString:@"Mac"]) {
        NSString *candidate = [macBundlePath stringByAppendingPathComponent:@"Mac"];
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
            macBundlePath = candidate;
        }
    }
    NSString *ueBaseDir = [macBundlePath stringByAppendingPathComponent:@"Contents/UE4/Hk_project/Binaries/Mac"];
    BOOL ueBaseDirExists = [NSFileManager.defaultManager fileExistsAtPath:ueBaseDir];
    if (ueBaseDirExists) {
        chdir(ueBaseDir.fileSystemRepresentation);
    }

    BOOL hasBaseDir = NO;
    BOOL hasUproject = NO;
    for (int i = 1; i < origArgc && origArgv && origArgv[i]; i++) {
        if (strcasestr(origArgv[i], "-basedir=")) hasBaseDir = YES;
        if (strcasestr(origArgv[i], ".uproject")) hasUproject = YES;
    }

    if (hasBaseDir && hasUproject) {
        if (!gSynthesizedArguments) {
            NSMutableArray *arr = [NSMutableArray new];
            for (int i = 0; i < origArgc && origArgv && origArgv[i]; i++) [arr addObject:@(origArgv[i])];
            gSynthesizedArguments = [arr copy];
            NSLog(@"SHIM LAUNCH [%s]: external arguments present (argc=%d): %@",
                  stage, origArgc, [arr componentsJoinedByString:@" "]);
        }
        if (ueBaseDirExists) {
            ShimSyncUnrealGSavedCommandLine(ueBaseDir, YES);
        }
        return;
    }

    if (!ueBaseDirExists) return;

    int targetW = (int)round(gCurrentViewportPoints.width);
    int targetH = (int)round(gCurrentViewportPoints.height);
    if (targetW < 640 || targetH < 360) { targetW = 1536; targetH = 864; }

    const char *uprojArg = "../../../Hk_project/Hk_project.uproject";
    NSString *baseDirFlag = [NSString stringWithFormat:@"-basedir=%@", ueBaseDir];
    NSString *resXFlag = [NSString stringWithFormat:@"-ResX=%d", targetW];
    NSString *resYFlag = [NSString stringWithFormat:@"-ResY=%d", targetH];

    int maxArgs = origArgc + 10;
    char **newArgv = (char **)calloc((size_t)maxArgs, sizeof(char *));
    int newArgc = 0;
    newArgv[newArgc++] = (origArgv && origArgv[0]) ? strdup(origArgv[0]) : strdup("Stray-Mac-Shipping");
    if (!hasUproject) newArgv[newArgc++] = strdup(uprojArg);
    if (!hasBaseDir) newArgv[newArgc++] = strdup(baseDirFlag.UTF8String);
    newArgv[newArgc++] = strdup(resXFlag.UTF8String);
    newArgv[newArgc++] = strdup(resYFlag.UTF8String);
    newArgv[newArgc++] = strdup("-sm5");
    newArgv[newArgc++] = strdup("-metalsm5");
    newArgv[newArgc++] = strdup("-metal");
    newArgv[newArgc++] = strdup("-log");
    for (int i = 1; i < origArgc && origArgv && origArgv[i]; i++) {
        if (!strncmp(origArgv[i], "-NSDocumentRevisionsDebugMode", 29)) continue;
        newArgv[newArgc++] = strdup(origArgv[i]);
    }
    newArgv[newArgc] = NULL;

    NSMutableArray<NSString *> *synth = [NSMutableArray arrayWithCapacity:(NSUInteger)newArgc];
    for (int i = 0; i < newArgc; i++) [synth addObject:@(newArgv[i])];
    gSynthesizedArguments = [synth copy];

    if (pArgc) *pArgc = newArgc;
    if (pArgv) *pArgv = newArgv;

    NSLog(@"SHIM AUTONOMOUS LAUNCH [%s]: synthesized argc=%d argv=%@",
          stage, newArgc, [synth componentsJoinedByString:@" "]);
    ShimSyncUnrealGSavedCommandLine(ueBaseDir, NO);
}

static void ShimUIKitFiberMain(void) {
    char **uikitArgv = gSafeUIKitArgv[0] ? gSafeUIKitArgv : *_NSGetArgv();
    UIApplicationMain(1, uikitArgv, @"UIApplication", @"ShimAppDelegate");
    abort();
}

static void ShimStartUIKitOnFiber(void) {
    NSLog(@"SHIM game polls for events: starting UIKit on its own stack");
    gUIKitStarted = gUIKitOnFiber = gPolling = YES;
    if (!gEventQueue) gEventQueue = [NSMutableArray new];
    size_t size = 8 << 20, guard = 16 << 10;
    char *stack = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (stack == MAP_FAILED) abort();
    mprotect(stack, guard, PROT_NONE);
    memset(&gUIKitContext, 0, sizeof gUIKitContext);
    gUIKitContext.x19_x30[11] = (uint64_t)ShimUIKitFiberMain;
    gUIKitContext.sp = ((uint64_t)stack + size) & ~15ULL;
    ShimContextSwitch(&gGameContext, &gUIKitContext);
}

static void ShimYieldToGame(void) {
    static BOOL yielded;
    if (!gUIKitOnFiber || yielded) return;
    yielded = YES;
    NSLog(@"SHIM UIKit up: resuming the game's loop");
    ShimContextSwitch(&gUIKitContext, &gGameContext);
}

static NSEvent *ShimTakeEvent(uint64_t mask, BOOL dequeue) {
    for (NSUInteger i = 0; i < gEventQueue.count; i++) {
        NSEvent *e = gEventQueue[i];
        if (!(mask & (1ULL << e.type))) continue;
        if (!dequeue) return e;
        [gEventQueue removeObjectAtIndex:i--];
        for (NSArray *m in [gMonitors copy]) {
            if (!([m[0] unsignedLongLongValue] & (1ULL << e.type))) continue;
            e = ((NSEvent *(^)(NSEvent *))m[1])(e);
            if (!e) break;
        }
        if (e) return e;
    }
    return nil;
}

@implementation NSApplication
SHIM_RESOLVE
+ (instancetype)sharedApplication {
    if (!NSApp) { NSApp = [self new]; gWindows = [NSMutableArray new]; }
    return NSApp;
}
- (BOOL)setActivationPolicy:(NSInteger)policy { return YES; }
- (void)activateIgnoringOtherApps:(BOOL)flag {}
- (void)preventWindowOrdering {}
- (void)finishLaunching {}
- (NSArray *)windows { return gWindows; }
- (NSWindow *)windowWithWindowNumber:(NSInteger)windowNum {
    for (NSWindow *w in gWindows) {
        if (w.windowNumber == windowNum) return w;
    }
    return ShimActiveGameWindow();
}
- (void)terminate:(id)sender { exit(0); }
- (void)sendEvent:(NSEvent *)e { [e.window sendEvent:e]; }
- (NSWindow *)keyWindow { return ShimActiveGameWindow(); }
- (NSWindow *)mainWindow { return ShimActiveGameWindow(); }
- (void)run {
    ShimPrepareAutonomousLaunchEnvironment("NSApp.run");
    if (gUIKitStarted) { for (;;) CFRunLoopRun(); }
    gUIKitStarted = YES;
    NSLog(@"SHIM -[NSApplication run] -> UIApplicationMain (delegate=%@)", self.delegate);
    char **uikitArgv = gSafeUIKitArgv[0] ? gSafeUIKitArgv : *_NSGetArgv();
    UIApplicationMain(1, uikitArgv, @"UIApplication", @"ShimAppDelegate");
}
- (BOOL)isRunning { return gUIKitStarted; }
- (NSUInteger)presentationOptions { return gPresentationOptions; }
- (void)setPresentationOptions:(NSUInteger)o { gPresentationOptions = o; }
- (BOOL)isActive { return YES; }
- (void)stop:(id)sender {}
- (void)updateWindows {}
- (NSEvent *)currentEvent { return gCurrentEvent; }
- (void)postEvent:(NSEvent *)e atStart:(BOOL)atStart {
    if (!gEventQueue) gEventQueue = [NSMutableArray new];
    if (atStart) [gEventQueue insertObject:e atIndex:0]; else [gEventQueue addObject:e];
}
- (void)discardEventsMatchingMask:(uint64_t)mask beforeEvent:(NSEvent *)last {
    NSIndexSet *drop = [gEventQueue indexesOfObjectsPassingTest:^BOOL(NSEvent *e, NSUInteger i, BOOL *stop) {
        if (e == last) { *stop = YES; return NO; }
        return (mask & (1ULL << e.type)) != 0;
    }];
    [gEventQueue removeObjectsAtIndexes:drop];
}
- (NSEvent *)nextEventMatchingMask:(uint64_t)mask untilDate:(NSDate *)date inMode:(NSString *)mode dequeue:(BOOL)dequeue {
    if (!gUIKitStarted) ShimStartUIKitOnFiber();
    NSEvent *e = ShimTakeEvent(mask, dequeue);
    NSTimeInterval wait = date ? date.timeIntervalSinceNow : 0;
    while (!e) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, MAX(0, MIN(wait, 0.25)), true);
        e = ShimTakeEvent(mask, dequeue);
        wait = date ? date.timeIntervalSinceNow : 0;
        if (wait <= 0) break;
    }
    if (e && dequeue) gCurrentEvent = e;
    static unsigned polls, delivered; static CFAbsoluteTime last;
    polls++; if (e && dequeue) delivered++;
    if (CFAbsoluteTimeGetCurrent() - last > 5) {
        NSLog(@"SHIM polls=%u delivered=%u queued=%lu (last 5 s)", polls, delivered, (unsigned long)gEventQueue.count);
        polls = delivered = 0; last = CFAbsoluteTimeGetCurrent();
    }
    return e;
}
@end

static NSString *ExeDelegateClass(void) {
    unsigned n = 0;
    const char **names = objc_copyClassNamesForImage(_dyld_get_image_name(0), &n);
    NSString *found = nil;
    for (unsigned i = 0; i < n && !found; i++) {
        unsigned pc = 0;
        Protocol * __unsafe_unretained *ps = class_copyProtocolList(objc_getClass(names[i]), &pc);
        for (unsigned j = 0; j < pc; j++)
            if (!strcmp(protocol_getName(ps[j]), "NSApplicationDelegate")) found = @(names[i]);
        free(ps);
    }
    free(names);
    return found;
}

static NSString *NibDelegateClass(NSString *nibName) {
    NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingFormat:@"/Contents/Resources/%@.nib/designable.nib", nibName];
    NSString *xml = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!xml) return ExeDelegateClass();
    NSRegularExpression *outlet = [NSRegularExpression regularExpressionWithPattern:@"<outlet property=\"delegate\" destination=\"([^\"]+)\"" options:0 error:nil];
    NSTextCheckingResult *m = xml ? [outlet firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)] : nil;
    if (!m) return nil;
    NSString *dest = [xml substringWithRange:[m rangeAtIndex:1]];
    NSString *pattern = [NSString stringWithFormat:@"id=\"%@\"[^>]*customClass=\"([^\"]+)\"", dest];
    NSRegularExpression *obj = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *c = [obj firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
    return c ? [xml substringWithRange:[c rangeAtIndex:1]] : nil;
}

static void ShimDispatch(NSEvent *e) {
    if (!e) return;
    if (!e.window) e.window = ShimActiveGameWindow();
    gCurrentEvent = e;
    if (e.type == NSEventTypeKeyDown || e.type == NSEventTypeKeyUp) {
        static int loggedKeys = 0;
        if (loggedKeys++ < 80) {
            NSLog(@"SHIM NSEVENT KEY %s: keyCode=0x%02x chars=\"%@\" win=%@ monitors=%lu",
                  e.type == NSEventTypeKeyDown ? "DOWN" : "UP",
                  e.keyCode,
                  [e.characters stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"],
                  NSStringFromClass([e.window class]),
                  (unsigned long)gMonitors.count);
        }
    }
    if (gPolling) {
        if (!gEventQueue) gEventQueue = [NSMutableArray new];
        [gEventQueue addObject:e];
        return;
    }
    for (NSArray *m in [gMonitors copy]) {
        if (!([m[0] unsignedLongLongValue] & (1ULL << e.type))) continue;
        e = ((NSEvent *(^)(NSEvent *))m[1])(e);
        if (!e) return;
    }
    [(NSApplication *)NSApp sendEvent:e];
}

__attribute__((visibility("default"))) int NSApplicationMain(int argc, const char *argv[]) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    Class principal = NSClassFromString(info[@"NSPrincipalClass"]) ?: [NSApplication class];
    NSApplication *app = [principal sharedApplication];
    NSString *delegateName = info[@"SHIMAppDelegate"] ?: NibDelegateClass(info[@"NSMainNibFile"]);
    static id delegate;
    delegate = [NSClassFromString(delegateName) new];
    NSLog(@"SHIM NSApplicationMain principal=%@ delegate=%@ (%@)", principal, delegateName, delegate);
    app.delegate = delegate;
    [app run];
    return 0;
}

// MARK: Priority 3 & 4 — Real DualShock 4 + Virtual GameController with Immutable Snapshots

@interface ShimVirtualAxis : GCControllerAxisInput
@property (nonatomic) float shimValue;
@property (nonatomic, copy) GCControllerAxisValueChangedHandler shimHandler;
- (instancetype)copySnapshot;
@end

@implementation ShimVirtualAxis
- (float)value { return _shimValue; }
- (void)setValue:(float)v {
    if (fabsf(_shimValue - v) < 0.0001f) return;
    _shimValue = v;
    if (_shimHandler) _shimHandler(self, v);
}
- (GCControllerAxisValueChangedHandler)valueChangedHandler { return _shimHandler; }
- (void)setValueChangedHandler:(GCControllerAxisValueChangedHandler)h { _shimHandler = [h copy]; }
- (instancetype)copySnapshot {
    ShimVirtualAxis *s = [ShimVirtualAxis new];
    s.shimValue = _shimValue;
    return s;
}
@end

@interface ShimVirtualButton : GCControllerButtonInput
@property (nonatomic) float shimValue;
@property (nonatomic) BOOL shimPressed;
@property (nonatomic) BOOL unobservedPress;
@property (nonatomic) BOOL pendingRelease;
@property (nonatomic, copy) NSString *shimName;
@property (nonatomic, copy) GCControllerButtonValueChangedHandler shimValueHandler;
@property (nonatomic, copy) GCControllerButtonValueChangedHandler shimPressedHandler;
- (instancetype)initWithName:(NSString *)name;
- (void)updatePressed:(BOOL)pressed value:(float)val;
- (instancetype)consumeAndCopySnapshot;
@end

@implementation ShimVirtualButton
- (instancetype)initWithName:(NSString *)name {
    if ((self = [super init])) { _shimName = [name copy]; }
    return self;
}
- (NSString *)localizedName { return _shimName ?: @"Button"; }
- (float)value { return _shimValue; }
- (BOOL)isPressed { return _shimPressed; }
- (BOOL)isTouched { return _shimPressed; }
- (void)updatePressed:(BOOL)pressed value:(float)val {
    @synchronized (self) {
        if (pressed) {
            _pendingRelease = NO;
            _unobservedPress = YES;
            BOOL changed = (!_shimPressed) || (fabsf(_shimValue - val) > 0.001f);
            _shimPressed = YES;
            _shimValue = val;
            if (changed) {
                if (_shimPressedHandler) _shimPressedHandler(self, val, YES);
                if (_shimValueHandler) _shimValueHandler(self, val, YES);
            }
        } else {
            if (_unobservedPress) {
                // Keep pressed=YES until at least one Unreal poll (capture) observes the press!
                _pendingRelease = YES;
            } else {
                _pendingRelease = NO;
                BOOL changed = _shimPressed || (_shimValue > 0.001f);
                _shimPressed = NO;
                _shimValue = 0.0f;
                if (changed) {
                    if (_shimPressedHandler) _shimPressedHandler(self, 0.0f, NO);
                    if (_shimValueHandler) _shimValueHandler(self, 0.0f, NO);
                }
            }
        }
    }
}
- (instancetype)consumeAndCopySnapshot {
    ShimVirtualButton *s = [[ShimVirtualButton alloc] initWithName:_shimName];
    @synchronized (self) {
        if (_unobservedPress) {
            // Frame N: let this frame observe the press in both snapshot (x28) and live (Current)
            _unobservedPress = NO;
        } else if (_pendingRelease) {
            // Frame N+1: press was observed on Frame N; now release cleanly so Frame N+1 fires OnControllerButtonReleased
            _pendingRelease = NO;
            _shimPressed = NO;
            _shimValue = 0.0f;
        }
        s.shimPressed = _shimPressed;
        s.shimValue = _shimValue;
    }
    return s;
}
- (GCControllerButtonValueChangedHandler)valueChangedHandler { return _shimValueHandler; }
- (void)setValueChangedHandler:(GCControllerButtonValueChangedHandler)h { _shimValueHandler = [h copy]; }
- (GCControllerButtonValueChangedHandler)pressedChangedHandler { return _shimPressedHandler; }
- (void)setPressedChangedHandler:(GCControllerButtonValueChangedHandler)h { _shimPressedHandler = [h copy]; }
@end

@interface ShimVirtualDpad : GCControllerDirectionPad
@property (nonatomic, strong) ShimVirtualAxis *shimXAxis;
@property (nonatomic, strong) ShimVirtualAxis *shimYAxis;
@property (nonatomic, strong) ShimVirtualButton *shimUp;
@property (nonatomic, strong) ShimVirtualButton *shimDown;
@property (nonatomic, strong) ShimVirtualButton *shimLeft;
@property (nonatomic, strong) ShimVirtualButton *shimRight;
@property (nonatomic, copy) GCControllerDirectionPadValueChangedHandler shimHandler;
- (void)setX:(float)x y:(float)y;
- (instancetype)consumeAndCopySnapshot;
@end

@implementation ShimVirtualDpad
- (instancetype)init {
    if ((self = [super init])) {
        _shimXAxis = [ShimVirtualAxis new];
        _shimYAxis = [ShimVirtualAxis new];
        _shimUp = [[ShimVirtualButton alloc] initWithName:@"Up"];
        _shimDown = [[ShimVirtualButton alloc] initWithName:@"Down"];
        _shimLeft = [[ShimVirtualButton alloc] initWithName:@"Left"];
        _shimRight = [[ShimVirtualButton alloc] initWithName:@"Right"];
    }
    return self;
}
- (GCControllerAxisInput *)xAxis { return _shimXAxis; }
- (GCControllerAxisInput *)yAxis { return _shimYAxis; }
- (GCControllerButtonInput *)up { return _shimUp; }
- (GCControllerButtonInput *)down { return _shimDown; }
- (GCControllerButtonInput *)left { return _shimLeft; }
- (GCControllerButtonInput *)right { return _shimRight; }
- (GCControllerDirectionPadValueChangedHandler)valueChangedHandler { return _shimHandler; }
- (void)setValueChangedHandler:(GCControllerDirectionPadValueChangedHandler)h { _shimHandler = [h copy]; }
- (void)setX:(float)x y:(float)y {
    float cx = fmaxf(-1.0f, fminf(1.0f, x));
    float cy = fmaxf(-1.0f, fminf(1.0f, y));
    BOOL changed = (fabsf(_shimXAxis.shimValue - cx) > 0.001f) || (fabsf(_shimYAxis.shimValue - cy) > 0.001f);
    [_shimXAxis setValue:cx];
    [_shimYAxis setValue:cy];
    [_shimRight updatePressed:(cx > 0.35f) value:(cx > 0.0f ? cx : 0.0f)];
    [_shimLeft updatePressed:(cx < -0.35f) value:(cx < 0.0f ? -cx : 0.0f)];
    [_shimUp updatePressed:(cy > 0.35f) value:(cy > 0.0f ? cy : 0.0f)];
    [_shimDown updatePressed:(cy < -0.35f) value:(cy < -0.0f ? -cy : 0.0f)];
    if (changed && _shimHandler) {
        _shimHandler(self, cx, cy);
    }
}
- (instancetype)consumeAndCopySnapshot {
    ShimVirtualDpad *s = [ShimVirtualDpad new];
    s.shimXAxis = [_shimXAxis copySnapshot];
    s.shimYAxis = [_shimYAxis copySnapshot];
    s.shimUp = [_shimUp consumeAndCopySnapshot];
    s.shimDown = [_shimDown consumeAndCopySnapshot];
    s.shimLeft = [_shimLeft consumeAndCopySnapshot];
    s.shimRight = [_shimRight consumeAndCopySnapshot];
    return s;
}
@end

@interface ShimVirtualExtendedGamepad : GCExtendedGamepad
@property (nonatomic, weak) ShimVirtualGCController *shimController;
@property (nonatomic, strong) ShimVirtualDpad *shimDpad;
@property (nonatomic, strong) ShimVirtualDpad *shimLeftStick;
@property (nonatomic, strong) ShimVirtualDpad *shimRightStick;
@property (nonatomic, strong) ShimVirtualButton *shimButtonA;
@property (nonatomic, strong) ShimVirtualButton *shimButtonB;
@property (nonatomic, strong) ShimVirtualButton *shimButtonX;
@property (nonatomic, strong) ShimVirtualButton *shimButtonY;
@property (nonatomic, strong) ShimVirtualButton *shimLeftShoulder;
@property (nonatomic, strong) ShimVirtualButton *shimRightShoulder;
@property (nonatomic, strong) ShimVirtualButton *shimLeftTrigger;
@property (nonatomic, strong) ShimVirtualButton *shimRightTrigger;
@property (nonatomic, strong) ShimVirtualButton *shimLeftThumbstickButton;
@property (nonatomic, strong) ShimVirtualButton *shimRightThumbstickButton;
@property (nonatomic, strong) ShimVirtualButton *shimButtonMenu;
@property (nonatomic, strong) ShimVirtualButton *shimButtonOptions;
@property (nonatomic, strong) ShimVirtualButton *shimButtonHome;
@property (nonatomic, copy) GCExtendedGamepadValueChangedHandler shimValueChangedHandler;
- (void)notifyElementChanged:(GCControllerElement *)element;
- (instancetype)consumeAndCopySnapshot;
- (uint32_t)pressedButtonsBitmask;
@end

@implementation ShimVirtualExtendedGamepad
- (instancetype)init {
    if ((self = [super init])) {
        _shimDpad = [ShimVirtualDpad new];
        _shimLeftStick = [ShimVirtualDpad new];
        _shimRightStick = [ShimVirtualDpad new];
        _shimButtonA = [[ShimVirtualButton alloc] initWithName:@"Button A"];
        _shimButtonB = [[ShimVirtualButton alloc] initWithName:@"Button B"];
        _shimButtonX = [[ShimVirtualButton alloc] initWithName:@"Button X"];
        _shimButtonY = [[ShimVirtualButton alloc] initWithName:@"Button Y"];
        _shimLeftShoulder = [[ShimVirtualButton alloc] initWithName:@"Left Shoulder"];
        _shimRightShoulder = [[ShimVirtualButton alloc] initWithName:@"Right Shoulder"];
        _shimLeftTrigger = [[ShimVirtualButton alloc] initWithName:@"Left Trigger"];
        _shimRightTrigger = [[ShimVirtualButton alloc] initWithName:@"Right Trigger"];
        _shimLeftThumbstickButton = [[ShimVirtualButton alloc] initWithName:@"Left Thumbstick Button"];
        _shimRightThumbstickButton = [[ShimVirtualButton alloc] initWithName:@"Right Thumbstick Button"];
        _shimButtonMenu = [[ShimVirtualButton alloc] initWithName:@"Button Menu"];
        _shimButtonOptions = [[ShimVirtualButton alloc] initWithName:@"Button Options"];
        _shimButtonHome = [[ShimVirtualButton alloc] initWithName:@"Button Home"];
    }
    return self;
}
- (GCController *)controller { return (GCController *)_shimController; }
- (GCExtendedGamepad *)saveSnapshot { return [self consumeAndCopySnapshot]; }
- (GCControllerDirectionPad *)dpad { return _shimDpad; }
- (GCControllerDirectionPad *)leftThumbstick { return _shimLeftStick; }
- (GCControllerDirectionPad *)rightThumbstick { return _shimRightStick; }
- (GCControllerButtonInput *)buttonA { return _shimButtonA; }
- (GCControllerButtonInput *)buttonB { return _shimButtonB; }
- (GCControllerButtonInput *)buttonX { return _shimButtonX; }
- (GCControllerButtonInput *)buttonY { return _shimButtonY; }
- (GCControllerButtonInput *)leftShoulder { return _shimLeftShoulder; }
- (GCControllerButtonInput *)rightShoulder { return _shimRightShoulder; }
- (GCControllerButtonInput *)leftTrigger { return _shimLeftTrigger; }
- (GCControllerButtonInput *)rightTrigger { return _shimRightTrigger; }
- (GCControllerButtonInput *)leftThumbstickButton { return _shimLeftThumbstickButton; }
- (GCControllerButtonInput *)rightThumbstickButton { return _shimRightThumbstickButton; }
- (GCControllerButtonInput *)buttonMenu { return _shimButtonMenu; }
- (GCControllerButtonInput *)buttonOptions { return _shimButtonOptions; }
- (GCControllerButtonInput *)buttonHome { return _shimButtonHome; }
- (GCExtendedGamepadValueChangedHandler)valueChangedHandler { return _shimValueChangedHandler; }
- (void)setValueChangedHandler:(GCExtendedGamepadValueChangedHandler)h { _shimValueChangedHandler = [h copy]; }
- (void)notifyElementChanged:(GCControllerElement *)element {
    if (_shimValueChangedHandler) {
        _shimValueChangedHandler(self, element);
    }
}
- (uint32_t)pressedButtonsBitmask {
    uint32_t m = 0;
    if (_shimButtonA.isPressed) m |= (1U << 0);
    if (_shimButtonB.isPressed) m |= (1U << 1);
    if (_shimButtonX.isPressed) m |= (1U << 2);
    if (_shimButtonY.isPressed) m |= (1U << 3);
    if (_shimLeftShoulder.isPressed) m |= (1U << 4);
    if (_shimRightShoulder.isPressed) m |= (1U << 5);
    if (_shimLeftTrigger.isPressed) m |= (1U << 6);
    if (_shimRightTrigger.isPressed) m |= (1U << 7);
    if (_shimDpad.shimUp.isPressed) m |= (1U << 8);
    if (_shimDpad.shimDown.isPressed) m |= (1U << 9);
    if (_shimDpad.shimLeft.isPressed) m |= (1U << 10);
    if (_shimDpad.shimRight.isPressed) m |= (1U << 11);
    if (_shimButtonMenu.isPressed) m |= (1U << 12);
    if (_shimButtonOptions.isPressed) m |= (1U << 13);
    if (_shimLeftThumbstickButton.isPressed) m |= (1U << 14);
    if (_shimRightThumbstickButton.isPressed) m |= (1U << 15);
    return m;
}
- (instancetype)consumeAndCopySnapshot {
    ShimVirtualExtendedGamepad *s = [ShimVirtualExtendedGamepad new];
    s.shimController = _shimController;
    s.shimDpad = [_shimDpad consumeAndCopySnapshot];
    s.shimLeftStick = [_shimLeftStick consumeAndCopySnapshot];
    s.shimRightStick = [_shimRightStick consumeAndCopySnapshot];
    s.shimButtonA = [_shimButtonA consumeAndCopySnapshot];
    s.shimButtonB = [_shimButtonB consumeAndCopySnapshot];
    s.shimButtonX = [_shimButtonX consumeAndCopySnapshot];
    s.shimButtonY = [_shimButtonY consumeAndCopySnapshot];
    s.shimLeftShoulder = [_shimLeftShoulder consumeAndCopySnapshot];
    s.shimRightShoulder = [_shimRightShoulder consumeAndCopySnapshot];
    s.shimLeftTrigger = [_shimLeftTrigger consumeAndCopySnapshot];
    s.shimRightTrigger = [_shimRightTrigger consumeAndCopySnapshot];
    s.shimLeftThumbstickButton = [_shimLeftThumbstickButton consumeAndCopySnapshot];
    s.shimRightThumbstickButton = [_shimRightThumbstickButton consumeAndCopySnapshot];
    s.shimButtonMenu = [_shimButtonMenu consumeAndCopySnapshot];
    s.shimButtonOptions = [_shimButtonOptions consumeAndCopySnapshot];
    s.shimButtonHome = [_shimButtonHome consumeAndCopySnapshot];
    return s;
}
@end

@interface ShimVirtualGCController : GCController
@property (nonatomic, strong) ShimVirtualExtendedGamepad *shimGamepad;
@property (nonatomic) GCControllerPlayerIndex shimPlayerIndex;
@property (nonatomic, strong) dispatch_queue_t shimHandlerQueue;
@property (nonatomic, copy) void (^shimPausedHandler)(GCController *controller);
@property (nonatomic) BOOL shimIsSnapshot;
@end

@implementation ShimVirtualGCController
- (instancetype)init {
    if ((self = [super init])) {
        _shimGamepad = [ShimVirtualExtendedGamepad new];
        _shimGamepad.shimController = self;
        _shimPlayerIndex = GCControllerPlayerIndex1;
        _shimHandlerQueue = dispatch_get_main_queue();
    }
    return self;
}
- (NSString *)vendorName { return @"Stray Touch Controller"; }
- (NSString *)productCategory { return @"MFi"; }
- (BOOL)isAttachedToDevice { return NO; }
- (BOOL)isSnapshot { return _shimIsSnapshot; }
- (GCControllerPlayerIndex)playerIndex { return _shimPlayerIndex; }
- (void)setPlayerIndex:(GCControllerPlayerIndex)idx { _shimPlayerIndex = idx; }
- (dispatch_queue_t)handlerQueue { return _shimHandlerQueue ?: dispatch_get_main_queue(); }
- (void)setHandlerQueue:(dispatch_queue_t)q { _shimHandlerQueue = q; }
- (void (^)(GCController *))controllerPausedHandler { return _shimPausedHandler; }
- (void)setControllerPausedHandler:(void (^)(GCController *))h { _shimPausedHandler = [h copy]; }
- (GCExtendedGamepad *)extendedGamepad {
    if (!_shimIsSnapshot && !gUnrealPolledVirtualGamepad) {
        gUnrealPolledVirtualGamepad = YES;
        NSLog(@"SHIM VGC: Unreal FAppleControllerInterface attached & polling extendedGamepad");
    }
    return _shimGamepad;
}
- (GCMicroGamepad *)microGamepad { return nil; }
- (GCMotion *)motion { return nil; }
- (id)haptics { return nil; }
- (id)light { return nil; }
- (GCController *)capture {
    if (!gUnrealPolledVirtualGamepad) {
        gUnrealPolledVirtualGamepad = YES;
        NSLog(@"SHIM VGC: Unreal FAppleControllerInterface called -[GCController capture] (returning immutable snapshot)");
    }
    ShimVirtualGCController *snap = [ShimVirtualGCController new];
    snap.shimIsSnapshot = YES;
    snap.shimPlayerIndex = _shimPlayerIndex;
    snap.shimGamepad = [_shimGamepad consumeAndCopySnapshot];
    snap.shimGamepad.shimController = snap;

    // Log state transitions observed by Unreal's polling loop (never per-frame spam)
    static uint32_t sLastPolledMask = 0;
    static float sLastLX = 0.0f, sLastLY = 0.0f, sLastRX = 0.0f, sLastRY = 0.0f;
    uint32_t mask = [snap.shimGamepad pressedButtonsBitmask];
    float lx = snap.shimGamepad.shimLeftStick.shimXAxis.value;
    float ly = snap.shimGamepad.shimLeftStick.shimYAxis.value;
    float rx = snap.shimGamepad.shimRightStick.shimXAxis.value;
    float ry = snap.shimGamepad.shimRightStick.shimYAxis.value;
    if (mask != sLastPolledMask ||
        fabsf(lx - sLastLX) > 0.28f || fabsf(ly - sLastLY) > 0.28f ||
        fabsf(rx - sLastRX) > 0.28f || fabsf(ry - sLastRY) > 0.28f) {
        sLastPolledMask = mask;
        sLastLX = lx; sLastLY = ly; sLastRX = rx; sLastRY = ry;
        NSLog(@"SHIM VGC POLLED BY UNREAL: buttonsMask=0x%04x L=(%.2f,%.2f) R=(%.2f,%.2f)",
              mask, lx, ly, rx, ry);
    }
    return snap;
}
- (id)physicalInputProfile { return _shimGamepad; }
@end

static ShimVirtualGCController *gVirtualController = nil;
static BOOL gVirtualControllerConnectedInUnreal = NO;
static IMP gOrigGCControllers = NULL;
static IMP gOrigGCCapture = NULL;

static ShimVirtualGCController *ShimGetVirtualController(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gVirtualController = [ShimVirtualGCController new];
    });
    return gVirtualController;
}

// Returns ONLY genuine physical controllers (e.g. DUALSHOCK 4 Wireless Controller), never ShimVirtualGCController.
static NSArray<GCController *> *ShimRealControllers(void) {
    NSArray<GCController *> *raw = gOrigGCControllers
        ? ((NSArray<GCController *> *(*)(id, SEL))gOrigGCControllers)(GCController.class, @selector(controllers))
        : @[];
    if (!raw.count) return @[];
    NSMutableArray<GCController *> *real = [NSMutableArray arrayWithCapacity:raw.count];
    for (GCController *c in raw) {
        if ([c isKindOfClass:ShimVirtualGCController.class]) continue;
        if ([c.vendorName isEqualToString:@"Stray Touch Controller"]) continue;
        [real addObject:c];
    }
    return real;
}

static BOOL ShimHasRealControllerConnected(void) {
    return ShimRealControllers().count > 0;
}

// Diagnostic state-change logging when Unreal FAppleControllerInterface::SendControllerEvents
// calls -[GCController capture] on a real physical controller (e.g. DualShock 4).
static GCController *ShimRealGCCapture(GCController *self, SEL _cmd) {
    if ([self isKindOfClass:ShimVirtualGCController.class]) {
        return [(ShimVirtualGCController *)self capture];
    }
    GCController *snap = gOrigGCCapture
        ? ((GCController *(*)(id, SEL))gOrigGCCapture)(self, _cmd)
        : nil;

    GCExtendedGamepad *gp = self.extendedGamepad;
    if (gp) {
        if (!gUnrealPolledRealGamepad) {
            gUnrealPolledRealGamepad = YES;
            BOOL isDS = [gp isKindOfClass:NSClassFromString(@"GCDualShockGamepad") ?: NSObject.class];
            NSLog(@"SHIM REAL GC POLLED BY UNREAL: vendor=\"%@\" category=\"%@\" playerIndex=%ld extended=%p dualShock=%d",
                  self.vendorName, self.productCategory, (long)self.playerIndex, gp, isDS);
        }
        uint32_t mask = 0;
        if (gp.buttonA.isPressed) mask |= (1U << 0);
        if (gp.buttonB.isPressed) mask |= (1U << 1);
        if (gp.buttonX.isPressed) mask |= (1U << 2);
        if (gp.buttonY.isPressed) mask |= (1U << 3);
        if (gp.leftShoulder.isPressed) mask |= (1U << 4);
        if (gp.rightShoulder.isPressed) mask |= (1U << 5);
        if (gp.leftTrigger.isPressed) mask |= (1U << 6);
        if (gp.rightTrigger.isPressed) mask |= (1U << 7);
        if (gp.dpad.up.isPressed) mask |= (1U << 8);
        if (gp.dpad.down.isPressed) mask |= (1U << 9);
        if (gp.dpad.left.isPressed) mask |= (1U << 10);
        if (gp.dpad.right.isPressed) mask |= (1U << 11);
        if (gp.buttonMenu.isPressed) mask |= (1U << 12);
        if (gp.buttonOptions.isPressed) mask |= (1U << 13);
        if (gp.leftThumbstickButton.isPressed) mask |= (1U << 14);
        if (gp.rightThumbstickButton.isPressed) mask |= (1U << 15);

        float lx = gp.leftThumbstick.xAxis.value;
        float ly = gp.leftThumbstick.yAxis.value;
        float rx = gp.rightThumbstick.xAxis.value;
        float ry = gp.rightThumbstick.yAxis.value;
        float l2 = gp.leftTrigger.value;
        float r2 = gp.rightTrigger.value;

        static uint32_t sLastRealMask = 0;
        static float sLastRLX = 0.0f, sLastRLY = 0.0f, sLastRRX = 0.0f, sLastRRY = 0.0f;
        if (mask != sLastRealMask ||
            fabsf(lx - sLastRLX) > 0.25f || fabsf(ly - sLastRLY) > 0.25f ||
            fabsf(rx - sLastRRX) > 0.25f || fabsf(ry - sLastRRY) > 0.25f) {
            sLastRealMask = mask;
            sLastRLX = lx; sLastRLY = ly; sLastRRX = rx; sLastRRY = ry;
            NSMutableArray<NSString *> *names = [NSMutableArray new];
            if (mask & (1U << 0)) [names addObject:@"Cross/A"];
            if (mask & (1U << 1)) [names addObject:@"Circle/B"];
            if (mask & (1U << 2)) [names addObject:@"Square/X"];
            if (mask & (1U << 3)) [names addObject:@"Triangle/Y"];
            if (mask & (1U << 4)) [names addObject:@"L1"];
            if (mask & (1U << 5)) [names addObject:@"R1"];
            if (mask & (1U << 6)) [names addObject:@"L2"];
            if (mask & (1U << 7)) [names addObject:@"R2"];
            if (mask & (1U << 8)) [names addObject:@"DUp"];
            if (mask & (1U << 9)) [names addObject:@"DDown"];
            if (mask & (1U << 10)) [names addObject:@"DLeft"];
            if (mask & (1U << 11)) [names addObject:@"DRight"];
            if (mask & (1U << 12)) [names addObject:@"Options/Menu"];
            if (mask & (1U << 13)) [names addObject:@"Share/Options"];
            if (mask & (1U << 14)) [names addObject:@"L3"];
            if (mask & (1U << 15)) [names addObject:@"R3"];
            NSLog(@"SHIM REAL GC INPUT [%@]: mask=0x%04x [%@] L=(%.2f,%.2f) R=(%.2f,%.2f) L2=%.2f R2=%.2f",
                  self.vendorName, mask, [names componentsJoinedByString:@","], lx, ly, rx, ry, l2, r2);
        }
    }
    return snap;
}

// Priority 4: When any real physical controller is connected, return ONLY the real physical
// controller(s) so FAppleControllerInterface assigns Slot 0 (PlayerIndex = 0) exclusively to the
// physical controller and never disables it with PlayerIndex = 4.
static NSArray<GCController *> *ShimGCControllers(id self, SEL _cmd) {
    NSArray<GCController *> *real = ShimRealControllers();
    if (real.count > 0) {
        gVirtualControllerConnectedInUnreal = NO;
        return real;
    }
    if (gInputMode == ShimInputModeKeyMouseOnly) {
        return @[];
    }
    ShimVirtualGCController *vgc = ShimGetVirtualController();
    gVirtualControllerConnectedInUnreal = YES;
    return @[vgc];
}

__attribute__((constructor)) static void HookVirtualGCController(void) {
    Method m = class_getClassMethod(GCController.class, @selector(controllers));
    if (m) gOrigGCControllers = method_setImplementation(m, (IMP)ShimGCControllers);
    Method cap = class_getInstanceMethod(GCController.class, @selector(capture));
    if (cap) gOrigGCCapture = method_setImplementation(cap, (IMP)ShimRealGCCapture);
}

// MARK: Synthetic Key & Mouse Helpers for Stray Input Mappings

enum {
    kVK_ANSI_A     = 0x00,
    kVK_ANSI_S     = 0x01,
    kVK_ANSI_D     = 0x02,
    kVK_ANSI_F     = 0x03,
    kVK_ANSI_G     = 0x05,
    kVK_ANSI_Q     = 0x0C,
    kVK_ANSI_W     = 0x0D,
    kVK_ANSI_E     = 0x0E,
    kVK_ANSI_R     = 0x0F,
    kVK_ANSI_1     = 0x12,
    kVK_ANSI_2     = 0x13,
    kVK_Return     = 0x24,
    kVK_Tab        = 0x30,
    kVK_Space      = 0x31,
    kVK_Escape     = 0x35,
    kVK_Shift      = 0x38,
    kVK_Option     = 0x3A,
    kVK_Control    = 0x3B,
    kVK_LeftArrow  = 0x7B,
    kVK_RightArrow = 0x7C,
    kVK_DownArrow  = 0x7D,
    kVK_UpArrow    = 0x7E,
};

static NSString *ShimArrowChar(unichar code) {
    return [NSString stringWithCharacters:&code length:1];
}

static void ShimSendKey(unsigned short keyCode, NSString *chars, BOOL down) {
    BOOL isMod = (keyCode == kVK_Shift || keyCode == kVK_Option || keyCode == kVK_Control);
    NSUInteger modBit = 0;
    if (keyCode == kVK_Shift) modBit = (1 << 17);
    else if (keyCode == kVK_Control) modBit = (1 << 18);
    else if (keyCode == kVK_Option) modBit = (1 << 19);

    if (modBit) {
        if (down) gModifiers |= modBit;
        else gModifiers &= ~modBit;
    }

    NSEvent *e = [NSEvent new];
    e.type = isMod ? NSEventTypeFlagsChanged : (down ? NSEventTypeKeyDown : NSEventTypeKeyUp);
    e.keyCode = keyCode;
    // FMacApplication::DeferEvent (0x10167d354) drops any KeyDown/KeyUp whose characters.length == 0!
    NSString *nonEmptyChars = (chars && chars.length > 0) ? chars : @" ";
    e.characters = isMod ? @"" : nonEmptyChars;
    e.charactersIgnoringModifiers = isMod ? @"" : nonEmptyChars;
    e.modifierFlags = gModifiers;
    e.isARepeat = NO;
    e.timestamp = NSProcessInfo.processInfo.systemUptime;
    e.locationInWindow = gMouse;
    e.window = ShimActiveGameWindow();
    ShimDispatch(e);
}

static void ShimSendMouseDelta(CGFloat dx, CGFloat dy) {
    NSWindow *w = ShimActiveGameWindow();
    CGSize sz = w ? w.frame.size : gCurrentViewportPoints;
    if (sz.width <= 0 || sz.height <= 0) sz = CGSizeMake(1536, 864);
    gMouse.x = fmax(0.0, fmin(sz.width, gMouse.x + dx));
    gMouse.y = fmax(0.0, fmin(sz.height, gMouse.y - dy));

    NSEvent *e = [NSEvent new];
    e.type = (gPressedMouseButtons & 1) ? NSEventTypeLeftMouseDragged : NSEventTypeMouseMoved;
    e.locationInWindow = gMouse;
    e.deltaX = dx;
    e.deltaY = dy;
    e.timestamp = NSProcessInfo.processInfo.systemUptime;
    e.window = w;
    e.modifierFlags = gModifiers;
    ShimDispatch(e);
}

static void ShimSendMouseButton(NSInteger buttonNumber, BOOL down, CGPoint windowPt) {
    if (buttonNumber == 0) {
        if (down) gPressedMouseButtons |= (1 << 0);
        else gPressedMouseButtons &= ~(1UL << 0);
    } else if (buttonNumber == 1) {
        if (down) gPressedMouseButtons |= (1 << 1);
        else gPressedMouseButtons &= ~(1UL << 1);
    } else {
        if (down) gPressedMouseButtons |= (1 << 2);
        else gPressedMouseButtons &= ~(1UL << 2);
    }
    gMouse = windowPt;
    NSEvent *e = [NSEvent new];
    if (buttonNumber == 0) e.type = down ? NSEventTypeLeftMouseDown : NSEventTypeLeftMouseUp;
    else if (buttonNumber == 1) e.type = down ? NSEventTypeRightMouseDown : NSEventTypeRightMouseUp;
    else e.type = down ? NSEventTypeOtherMouseDown : NSEventTypeOtherMouseUp;
    e.buttonNumber = buttonNumber;
    e.clickCount = 1;
    e.locationInWindow = windowPt;
    e.timestamp = NSProcessInfo.processInfo.systemUptime;
    e.window = ShimActiveGameWindow();
    e.modifierFlags = gModifiers;
    ShimDispatch(e);
}

// MARK: Priority 3 — Adaptive, Zero-Overlap Multi-Touch HUD

typedef NS_ENUM(NSInteger, ShimActionID) {
    ShimActionJump = 1,       // A / Cross / SpaceBar / Enter (JumpUp, MenuAccept, GUI_Validate, SkipCinematic)
    ShimActionMeow = 2,       // B / Circle / LeftAlt / LeftCtrl (Meow, JumpDown, MenuDecline, GUI_Cancel)
    ShimActionInteract = 3,   // X / Square / E (Interact, NextDialogLine, GUI_X)
    ShimActionCatButton = 4,  // Y / Triangle / Q / Tab (CatButton, GUI_Y, MenuReset / Brightness Defaults)
    ShimActionRun = 5,        // RT / R2 / LeftShift (AnalogRun, ContextualAxisRight, MenuTabRight)
    ShimActionZoom = 6,       // LT / L2 / RightMouseButton (ShoulderCamera, ContextualAxisLeft, MenuTabLeft)
    ShimActionDefluxor = 7,   // LB / L1 / LeftMouseButton (StrongLight, GUI_LB)
    ShimActionActionCam = 8,  // RB / R3 / MiddleMouseButton (ActionCamera, GUI_RB)
    ShimActionDpadUp = 9,     // D-Pad Up / Up / Tab (GUI_Open / Inventory B-12, MenuUp)
    ShimActionDpadDown = 10,  // D-Pad Down / Down / 1 (Help / B-12 Hint, MenuDown)
    ShimActionDpadLeft = 11,  // D-Pad Left / Left / 2 (ToggleLight / Flashlight, MenuLeft / Brightness -)
    ShimActionDpadRight = 12, // D-Pad Right / Right (MenuRight / Brightness +)
    ShimActionPause = 13,     // Options / Escape (MenuStart, MenuInputEscapeKey)
    ShimActionSelect = 14,    // Share / Tab / R (MenuSelect, GUI_Validate)
};

@interface ShimTouchButton : UIView
@property (nonatomic) ShimActionID actionID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic) BOOL isCircular;
@property (nonatomic) BOOL activePressed;
@end

@implementation ShimTouchButton
- (instancetype)initWithAction:(ShimActionID)action title:(NSString *)title subtitle:(NSString *)subtitle color:(UIColor *)color circular:(BOOL)circular {
    if ((self = [super initWithFrame:CGRectZero])) {
        _actionID = action;
        _title = [title copy];
        _subtitle = [subtitle copy];
        _accentColor = color ?: [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0];
        _isCircular = circular;
        self.multipleTouchEnabled = YES;
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.62];
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [_accentColor colorWithAlphaComponent:0.82].CGColor;

        _titleLabel = [UILabel new];
        _titleLabel.text = _title;
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:circular ? 13.0 : 10.5];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_titleLabel];

        if (_subtitle.length) {
            _subLabel = [UILabel new];
            _subLabel.text = _subtitle;
            _subLabel.textColor = [_accentColor colorWithAlphaComponent:0.95];
            _subLabel.font = [UIFont systemFontOfSize:7.0 weight:UIFontWeightSemibold];
            _subLabel.textAlignment = NSTextAlignmentCenter;
            [self addSubview:_subLabel];
        }
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    self.layer.cornerRadius = _isCircular ? (MIN(w, h) * 0.5) : 9.0;
    if (_subLabel) {
        _titleLabel.frame = CGRectMake(2, h * 0.12, w - 4, h * 0.48);
        _subLabel.frame = CGRectMake(2, h * 0.56, w - 4, h * 0.34);
    } else {
        _titleLabel.frame = self.bounds;
    }
}
- (void)setActivePressed:(BOOL)p {
    if (_activePressed == p) return;
    _activePressed = p;
    self.backgroundColor = p ? [_accentColor colorWithAlphaComponent:0.55] : [UIColor colorWithWhite:0.08 alpha:0.62];
    self.transform = p ? CGAffineTransformMakeScale(0.93, 0.93) : CGAffineTransformIdentity;
}
@end

@interface ShimTouchOverlayView : UIView
@property (nonatomic, strong) UIView *controlsContainer;
@property (nonatomic, strong) UIView *joystickBase;
@property (nonatomic, strong) UIView *joystickKnob;
@property (nonatomic, strong) NSMutableArray<ShimTouchButton *> *actionButtons;
@property (nonatomic, strong) NSMapTable<UITouch *, ShimTouchButton *> *activeButtonTouches;
@property (nonatomic, strong) UITouch *joystickTouch;
@property (nonatomic, strong) UITouch *cameraTouch;
@property (nonatomic) CGPoint joystickCenter;
@property (nonatomic) CGFloat joystickRadius;
@property (nonatomic) CGPoint cameraStartPt;
@property (nonatomic) CGPoint cameraLastPt;
@property (nonatomic) NSTimeInterval cameraTouchStartTime;
@property (nonatomic) BOOL cameraDidDrag;
@property (nonatomic) uint64_t cameraLookSeq;
@property (nonatomic) BOOL keyWDown, keyADown, keySDown, keyDDown;
@property (nonatomic) BOOL hiddenByPhysicalController;
@property (nonatomic) BOOL settingsPanelOpen;
@property (nonatomic, strong) UIButton *settingsGearButton;
@property (nonatomic, strong) UIView *settingsPanel;
@property (nonatomic, strong) UIButton *aspectPill;
@property (nonatomic, strong) UIButton *inputModePill;
@property (nonatomic, strong) UIButton *sensPill;
@property (nonatomic, strong) UIButton *opacPill;
@property (nonatomic, strong) UIButton *metalHudPill;
@property (nonatomic, strong) UIButton *pausePanelBtn;
@property (nonatomic, strong) UIButton *selectPanelBtn;
- (void)updateForPhysicalControllerState;
- (void)resetAllActiveTouches;
@end

@implementation ShimTouchOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _controlsContainer = [[UIView alloc] initWithFrame:self.bounds];
        _controlsContainer.multipleTouchEnabled = YES;
        _controlsContainer.userInteractionEnabled = NO; // overlay itself handles multi-touch routing cleanly
        _controlsContainer.backgroundColor = [UIColor clearColor];
        _controlsContainer.alpha = gHudOpacity;
        [self addSubview:_controlsContainer];

        _actionButtons = [NSMutableArray new];
        _activeButtonTouches = [NSMapTable weakToWeakObjectsMapTable];

        // Virtual Left Analog Joystick (54pt radius = 108pt diameter: fixed center inside safe area)
        _joystickRadius = 54.0;
        _joystickBase = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 108, 108)];
        _joystickBase.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.42];
        _joystickBase.layer.cornerRadius = 54.0;
        _joystickBase.layer.borderWidth = 1.8;
        _joystickBase.layer.borderColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:0.65].CGColor;
        [_controlsContainer addSubview:_joystickBase];

        _joystickKnob = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
        _joystickKnob.backgroundColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:0.78];
        _joystickKnob.layer.cornerRadius = 22.0;
        _joystickKnob.layer.borderWidth = 1.5;
        _joystickKnob.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
        [_controlsContainer addSubview:_joystickKnob];

        UIColor *orange = [UIColor colorWithRed:1.0 green:0.52 blue:0.12 alpha:1.0];
        UIColor *cyan   = [UIColor colorWithRed:0.20 green:0.82 blue:0.95 alpha:1.0];
        UIColor *green  = [UIColor colorWithRed:0.25 green:0.88 blue:0.45 alpha:1.0];
        UIColor *pink   = [UIColor colorWithRed:0.98 green:0.36 blue:0.52 alpha:1.0];
        UIColor *yellow = [UIColor colorWithRed:0.98 green:0.82 blue:0.20 alpha:1.0];
        UIColor *silver = [UIColor colorWithWhite:0.82 alpha:1.0];

        // Face Diamond Buttons
        [self addActionButton:ShimActionJump      title:@"A"   subtitle:@"OK/SALTAR" color:green  circular:YES];
        [self addActionButton:ShimActionMeow      title:@"B"   subtitle:@"MIAU/ATRÁS" color:pink  circular:YES];
        [self addActionButton:ShimActionInteract  title:@"X"   subtitle:@"USAR (E)"  color:cyan   circular:YES];
        [self addActionButton:ShimActionCatButton title:@"Y"   subtitle:@"GATO (Q)"  color:yellow circular:YES];

        // Triggers & Shoulders
        [self addActionButton:ShimActionRun       title:@"RT"  subtitle:@"CORRER"    color:orange circular:NO];
        [self addActionButton:ShimActionZoom      title:@"LT"  subtitle:@"ZOOM"      color:silver circular:NO];
        [self addActionButton:ShimActionDefluxor  title:@"LB"  subtitle:@"LUZ UV"    color:cyan   circular:NO];
        [self addActionButton:ShimActionActionCam title:@"RB"  subtitle:@"CÁMARA"    color:silver circular:NO];

        // D-Pad (B-12 Inventory, Flashlight, Help, Menu Left/Right/Up/Down)
        [self addActionButton:ShimActionDpadUp    title:@"▲"   subtitle:@"INV"       color:silver circular:NO];
        [self addActionButton:ShimActionDpadDown  title:@"▼"   subtitle:@"B-12"      color:silver circular:NO];
        [self addActionButton:ShimActionDpadLeft  title:@"◀"   subtitle:@"LUZ"       color:yellow circular:NO];
        [self addActionButton:ShimActionDpadRight title:@"▶"   subtitle:@"DER"       color:silver circular:NO];

        // Compact Top-Left System Buttons (No top bar!)
        [self addActionButton:ShimActionPause     title:@"⏸"   subtitle:nil          color:orange circular:NO];
        [self addActionButton:ShimActionSelect    title:@"⊞"   subtitle:nil          color:silver circular:NO];

        // Single Compact Top-Right Gear Button ('⚙') + Collapsible Settings Panel
        _settingsGearButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_settingsGearButton setTitle:@"⚙" forState:UIControlStateNormal];
        [_settingsGearButton setTitleColor:[UIColor colorWithWhite:0.95 alpha:1.0] forState:UIControlStateNormal];
        _settingsGearButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
        _settingsGearButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.62];
        _settingsGearButton.layer.cornerRadius = 16.0;
        _settingsGearButton.layer.borderWidth = 1.2;
        _settingsGearButton.layer.borderColor = [UIColor colorWithWhite:0.65 alpha:0.65].CGColor;
        [_settingsGearButton addTarget:self action:@selector(toggleSettingsPanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_settingsGearButton];

        _settingsPanel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 210, 198)];
        _settingsPanel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.90];
        _settingsPanel.layer.cornerRadius = 14.0;
        _settingsPanel.layer.borderWidth = 1.2;
        _settingsPanel.layer.borderColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:0.75].CGColor;
        _settingsPanel.hidden = YES;
        [self addSubview:_settingsPanel];

        _inputModePill  = [self makePanelButton:@"MODO: HÍBRIDO"     action:@selector(cycleInputMode)];
        _aspectPill     = [self makePanelButton:@"VISTA: 16:9"       action:@selector(cycleAspectMode)];
        _sensPill       = [self makePanelButton:@"SENSIBILIDAD: 1.0x" action:@selector(cycleSensitivity)];
        _opacPill       = [self makePanelButton:@"OPACIDAD HUD: 78%" action:@selector(cycleOpacity)];
        _metalHudPill   = [self makePanelButton:@"METAL HUD: OFF"    action:@selector(toggleMetalHud)];
        _pausePanelBtn  = [self makePanelButton:@"⏸ PAUSA (ESC)"     action:@selector(triggerPauseFromPanel)];
        _selectPanelBtn = [self makePanelButton:@"⊞ SELECT (TAB)"    action:@selector(triggerSelectFromPanel)];

        [self updateUtilityPillTitles];
        [self updateForPhysicalControllerState];
    }
    return self;
}

- (ShimTouchButton *)addActionButton:(ShimActionID)action title:(NSString *)title subtitle:(NSString *)sub color:(UIColor *)color circular:(BOOL)circular {
    ShimTouchButton *btn = [[ShimTouchButton alloc] initWithAction:action title:title subtitle:sub color:color circular:circular];
    [_controlsContainer addSubview:btn];
    [_actionButtons addObject:btn];
    return btn;
}

- (UIButton *)makePanelButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.96 alpha:1.0] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.85];
    b.layer.cornerRadius = 8.0;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:0.65].CGColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [_settingsPanel addSubview:b];
    return b;
}

- (ShimTouchButton *)buttonForAction:(ShimActionID)act {
    for (ShimTouchButton *b in _actionButtons) {
        if (b.actionID == act) return b;
    }
    return nil;
}

- (void)toggleSettingsPanel {
    _settingsPanelOpen = !_settingsPanelOpen;
    _settingsPanel.hidden = !_settingsPanelOpen || _hiddenByPhysicalController;
    _settingsGearButton.backgroundColor = _settingsPanelOpen
        ? [UIColor colorWithRed:1.0 green:0.52 blue:0.12 alpha:0.80]
        : [UIColor colorWithWhite:0.08 alpha:0.62];
    NSLog(@"SHIM TOUCH HUD: settings panel %@", _settingsPanelOpen ? @"OPENED" : @"CLOSED");
}

- (void)updateForPhysicalControllerState {
    BOOL hasReal = ShimHasRealControllerConnected();
    if (_hiddenByPhysicalController != hasReal) {
        _hiddenByPhysicalController = hasReal;
        NSLog(@"SHIM TOUCH HUD: physical controller connected=%d -> touch HUD %@",
              hasReal, hasReal ? @"AUTO-HIDDEN" : @"AUTO-RESTORED");
    }
    if (hasReal) {
        _controlsContainer.hidden = YES;
        _settingsGearButton.hidden = YES;
        _settingsPanel.hidden = YES;
    } else {
        _settingsGearButton.hidden = NO;
        _settingsPanel.hidden = !_settingsPanelOpen;
        _controlsContainer.alpha = gHudOpacity;
        _controlsContainer.hidden = (gHudOpacity <= 0.02);
    }
}

- (void)updateUtilityPillTitles {
    static const char *const kInModes[] = {"MODO: HÍBRIDO", "MODO: GAMEPAD", "MODO: TECL+RATÓN"};
    static const char *const kAspModes[] = {"VISTA: 16:9", "VISTA: SAFE", "VISTA: FULL"};
    [_inputModePill setTitle:@(kInModes[gInputMode % 3]) forState:UIControlStateNormal];
    [_aspectPill setTitle:@(kAspModes[gAspectMode % 3]) forState:UIControlStateNormal];
    [_sensPill setTitle:[NSString stringWithFormat:@"SENSIBILIDAD: %.1fx", gLookSensitivity] forState:UIControlStateNormal];
    int pct = (int)round(gHudOpacity * 100.0);
    [_opacPill setTitle:(pct <= 5 ? @"OPACIDAD HUD: OCULTO" : [NSString stringWithFormat:@"OPACIDAD HUD: %d%%", pct]) forState:UIControlStateNormal];
    [_metalHudPill setTitle:(gMetalHudEnabled ? @"METAL HUD: ON" : @"METAL HUD: OFF") forState:UIControlStateNormal];
}

- (void)cycleInputMode {
    gInputMode = (ShimInputMode)((gInputMode + 1) % 3);
    [self updateUtilityPillTitles];
    NSLog(@"SHIM TOUCH HUD: input mode switched to %ld (0=Hybrid, 1=GamepadOnly, 2=KeyMouseOnly)", (long)gInputMode);
}

- (void)cycleAspectMode {
    gAspectMode = (ShimAspectMode)((gAspectMode + 1) % 3);
    [self updateUtilityPillTitles];
    for (NSWindow *w in gWindows) {
        ShimSyncWindowAndViewGeometry(w, YES);
    }
    [self setNeedsLayout];
}

- (void)cycleSensitivity {
    if (gLookSensitivity < 0.9) gLookSensitivity = 1.0;
    else if (gLookSensitivity < 1.3) gLookSensitivity = 1.5;
    else if (gLookSensitivity < 1.9) gLookSensitivity = 2.2;
    else gLookSensitivity = 0.7;
    [self updateUtilityPillTitles];
    NSLog(@"SHIM TOUCH HUD: camera look sensitivity -> %.1fx", gLookSensitivity);
}

- (void)cycleOpacity {
    if (gHudOpacity > 0.65) gHudOpacity = 0.45;
    else if (gHudOpacity > 0.30) gHudOpacity = 0.20;
    else if (gHudOpacity > 0.05) gHudOpacity = 0.0;
    else gHudOpacity = 0.78;
    _controlsContainer.alpha = gHudOpacity;
    _controlsContainer.hidden = _hiddenByPhysicalController || (gHudOpacity <= 0.02);
    [self updateUtilityPillTitles];
    NSLog(@"SHIM TOUCH HUD: overlay opacity -> %.2f", gHudOpacity);
}

- (void)toggleMetalHud {
    gMetalHudEnabled = !gMetalHudEnabled;
    ShimApplyMetalHudSetting();
    [self updateUtilityPillTitles];
    NSLog(@"SHIM TOUCH HUD: Metal Performance HUD -> %@", gMetalHudEnabled ? @"ON" : @"OFF");
}

- (void)triggerPauseFromPanel {
    [self triggerAction:ShimActionPause pressed:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self triggerAction:ShimActionPause pressed:NO];
    });
}

- (void)triggerSelectFromPanel {
    [self triggerAction:ShimActionSelect pressed:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self triggerAction:ShimActionSelect pressed:NO];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _controlsContainer.frame = self.bounds;
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    if (W <= 0 || H <= 0) return;

    UIEdgeInsets safe = self.safeAreaInsets;
    // Respect actual safe area insets (e.g., L:62, R:62, B:20 on iPhone 17 Pro Max 956x440)
    CGFloat padL = MAX(20.0, safe.left > 0 ? safe.left : 62.0);
    CGFloat padR = MAX(20.0, safe.right > 0 ? safe.right : 62.0);
    CGFloat padB = MAX(14.0, safe.bottom > 0 ? safe.bottom : 20.0);
    CGFloat padT = MAX(10.0, safe.top > 0 ? safe.top + 6.0 : 12.0);

    // 1. Left Analog Joystick (Bottom-Left inside safe area, fixed center)
    CGFloat joyR = _joystickRadius; // 54pt
    _joystickCenter = CGPointMake(padL + joyR + 8.0, H - padB - joyR - 6.0);
    _joystickBase.frame = CGRectMake(_joystickCenter.x - joyR, _joystickCenter.y - joyR, joyR * 2.0, joyR * 2.0);
    if (!_joystickTouch) {
        _joystickKnob.center = _joystickCenter;
    }

    // 2. D-Pad Cluster (Above Left Joystick with >= 22pt vertical clearance to joystickBase)
    CGFloat dSize = 34.0;
    CGFloat dGap = 4.0;
    CGFloat dCx = _joystickCenter.x;
    CGFloat dCy = _joystickCenter.y - joyR - 22.0 - dSize - dGap + (dSize * 0.5);
    [self buttonForAction:ShimActionDpadUp].frame    = CGRectMake(dCx - dSize * 0.5, dCy - dSize * 0.5 - dGap - dSize, dSize, dSize);
    [self buttonForAction:ShimActionDpadDown].frame  = CGRectMake(dCx - dSize * 0.5, dCy + dSize * 0.5 + dGap, dSize, dSize);
    [self buttonForAction:ShimActionDpadLeft].frame  = CGRectMake(dCx - dSize * 0.5 - dGap - dSize, dCy - dSize * 0.5, dSize, dSize);
    [self buttonForAction:ShimActionDpadRight].frame = CGRectMake(dCx + dSize * 0.5 + dGap, dCy - dSize * 0.5, dSize, dSize);

    // 3. Left Triggers LT / LB (Above D-Pad with >= 18pt vertical clearance)
    CGFloat trW = 54.0, trH = 32.0;
    CGFloat dpadTopY = CGRectGetMinY([self buttonForAction:ShimActionDpadUp].frame);
    CGFloat leftShoulderY = MAX(padT + 36.0, dpadTopY - trH - 18.0);
    [self buttonForAction:ShimActionZoom].frame      = CGRectMake(padL + 4.0, leftShoulderY, trW, trH);
    [self buttonForAction:ShimActionDefluxor].frame  = CGRectMake(padL + trW + 12.0, leftShoulderY, trW, trH);

    // 4. Compact Top-Left System Buttons (Pause '⏸' & Select '⊞' — no top bar!)
    CGFloat sysW = 36.0, sysH = 28.0;
    [self buttonForAction:ShimActionPause].frame  = CGRectMake(padL + 4.0, padT, sysW, sysH);
    [self buttonForAction:ShimActionSelect].frame = CGRectMake(padL + sysW + 10.0, padT, sysW, sysH);

    // 5. Action Diamond (Bottom-Right: A=Bottom, B=Right, X=Left, Y=Top)
    // abSize=46, abStep=52 -> diagonal distance 52*sqrt(2)=73.5pt > 46pt and bounding box gap 52-46=6pt (0 overlaps!)
    CGFloat abSize = 46.0;
    CGFloat abStep = 52.0;
    CGFloat dRightCx = W - padR - abStep - abSize * 0.5 - 6.0;
    CGFloat dRightCy = H - padB - abStep - abSize * 0.5 - 6.0;
    [self buttonForAction:ShimActionJump].frame      = CGRectMake(dRightCx - abSize * 0.5, dRightCy + abStep - abSize * 0.5, abSize, abSize);
    [self buttonForAction:ShimActionMeow].frame      = CGRectMake(dRightCx + abStep - abSize * 0.5, dRightCy - abSize * 0.5, abSize, abSize);
    [self buttonForAction:ShimActionInteract].frame  = CGRectMake(dRightCx - abStep - abSize * 0.5, dRightCy - abSize * 0.5, abSize, abSize);
    [self buttonForAction:ShimActionCatButton].frame = CGRectMake(dRightCx - abSize * 0.5, dRightCy - abStep - abSize * 0.5, abSize, abSize);

    // 6. Right Triggers RB / RT (Above Action Diamond with >= 20pt vertical clearance)
    CGFloat diamondTopY = CGRectGetMinY([self buttonForAction:ShimActionCatButton].frame);
    CGFloat rightShoulderY = MAX(padT + 40.0, diamondTopY - trH - 20.0);
    [self buttonForAction:ShimActionRun].frame       = CGRectMake(W - padR - trW - 4.0, rightShoulderY, trW, trH);
    [self buttonForAction:ShimActionActionCam].frame = CGRectMake(W - padR - trW * 2.0 - 12.0, rightShoulderY, trW, trH);

    // 7. Single Compact Top-Right Settings Gear Button ('⚙') & Floating Panel
    CGFloat gearSize = 32.0;
    _settingsGearButton.frame = CGRectMake(W - padR - gearSize - 4.0, padT, gearSize, gearSize);

    CGFloat panelW = 216.0, panelH = 196.0;
    CGFloat panelX = CGRectGetMaxX(_settingsGearButton.frame) - panelW;
    CGFloat panelY = CGRectGetMaxY(_settingsGearButton.frame) + 6.0;
    _settingsPanel.frame = CGRectMake(panelX, panelY, panelW, panelH);

    CGFloat rowW = panelW - 20.0, rowH = 26.0;
    _inputModePill.frame  = CGRectMake(10.0, 10.0,  rowW, rowH);
    _aspectPill.frame     = CGRectMake(10.0, 40.0,  rowW, rowH);
    _sensPill.frame       = CGRectMake(10.0, 70.0,  rowW, rowH);
    _opacPill.frame       = CGRectMake(10.0, 100.0, rowW, rowH);
    _metalHudPill.frame   = CGRectMake(10.0, 130.0, rowW, rowH);
    CGFloat halfW = (rowW - 6.0) * 0.5;
    _pausePanelBtn.frame  = CGRectMake(10.0, 160.0, halfW, rowH);
    _selectPanelBtn.frame = CGRectMake(10.0 + halfW + 6.0, 160.0, halfW, rowH);

    // 8. Automatic Non-Overlap & Safe-Bounds Verification Log (once per distinct screen size)
    static CGSize sLastVerifiedSize = {0, 0};
    if (fabs(W - sLastVerifiedSize.width) > 0.5 || fabs(H - sLastVerifiedSize.height) > 0.5) {
        sLastVerifiedSize = CGSizeMake(W, H);
        int overlaps = 0;
        int outOfBounds = 0;
        for (NSUInteger i = 0; i < _actionButtons.count; i++) {
            ShimTouchButton *b1 = _actionButtons[i];
            if (CGRectGetMinX(b1.frame) < 0 || CGRectGetMaxX(b1.frame) > W ||
                CGRectGetMinY(b1.frame) < 0 || CGRectGetMaxY(b1.frame) > H) {
                outOfBounds++;
            }
            if (CGRectIntersectsRect(b1.frame, _joystickBase.frame)) {
                overlaps++;
            }
            for (NSUInteger j = i + 1; j < _actionButtons.count; j++) {
                ShimTouchButton *b2 = _actionButtons[j];
                if (b1.isCircular && b2.isCircular) {
                    CGPoint c1 = CGPointMake(CGRectGetMidX(b1.frame), CGRectGetMidY(b1.frame));
                    CGPoint c2 = CGPointMake(CGRectGetMidX(b2.frame), CGRectGetMidY(b2.frame));
                    CGFloat rSum = (b1.frame.size.width + b2.frame.size.width) * 0.5;
                    if (hypot(c1.x - c2.x, c1.y - c2.y) < rSum - 0.5) overlaps++;
                } else if (CGRectIntersectsRect(b1.frame, b2.frame)) {
                    overlaps++;
                }
            }
        }
        NSLog(@"SHIM HUD LAYOUT VERIFIED on %.0fx%.0f (safe L:%.0f R:%.0f B:%.0f): joyCenter=(%.0f,%.0f) diamondCenter=(%.0f,%.0f) gear=(%.0f,%.0f) overlaps=%d outOfBounds=%d",
              W, H, safe.left, safe.right, safe.bottom,
              _joystickCenter.x, _joystickCenter.y, dRightCx, dRightCy,
              _settingsGearButton.frame.origin.x, _settingsGearButton.frame.origin.y,
              overlaps, outOfBounds);
    }
}

- (ShimTouchButton *)hitActionButtonAt:(CGPoint)pt {
    if (_hiddenByPhysicalController || _controlsContainer.hidden || _controlsContainer.alpha <= 0.02) return nil;
    // Two-pass hit-test: exact frame first, then 3.5pt margin (never stealing from an exact hit)
    for (ShimTouchButton *b in _actionButtons) {
        if (b.isCircular) {
            CGPoint c = CGPointMake(CGRectGetMidX(b.frame), CGRectGetMidY(b.frame));
            if (hypot(pt.x - c.x, pt.y - c.y) <= b.frame.size.width * 0.5) return b;
        } else if (CGRectContainsPoint(b.frame, pt)) {
            return b;
        }
    }
    for (ShimTouchButton *b in _actionButtons) {
        CGRect hitRect = CGRectInset(b.frame, -3.5, -3.5);
        if (b.isCircular) {
            CGPoint c = CGPointMake(CGRectGetMidX(b.frame), CGRectGetMidY(b.frame));
            if (hypot(pt.x - c.x, pt.y - c.y) <= (b.frame.size.width * 0.5 + 3.5)) return b;
        } else if (CGRectContainsPoint(hitRect, pt)) {
            return b;
        }
    }
    return nil;
}

- (BOOL)isPointInJoystickZone:(CGPoint)pt {
    if (_hiddenByPhysicalController || _controlsContainer.hidden || _controlsContainer.alpha <= 0.02) return NO;
    CGFloat dx = pt.x - _joystickCenter.x;
    CGFloat dy = pt.y - _joystickCenter.y;
    return hypot(dx, dy) <= (_joystickRadius * 1.25);
}

// Priority 3: When Unreal is polling the virtual controller (gUnrealPolledVirtualGamepad == YES),
// dispatch exclusively through ShimVirtualExtendedGamepad so Stray stays in Gamepad UI mode and
// never receives duplicate Return/Space/Escape/WASD events on the same frame.
- (void)triggerAction:(ShimActionID)action pressed:(BOOL)pressed {
    ShimVirtualExtendedGamepad *pad = ShimGetVirtualController().shimGamepad;
    BOOL useGamepad = (gInputMode != ShimInputModeKeyMouseOnly);
    BOOL useKeys    = (gInputMode == ShimInputModeKeyMouseOnly) ||
                      (gInputMode == ShimInputModeHybrid && !gUnrealPolledVirtualGamepad);

    float v = pressed ? 1.0f : 0.0f;
    static int loggedActions = 0;
    if (loggedActions++ < 80) {
        NSLog(@"SHIM TOUCH ACTION #%d: id=%ld pressed=%d (useGamepad=%d useKeys=%d vgcPolled=%d)",
              loggedActions, (long)action, pressed, useGamepad, useKeys, gUnrealPolledVirtualGamepad);
    }

    switch (action) {
        case ShimActionJump:
            if (useGamepad) { [pad.shimButtonA updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimButtonA]; }
            if (useKeys) { ShimSendKey(kVK_Return, @"\r", pressed); }
            break;
        case ShimActionMeow:
            if (useGamepad) { [pad.shimButtonB updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimButtonB]; }
            if (useKeys) { ShimSendKey(kVK_Option, @"", pressed); }
            break;
        case ShimActionInteract:
            if (useGamepad) { [pad.shimButtonX updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimButtonX]; }
            if (useKeys) { ShimSendKey(kVK_ANSI_E, @"e", pressed); }
            break;
        case ShimActionCatButton:
            if (useGamepad) { [pad.shimButtonY updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimButtonY]; }
            if (useKeys) { ShimSendKey(kVK_ANSI_Q, @"q", pressed); }
            break;
        case ShimActionRun:
            if (useGamepad) { [pad.shimRightTrigger updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimRightTrigger]; }
            if (useKeys) { ShimSendKey(kVK_Shift, @"", pressed); }
            break;
        case ShimActionZoom:
            if (useGamepad) { [pad.shimLeftTrigger updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimLeftTrigger]; }
            if (useKeys) { ShimSendMouseButton(1, pressed, gMouse); }
            break;
        case ShimActionDefluxor:
            if (useGamepad) { [pad.shimLeftShoulder updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimLeftShoulder]; }
            if (useKeys) { ShimSendMouseButton(0, pressed, gMouse); }
            break;
        case ShimActionActionCam:
            if (useGamepad) {
                [pad.shimRightThumbstickButton updatePressed:pressed value:v];
                [pad.shimRightShoulder updatePressed:pressed value:v];
                [pad notifyElementChanged:pad.shimRightThumbstickButton];
            }
            if (useKeys) { ShimSendMouseButton(2, pressed, gMouse); }
            break;
        case ShimActionDpadUp:
            if (useGamepad) { [pad.shimDpad.shimUp updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimDpad]; }
            if (useKeys) { ShimSendKey(kVK_UpArrow, ShimArrowChar(0xF700), pressed); }
            break;
        case ShimActionDpadDown:
            if (useGamepad) { [pad.shimDpad.shimDown updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimDpad]; }
            if (useKeys) { ShimSendKey(kVK_DownArrow, ShimArrowChar(0xF701), pressed); }
            break;
        case ShimActionDpadLeft:
            if (useGamepad) { [pad.shimDpad.shimLeft updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimDpad]; }
            if (useKeys) { ShimSendKey(kVK_LeftArrow, ShimArrowChar(0xF702), pressed); }
            break;
        case ShimActionDpadRight:
            if (useGamepad) { [pad.shimDpad.shimRight updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimDpad]; }
            if (useKeys) { ShimSendKey(kVK_RightArrow, ShimArrowChar(0xF703), pressed); }
            break;
        case ShimActionPause:
            if (useGamepad) { [pad.shimButtonMenu updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimButtonMenu]; }
            if (useKeys) { ShimSendKey(kVK_Escape, @"\x1b", pressed); }
            break;
        case ShimActionSelect:
            if (useGamepad) { [pad.shimButtonOptions updatePressed:pressed value:v]; [pad notifyElementChanged:pad.shimButtonOptions]; }
            if (useKeys) { ShimSendKey(kVK_Tab, @"\t", pressed); }
            break;
    }
}

- (void)updateJoystickWithPoint:(CGPoint)pt {
    CGFloat dx = pt.x - _joystickCenter.x;
    CGFloat dy = pt.y - _joystickCenter.y;
    CGFloat dist = hypot(dx, dy);
    CGFloat maxR = _joystickRadius;
    if (dist > maxR && dist > 0.0001) {
        dx = (dx / dist) * maxR;
        dy = (dy / dist) * maxR;
        dist = maxR;
    }
    _joystickKnob.center = CGPointMake(_joystickCenter.x + dx, _joystickCenter.y + dy);

    float nx = (float)(dx / maxR);
    float ny = (float)(-dy / maxR); // Up on screen is +Y in Gamepad_LeftY
    float mag = hypotf(nx, ny);
    const float deadZone = 0.15f;
    if (mag < deadZone) {
        nx = 0.0f;
        ny = 0.0f;
    } else {
        float scaled = (mag - deadZone) / (1.0f - deadZone);
        nx = (nx / mag) * fminf(1.0f, scaled);
        ny = (ny / mag) * fminf(1.0f, scaled);
    }

    BOOL useGamepad = (gInputMode != ShimInputModeKeyMouseOnly);
    BOOL useKeys    = (gInputMode == ShimInputModeKeyMouseOnly) ||
                      (gInputMode == ShimInputModeHybrid && !gUnrealPolledVirtualGamepad);

    if (useGamepad) {
        ShimVirtualExtendedGamepad *pad = ShimGetVirtualController().shimGamepad;
        [pad.shimLeftStick setX:nx y:ny];
        [pad notifyElementChanged:pad.shimLeftStick];
    }

    if (useKeys) {
        BOOL w = (ny > 0.35f);
        BOOL s = (ny < -0.35f);
        BOOL d = (nx > 0.35f);
        BOOL a = (nx < -0.35f);
        if (w != _keyWDown) { _keyWDown = w; ShimSendKey(kVK_ANSI_W, @"w", w); }
        if (s != _keySDown) { _keySDown = s; ShimSendKey(kVK_ANSI_S, @"s", s); }
        if (d != _keyDDown) { _keyDDown = d; ShimSendKey(kVK_ANSI_D, @"d", d); }
        if (a != _keyADown) { _keyADown = a; ShimSendKey(kVK_ANSI_A, @"a", a); }
    }
}

- (void)resetJoystick {
    _joystickTouch = nil;
    _joystickKnob.center = _joystickCenter;
    ShimVirtualExtendedGamepad *pad = ShimGetVirtualController().shimGamepad;
    [pad.shimLeftStick setX:0.0f y:0.0f];
    [pad notifyElementChanged:pad.shimLeftStick];
    if (_keyWDown) { _keyWDown = NO; ShimSendKey(kVK_ANSI_W, @"w", NO); }
    if (_keySDown) { _keySDown = NO; ShimSendKey(kVK_ANSI_S, @"s", NO); }
    if (_keyDDown) { _keyDDown = NO; ShimSendKey(kVK_ANSI_D, @"d", NO); }
    if (_keyADown) { _keyADown = NO; ShimSendKey(kVK_ANSI_A, @"a", NO); }
}

- (void)resetAllActiveTouches {
    [self resetJoystick];
    for (UITouch *t in [[_activeButtonTouches keyEnumerator] allObjects]) {
        ShimTouchButton *btn = [_activeButtonTouches objectForKey:t];
        if (btn) {
            [btn setActivePressed:NO];
            [self triggerAction:btn.actionID pressed:NO];
        }
    }
    [_activeButtonTouches removeAllObjects];
    _cameraLookSeq++;
    _cameraTouch = nil;
    ShimVirtualExtendedGamepad *pad = ShimGetVirtualController().shimGamepad;
    [pad.shimRightStick setX:0.0f y:0.0f];
    [pad notifyElementChanged:pad.shimRightStick];
}

// Priority 1 & 3: Convert a touch point in the UIKit overlay (956x440 pt) into the 1536x864 AppKit
// window coordinate space (bottom-left origin) used by FMacApplication / Slate hit-testing.
- (CGPoint)convertOverlayPointToViewportWindowPoint:(CGPoint)overlayPt {
    CGRect vpRect = gCurrentViewportContainerRect;
    if (vpRect.size.width <= 0 || vpRect.size.height <= 0) {
        vpRect = self.bounds;
    }
    CGFloat localX = fmax(0.0, fmin(vpRect.size.width, overlayPt.x - vpRect.origin.x));
    CGFloat localY = fmax(0.0, fmin(vpRect.size.height, overlayPt.y - vpRect.origin.y));
    CGFloat scaleX = (vpRect.size.width > 0) ? (gCurrentViewportPoints.width / vpRect.size.width) : 2.0;
    CGFloat scaleY = (vpRect.size.height > 0) ? (gCurrentViewportPoints.height / vpRect.size.height) : 2.0;
    return CGPointMake(localX * scaleX, (vpRect.size.height - localY) * scaleY);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) {
        CGPoint pt = [t locationInView:self];

        // If settings panel is open and user taps outside it, close it cleanly
        if (_settingsPanelOpen && !_settingsPanel.hidden &&
            !CGRectContainsPoint(_settingsPanel.frame, pt) &&
            !CGRectContainsPoint(_settingsGearButton.frame, pt)) {
            [self toggleSettingsPanel];
        }

        // 1. Check virtual action buttons
        ShimTouchButton *btn = [self hitActionButtonAt:pt];
        if (btn) {
            [_activeButtonTouches setObject:btn forKey:t];
            [btn setActivePressed:YES];
            [self triggerAction:btn.actionID pressed:YES];
            continue;
        }

        // 2. Check left analog joystick zone (fixed center)
        if (!_joystickTouch && [self isPointInJoystickZone:pt]) {
            _joystickTouch = t;
            [self updateJoystickWithPoint:pt];
            continue;
        }

        // 3. Camera look / direct viewport click zone
        if (!_cameraTouch) {
            _cameraTouch = t;
            _cameraStartPt = pt;
            _cameraLastPt = pt;
            _cameraTouchStartTime = NSProcessInfo.processInfo.systemUptime;
            _cameraDidDrag = NO;
            _cameraLookSeq++;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *t in touches) {
        CGPoint pt = [t locationInView:self];

        if (t == _joystickTouch) {
            [self updateJoystickWithPoint:pt];
            continue;
        }

        ShimTouchButton *prevBtn = [_activeButtonTouches objectForKey:t];
        if (prevBtn) {
            ShimTouchButton *nowBtn = [self hitActionButtonAt:pt];
            if (nowBtn != prevBtn) {
                [prevBtn setActivePressed:NO];
                [self triggerAction:prevBtn.actionID pressed:NO];
                if (nowBtn) {
                    [_activeButtonTouches setObject:nowBtn forKey:t];
                    [nowBtn setActivePressed:YES];
                    [self triggerAction:nowBtn.actionID pressed:YES];
                } else {
                    [_activeButtonTouches removeObjectForKey:t];
                }
            }
            continue;
        }

        if (t == _cameraTouch) {
            CGFloat dx = (pt.x - _cameraLastPt.x) * gLookSensitivity;
            CGFloat dy = (pt.y - _cameraLastPt.y) * gLookSensitivity;
            _cameraLastPt = pt;
            if (hypot(pt.x - _cameraStartPt.x, pt.y - _cameraStartPt.y) > 6.0) {
                _cameraDidDrag = YES;
            }
            if (fabs(dx) > 0.01 || fabs(dy) > 0.01) {
                uint64_t seq = ++_cameraLookSeq;
                if (gInputMode != ShimInputModeKeyMouseOnly && !_hiddenByPhysicalController) {
                    ShimVirtualExtendedGamepad *pad = ShimGetVirtualController().shimGamepad;
                    float rx = fmaxf(-1.0f, fminf(1.0f, (float)(dx / 12.0)));
                    float ry = fmaxf(-1.0f, fminf(1.0f, (float)(-dy / 12.0)));
                    [pad.shimRightStick setX:rx y:ry];
                    [pad notifyElementChanged:pad.shimRightStick];
                    __weak ShimTouchOverlayView *weakSelf = self;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.065 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        ShimTouchOverlayView *strongSelf = weakSelf;
                        if (strongSelf && strongSelf.cameraLookSeq == seq) {
                            ShimVirtualExtendedGamepad *p = ShimGetVirtualController().shimGamepad;
                            [p.shimRightStick setX:0.0f y:0.0f];
                            [p notifyElementChanged:p.shimRightStick];
                        }
                    });
                } else if (gInputMode == ShimInputModeKeyMouseOnly) {
                    ShimSendMouseDelta(dx * 2.5, dy * 2.5);
                }
            }
        }
    }
}

- (void)endOrCancelTouches:(NSSet<UITouch *> *)touches {
    for (UITouch *t in touches) {
        if (t == _joystickTouch) {
            [self resetJoystick];
            continue;
        }

        ShimTouchButton *btn = [_activeButtonTouches objectForKey:t];
        if (btn) {
            [btn setActivePressed:NO];
            [self triggerAction:btn.actionID pressed:NO];
            [_activeButtonTouches removeObjectForKey:t];
            continue;
        }

        if (t == _cameraTouch) {
            _cameraLookSeq++;
            if (!_hiddenByPhysicalController) {
                ShimVirtualExtendedGamepad *pad = ShimGetVirtualController().shimGamepad;
                [pad.shimRightStick setX:0.0f y:0.0f];
                [pad notifyElementChanged:pad.shimRightStick];
            }

            NSTimeInterval dt = NSProcessInfo.processInfo.systemUptime - _cameraTouchStartTime;
            if (!_cameraDidDrag && dt < 0.30) {
                // Quick tap in viewport -> ensure window is active and send mouse click at that exact 1536x864 window coordinate
                ShimActivateGameWindowNow(ShimActiveGameWindow(), @"ViewportTap");
                CGPoint winPt = [self convertOverlayPointToViewportWindowPoint:_cameraStartPt];
                ShimSendMouseDelta(0, 0);
                ShimSendMouseButton(0, YES, winPt);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    ShimSendMouseButton(0, NO, winPt);
                });
            }
            _cameraTouch = nil;
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endOrCancelTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endOrCancelTouches:touches];
}

@end

// Coordinates physical vs. virtual controller connections in Unreal's FAppleControllerInterface
// and updates the adaptive touch HUD (Priorities 3 & 4).
static void ShimSyncControllersAndHud(NSString *reason) {
    NSArray<GCController *> *real = ShimRealControllers();
    ShimVirtualGCController *vgc = ShimGetVirtualController();

    if (real.count > 0) {
        if (gVirtualControllerConnectedInUnreal) {
            gVirtualControllerConnectedInUnreal = NO;
            NSLog(@"SHIM CONTROLLER SYNC (%@): disconnecting virtual controller so physical controller owns PlayerIndex=0", reason);
            [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidDisconnectNotification object:vgc];
        }
        GCController *primary = real.firstObject;
        primary.playerIndex = GCControllerPlayerIndex1;
        NSLog(@"SHIM CONTROLLER SYNC (%@): active physical controller=\"%@\" category=\"%@\" playerIndex=%ld (total real=%lu)",
              reason, primary.vendorName, primary.productCategory, (long)primary.playerIndex, (unsigned long)real.count);
    } else {
        if (gInputMode != ShimInputModeKeyMouseOnly && !gVirtualControllerConnectedInUnreal) {
            gVirtualControllerConnectedInUnreal = YES;
            NSLog(@"SHIM CONTROLLER SYNC (%@): no physical controller -> connecting Stray Touch Controller (PlayerIndex=0)", reason);
            [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:vgc];
        }
    }
    if (gTouchOverlay) {
        [gTouchOverlay updateForPhysicalControllerState];
    }
}

static void ShimEnsureTouchOverlayOnTop(void) {
    if (!gRootVC || !gRootVC.view) return;
    if (!gTouchOverlay) {
        gTouchOverlay = [[ShimTouchOverlayView alloc] initWithFrame:gRootVC.view.bounds];
        [gRootVC.view addSubview:gTouchOverlay];
    } else if (gTouchOverlay.superview != gRootVC.view) {
        gTouchOverlay.frame = gRootVC.view.bounds;
        [gRootVC.view addSubview:gTouchOverlay];
    } else {
        [gRootVC.view bringSubviewToFront:gTouchOverlay];
    }
    [gTouchOverlay updateForPhysicalControllerState];
}

// MARK: UIKit side (ShimViewController & ShimSceneDelegate)

@interface ShimViewController : UIViewController
@end

static int ShimMacKeyCode(long hid) {
    static const short letters[26] = {0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6};
    static const short digits[10] = {18, 19, 20, 21, 23, 22, 26, 28, 25, 29};
    static const short fkeys[12] = {122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111};
    if (hid >= 4 && hid <= 29) return letters[hid - 4];
    if (hid >= 30 && hid <= 39) return digits[hid - 30];
    if (hid >= 58 && hid <= 69) return fkeys[hid - 58];
    switch (hid) {
        case 40: return 36;  case 41: return 53;  case 42: return 51;  case 43: return 48;  case 44: return 49;
        case 45: return 27;  case 46: return 24;  case 47: return 33;  case 48: return 30;  case 49: return 42;
        case 51: return 41;  case 52: return 39;  case 53: return 50;  case 54: return 43;  case 55: return 47;
        case 56: return 44;  case 57: return 57;  case 74: return 115; case 75: return 116; case 76: return 117;
        case 77: return 119; case 78: return 121; case 79: return 124; case 80: return 123; case 81: return 125;
        case 82: return 126; case 224: return 59; case 225: return 56; case 226: return 58; case 227: return 55;
        case 228: return 62; case 229: return 60; case 230: return 61; case 231: return 54;
    }
    return -1;
}

static NSUInteger ShimMacModifiers(UIKeyModifierFlags f) {
    NSUInteger m = 0;
    if (f & UIKeyModifierAlphaShift) m |= 1 << 16;
    if (f & UIKeyModifierShift) m |= 1 << 17;
    if (f & UIKeyModifierControl) m |= 1 << 18;
    if (f & UIKeyModifierAlternate) m |= 1 << 19;
    if (f & UIKeyModifierCommand) m |= 1 << 20;
    return m;
}

@implementation ShimViewController
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeLeft; }
- (BOOL)shouldAutorotate { return YES; }
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    for (NSWindow *w in gWindows) ShimSyncWindowAndViewGeometry(w, YES);
    ShimEnsureTouchOverlayOnTop();
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for (NSWindow *w in gWindows) ShimSyncWindowAndViewGeometry(w, YES);
    ShimEnsureTouchOverlayOnTop();
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    NSLog(@"SHIM orientation/size transition -> %.0fx%.0f", size.width, size.height);
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        for (NSWindow *w in gWindows) ShimSyncWindowAndViewGeometry(w, YES);
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        for (NSWindow *w in gWindows) ShimSyncWindowAndViewGeometry(w, YES);
    }];
}
- (void)sendPresses:(NSSet<UIPress *> *)presses down:(BOOL)down {
    for (UIPress *press in presses) {
        UIKey *key = press.key;
        if (!key) continue;
        int code = ShimMacKeyCode(key.keyCode);
        if (code < 0) continue;
        NSUInteger before = gModifiers;
        gModifiers = ShimMacModifiers(key.modifierFlags);
        BOOL modifierKey = key.keyCode >= 224 && key.keyCode <= 231;
        NSEvent *e = [NSEvent new];
        e.type = modifierKey ? NSEventTypeFlagsChanged : (down ? NSEventTypeKeyDown : NSEventTypeKeyUp);
        if (modifierKey && before == gModifiers) continue;
        e.keyCode = code;
        NSString *chars = (key.characters && key.characters.length > 0) ? key.characters : @" ";
        e.characters = modifierKey ? @"" : chars;
        e.charactersIgnoringModifiers = modifierKey ? @"" : ((key.charactersIgnoringModifiers && key.charactersIgnoringModifiers.length > 0) ? key.charactersIgnoringModifiers : chars);
        e.modifierFlags = gModifiers;
        e.timestamp = press.timestamp;
        e.locationInWindow = gMouse;
        ShimDispatch(e);
    }
}
- (void)pressesBegan:(NSSet<UIPress *> *)p withEvent:(UIPressesEvent *)e { [self sendPresses:p down:YES]; }
- (void)pressesEnded:(NSSet<UIPress *> *)p withEvent:(UIPressesEvent *)e { [self sendPresses:p down:NO]; }
- (void)pressesCancelled:(NSSet<UIPress *> *)p withEvent:(UIPressesEvent *)e { [self sendPresses:p down:NO]; }
@end

@interface ShimAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation ShimAppDelegate
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskLandscape;
}
@end

@interface ShimSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ShimSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindowScene *ws = (UIWindowScene *)scene;
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
        [ws requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) {
            if (error) NSLog(@"SHIM landscape geometry request error: %@", error);
        }];
    }
    self.window = [[UIWindow alloc] initWithWindowScene:ws];
    gRootVC = [ShimViewController new];
    gRootVC.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = gRootVC;
    [self.window makeKeyAndVisible];
    ShimEnsureTouchOverlayOnTop();
    for (NSWindow *w in gWindows) ShimAttach(w);

    static BOOL launched;
    if (launched) return;
    launched = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ [self finishMacLaunch]; });
}

static void ShimPostApp(NSString *name, SEL delegateSel) {
    NSApplication *app = NSApp;
    NSNotification *n = [NSNotification notificationWithName:name object:app];
    if ([app.delegate respondsToSelector:delegateSel]) ((void (*)(id, SEL, id))objc_msgSend)(app.delegate, delegateSel, n);
    [NSNotificationCenter.defaultCenter postNotification:n];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    NSLog(@"SHIM scene sceneWillResignActive (app state %ld)", (long)UIApplication.sharedApplication.applicationState);
    if (gTouchOverlay) [gTouchOverlay resetAllActiveTouches];
    ShimPostApp(@"NSApplicationWillResignActiveNotification", @selector(applicationWillResignActive:));
    ShimPostApp(@"NSApplicationDidResignActiveNotification", @selector(applicationDidResignActive:));
    ShimWorkspaceActivation(NO);
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    NSLog(@"SHIM scene sceneDidEnterBackground (app state %ld)", (long)UIApplication.sharedApplication.applicationState);
    if (gTouchOverlay) [gTouchOverlay resetAllActiveTouches];
    ShimPostApp(@"NSApplicationWillHideNotification", @selector(applicationWillHide:));
    ShimPostApp(@"NSApplicationDidHideNotification", @selector(applicationDidHide:));
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    NSLog(@"SHIM scene sceneWillEnterForeground (app state %ld)", (long)UIApplication.sharedApplication.applicationState);
    ShimPostApp(@"NSApplicationWillUnhideNotification", @selector(applicationWillUnhide:));
    ShimPostApp(@"NSApplicationDidUnhideNotification", @selector(applicationDidUnhide:));
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    NSLog(@"SHIM scene sceneDidBecomeActive (app state %ld)", (long)UIApplication.sharedApplication.applicationState);
    ShimPostApp(@"NSApplicationWillBecomeActiveNotification", @selector(applicationWillBecomeActive:));
    ShimPostApp(@"NSApplicationDidBecomeActiveNotification", @selector(applicationDidBecomeActive:));
    ShimWorkspaceActivation(YES);
    for (NSWindow *w in gWindows) {
        ShimSyncWindowAndViewGeometry(w, YES);
    }
    ShimUpdateWindowHostViewsVisibility();
    ShimActivateGameWindowNonBlocking(ShimActiveGameWindow(), @"sceneDidBecomeActive");
    ShimEnsureTouchOverlayOnTop();
}

- (void)finishMacLaunch {
    ShimPrepareAutonomousLaunchEnvironment("finishMacLaunch");
    ShimGetVirtualController();

    // Observe physical controller connect/disconnect events to auto-switch between physical controller & touch HUD
    static dispatch_once_t onceControllerObs;
    dispatch_once(&onceControllerObs, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *note) {
            GCController *c = note.object;
            if ([c isKindOfClass:ShimVirtualGCController.class]) return;
            NSLog(@"SHIM PHYSICAL CONTROLLER CONNECTED: vendor=\"%@\" category=\"%@\"", c.vendorName, c.productCategory);
            ShimSyncControllersAndHud(@"PhysicalDidConnect");
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidDisconnectNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification *note) {
            GCController *c = note.object;
            if ([c isKindOfClass:ShimVirtualGCController.class]) return;
            NSLog(@"SHIM PHYSICAL CONTROLLER DISCONNECTED: vendor=\"%@\" category=\"%@\"", c.vendorName, c.productCategory);
            ShimSyncControllersAndHud(@"PhysicalDidDisconnect");
        }];
    });

    NSApplication *app = NSApp;
    NSNotification *will = [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:app];
    NSNotification *did = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app];
    if ([app.delegate respondsToSelector:@selector(applicationWillFinishLaunching:)])
        [app.delegate performSelector:@selector(applicationWillFinishLaunching:) withObject:will];
    [NSNotificationCenter.defaultCenter postNotification:will];
    if ([app.delegate respondsToSelector:@selector(applicationDidFinishLaunching:)])
        [app.delegate performSelector:@selector(applicationDidFinishLaunching:) withObject:did];
    [NSNotificationCenter.defaultCenter postNotification:did];
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        ShimPostApp(@"NSApplicationWillBecomeActiveNotification", @selector(applicationWillBecomeActive:));
        ShimPostApp(@"NSApplicationDidBecomeActiveNotification", @selector(applicationDidBecomeActive:));
        ShimWorkspaceActivation(YES);
        for (NSWindow *w in gWindows) {
            ShimSyncWindowAndViewGeometry(w, YES);
        }
        ShimUpdateWindowHostViewsVisibility();
        ShimActivateGameWindowNonBlocking(ShimActiveGameWindow(), @"finishMacLaunch");
    }

    // Coordinate initial controller state once FAppleControllerInterface is initialized
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ShimSyncControllersAndHud(@"InitialCheck+1.5s");
        NSArray<GCController *> *real = ShimRealControllers();
        if (real.count > 0) {
            if (!gUnrealPolledRealGamepad) {
                GCController *primary = real.firstObject;
                NSLog(@"SHIM announcing single connect for unpolled physical controller: %@", primary.vendorName);
                [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:primary];
            }
        } else if (!gUnrealPolledVirtualGamepad && gInputMode != ShimInputModeKeyMouseOnly) {
            ShimVirtualGCController *vgc = ShimGetVirtualController();
            NSLog(@"SHIM announcing single connect for unpolled virtual controller: %@", vgc.vendorName);
            [NSNotificationCenter.defaultCenter postNotificationName:GCControllerDidConnectNotification object:vgc];
        }
        NSWindow *activeWin = ShimActiveGameWindow();
        if (activeWin) {
            ShimActivateGameWindowNow(activeWin, @"InitialCheck+1.5s");
        }
        ShimEnsureTouchOverlayOnTop();
    });

    CFRunLoopTimerRef t = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent(), 0, 0, 0,
                                                          ^(CFRunLoopTimerRef timer) { ShimYieldToGame(); });
    CFRunLoopAddTimer(CFRunLoopGetMain(), t, kCFRunLoopCommonModes);
    CFRelease(t);
}
@end

// MARK: NSAlert

@interface NSAlert : NSObject
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *informativeText;
@end

@implementation NSAlert
SHIM_RESOLVE
- (id)addButtonWithTitle:(NSString *)title { NSLog(@"SHIM NSAlert button: %@", title); return nil; }
- (NSInteger)runModal {
    NSLog(@"SHIM NSAlert runModal: %@ | %@", self.messageText, self.informativeText);
    return 1000;
}
@end

