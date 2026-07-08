package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"

hit_sphere :: proc(sphere: Sphere, r: Ray, t_min, t_max: f32) -> (rec: Hit_Record, ok: bool) {
	oc := r.origin - sphere.center
	a := linalg.dot(r.dir, r.dir)
	half_b := linalg.dot(oc, r.dir)
	c := linalg.dot(oc, oc) - sphere.radius * sphere.radius

	discriminant := half_b * half_b - a * c
	if discriminant < 0 {
		return rec, false
	}
	sqrt_d := math.sqrt(discriminant)

	root := (-half_b - sqrt_d) / a
	if root < t_min || root > t_max {
		root = (-half_b + sqrt_d) / a
		if root < t_min || root > t_max {
			return rec, false
		}
	}

	rec.t = root
	rec.point = ray_at(r, root)
	outward_normal := (rec.point - sphere.center) / sphere.radius
	rec.front_face = linalg.dot(r.dir, outward_normal) < 0
	rec.normal = rec.front_face ? outward_normal : -outward_normal
	rec.material_id = sphere.material_id
	return rec, true
}

// Linear scan over the sphere slice. At this scene size (dozens of
// spheres) a BVH buys nothing and just adds a pointer-chasing tree the
// interviewer has to read through - noted in the README as the obvious
// next step once sphere counts grow into the thousands.
hit_scene :: proc(scene: ^Scene, r: Ray, t_min, t_max: f32) -> (rec: Hit_Record, ok: bool) {
	closest := t_max
	for sphere in scene.spheres {
		if candidate, hit_ok := hit_sphere(sphere, r, t_min, closest); hit_ok {
			rec = candidate
			closest = candidate.t
			ok = true
		}
	}
	return rec, ok
}

ray_color :: proc(scene: ^Scene, r: Ray, depth: int) -> Vec3 {
	if depth <= 0 {
		return Vec3{0, 0, 0}
	}

	if rec, ok := hit_scene(scene, r, 0.001, math.F32_MAX); ok {
		mat, mat_ok := scene.materials[rec.material_id]
		if !mat_ok {
			// Missing material is a scene-authoring bug, not a crash: surface it
			// visually (hot magenta) instead of indexing a zero-value Material.
			return Vec3{1, 0, 1}
		}
		if result, scatter_ok := material_scatter(mat, r, rec); scatter_ok {
			return result.attenuation * ray_color(scene, result.scattered, depth - 1)
		}
		return Vec3{0, 0, 0}
	}

	unit_dir := linalg.normalize(r.dir)
	t := 0.5 * (unit_dir.y + 1.0)
	return (1.0 - t) * Vec3{1, 1, 1} + t * Vec3{0.5, 0.7, 1.0}
}

Render_Config :: struct {
	width:          int,
	height:         int,
	samples_per_px: int,
	max_depth:      int,
}

// render_scene owns none of its memory long-term: `pixels` is caller
// allocated, and `frame_allocator` is where every scratch allocation
// made *during* this call (temp Vec3s, anything linalg needs to spill
// to the heap) is routed. The context override is local to this proc;
// once it returns, the caller's own context.allocator is untouched.
render_scene :: proc(
	scene: ^Scene,
	cfg: Render_Config,
	pixels: []u8,
	frame_allocator: mem.Allocator,
) -> Render_Error {
	if cfg.width <= 0 || cfg.height <= 0 {
		return .Invalid_Dimensions
	}
	if len(scene.spheres) == 0 {
		return .Empty_Scene
	}
	if len(pixels) < cfg.width * cfg.height * 4 {
		return .Buffer_Too_Small
	}

	context.allocator = frame_allocator
	context.temp_allocator = frame_allocator

	cam := camera_init(cfg.width, cfg.height)

	for y := 0; y < cfg.height; y += 1 {
		for x := 0; x < cfg.width; x += 1 {
			color := Vec3{0, 0, 0}
			for s := 0; s < cfg.samples_per_px; s += 1 {
				u := (f32(x) + rand.float32()) / f32(cfg.width - 1)
				v := (f32(cfg.height - 1 - y) + rand.float32()) / f32(cfg.height - 1)
				r := camera_get_ray(cam, u, v)
				color += ray_color(scene, r, cfg.max_depth)
			}
			write_pixel(pixels, x, y, cfg.width, color, cfg.samples_per_px)
		}
	}

	return .None
}

write_pixel :: proc(pixels: []u8, x, y, width: int, color: Vec3, samples: int) {
	scale := 1.0 / f32(samples)
	// Gamma-correct (gamma=2) via sqrt before quantizing to u8.
	r := math.sqrt(color.x * scale)
	g := math.sqrt(color.y * scale)
	b := math.sqrt(color.z * scale)

	idx := (y * width + x) * 4
	pixels[idx + 0] = u8(clamp(r, 0, 0.999) * 256)
	pixels[idx + 1] = u8(clamp(g, 0, 0.999) * 256)
	pixels[idx + 2] = u8(clamp(b, 0, 0.999) * 256)
	pixels[idx + 3] = 255
}
