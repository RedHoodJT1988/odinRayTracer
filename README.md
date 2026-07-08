# Odin Ray Tracer

A software (CPU) ray tracer written from scratch in [Odin](https://odin-lang.org/), using
`core:math/linalg` for vector math and `vendor:raylib` purely as a pixel-buffer
display surface — every ray/sphere/material calculation is hand-written.

<!--
  TODO: replace this with a real capture before publishing the repo.
  Windows: record with ScreenToGif (free) or Xbox Game Bar (Win+G), 5-8
  seconds is plenty. Save as docs/demo.gif and this line will render it
  at the top of the GitHub README automatically.
-->
![demo](docs/demo.mp4)

Press **R** while the window is focused to reshuffle the scene and re-render.
The console prints render time for every frame (see [Performance](#performance)).

## Why this exists

This is a portfolio piece, not a production renderer. The goal was to write
idiomatic Odin — not C with Odin syntax — so the code deliberately shows off:

- explicit allocators passed as parameters, not grabbed off `context` implicitly
- a growing arena (`core:mem/virtual`) for per-frame scratch memory
- a tracking allocator wrapping the permanent heap allocations, with a real
  leak report printed on exit
- multi-return error handling (`(result, Render_Error)`, `(rec, ok)`) instead
  of panics or a global "last error"
- Odin's native `map` and `[dynamic]` types for the scene graph

## Architecture

```
src/
  types.odin    Vec3 alias, Ray, Material, Sphere, Scene, Render_Error
  scene.odin    scene_init/destroy/add_*, demo scene construction
  camera.odin   simple pinhole camera -> ray generation
  material.odin Lambertian / Metal / Dielectric scatter functions
  render.odin   sphere intersection, recursive ray_color, render_scene
  main.odin     raylib window, arena + tracking allocator lifecycle
```

### Data layout

`Scene` is intentionally simple: `spheres: [dynamic]Sphere` (array-of-structs)
plus `materials: map[string]Material`. Spheres store a `material_id: string`
key instead of embedding a `Material` or a pointer to one. Trade-off, stated
plainly:

- **Pro:** many spheres can share one material record, materials can be
  edited or hot-swapped by name without touching every sphere, and the scene
  reads like data (`"left" -> Dielectric`) instead of an opaque handle table.
- **Con:** a string-keyed map hash-lookup per hit is slower than an integer
  index into a slice. At the sphere counts here (single digits to low
  hundreds) it's not measurable; at tens of thousands of primitives, this is
  the first thing to change (swap `material_id` for an integer index into a
  `[]Material` slice built once at scene-load time).

`hit_scene` is a flat linear scan over `scene.spheres` — no BVH. Same logic:
correct and simple beats a tree structure the reader has to trust, until the
scene is large enough that O(n) actually shows up in the frame time. That
threshold and the intended fix (a BVH keyed on `core:container` or a manual
binary tree over an `[dynamic]AABB`) are noted in
[Next steps](#next-steps) rather than built speculatively.

### Memory management

Two allocators, two different lifetimes, used on purpose instead of one
allocator for everything:

1. **Permanent allocator** (`main.odin`): the real `context.allocator`,
   wrapped in a `mem.Tracking_Allocator`. Scene data (the `[dynamic]Sphere`,
   the `map[string]Material`, the pixel buffer) lives here for the process
   lifetime and is torn down with explicit `defer delete(...)` /
   `scene_destroy` calls. On exit, `track.allocation_map` is walked and any
   surviving entries are printed as leaks — this is a real check, not an
   assertion of "no leaks" by assumption.

2. **Per-frame arena** (`core:mem/virtual`, growing arena): every call to
   `render_scene` receives `frame_allocator` explicitly and sets
   `context.allocator = frame_allocator` / `context.temp_allocator =
   frame_allocator` for the duration of that call only — the override never
   leaks out to the caller's context. At 640x360 @ 16 samples/pixel that's
   ~3.7M primary + scattered ray evaluations per frame; routing their
   scratch allocations through an arena and reclaiming everything with a
   single `free_all(frame_allocator)` on the **R** key is a lot cheaper than
   individually freeing each one, and it's impossible to leak scratch memory
   by forgetting a `delete()` somewhere in a hot recursive function.

### Error handling

No panics, no global "did the last call fail" flag. Every fallible
function returns Odin's native multiple values:

```odin
render_scene :: proc(scene: ^Scene, cfg: Render_Config, pixels: []u8,
                      frame_allocator: mem.Allocator) -> Render_Error

hit_scene :: proc(scene: ^Scene, r: Ray, t_min, t_max: f32) -> (rec: Hit_Record, ok: bool)

material_scatter :: proc(mat: Material, r_in: Ray, hit: Hit_Record) -> (result: Scatter_Result, ok: bool)
```

`Render_Error` is a closed enum (`None`, `Invalid_Dimensions`, `Empty_Scene`,
`Missing_Material`, `Buffer_Too_Small`) checked at the call site in
`main.odin`, so adding a new failure mode is a compiler error at every switch
that doesn't handle it, not a silent `if err != nil` that keeps compiling.

## Building

Requires the [Odin compiler](https://odin-lang.org/docs/install/) on `PATH`
(raylib bindings ship with the compiler under `vendor:raylib`, no separate
install needed on Windows).

```bat
build.bat            :: debug build, -debug
build.bat release    :: optimized build, -o:speed -no-bounds-check
build.bat clean       :: remove build artifacts
```

Run the resulting `raytracer.exe`. Controls:

| Key | Action                          |
|-----|----------------------------------|
| R   | Reshuffle spheres and re-render  |
| Esc | Close the window                 |

## Performance

Numbers below are from the render-time line the app prints to the console
every frame (`fmt.printfln("rendered %dx%d @ %d spp in %.1fms", ...)`) and
from `track.allocation_map` on exit. Fill in with your own hardware —
these are placeholders until measured on the target machine:

| Resolution | Samples/px | Max depth | Render time | Notes                       |
|-----------:|-----------:|----------:|------------:|------------------------------|
| 640x360    | 16         | 8         | _measure_   | debug build                  |
| 640x360    | 16         | 8         | _measure_   | `build.bat release`          |
| 1280x720   | 32         | 12        | _measure_   | `build.bat release`          |

To reproduce: run `build.bat release`, launch `raytracer.exe`, read the
render time printed to the console (and shown on-screen under the FPS
counter), and note memory via Task Manager or by adding a print of
`arena.total_used` in `main.odin`.

## Next steps

Ideas kept out of v1 on purpose, listed here instead of half-implemented:

- **BVH** over `scene.spheres` once primitive counts go beyond a few hundred
- **Multithreading** via `core:thread` — the render loop is embarrassingly
  parallel per-row; each row would need its own arena slice to avoid
  contention on a single arena allocator
- **Integer material handles** instead of `string` keys, once the map
  lookup shows up in a profile
- **Denoising / progressive accumulation** instead of a single fixed
  `samples_per_px` pass
