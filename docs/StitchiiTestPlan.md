# Stitchii controlled Windows performance tests

**No builds have been started.** The source branch `stitchii/stutterfix` does not trigger GitHub Actions. The owner must explicitly approve the first build.

## Gated Windows compilation

- The isolated workflow is [`.github/workflows/stitchii-dev-windows.yml`](../.github/workflows/stitchii-dev-windows.yml).
- It triggers **only on a push to `stitchii/ci-test`**, which is deliberately **not created yet**. After approval, copy the reviewed source commit to that branch; its first push starts a Windows MSVC compile.
- This job has `contents: read` permissions, never creates a tag/release, and uploads only a seven-day GitHub Actions artifact. It includes the analyzer.
- The existing Fritchii `release-binaries.yml` is **not** used: that workflow has broader platform/release behavior and should not be used for early tests.
- GitHub Actions reports whether CMake configuration, compilation and packaging succeed. A successful build **does not** prove better graphics or higher FPS.

## Runtime switches

Change these only **before** launching the EXE. The defaults are the new Stitchii behavior; each switch can isolate one hypothesis. No external launchers or installed tools are necessary.

| Variable | Default | Controlled alternative |
| --- | --- | --- |
| `STITCHII_ADAPTIVE_TEXTURE_CACHE` | `1` | `0`: use the original hard 5 GiB texture limit |
| `STITCHII_ASYNC_USAGE_SAVE` | `1` | `0`: restore synchronous pipeline-use writes |
| `EDEN_NX2_BACKGROUND_PIPELINES` | `1` | `0`: no background prebuilding |
| `EDEN_NX2_BACKGROUND_PIPELINE_THREADS` | 1–2 | Force `1` or compare `4` |
| `EDEN_NX2_BACKGROUND_PIPELINE_LIMIT` | `2048` | `0`, `4096` or `8192` |
| `EDEN_NX2_GPU_PROFILE` | off | `1`: detailed CPU/GPU timing, for a separate diagnostic run |
| `EDEN_NX2_RENDER_TRACE` | off | `1`: up to 64 invalid TIC/index diagnostics, for a separate diagnostic run |
| `EDEN_NX2_PIPELINE_DIFF` | off | `1`: pipeline state change diagnostics (verbose) |

The adaptive texture-cache policy logs `Stitchii texture cache: policy=adaptive` (or `legacy-5GiB`). The pipeline loader logs `Stitchii cache controls: async_usage_save=..., prebuild=..., prebuild_threads=..., prebuild_limit=...`.

## Simple A/B test

Run each profile **from the same save**, in the same location with the same camera movement and all ordinary game settings held fixed:

1. **Reference:** existing Fritchii v3, warmed up in its own shader cache.
2. **Stitchii default:** warmed up in its **separate** shader cache; all switch defaults.
3. **Stitchii legacy texture cap:** `STITCHII_ADAPTIVE_TEXTURE_CACHE=0`, all else unchanged.
4. **Stitchii no prebuild:** `EDEN_NX2_BACKGROUND_PIPELINES=0`, all else unchanged.
5. **Stitchii sync-save:** `STITCHII_ASYNC_USAGE_SAVE=0`, all else unchanged.
6. If the results are unclear, do a **short separate diagnostic run** with `EDEN_NX2_GPU_PROFILE=1` or `EDEN_NX2_RENDER_TRACE=1`. Do not compare these diagnostic runs' performance directly against the normal ones.

Example: start only the legacy-cache-control run in PowerShell (replace EXE path):

```powershell
$env:STITCHII_ADAPTIVE_TEXTURE_CACHE = "0"
& "C:\path\to\Stitchii\lichii.exe"
Remove-Item Env:\STITCHII_ADAPTIVE_TEXTURE_CACHE -ErrorAction SilentlyContinue
```

The original game save remains in the usual Eden location; the cache filenames are distinct. **Do not share the full `eden_log.txt` publicly**; it may include local paths and hardware details.

## Compare two logs without revealing machine details

Save each log locally **before** the next test, because Eden rotates `eden_log.txt` on startup. The log is typically at `$env:APPDATA\eden\log\eden_log.txt`.

```powershell
.\tools\stitchii-analyze-log.ps1 -LogPath .\logs\stitchii.txt -CompareTo .\logs\fritchii.txt
```

For a numbers-only report suitable for sharing:

```powershell
.\tools\stitchii-analyze-log.ps1 -LogPath .\logs\stitchii.txt -CsvPath .\stitchii-metrics.csv
```

This parser reports 600-present averaged frame times, worst individual reported frame, number of frames over 100 ms, runtime pipeline counts, GPU-thread shader time, texture failures, skipped draws, and back-memory failures. It **does not claim P99 or 1%-low FPS**: the aggregated log does not contain enough individual frame samples to calculate those reliably.

### Comparability rules

- First startup may recompile shaders in a new fork cache. Compare warmed-up runs, not first boot vs fifth boot.
- Use **one game launch per log**. If the parser reports multiple boots or mixed frame-generation / 30-FPS settings, the metrics are not a clean A/B comparison.
- Keep the same display refresh, VSync, frame pacing, docked mode, resolution and mods.
- Keep frame generation **off** while comparing base rendering speed.
- The analyzer's estimated FPS is `1000 / averaged-present-interval-ms`, not a direct measure of the game's simulation frame rate.
- **Do not interpret a lower shader error count from an incomplete game run as a fix**; match runtime duration and location.
