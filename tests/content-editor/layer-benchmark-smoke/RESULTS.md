Layered runtime benchmark — 2026-09-28

Three fresh-process trials on the local Windows machine with bundled LOVE.
Baseline: `a1ab535`; updated renderer: `7a32322`.
Reproduce with `tests/content-editor/run-layer-benchmark.ps1`.

The fixture builds five 80×200 maps, three layers per map (240,000 authored
cell references), with 4,097 atlas slots per map. One map is visible. The
native sand bank changes but none of these maps use its animated tile. The
animated scenario also has a 100 ms custom animation affecting eight slots.
Each trial runs 600 simulated 60 Hz steps. Native game modules are fixtures;
canvases, textures, sprite batches, rendering and readback use real LOVE graphics.

Medians across the three trials:

| Measurement | Original | Updated |
|---|---:|---:|
| Static scenario: render submission time, 600 steps | 452.487 ms | 0.143 ms |
| Static scenario: draw calls | 909,386 | 0 |
| Animated scenario: render submission time, 600 steps | 883.296 ms | 18.833 ms |
| Animated scenario: elapsed time including final GPU sync | 888.959 ms | 20.210 ms |
| Animated scenario: draw calls | 1,659,015 | 300 |
| Animated scenario: `T.get` calls after build | 209 | 0 |
| Animated scenario: retained Lua heap after full collection | 53.325 MiB | 32.082 MiB |
| Animated scenario: full GC duration | 23.985 ms | 10.129 ms |

Each GC value is the median of nine full collections within a trial, then
the median across trials. The animated workload retains about 40% less Lua
heap and full collection takes about 58% less time. GC timing covers the
fixture's whole retained Lua heap, not just layer tables. Lua heap measurements
exclude texture/driver memory.

Animated submission times ranged from 864.739–909.976 ms originally and
17.754–25.808 ms after the changes. The updated renderer clears 1,600 small
16×16 slot rectangles, versus 270 full-canvas clears originally. The larger
clear-call count is expected; the cleared area and drawing work are much smaller.

These are component workload measurements, not whole-game FPS or gameplay
frame-time results. They exclude native pair-binding uploads, player simulation,
UI, audio, and normal field rendering. Do not interpret the submission-time ratio
as a whole-game speedup. The renderer's pixel-correctness regression test also
passes independently.

Bridge follow-up:

The native player calls `nextElevation`, which reads `elevationOn` directly.
The previous editor hook only intercepted `elevationAt`, so movement ignored
bridge height. The fix intercepts the shared elevation lookup, accounts for
authorized entrance/exit height changes during collision checks, and restores
both player elevation fields from saves. The full native bridge smoke test now
passes for FireRed and LeafGreen, including forward and reverse traversal,
underpass collision, deck edges, rendering planes, and save restoration.
Waterfall and layered-rendering regression tests also pass.
