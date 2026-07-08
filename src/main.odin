package main

import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:time"
import rl "vendor:raylib"

WIDTH :: 640
HEIGHT :: 360
SAMPLES_PER_PIXEL :: 16
MAX_DEPTH :: 8

main :: proc() {
	// --- Permanent-allocation tracking -------------------------------
	// Wraps context.allocator so every make()/new() for the *lifetime*
	// of the scene (spheres, materials) is recorded. On shutdown we
	// print anything that was never delete()'d - a real leak check, not
	// a guess.
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	scene := build_demo_scene(context.allocator)
	defer scene_destroy(&scene)

	// --- Per-frame scratch arena -------------------------------------
	// Every render_scene() call routes its transient allocations here.
	// Instead of freeing thousands of small per-ray allocations one at a
	// time, we call arena_free_all once per frame and reclaim
	// everything in a single pointer-bump reset.
	arena: vmem.Arena
	if arena_err := vmem.arena_init_growing(&arena, 32 * mem.Megabyte); arena_err != nil {
		fmt.eprintln("failed to initialize render arena:", arena_err)
		return
	}
	defer vmem.arena_destroy(&arena)
	frame_allocator := vmem.arena_allocator(&arena)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(WIDTH, HEIGHT, "Odin Ray Tracer")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	pixels := make([]u8, WIDTH * HEIGHT * 4, context.allocator)
	defer delete(pixels)

	image := rl.Image{
		data    = raw_data(pixels),
		width   = WIDTH,
		height  = HEIGHT,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := rl.LoadTextureFromImage(image)
	defer rl.UnloadTexture(texture)

	cfg := Render_Config{
		width          = WIDTH,
		height         = HEIGHT,
		samples_per_px = SAMPLES_PER_PIXEL,
		max_depth      = MAX_DEPTH,
	}

	needs_render := true
	last_render_ms: f64 = 0

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.R) {
			// Reclaim every scratch byte from the previous frame(s) in
			// one call, then generate a new arrangement of spheres.
			free_all(frame_allocator)
			randomize_scene(&scene)
			needs_render = true
		}

		if needs_render {
			start := time.now()
			if err := render_scene(&scene, cfg, pixels, frame_allocator); err != .None {
				fmt.eprintln("render failed:", err)
			} else {
				last_render_ms = time.duration_milliseconds(time.since(start))
				fmt.printfln(
					"rendered %dx%d @ %d spp in %.1fms",
					cfg.width,
					cfg.height,
					cfg.samples_per_px,
					last_render_ms,
				)
			}
			rl.UpdateTexture(texture, raw_data(pixels))
			needs_render = false
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.DrawTexture(texture, 0, 0, rl.WHITE)
		rl.DrawFPS(10, 10)
		rl.DrawText(fmt.ctprintf("last render: %.1fms  [R] regenerate", last_render_ms), 10, 32, 18, rl.PURPLE)
		rl.EndDrawing()
	}

	// --- Leak report --------------------------------------------------
	if len(track.allocation_map) > 0 {
		fmt.eprintfln("=== %d leaked allocation(s) ===", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintfln("  %v bytes at %v", entry.size, entry.location)
		}
	} else {
		fmt.println("no leaks detected")
	}
}
