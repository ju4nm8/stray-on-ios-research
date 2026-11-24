# TEST 39 FINAL IMPLEMENTATION HANDOFF FOR CLAUDE HIGH

**Document:** `coordination/TEST39_FINAL_HANDOFF.md`  
**Author:** Antigravity (Implementation Owner)  
**Date:** 2026-11-23  
**Target Hardware:** Physical iPhone 17 Pro Max (`00008150-00026D410C38C01C`, iOS 27.3, Apple A19 Pro GPU, 8 GB Unified Memory)  
**Workspace:** `/Volumes/Disco Juan/Projects/Stray iOS/PortWorkspace/Stray-iOS-From-Scratch`  
**Production App Bundle:** `work/out_icu/Stray.app`  
**Bundle Identifier:** `com.ju4nm8.strayios`  
**Signing Identity:** `Apple Development: juan.andres.medina08@gmail.com (XSA98KJG96)`  

---

## 1. EXACT CURRENT STATE (GROUND TRUTH)

> [!CAUTION]
> **DO NOT MISREPRESENT:** The port is **NOT** visually complete, nor playable, nor visually authentic.
> While launch, PhysX, Metal RHI, autonomous navigation, and touch controls are functional, the visual output remains severely broken.

### Visual Status (Physical Device Ground Truth):
1. **Protagonist Cat:** **NOT VISIBLE**. The 3D model of the cat does not appear in the scene.
2. **Main Menu:** The background scene is **COMPLETELY BLACK**. Only the on-screen touch HUD controls (settings icon top-right, action icons bottom-left) render against a black void.
3. **In-Game 3D Scene:** Level geometry renders as dark/primitive grey-teal structures. Environmental detail, props, foliage, and secondary dynamic actors are missing or visually degraded.
4. **Textures:** Textures appear flat, low-resolution, or black. Full high-resolution mips from `pakchunk0_s1-MacNoEditor.pak` are not streaming into the Metal texture cache.
5. **Lighting & Shadows:** Overexposure was mitigated (+1.6 EV $\rightarrow$ 0.0 EV bias), but there are no dynamic shadows, no indirect lighting/GI bounces, and no authentic post-processing effects.
6. **Controls & Audio:** On-screen virtual gamepad and physical DualShock 4 controller are fully functional. Metal frame pacing runs between 20–35 FPS in the 3D level with ~2.62 GB RAM and `thermal=nominal`.

