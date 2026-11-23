# Metal Compatibility & Graphics Architecture

This document describes the Metal graphics runtime requirements, compatibility shims, and architectural differences between macOS and iOS when running the Unreal Engine 4 Metal RHI (`FMetalDynamicRHI`).

---

## 1. Storage Mode Translation: Managed to Shared

In the macOS Metal runtime, applications can allocate resources with `MTLStorageModeManaged` (mode 1), where the driver manages synchronization between host (CPU) and discrete GPU memory.

On iOS (Apple Silicon unified memory architecture), `MTLStorageModeManaged` does not exist:
- Permitted storage modes: `MTLStorageModeShared` (0), `MTLStorageModePrivate` (2), and `MTLStorageModeMemoryless` (3).
- Any attempt to create a buffer or texture with `storageMode == 1` causes an immediate validation assertion failure in `validateWithDevice:`.

### Shim Interception
The compatibility shim intercepts concrete descriptor classes (`MTLTextureDescriptorInternal`, `MTLBufferDescriptor`) at runtime:
```objc
if (desc.storageMode == MTLStorageModeManaged) {
    desc.storageMode = MTLStorageModeShared;
}
```
Any subsequent calls to `synchronizeResource:` or `synchronizeTexture:` are handled as no-ops by the blit command encoder wrapper.

---

## 2. GPU Family Queries & Feature Levels

Unreal Engine's Metal RHI checks device capabilities using `[MTLDevice supportsFamily:]`.

### GPU Family Differences
- **macOS Metal:** Queries `MTLGPUFamilyMac1` (Apple silicon & AMD GPUs) and `MTLGPUFamilyMac2`.
- **iOS Metal:** Queries `MTLGPUFamilyApple1` through `MTLGPUFamilyApple9`.

When the macOS Unreal binary runs on iOS, it expects Mac family indicators. If the device does not respond affirmatively to Mac queries or if broad family suppression is improperly configured, Unreal's format selection logic may choose unsupported texture view combinations (such as attempting an `R8Unorm` view of an `RGBA8Unorm_sRGB` parent texture).

The current shim implementation explicitly affirms `MTLGPUFamilyMac2` while forwarding underlying queries to the actual physical Apple GPU.

---

## 3. Shader Platform Selection (`SF_METAL_SM5`)

Unreal Engine 4's cooked shaders for Stray are compiled for **Shader Model 5 (`SF_METAL_SM5`)**:
- Engine internal enum: `SP_METAL_SM5 = 16`.
- Cache file: `GlobalShaderCache-SF_METAL_SM5.bin` (26,945,525 bytes, SHA-256 `d106cd781eff6be8c31a634495e94ad7b7ac2d04f6d1e6b142b61992b0a2a340`).

If `PlatformCreateDynamicRHI` receives feature level fallback `4` (due to missing CLI parameters or unparsed ini tables), the engine defaults to `SP_METAL_MAC_ES3_1 = 18` (`"SF_METAL"`). 

Because the game's PAK only contains cooked shaders for `SF_METAL_SM5`, the mismatch triggers `LowLevelFatalErrorHandler`:
```text
Shader platform: SF_METAL was not cooked! Please enable this shader platform in the project's target settings.
```
Injecting `-metalsm5` into the initial command line forces the RHI feature level to `SM5`, selecting platform 16 and properly matching the cooked shader cache.

---

## 4. Current Graphics Status

| Component | Status | Details |
|---|---|---|
| **Storage Mode Translation** | Implemented | Managed -> Shared translation operational. |
| **GPU Family Spoofing** | Implemented | Mac2 affirmed; hardware queries forwarded. |
| **RHI Creation** | In Progress | Active debugging to ensure `GDynamicRHI` instantiates cleanly. |
| **Global Shader Cache** | Staged | Byte-identical loose cache placed in `Mac/Contents/UE4/Engine/`. |
| **Viewport Presentation** | Not Started | `CAMetalLayer` binding pending successful RHI initialization. |
