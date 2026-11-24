# Current Technical Blockers & Active Investigation (Tests 31 to 41)

> **Status:** November 2026 Baseline  
> **Physical Hardware:** iPhone 17 Pro Max (Apple A19 Pro GPU, iOS 27.x)  
> **Engine State:** `GDynamicRHI = 0x12298af00`, Metal SM5 RHI Active, 3D Level Rendering at 25–33 FPS  

---

## Resolved Blockers (Milestones Passed)

1. **Early Termination During `FEngineLoop::AppInit` (Exit Code 1):**
   - **Resolved in Test 32–33:** Passing `-metalsm5`, populating synthetic `Apple A19 Pro GPU` descriptor via `libShim_IOKit.dylib`, and interposing `MTLStorageModeManaged` to `MTLStorageModeShared` allowed `FMetalDynamicRHI` to initialize completely.
2. **GPU Discovery SIGSEGV `0x28`:**
   - **Resolved in Test 31:** Null dereference in `0x10121a060` eliminated by synthetic IOKit registry.
3. **Texture View Assertion Failures:**
   - **Resolved in Test 35–36:** Interposing `-[MTLTexture newTextureViewWithPixelFormat:]` remapped incompatible depth (`260 -> 252`) and stencil (`260 -> 261`) formats.
4. **Bone Limit Check Abort Hypothesis:**
   - **Refuted in Test 40:** Custom binary probe instrumenting `USkinnedMeshComponent::CreateSceneProxy` recorded section bone counts of 14 vs 256 max limit. Valid `FSkeletalMeshSceneProxy` is successfully instantiated.

---

## Active Current Blockers

### Blocker 1: Protagonist Cat Renders as Dark Silhouette
- **Observed Behavior:** In Test 41 in-game screen captures (42s into gameplay), image forensics confirmed the cat mesh is physically rasterized and occludes background geometry, but appears 100% black.
- **Root Cause Analysis:**
  1. **Subsurface Profile Shading Model (`MSM_SubsurfaceProfile`):** Cat's primary material `MI_CAT_Body_2sidedshading` requires screen-space bilateral blur post-processing (`FPostProcessSubsurface`), which fails or outputs black on iOS Metal. Setting `r.SubsurfaceScattering=0` forces fallback to standard Lambertian diffuse `MSM_DefaultLit`.
  2. **Volumetric Lightmap (VLM) Sampling:** Stray's static-lit levels evaluate indirect lighting for movable dynamic skeletal meshes using VLM. In interior shelter areas, unprobed meshes evaluate to 0.0 lumens.
- **Pending Physical Test:** Test 42 will validate `r.SubsurfaceScattering=0` and exposure bias fallback on device.

### Blocker 2: GFur PRO Procedural Fur Shaders
- **Observed Behavior:** Stray uses the GFur PRO plugin for procedural fur shell rendering. In native code, `UGFurComponent` sets `bHideSkin=1` and `bVisible=0` on the base cat mesh.
- **Root Cause Analysis:** GFur's compute shaders and fin/shell generation do not execute under the current iOS Metal pipeline.
- **Remediation:** Surgical binary patches (`0x102fd67f0` NOP `bHideSkin`, `0x102fd6e44` NOP `cbz w0`, and native Blueprint `0x1008f9134` `mov w1, #1`) bypass GFur suppression and keep the base cat skin active.

### Blocker 3: 3D Main Menu Background
- **Observed Behavior:** The main menu title screen displays virtual touch and UI widgets against a pitch-black background.
- **Investigation:** World rendering pass in menu level is suppressed or occluded before Slate viewport compositing.

### Blocker 4: Desktop Texture Streaming (BC1–BC7)
- **Observed Behavior:** Geometry textures appear low-resolution.
- **Remediation:** Configured `r.TextureStreaming=1`, `r.Streaming.PoolSize=2048`, and `r.Streaming.FullyLoadUsedTextures=1` to force high-detail mips from `pakchunk0_s1-MacNoEditor.pak` to reside in unified memory.
