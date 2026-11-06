# Metal compatibility: macOS Managed storage and GPU-family handling

I document two separate Metal compatibility investigations here: the original `MTLStorageModeManaged` failure and a later GPU-family/texture-view issue. I do not treat either workaround as universally correct for every resource type or game.

## Failure 1 — Managed storage on iOS

During Phase F3, Unreal attempted to create a 3D texture while initializing system textures. The descriptor used `MTLStorageModeManaged` (numeric value 1), and the iPhone rejected that storage mode in `validateWithDevice:`. The validation message listed Shared (0), Private (2) and Memoryless (3) as accepted modes.

## Why my first hooks did not solve it

My earlier hooks targeted abstract descriptor types. Metal used concrete runtime implementations such as `MTLTextureDescriptorInternal`, and Unreal's mtlpp wrapper cached method implementations. I therefore had to intercept the concrete runtime classes used by the observed calls.

## Phase-G adaptation

I added targeted hooks for concrete texture and heap descriptor classes, device resource creation and relevant buffer/blit operations. For the requests I observed using Managed storage, the shim translated the mode to Shared while preserving other storage modes.

The Phase-G log confirms Managed-to-Shared conversions and calls to a no-op `synchronizeTexture` path, followed by continued rendering and the initial Stray interface.

## Failure 2 — GPU-family selection and texture views

In a later Run 3 attempt, UE4 entered a fatal-error loop after Metal rejected a texture view. The source texture was reported as `RGBA8Unorm_sRGB`, while the requested view format was `R8Unorm`. I traced the investigation to UE4's `ToSRGBFormat` path and the shim's `supportsFamily:` interception.

I had tested broad Apple GPU-family suppression and forced Mac-family responses. That approach changed UE4's format-selection behavior and was not safe to treat as a proven fix.

I then revised `ShimSupportsFamily`: I stopped force-claiming `MTLGPUFamilyMac1`, explicitly claimed `MTLGPUFamilyMac2` and allowed the real Metal implementation to answer other GPU-family queries. I compiled, signed and installed the revised `libShim_AppKit.dylib` before Run 4. Runs 4–6 progressed into the level without the same texture-view fatal error appearing in the supplied log excerpts.

This is consistent with the revision mitigating that specific fatal path, but I have not run a controlled A/B test. It does not prove that every texture format or GPU-family feature check is correct.

## Important limitations

- Managed and Shared are not universally interchangeable across every resource usage pattern or platform.
- My storage-mode result only demonstrates that the observed initialization/rendering path progressed with these adaptations.
- I have not proven correctness for all CPU/GPU synchronization, resource heaps, readbacks, streaming or later gameplay workloads.
- I keep the hooks narrowly scoped; I do not force every texture or buffer into Shared.
- I keep the storage-mode adaptation separate from the GPU-family/texture-view adaptation because they address different observed failures.

## Current state

The Phase-G run no longer showed the earlier `invalid storageMode (1)` validation failure. The revised GPU-family hook was installed before Run 4, and the same texture-view fatal error does not appear in the supplied Run 4–6 excerpts. I still need broader gameplay and long-duration tests before claiming that Metal compatibility is complete.