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
