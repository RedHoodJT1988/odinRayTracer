package main

import "core:math/linalg"

// Alias onto core:math/linalg's vector type instead of hand-rolling a
// Vec3 + operator overload set. We get dot/cross/reflect/refract/
// normalize for free and for correctness parity with the rest of the
// standard library.
Vec3 :: linalg.Vector3f32

Ray :: struct {
	origin: Vec3,
	dir:    Vec3,
}

ray_at :: proc(r: Ray, t: f32) -> Vec3 {
	return r.origin + r.dir * t
}

Material_Kind :: enum {
	Lambertian,
	Metal,
	Dielectric,
}

Material :: struct {
	kind:   Material_Kind,
	albedo: Vec3, // Lambertian / Metal
	fuzz:   f32, // Metal only, 0 = perfect mirror
	ir:     f32, // Dielectric only, index of refraction
}

// Spheres reference materials by name rather than embedding a Material
// value or a raw pointer. This keeps Sphere small and lets many spheres
// share one material record living in Scene.materials.
Sphere :: struct {
	center:      Vec3,
	radius:      f32,
	material_id: string,
}

Hit_Record :: struct {
	point:       Vec3,
	normal:      Vec3,
	t:           f32,
	front_face:  bool,
	material_id: string,
}

Scene :: struct {
	spheres:   [dynamic]Sphere,
	materials: map[string]Material,
}

// Explicit, local error values instead of a global "last_error" or a
// panic. Every fallible proc in this codebase returns one of these
// alongside its normal result so callers decide what "failure" means to
// them (retry, log, abort the frame, etc).
Render_Error :: enum {
	None,
	Invalid_Dimensions,
	Empty_Scene,
	Missing_Material,
	Buffer_Too_Small,
}
