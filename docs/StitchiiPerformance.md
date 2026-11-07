# Stitchii performance workbench

Status: **source changes only; NOT COMPILED and NOT BENCHMARKED**.
Base: Frizti/Fritchii tag `frizti-v3` (`72e5ad6c22ea5b159b44a184d4dea6b669df0ede`).
Development branch: `stitchii/stutterfix`. The original `nx2` branch is untouched.

## Motivation

Long, repeated frame-time stalls can come from multiple, distinct causes:
* Translation and SPIR-V emission still run partly on the emulated GPU thread when a pipeline is first encountered.
* Cached-but-not-preloaded pipelines are rebuilt while the game is running.
* Compiling thousands of historical graphics pipelines in the background can compete for CPU time and Vulkan-driver resources.
* Writing the list of recently used pipelines synchronously on the GPU thread can interrupt rendering.
* Waiting on unfinished pipelines can block frames even with asynchronous shaders enabled.

**The existing runtime-pipeline telemetry is the source of truth.** These changes are hypotheses until a controlled A/B game benchmark verifies them. This fork does not promise 60 FPS.

## Changes prepared

1. **Less CPU contention on prebuild:** the default `EDEN_NX2_BACKGROUND_PIPELINE_THREADS` is now 1–2 threads, instead of 1–6. The explicit environment override (1–16) is unchanged.
2. **Bounded prebuild backlog:** retain at most the 2,048 most recent cached graphics pipelines for background prebuilding. Older entries remain in the persistent cache and are built when needed, but no longer occupy background workers and memory for the whole play session. Override with `EDEN_NX2_BACKGROUND_PIPELINE_LIMIT` (0–32768). A value of 0 disables the prebuild backlog.
3. **Nonblocking usage-history file writes:** snapshot recently used pipeline keys on the GPU thread, queue disk writing to the existing serialization worker; keep the final shutdown write synchronous after draining queued work. The normal periodic checkpoint interval is 30 seconds (15 seconds when the existing pipeline-retention performance option is active). This reduces loss of usage history across unexpectedly short sessions.
4. **Lower runtime telemetry overhead:** compute the detailed shader-hash text for expensive runtime pipelines only when the existing profiler actually emits a per-pipeline log. Ten-second aggregate telemetry remains active.
5. **Isolated Stitchii caches:** shader-pipeline, used-pipeline and Vulkan driver-cache files have separate `stitchii` names. Do not import old Lichii/Fritchii cache records: the supplied runtime log showed `Uncached read texture pixel format` 220 times after a cross-fork import. The GUI cache deletion commands target the new names and remove the used-pipeline history with the shader cache. **The first Stitchii boot will build a fresh cache**.
6. **Large-VRAM texture retention:** on Switch 2 rendering, the 5 GiB hard cap is retained for budgets up to 8 GiB; larger actual Vulkan budgets instead permit up to 75% of that current budget, subject to existing pressure/slack margins. This avoids the observed fixed 4,352/5,120 MiB thresholds on high-memory cards ([Eglantine #498](https://github.com/Djihads80/Eglantine/issues/498)).
7. **Windows guest-memory lifecycle:** release Switch 2 guest RAM when an application stops, reallocate it at next launch (adapted from [Eglantine #634](https://github.com/Djihads80/Eglantine/pull/634)). The Fastmem CreateFileMapping2 failure now reports its Windows error code and no longer triggers an irrelevant attempt to close a null handle. This improves diagnosis, **but cannot guarantee an allocation succeeds when system commit is exhausted**.
8. **Failure tracing:** cached shader errors distinguish missing constant-buffer values from missing texture types/formats, with failing handle and shader hashes. Opt-in `EDEN_NX2_RENDER_TRACE=1` logs up to 64 invalid TIC indices with relevant context; no rendering semantics are silently altered.
9. **Log privacy:** when the existing `censor_username` setting is enabled, the file logger replaces both Windows profile-path spellings and prefers `USERNAME` over a potentially misleading Unix `LOGNAME`. Hardware identification remains in the application log; only the profile path is redacted automatically.

## Tuning without recompilation

All variables apply to the emulator process at startup.

| Environment variable | Default in Stitchii | Purpose |
| --- | --- | --- |
| `EDEN_NX2_BACKGROUND_PIPELINES` | enabled | `0` disables cached-pipeline prebuilding |
| `EDEN_NX2_BACKGROUND_PIPELINE_THREADS` | 1–2 by CPU count | May be set to 1–16 |
| `EDEN_NX2_BACKGROUND_PIPELINE_LIMIT` | 2048 | Number of most recent pipelines prebuilt in the background; `0` disables |
| `EDEN_NX2_PIPELINE_EVICT_ABOVE` | 8000 | Existing cache retention threshold (higher values use more memory) |
| `EDEN_NX2_PIPELINE_DIFF` | unset | `1`: log graphics-pipeline state differences; debug use only |
| `EDEN_NX2_GPU_PROFILE` | unset | `1`: GPU-side processing profiler; debug use only |
| `EDEN_DKB_FRAME_TRACE` | unset | `1`: presentation/fence timing trace; debug use only |

The background limit trades persistent CPU load for potential first-use pipeline waits. Raising the limit can help when enough CPU and GPU resources are available; lowering it is worth testing for persistent stutter. No value is universally optimal.

## A/B experiment after build approval

1. Use the **same save, game settings, driver, and camera route** in Fritchii v3 and Stitchii, but separate their shader cache files. Warm each emulator's own cache before comparison. Do not compare a cold-cache first run to a warmed-cache second run.
2. Record **frame times, especially P95/P99 and 1%-low FPS**, not only the emulator's headline FPS counter.
3. Collect the following log records, particularly the **texture cache thresholds** (a larger-budget GPU should be allowed above the former 5 GiB cap):
   * `Runtime pipelines in the last 10 s` — how much of each window was spent on the GPU thread, SPIR-V workers, or waiting for builds.
   * `Background pipelines done` — how many pipeline builds completed, were already taken, or were superseded by foreground work.
   * `cached graphics pipelines skipped at boot` — how many cached pipelines were admitted to prebuild and dropped due to backlog limits.
   * `Evicted ... graphics pipelines` — repeated rebuilds after memory retention.
4. If stutter improves but shader pop-in increases, compare `EDEN_NX2_BACKGROUND_PIPELINE_LIMIT=2048`, `4096`, and `0`.
5. If runtime-pipeline counts are near zero but 15 FPS persists, investigate command processing, buffer/texture cache synchronization, GPU compute, or game timing. Shader-cache tweaks are not sufficient in that case.

## Explicitly NOT done

- No Windows executable compiled or tested.
- No GitHub Actions builds, releases or merges started.
- No gameplay validation or FPS claims.
- No changes to shader arithmetic, pipeline correctness, GPU synchronization semantics, or frame pacing without logs establishing their bottleneck.
- The original user log and its Windows username are **not committed**; only aggregate, privacy-minimized findings are documented.
- No copied copyrighted game content or keys.

## Existing upstream fixes reviewed

- [Eglantine #696](https://github.com/Djihads80/Eglantine/pull/696): prebuild all Switch 2 pipelines and keep them resident; do not adopt blindly because unlimited driver memory grows quickly.
- [Eglantine #708](https://github.com/Djihads80/Eglantine/pull/708): reintroduced no-eviction policy; Fritchii v3 already uses a bounded-retention alternative.
- [Eglantine #544](https://github.com/Djihads80/Eglantine/pull/544): pipeline-key alpha-test quantization. This is game/render-state-specific and needs visual correctness tests before porting.
- [Eglantine #599](https://github.com/Djihads80/Eglantine/issues/599): persistent-cache hang on OoT. Different symptom from ordinary shader stuttering; cache corruption must be ruled out if a game never presents frames.

## Release gate

**Wait for an explicit user GO before any compilation.** The branch is for code review only. After approval: run compilation and static/tests through an isolated GitHub Actions workflow, inspect any build failures, then benchmark before calling this a performance improvement.
