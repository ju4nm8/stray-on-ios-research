# [Technical / Reverse Engineering] Porting Stray (macOS ARM64 / UE4 4.27) to iOS — Metal SM5 RHI, 3D Geometry Rendering & The Cat Protagonist Shading Brick Wall

**TL;DR:** We have gotten the un-recompiled ARM64 macOS binary of **Stray** (Unreal Engine 4.27) running on a physical iPhone 17 Pro Max using userspace compatibility shims (`AppKit` $\rightarrow$ `UIKit`, synthetic `IOKit` GPU registration, POSIX VFS redirects). The game boots, initializes a desktop-class Metal SM5 RHI, loads PhysX, streams 2.65 GB of level data, and renders in-game 3D world geometry at **25–33 FPS** with working touch and DualShock 4 controls. 

**However, the port is NOT yet playable:** The protagonist cat currently renders as a pitch-black silhouette, procedural fur (GFur) is missing, and the 3D main menu background is black. We are sharing our reverse-engineering findings and calling for help from UE4 / Metal graphics experts!

---

### Disclaimer & Community Rules

> [!IMPORTANT]
> **No Game Distribution / 100% Legal Research:** We do NOT distribute game executables, `.pak` archives, 3D models, textures, or copyrighted assets. All research is conducted by modifying binary headers and injecting userspace shims on legally owned software. The project repository is purely open-source shims and technical documentation.

---

### What Actually Works Today on Physical Hardware

- **Device:** iPhone 17 Pro Max (Apple A19 Pro GPU, iOS 27.x, 8 GB RAM).
- **Binary:** Original macOS Mach-O binary (`Stray-Mac-Shipping`, 161 MB) adapted to target `IOS` via `vtool`.
- **RHI Status:** `GDynamicRHI` is alive! Running under `SF_METAL_SM5` (Feature Level SM5).
- **In-Game Rendering:** 3D environment geometry (tunnel walls, metal pipes, valves, ventilation ducts) renders to the display in real-time.
- **Performance:** 25–33 FPS sustained in the 3D level; 60 FPS in Slate UI menus. Memory reaches 2.65 GB RAM with nominal device thermals.
- **Controls & Audio:** Virtual on-screen gamepad overlay works; connected DualShock 4 controllers auto-hide the touch HUD and take control smoothly.

---

### The Current Brick Wall: Why is the Cat a Black Silhouette?

For a long time, the cat protagonist didn't appear at all. Many assumed it was hitting mobile bone limits (e.g. `FGPUBaseSkinVertexFactory` aborting if bone count exceeded a limit).

We injected a custom binary probe into a zero-filled code cave to trace `USkinnedMeshComponent::CreateSceneProxy`:
- **The Bone Limit Check is innocent:** The section bone count is ~14 bones vs a limit of 256. The proxy creates successfully!
- **Pixel Forensics on In-Game Captures:** When analyzing our native 2868x1320 in-game screen capture, contrast enhancement revealed that **the cat mesh IS physically rasterized into the framebuffer!** It cleanly occludes the background pipes, valves, and geometry. Pointed ears, arch of the back, and paws are clearly present.

**So why is the cat pitch-black?**
1. **Subsurface Profile Shading Model (`MSM_SubsurfaceProfile`):** Stray's cat material uses UE4's subsurface profile. In deferred rendering, this requires a screen-space bilateral blur post-processing pass (`FPostProcessSubsurface`). On iOS Metal, this post-processing pass seems to fail or discard radiance.
2. **Volumetric Lightmaps (VLM):** Stray's intro level uses precomputed baked static lightmaps. Static geometry gets lightmaps, but dynamic skeletal meshes rely on Volumetric Lightmap interpolation. In interior tunnels without direct directional sunlight, unprobed dynamic meshes receive 0.0 lumens of ambient light.
3. **GFur PRO Plugin:** Stray relies on GFur PRO for procedural fur shell rendering. In native code, the plugin hides the base skin mesh (`bHideSkin=1`, `bVisible=0`) expecting fur shells to cover it. On iOS Metal, GFur's compute shaders don't execute, so neither fur nor skin renders without surgical binary patches.

---

### Questions for UE4 & Metal Graphics Programmers

If you have experience with Unreal Engine 4's deferred renderer, Metal SM5 shaders, or material pipelines, we'd love your insight:

1. **How to cleanly force UE4 4.27 to evaluate `MSM_SubsurfaceProfile` as standard `MSM_DefaultLit` on a cooked binary?** Does `r.SubsurfaceScattering=0` in `Engine.ini` fall back to diffuse BaseColor, or does it leave subsurface materials unlit?
2. **Why might Volumetric Lightmaps (VLM) return zero indirect lighting for dynamic skeletal meshes** while static geometry lightmaps render properly on Metal? Are there console variables or buffer limits we should look into?
3. **Handling Desktop BC1–BC7 Compression on Apple Silicon iOS:** Any known caveats when sampling macOS BC textures through Metal texture views on iOS?

---

### Repository & Technical Diagnostics

All research documents, binary disassembly, sanitized logs, and shim sources are available on GitHub:
👉 **Repository:** [https://github.com/ju4nm8/stray-on-ios-research](https://github.com/ju4nm8/stray-on-ios-research)
- Full technical breakdown: `community/REDDIT_TECHNICAL_HELP.md`
- Diagnostic logs and traces: `community/diagnostics/`
- Compatibility shims: `source/shims/`

Any suggestions, ideas, or pointers from the community are warmly welcome!
