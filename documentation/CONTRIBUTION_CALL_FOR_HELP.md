# Call for External Expertise & Technical RFC

We invite external graphics, Unreal Engine 4, and Metal developers to help solve the remaining compatibility hurdles.

If you have experience with **Unreal Engine 4.27 RHI**, **Apple Metal rendering pipelines**, or **UIKit/AppKit graphics bridging**, your insights would be invaluable!

---

## Technical Questions Requiring Community Input

### Question 1: Unreal Engine Viewport Target vs `CAMetalLayer`
- **Observed**: In `test33`, Metal dynamic RHI initializes, texture descriptors are created in `Shared` mode, shaders compile, and `[CAMetalDrawable present]` is called at 60 FPS. However, only 2D UI elements appear on screen; 3D world meshes do not render.
- **Specific Question**: In UE4 desktop Metal RHI (`FMetalDynamicRHI`), how does the engine manage the swapchain between offscreen scene render targets (`SceneColor`, `SceneDepthZ`) and the primary window drawable? Is there a post-processing or blit pass that could be skipped or failing silently due to missing desktop pipeline state objects?
- **How to help**: If you know how UE4 binds `CAMetalDrawable` in `FMetalViewport::Present` or how desktop vs mobile composite passes differ, please share your architectural knowledge!

### Question 2: Desktop BC Texture Formats vs Mobile ASTC Decoding
- **Observed**: The shim currently spoofs `supportsFamily:MTLGPUFamilyMac2 -> YES` and `supportsFamily:MTLGPUFamilyApple1..3 -> NO`.
- **Specific Question**: Does an Apple Silicon mobile GPU (e.g., A19 Pro) fully decode desktop BC1-BC7 (DXT) textures natively in hardware when running an iOS app, or does the driver reject specific BC compression formats unless configured through private device capabilities? If texture decoding fails, does UE4 cull the mesh or render a black texture?

### Question 3: Skeletal Mesh & Bone Limitations
- **Observed**: Stray's `Engine.ini` contains `MaxSkinBones=(Default=65536,PerPlatform=(("Mobile",256)))`.
- **Specific Question**: If the engine internally identifies the platform as Mobile (via `TargetPlatform` or runtime OS check), does it truncate vertex streams or skip rendering of `USkeletalMeshComponent` (`m_visual`) when the cat rig exceeds 256 bones? How can we force UE4 to evaluate the Desktop bone limit pipeline at runtime?

### Question 4: Aspect Ratio & Orientation Forwarding
- **Observed**: Rotating the physical iPhone from portrait to landscape stretches the rendered framebuffer instead of triggering a native viewport recalculation.
- **Specific Question**: When AppKit `NSView` bounds change on an emulated window, what notification or selector does Unreal Engine 4 listen to (`windowDidResize:`, `viewDidChangeBackingProperties:`, or custom RHI resize calls) to recalculate its camera projection matrix?

---

## How to Contribute Findings

1. Open a discussion or submit an issue using our structured **Technical Review** issue template.
2. Provide reproducible evidence:
   - Specific Unreal Engine 4.27 source file references and function names.
   - Disassembly offsets or lldb trace methodology.
   - Proposed minimal shim modifications or proof-of-concept code.
3. Do not submit proprietary game assets, executables, or cracked binaries.
