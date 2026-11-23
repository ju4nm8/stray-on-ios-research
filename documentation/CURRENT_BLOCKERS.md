# Current Technical Blockers & Device State

**Document Status:** Grounded Physical Device Verification  
**Device:** iPhone 17 Pro Max (Apple Silicon A19 Pro GPU, iOS 27.3)  
**Latest Verification Date:** 2026-11-23

---

## 1. Verified Device Observations (Strict Facts)

The following observations have been verified directly on physical hardware:

1. **Successful Boot & Stability:**
   - The converted application launches successfully on a physical iPhone 17 Pro Max running iOS 27.3.
   - The application does not crash on launch; it remains running continuously under supervision.
   - The latest reported exit code 9 was caused by the user manually closing the application, not by a crash or watchdog abort.
2. **UI & Input:**
   - 2D user interface elements, menus, and text overlays are visible on screen.
   - A connected PlayStation DualShock 4 controller is recognized by the game controller subsystem.
3. **Orientation & Aspect Ratio:**
   - The application initially appears in portrait orientation.
   - Rotating the device to landscape causes severe image stretching and aspect ratio distortion.
4. **3D World & Scene Rendering Status:**
   - **The Stray title/menu 3D scene does NOT visibly render its cat character, 3D logo, or expected background geometry.**
   - **Starting the game does NOT produce a visibly rendered 3D world.**
   - Screen displays background UI elements or black/dark frames where 3D geometry should appear.
5. **Metal Subsystem Observations:**
   - Metal-related activity, render encoders, drawable presentation, and completed command buffers have been observed in logs and traces.
   - **Critical note:** These Metal command buffer completions and presentation events do NOT prove successful 3D scene rendering. They merely demonstrate that the presentation pipeline is executing present calls for the render targets.

---

## 2. Technical Breakdown of Open Blockers

### Blocker 1: Missing 3D Scene Geometry (Invisible World & Cat)

- **Observed Behavior:** The display pipeline presents frames, but 3D meshes (cat skeletal mesh `m_visual`, world static meshes, lighting passes) are not visibly rendered to the active viewport.
- **Log-Derived Evidence:**
  - `FMetalDynamicRHI` completes initialization (`featLevel=3 maxShaderPlatform=16`).
  - Shaders compile via `newLibraryWithSource` and `newLibraryWithData`.
  - Texture creation succeeds with `MTLStorageModeShared (0)`.
- **Active Hypotheses:**
  - *Hypothesis 1A (Render Target / Viewport Binding):* Unreal Engine's viewport manager may be rendering 3D scene passes into an offscreen render target or texture that is not being blitted/composited into the primary `CAMetalLayer` or `MTKView`.
  - *Hypothesis 1B (Camera ViewTarget & PCOwner):* During initialization, `AHKPlayerCameraManager` may be unattached or pointing to an invalid `ViewTarget`, resulting in camera positioning outside the scene bounds (e.g., origin `(0,0,0)`).
  - *Hypothesis 1C (Mobile Bone Limit Clamping):* `Engine.ini` specifies `MaxSkinBones=(Default=65536,PerPlatform=(("Mobile",256)))`. If UE4 treats the runtime environment as Mobile, skeletal meshes exceeding 256 bones may be culled or rejected by vertex shaders.
  - *Hypothesis 1D (Mesh Hidden Flags):* In Unreal blueprints (`BP_CatPawn_C`), specific flags such as `HiddenInGameplay` or LOD culling parameters may be toggled.

### Blocker 2: Viewport Aspect Ratio & Rotation Distortion

- **Observed Behavior:** The application boots in portrait mode despite `UIInterfaceOrientationLandscape` specified in `Info.plist`. When rotated, the canvas stretches non-uniformly.
- **Root Cause:** AppKit window metrics (`NSWindow`, `NSScreen`, `NSRect`) map to UIKit `UIWindow` and `UIScreen`. When orientation changes occur, `ShimSaveViewportMetricsToDefaults` and the AppKit view hierarchy must resize the backing `CAMetalDrawable` and update Unreal Engine's `FSceneView` projection matrices (`ResX`, `ResY`, safe area insets).
- **Status:** Requires proper orientation change event forwarding from `UIViewController` to AppKit window listeners.

### Blocker 3: Touch Interface & Virtual Controller

- **Observed Behavior:** Gamepad input (DualShock 4) is detected, but there is no native on-screen touch overlay for gameplay interaction without an external controller.
- **Status:** Virtual on-screen touch joystick and action button overlay (`ShimTouchOverlayView`) recovered from earlier prototypes needs verification and integration.

### Blocker 4: Audio Subsystem

- **Observed Behavior:** No game audio has been verified on device.
- **Log Evidence:** macOS `AudioUnit` and CoreAudio desktop graphs require translation to iOS `AVAudioSession` and mobile audio endpoints.
- **Status:** Investigating audio session category setup and CoreAudio output routing.

---

## 3. Separation of Knowledge

To maintain absolute scientific accuracy, we classify all claims into five tiers:

| Tier | Category | Verified Items |
|---|---|---|
| **Tier 1** | **Verified On-Device Observations** | Launch without crash; menus/UI visible; DualShock 4 connected; portrait orientation on boot; landscape stretching; **3D scene/cat NOT visible**; manual close exit code 9. |
| **Tier 2** | **Log-Derived Evidence** | ICU data directory discovery resolved; case-sensitivity hook functioning; IOKit synthetic GPU initialized; Metal RHI initialized; storageMode managed->shared; shader compilation OK. |
| **Tier 3** | **Static Analysis** | Mach-O 12.0 ARM64 load commands; 109 missing framework symbols; 3,463 ICU entries in pakchunk0; `Engine.ini` Mobile bone limit=256. |
| **Tier 4** | **Unverified Hypotheses** | Offscreen render target compositing failure; camera frustum clipping; bone limit culling; blueprint `HiddenInGameplay` flag. |
| **Tier 5** | **Planned Work** | Metal frame capture analysis; viewport matrix update hooks; touch overlay integration; AVAudioSession shims. |