### Device Evidence Artifacts:
- **Test 39 Menu Screenshot (10s):** [artifacts/screenshots/test39_cat_surgical_visibility_menu.png](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/artifacts/screenshots/test39_cat_surgical_visibility_menu.png) (2868x1320, black background with touch overlay).
- **Test 39 In-Game Screenshot (42s):** [artifacts/screenshots/test39_cat_surgical_visibility_ingame.png](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/artifacts/screenshots/test39_cat_surgical_visibility_ingame.png) (2868x1320, 3D tunnel structure, cat absent).
- **Console Log:** [artifacts/logs/session_20261123/test39_cat_surgical_visibility_console.log](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/artifacts/logs/session_20261123/test39_cat_surgical_visibility_console.log)
- **Watchdog Execution Log:** [artifacts/logs/session_20261123/test39_cat_surgical_visibility_watchdog.log](file:///Volumes/Disco%20Juan/Projects/Stray%20iOS/PortWorkspace/Stray-iOS-From-Scratch/artifacts/logs/session_20261123/test39_cat_surgical_visibility_watchdog.log)

---

## 2. EXACT BINARY STATE & MODIFICATIONS APPLIED

### Binary Under Test:
`work/out_icu/Stray.app/Stray-Mac-Shipping` (Mach-O 64-bit ARM64, 161 MB)

### Recoverable Backups:
- Clean baseline (Test 37): `artifacts/backups/Stray-Mac-Shipping.baseline_test37` (`SHA256: f9f7d2118abecadbecc731dca6cde368f9baf5fcdd284e9fc275f468a2abd5f1`)
- Pre-Test 39 baseline (Test 38): `artifacts/backups/Stray-Mac-Shipping.test38_post_capture` (`SHA256: b18c137d7bb78ca6a6c72294e66087d956c1c2164e61ee959d64d3629e02b507`)

### Active Binary Patches in `Stray-Mac-Shipping`:

| File Offset | Virtual Address | Original Instruction | Current Patched Instruction | Purpose / Effect |
|---|---|---|---|---|
| `0x2fd67f0` | `0x102fd67f0` | `37400289` (`tbnz w9, #0x8, 0x102fd6840`) | `d503201f` (`nop`) | Bypasses `bHideSkin` check in `USkinnedMeshComponent::CreateSceneProxy` to prevent proxy abort when GFur is present. |
| `0x2fd6e44` | `0x102fd6e44` | `34000780` (`cbz w0, 0x102fd6f34`) | `d503201f` (`nop`) | Bypasses `ShouldComponentAddToScene()` abort in `USkinnedMeshComponent::CreateRenderState_Concurrent` so `FSkeletalMeshObjectGPUSkin` is unconditionally instantiated at `[x19, #0x608]`. |
| `0x2fb20c0` | `0x102fb20c0` | `79429808 52808409 0a090108 7100811f 540000e1 f9405808` | `08984279 68005036 00008052 c0035fd6 20008052 c0035fd6` | **Surgical `bHiddenInGame` Filter:** In `USceneComponent::IsVisible()`, returns `0` if `bHiddenInGame=1` (keeps debug/triggers hidden), and returns `1` if `bHiddenInGame=0` (bypasses GFur `bVisible=0` suppression). |
| `0x2fd68c0` | `0x102fd68c0` | `54fffc0c` (`b.gt 0x102fd6840`) | **INTACT** (`54fffc0c`) | Section bone limit check in `USkinnedMeshComponent::CreateSceneProxy`. Kept intact during Test 39 per safety directive. |

### Supporting Shims:
1. `work/out_icu/Stray.app/Frameworks/libShim_AppKit.dylib`:
   - Interposes `-[MTLTexture newTextureViewWithPixelFormat:]` to prevent crashes when requesting incompatible stencil/depth formats (`260 -> 261`, `260 -> 252`).
   - Converts `MTLStorageModeManaged (1) -> Shared (0)` in `MTLTextureDescriptor`.
   - Forces 16:9 aspect fit (`768x432` container, `1536x864` drawable) on iPhone 17 Pro Max.
   - Hides touch overlay when physical controller is polled.
2. `work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib`:
   - Populates synthetic `Apple A19 Pro GPU` descriptor (`vendorId=0x106b`, `model=Apple A19 Pro GPU`, `plugin=AGXMetalG18P`).
3. `work/out_icu/Stray.app/Frameworks/libShim_libSystem.dylib`:
   - Case-insensitive redirect interposer (`open`, `stat`, `access`) for PhysX and cooked PAK assets.

---

## 3. VERIFIED TECHNICAL FINDINGS

### Confirmed Root Causes:
1. **Cat Mesh Render Proxy Abort (`bHideSkin`):**
   - In clean upstream Unreal with GFur PRO, `UGFurComponent` sets `bHideSkin = true` (`bit 8` of `[USkinnedMeshComponent + 0x5fe]`).
   - In `USkinnedMeshComponent::CreateSceneProxy` (`0x102fd67f0`), `tbnz w9, #0x8` unconditionally aborts proxy creation, returning NULL. (Confirmed & NOPed).
2. **Missing `MeshObject` Allocation:**
   - In `USkinnedMeshComponent::CreateRenderState_Concurrent` (`0x102fd6e44`), `cbz w0, 0x102fd6f34` skips allocation of `FSkeletalMeshObjectGPUSkin` if `ShouldComponentAddToScene()` returns 0. Without `MeshObject` at offset `0x608`, subsequent proxy creation fails. (Confirmed & NOPed).
3. **GFur `bVisible` Suppression:**
   - Blueprint `ABP_CatPawn_C__pf1235962618` calls `SetVisibility(false, true)` on `USkinnedMeshComponent` at `0x1008f913c` to hide the base skin under the procedural fur shells.
   - Clean `USceneComponent::IsVisible()` requires `(flags & 0x420) == 0x20` (both `bVisible=1` and `bHiddenInGame=0`). When `bVisible=0`, it returns 0.
   - This causes `USceneComponent::ShouldRender()` to return 0, which makes `UPrimitiveComponent::CreateRenderState_Concurrent` skip `AddPrimitive(this)`.

### Strongly Supported Hypotheses:
1. **The Bone Limit Check at `0x2fd68c0` (`b.gt 0x102fd6840`):**
   - In Test 39, `0x2fd68c0` was kept **INTACT**.
   - In the historical working November build (`B_178_iterate_stray.sh`), `0x2fd68c0` **WAS NOPed** (`0xd503201f`).
   - Disassembly of `CreateSceneProxy`:
     ```arm64
     102fd68b0: bl 0x10311db88 <FGPUBaseSkinVertexFactory::GetMaxGPUSkinBones>
     102fd68bc: cmp w22, w0
     102fd68c0: b.gt 0x102fd6840  <-- ABORTS PROXY IF SECTION BONES > w0
     ```
   - On the iOS Metal SM5 path, if `GetMaxGPUSkinBones()` evaluates the section bones as exceeding the vertex factory limit, `CreateSceneProxy` returns `NULL`. This is the primary remaining candidate for why `SK_Cat` proxy creation aborts.
2. **GFur Shell Pipeline vs Base Mesh:**
   - `UGFurComponent::CreateSceneProxy` (`0x100795894`) creates an `FFurSceneProxy` (`0x100799488`).
   - If GFur's compute shaders or fin/shell geometry passes fail to execute on Metal iOS, and GFur has disabled the base skin proxy, neither fur nor skin renders.
   - Forcing `UGFurComponent::CreateSceneProxy` to return `NULL` (or disabling GFur component registration) will force Unreal to fall back cleanly to the base skeletal mesh `SK_Cat`.
3. **Main Menu Black Background:**
   - The main menu map (`/Game/Maps/Menu/MainMenu` or `Hk_project`) renders a 3D scene behind Slate/UMG widgets.
   - If the main menu camera or world scene is not set to `bHiddenInGame=false`, or if the level streaming manager fails to unhide the menu level, the background remains clear black (`ClearColor=(0,0,0,1)`).
4. **Missing Texture Mips & Muddy Geometry:**
   - `r.TextureStreaming=0` or `r.Streaming.PoolSize=0` prevents streaming high-detail mips from `pakchunk0_s1-MacNoEditor.pak`.
   - Setting `r.Streaming.PoolSize=2048` and `r.TextureStreaming=1` in `Engine.ini` is required to allow the engine to stream mips onto the A19 Pro GPU.

### Ruled-Out Hypotheses:
1. **SIGSEGV / PhysX Instability:** Ruled out. Zero crashes across 60s+ runs.
2. **Memory Leaks / Jetsam OOM:** Ruled out. RAM usage plateaus at 2.62–2.76 GB on an 8 GB device with `thermal=nominal`.
3. **Global `IsVisible` NOP (`mov w0, #1; ret`):** Ruled out as unacceptable. Forcing global visibility causes debug wireframes, frustums, and camera collision shapes to clutter the screen.

---

## 4. CONCRETE IMPLEMENTATION TASKS FOR CLAUDE HIGH (ORDERED BY IMPACT)

### TASK 1: Bypass Bone Limit Check in `USkinnedMeshComponent::CreateSceneProxy`
- **Target File:** `work/out_icu/Stray.app/Stray-Mac-Shipping`
- **Offset:** `0x2fd68c0` (Virtual Address `0x102fd68c0`)
- **Current Instruction:** `54fffc0c` (`b.gt 0x102fd6840`)
- **Action:** Replace with `d503201f` (`nop`).
- **Technical Justification:** Historical script `B_178_iterate_stray.sh` line 20 proves this instruction was patched to NOP in the build where the cat was visible. If the cat rig sections exceed the mobile shader platform bone limit, this branch aborts proxy creation. NOPing it allows `FSkeletalMeshSceneProxy` to be allocated at `0x102fd68c8`.
- **Verification:** Disassemble `0x102fd68b8` to `0x102fd68c8` and confirm `cmp w22, w0; nop; mov w0, #0x220; bl operator new`.

### TASK 2: Force Neutralization of GFur Component Proxy
- **Target File:** `work/out_icu/Stray.app/Stray-Mac-Shipping`
- **Function:** `UGFurComponent::CreateSceneProxy()`
- **Offset:** `0x795894` (Virtual Address `0x100795894`)
- **Current Instruction:** `sub sp, sp, #0x90` (Prologue)
- **Action:** Patch prologue to return NULL immediately: `mov x0, #0; ret` (`0x52800000`, `0xd65f03c0`).
- **Technical Justification:** `UGFurComponent` attempts to render fur shells over `SK_Cat`. On iOS, GFur compute passes either do not dispatch or produce transparent shells. By returning NULL from `UGFurComponent::CreateSceneProxy`, GFur is disabled, ensuring that ONLY the base `FSkeletalMeshSceneProxy` renders without z-fighting or occlusion from empty fur passes.

### TASK 3: Restore Main Menu 3D Scene Background
- **Target File:** `Engine.ini` (Deployed via `AppKit.m` or container copy)
- **Subsystem:** Unreal World / UI Level Loading
- **Current State:** Menu background renders black (`RGBA = 0,0,0`).
- **Action:** 
  1. Inspect `work/out_icu/Stray.app/Mac/Contents/UE4/Hk_project/Config/DefaultEngine.ini` for `EditorStartupMap` and `GameDefaultMap`.
  2. In `Engine.ini`, add:
     ```ini
     [/Script/EngineSettings.GameMapsSettings]
     GameDefaultMap=/Game/Maps/Menu/Menu_Map.Menu_Map
     ```
  3. Ensure `r.DefaultFeature.MotionBlur=0` and `r.PostProcessing.DisableMaterials=0`.
- **Verification:** Menu screenshot shows 3D background geometry instead of solid black.

### TASK 4: Re-enable High-Resolution Texture Streaming
- **Target File:** Device `Engine.ini` (`Library/Preferences/Stray/MacNoEditor/Engine.ini`)
- **Current State:** Textures are blurry, missing, or unstreamed.
- **Action:** Ensure the following CVars are set in `[SystemSettings]`:
  ```ini
  r.TextureStreaming=1
  r.Streaming.PoolSize=2048
  r.Streaming.LimitPoolSizeToVRAM=0
  r.Streaming.HLODStrategy=2
  r.Streaming.MaxNumTexturesToStreamPerFrame=10
  r.Streaming.Boost=1.5
  ```
- **Verification:** Console log confirms `Texture pool allocated: 2048 MB`, and screenshot shows detailed surface normal and albedo maps.

### TASK 5: Restore Authentic Scene Lighting & Shadows
- **Target File:** Device `Engine.ini`
- **Current State:** Lighting is flat, shadows are missing, ambient occlusion is absent.
- **Action:** Configure in `[SystemSettings]`:
  ```ini
  r.DistanceFieldShadowing=0
  r.DistanceFieldAO=0
  r.SSGI.Enable=1
  r.SSGI.Quality=2
  r.ShadowQuality=3
  r.Shadow.CSM.MaxCascades=4
  r.Shadow.MaxResolution=2048
  r.DefaultFeature.AmbientOcclusion=1
  r.AmbientOcclusionLevels=2
  r.EyeAdaptation.ExposureBias=0.0
  DefaultFeatureAutoExposureBias=0.0
  ```
- **Verification:** Dynamic contact shadows appear beneath geometry and scene objects.

---

## 5. IMMEDIATE STARTING POINT FOR CLAUDE HIGH

Claude should execute the following sequence immediately upon opening the session:

1. **Step 1 — Apply Task 1 & Task 2 in `Stray-Mac-Shipping`:**
   - NOP `0x2fd68c0` (`b.gt` bone limit).
   - Patch `0x795894` (`UGFurComponent::CreateSceneProxy`) to `mov x0, #0; ret`.
2. **Step 2 — Re-sign the bundle:**
   ```bash
   SIGN_ID="Apple Development: juan.andres.medina08@gmail.com (XSA98KJG96)"
   ENT="artifacts/backups/entitlements.plist"
   APP="work/out_icu/Stray.app"
   codesign -f -s "$SIGN_ID" --entitlements "$ENT" --timestamp=none "$APP/Stray-Mac-Shipping"
   codesign -f -s "$SIGN_ID" --entitlements "$ENT" --timestamp=none "$APP"
   codesign --verify --deep --strict "$APP"
   ```
3. **Step 3 — Deploy & Run Test 40 via Test Runner:**
   ```bash
   xcrun devicectl device install app --device "00008150-00026D410C38C01C" "$APP"
   tools/run_test.sh 52 test40_cat_mesh_bone_fur_neutralized
   ```
4. **Step 4 — Evaluate Test 40 Screenshots:**
   - Inspect `artifacts/screenshots/test40_cat_mesh_bone_fur_neutralized_ingame.png`.
   - Verify whether the ginger tabby cat model is visible on screen.
