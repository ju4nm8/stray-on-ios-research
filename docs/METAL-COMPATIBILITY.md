# Metal compatibility: macOS Managed storage on iOS

## Observed failure

During phase F3, Unreal attempted to create a 3D texture while initializing system textures. The descriptor was assigned `MTLStorageModeManaged` (numeric value 1). The device rejected this mode in `validateWithDevice:`. The observed validation message listed Shared (0), Private (2), and Memoryless (3) as accepted modes.

## Why the first hooks did not solve it

The earlier hooks targeted abstract descriptor types. Metal uses concrete runtime implementations such as `MTLTextureDescriptorInternal`, and Unreal's mtlpp wrapper caches method implementations. Intercepting the concrete runtime class was necessary for the calls observed in this build.

## Phase-G adaptation

The shim added targeted hooks for concrete texture and heap descriptor classes, device resource creation and relevant buffer/blit operations. Requests whose storage mode is Managed were translated to Shared while preserving other storage modes.

The phase-G log confirms texture conversions and calls to a no-op `synchronizeTexture` path, followed by continued rendering and initial game UI.

## Important caveat

Managed and Shared are not universally interchangeable across all resource usage patterns or platforms. This result only demonstrates that the observed initialization/rendering path progressed with these adaptations. It does not prove that all CPU/GPU synchronization, resource heaps, readbacks, streaming or later gameplay workloads are correct. Do not broadly force every texture or buffer into Shared.

## Current state

The phase-G run no longer shows the earlier `invalid storageMode (1)` validation failure. More extensive gameplay and long-duration tests are required.

## GPU-family and texture-view follow-up

A later Run 3 attempt ended in a UE4 fatal error after a Metal texture-view validation failure: the source texture was reported as `RGBA8Unorm_sRGB`, while the requested view was `R8Unorm`. The investigation traced the call path to UE4's `ToSRGBFormat` logic and the shim's `supportsFamily:` interception. Earlier experiments that suppressed broad Apple GPU-family ranges and forced Mac-family responses changed UE4's format-selection path and were not safe to treat as a proven fix.

The shim was then revised: it stopped force-claiming `MTLGPUFamilyMac1`, explicitly claimed `MTLGPUFamilyMac2`, and allowed the real Metal implementation to answer other family queries. The revised `libShim_AppKit.dylib` was compiled, signed, and installed on the iPhone before Run 4. Runs 4–6 subsequently progressed into the level without the same texture-view fatal error appearing in the supplied excerpts.

This is encouraging evidence that the revised family reporting mitigated the specific fatal path, but the transcript does not show a controlled A/B test, and it does not prove all texture formats or GPU-family feature checks are correct. Keep this hook narrowly scoped and validate additional texture/view formats before generalizing the result.

This issue is distinct from the earlier `MTLStorageModeManaged` → `Shared` adaptation. Both compatibility changes are required in the current observed path, but their correctness across all gameplay workloads remains unproven.