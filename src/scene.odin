package main

import "core:math/rand"

// Every allocating proc in this file takes its allocator as an explicit
// parameter (defaulting to context.allocator, never reaching for it
// implicitly mid-function). That means a caller can hand scene_init a
// tracking allocator, an arena, or a temp allocator and every downstream
// allocation follows along predictably.

scene_init :: proc(allocator := context.allocator) -> Scene {
	return Scene{
		spheres   = make([dynamic]Sphere, allocator = allocator),
		materials = make(map[string]Material, allocator = allocator),
	}
}

scene_destroy :: proc(scene: ^Scene) {
	delete(scene.spheres)
	delete(scene.materials)
}

scene_add_material :: proc(scene: ^Scene, name: string, mat: Material) -> Render_Error {
	if name == "" {
		return .Missing_Material
	}
	scene.materials[name] = mat
	return .None
}

scene_add_sphere :: proc(scene: ^Scene, sphere: Sphere) -> Render_Error {
	if sphere.material_id not_in scene.materials {
		return .Missing_Material
	}
	append(&scene.spheres, sphere)
	return .None
}

// A small fixed demo scene: one ground sphere plus a glass / diffuse /
// metal trio, the classic "Ray Tracing in One Weekend" cover shot.
build_demo_scene :: proc(allocator := context.allocator) -> Scene {
	scene := scene_init(allocator)

	_ = scene_add_material(&scene, "ground", Material{kind = .Lambertian, albedo = {0.5, 0.5, 0.5}})
	_ = scene_add_material(&scene, "center", Material{kind = .Lambertian, albedo = {0.1, 0.2, 0.5}})
	_ = scene_add_material(&scene, "left", Material{kind = .Dielectric, ir = 1.5})
	_ = scene_add_material(&scene, "right", Material{kind = .Metal, albedo = {0.8, 0.6, 0.2}, fuzz = 0.05})

	_ = scene_add_sphere(&scene, Sphere{center = {0, -100.5, -1}, radius = 100, material_id = "ground"})
	_ = scene_add_sphere(&scene, Sphere{center = {0, 0, -1}, radius = 0.5, material_id = "center"})
	_ = scene_add_sphere(&scene, Sphere{center = {-1, 0, -1}, radius = 0.5, material_id = "left"})
	_ = scene_add_sphere(&scene, Sphere{center = {1, 0, -1}, radius = 0.5, material_id = "right"})

	return scene
}

// Reshuffles the three foreground spheres in place. Called on every
// press of R in main.odin. Note this mutates scene.spheres via clear()
// + append() rather than allocating a fresh dynamic array each time, so
// the permanent allocator sees no churn from re-randomizing the scene.
randomize_scene :: proc(scene: ^Scene) {
	clear(&scene.spheres)
	_ = scene_add_sphere(scene, Sphere{center = {0, -100.5, -1}, radius = 100, material_id = "ground"})

	names := [3]string{"center", "left", "right"}
	for i := 0; i < 3; i += 1 {
		x := rand.float32_range(-2, 2)
		z := rand.float32_range(-1.8, -0.6)
		r := rand.float32_range(0.3, 0.6)
		_ = scene_add_sphere(scene, Sphere{center = {x, 0, z}, radius = r, material_id = names[i]})
	}
}
