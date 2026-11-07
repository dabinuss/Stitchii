# Fritchii v3 runtime log review — 2026-11-07

This is a **privacy-minimized aggregate analysis** of a user-supplied `eden_log.txt`; the original log (including local usernames, paths and machine-related details) has **not** been uploaded to this public repository. This analysis describes observed facts, not verified root causes.

## Reproduction context
- Running binary: `Lichii Frizti v3 | oot-gather-fix-00ef0ea6cc`. The code branch used for Stitchii development is based on the subsequent `frizti-v3` tag, which is one commit ahead and modifies presentation timing.
- Host: Windows with a multi-core CPU and NVIDIA Vulkan GPU. Exact hardware, user paths and driver metadata have been omitted for privacy. The Vulkan memory-budget report is below the physical card capacity; that distinction matters for cache-pressure analysis.
- Two game boots in the same process, with **different configurations**:
  - Boot 1 at ~9s: `oot_30fps=false`, `frame_gen=false`, Immediate VSync.
  - Boot 2 at ~256s: `oot_30fps=true`, `frame_gen=true`, later switches to Mailbox and changes frame-pacing options. **Do not A/B compare their FPS without normalizing these settings.**
- Shader cache was imported from a version-53 cache into a Frizti version-52 cache at boot. First boot reports 1,320 cached pipelines; second reports 1,387.

## Measured abnormalities
| Signal | Log evidence | Interpretation |
| --- | --- | --- |
| Slow frame pacing | 600-present window: mean 64,205 µs and max 5,143,538 µs; 36 frames >100 ms | Real stutter confirmed. Some windows report 53–67 ms of game-frame time even when runtime shader builds are sparse. |
| Runtime shader translation | Seven reporting windows: 155 pipelines, totaling ~1,682.9 ms GPU-thread time; examples 47 pipelines / 659.7 ms and 41 / 505.6 ms | Clearly contributes to stutter, but insufficient alone to explain sustained ~15–20 FPS. |
| Invalid texture descriptors | 99 `texture format=0` assertions, 30 `index <= tic_limit` assertions and 220 `Uncached read texture pixel format` compilation errors | High-priority correctness and resource-binding hypothesis; failures happen both at preloading and during gameplay. |
| Compute failures | 8 `Uncached read texture type` compute pipeline failures; additional graphics failures | A missing/invalid cached texture descriptor prevents some pipelines from building. Avoid treating this as normal cache warming. |
| Device-memory reads | 16 `Unmapped Device ReadBlock` errors clustered around 73.8s | Investigate guest-memory address mapping/synchronization separately from shader compile. |
| Fastmem | Boot 1 fails to allocate 14,336 MiB backing memory: `Platform can support fastmem, but can't create it`. Not reproduced in boot 2 in the same log. | Potential first-boot CPU/host memory performance issue; not proof of all stutter. |
| Missing draws | `Draw skipped (no pipeline)` and `Async shaders: ... pipeline lookups skipped` | Some effects may be absent while pipelines compile or fail. |
| No observed eviction | **No** `Evicted ... graphics pipelines` and **no** `Background pipelines done` records in the provided log | The previous prebuild-thread / eviction hypotheses have **no direct confirmation** for this run. |
| GPU fence | The aggregate `nx2:vi2` reports 0 µs mean blocked on GPU fence | The sampled VI fence is unlikely to be the dominating wait; other GPU/CPU workloads remain possible. |
| Texture retention capped | Repeated `expected 4352 MiB, critical 5120 MiB` throughout the log | The 5 GiB hard cap overrides driver-budget thresholds even on large GPUs; replicated stuttering effect is reported in [Eglantine #498](https://github.com/Djihads80/Eglantine/issues/498). |

## Priority order for the next work
1. **Correctness diagnostics for shader texture descriptors**: first rule out cross-fork cache incompatibility by using the new isolated Stitchii cache. Then correlate remaining failing graphics pipelines to their stage shader hashes and origin (preload vs runtime). This motivated the low-risk graphics-pipeline exception log added in Stitchii. For zero-format TIC detail, use the existing opt-in `EDEN_NX2_RENDER_TRACE=1` instrumentation in `shader_environment.cpp`; it logs program, stage, handle, index, limit, descriptor address, mapped status, and raw descriptor (first 64). For frame-time profiling use `EDEN_NX2_GPU_PROFILE=1` in a separate short run. Avoid both simultaneously for comparable baseline performance.
2. **Investigate Fastmem first boot**: check Windows memory-commit/virtual-memory reservation when the 14 GiB failure happens, and whether a consistent later boot makes it succeed.
3. **Correlate presentation and GPU workload**: see existing `EDEN_DKB_FRAME_TRACE=1` and GPU profiling in short controlled runs. GPU/CPU scheduling and ASTC decoding should be examined, without interpreting the elapsed intervals of the aggregate ASTC decoder counter as per-decode latency.
4. **Test cached-pipeline compatibility**, with a backup, by comparing a cold cache to the same warmed cache. Do not erase users' cache as a 'fix'; record the cache version and failure counts.
5. **Performance patches already prepared** include a budget-aware texture cache threshold and fork-isolated caches. They are not compiled or benchmarked. Old background-prebuild and eviction tweaks remain hypotheses. In this log, no background-prebuild completion and no pipeline eviction were observed. Consequently, those two tweaks may have little effect on this precise workload.

## Baseline experiment for later (requires user permission to build)
- Start from the same saved game, settings, display refresh and driver. For actual base FPS, disable frame generation and control `oot_30fps` explicitly.
- Compare a warmed Fritchii v3 run to Stitchii with the same shader-cache state.
- Collect `Runtime pipelines in the last 10 s`, the new hash-aware `Graphics pipeline compilation failed` logs, the texture-cache budget/eviction counters, and frame-time P50/P95/P99.
- Do not claim a fix without a compiled binary and a reproduction on the same scene.

No compiled/tested binary exists for this branch; all edits remain source-only until the owner authorizes a build.
