# Test 41 In-Game Capture — Silhouette & Shading Forensics

## Executive Summary

In Test 41, the test suite captured a 2868x1320 native screenshot at $T=42\text{s}$ during gameplay on the iPhone 17 Pro Max (`test41_ingame.png`).

A common initial observation was that "the cat does not appear." However, mathematical image analysis (histogram stretching, contrast elevation, and bounding-box zoom) revealed a critical discovery:

> **The cat protagonist IS physically rasterized into the Metal frame buffer!**
> It appears as a dark silhouette standing directly in front of the tunnel wall and the right-hand pipe/valve assembly.

This refutes the theory that skeletal mesh geometry is missing from the render pipeline. Instead, the problem is **shading, lighting, and material evaluation**.

---

## 1. Pixel Forensics & Spatial Coordinates

In the 2868x1320 framebuffer:
- **Cat Position:** Bounding box $[X: 1850 \dots 2200, Y: 700 \dots 1050]$.
- **Physical Occlusion:** The silhouette clearly occludes the grey-teal pipes and circular valve handles behind it.
- **Geometric Features Identified:**
  - Distinct pointed cat ears (with faint specular highlight along the left ear rim).
  - Curved feline skull and muzzle profile.
  - Back arch and shoulder blade curvature.
  - Front paws and lower chest silhouette.

Because the silhouette cleanly occludes the background 3D static geometry, we know:
1. `FSkeletalMeshSceneProxy` is properly registered in the `FScene`.
2. Vertex transformation via `TGPUSkinVertexFactory` executes on the Apple A19 Pro GPU.
3. Depth buffer writes (`EarlyZPass`) and rasterization occur successfully.

---

## 2. Why Does the Cat Render as a Pitch-Black Silhouette?

Our reverse engineering of `pakchunk0-MacNoEditor.pak` and Unreal Engine 4's deferred shading pipeline on Metal SM5 isolated the following three root causes:

### A. Subsurface Profile Shading Model (`MSM_SubsurfaceProfile`)
- Stray's cat protagonist uses the material `MI_CAT_Body_2sidedshading` (parented to `M_Cat_Master`).
- The material shading model is `MSM_SubsurfaceProfile` (`ShadingModel = 5`), referencing subsurface profile asset `/Game/Character/Cat/Material/SSS_profil_cat`.
- In UE4's deferred renderer, materials using `MSM_SubsurfaceProfile` write:
  - BaseColor and Subsurface profile ID into GBuffer B and GBuffer C.
  - Diffuse lighting is accumulated into the SceneColor buffer *without* immediate surface scattering.
  - A dedicated screen-space post-processing pass (`FPostProcessSubsurface`) performs a bilateral blur using a subsurface profile kernel to compute the scattered radiance.
- If the screen-space subsurface pass fails to execute or is disabled on iOS Metal, the mesh either:
  1. Renders completely unlit black.
  2. Falls back to default lit diffuse only if `r.SubsurfaceScattering=0` is explicitly configured.

### B. Dynamic Movable Skeletal Mesh in Static-Baked Lighting
- Stray's opening chapter (`Zone01_Intro`) uses static baked lightmaps (`r.AllowStaticLighting=True`).
- Static geometry receives precomputed lightmaps stored in static texture packages.
- Dynamic movable skeletal meshes (such as the cat pawn) cannot use static lightmaps. Instead, Unreal Engine samples the **Volumetric Lightmap (VLM)** (`PrecomputedVolumetricLightmapAllocation`).
- In interior shelter areas without direct directional sunlight, if Volumetric Lightmap samples fail to stream or evaluate on iOS Metal, the indirect diffuse lighting contribution evaluates to **0.0 lumens** ($0, 0, 0$), rendering the mesh pitch-black.

### C. Texture Mips & DXT Compression
- The primary diffuse texture `CAT_Body_D` is a 1024x1024 DXT1 (BC1) texture.
- The highest 4 mip levels reside in `CAT_Body_D.ubulk`.
- If texture streaming is starved or fails to stream `.ubulk` data over the virtual filesystem, the engine falls back to the lowest 16x16 or 32x32 mip, or a placeholder black texture.

---

## 3. Recommended Remediation for Future Tests

1. **Force Subsurface Scattering Fallback:**
   Add to `Engine.ini` under `[SystemSettings]`:
   ```ini
   r.SubsurfaceScattering=0
   ```
   *Effect:* Forces UE4 to fall back from `MSM_SubsurfaceProfile` to standard Lambertian `MSM_DefaultLit`, allowing BaseColor to render directly without requiring screen-space bilateral blur passes.

2. **Force Texture Mip Streaming:**
   Add to `Engine.ini`:
   ```ini
   r.TextureStreaming=1
   r.Streaming.PoolSize=2048
   r.Streaming.FullyLoadUsedTextures=1
   ```
   *Effect:* Forces all active materials to immediately resident-load high-resolution mips rather than waiting for streaming distance heuristics.

3. **Provide Ambient Lighting Fallback:**
   Ensure `r.DefaultFeature.AutoExposure=1` with non-zero exposure bias (`1.6 EV`) or inject an ambient cube/skylight term so unprobed dynamic actors are visible in dark tunnels.
