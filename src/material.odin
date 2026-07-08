package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"

Scatter_Result :: struct {
	scattered:   Ray,
	attenuation: Vec3,
}

// Rather than a bool "success" out-param bolted onto a mutable struct,
// this returns (result, ok) - Odin's native multi-return. Callers use
// the `if result, ok := material_scatter(...); ok { ... }` idiom instead
// of checking a sentinel field.
material_scatter :: proc(mat: Material, r_in: Ray, hit: Hit_Record) -> (result: Scatter_Result, ok: bool) {
	switch mat.kind {
	case .Lambertian:
		scatter_dir := hit.normal + random_unit_vector()
		if near_zero(scatter_dir) {
			scatter_dir = hit.normal
		}
		result.scattered = Ray{origin = hit.point, dir = scatter_dir}
		result.attenuation = mat.albedo
		return result, true

	case .Metal:
		reflected := linalg.reflect(linalg.normalize(r_in.dir), hit.normal)
		reflected = reflected + mat.fuzz * random_in_unit_sphere()
		result.scattered = Ray{origin = hit.point, dir = reflected}
		result.attenuation = mat.albedo
		return result, linalg.dot(reflected, hit.normal) > 0

	case .Dielectric:
		result.attenuation = Vec3{1, 1, 1}
		refraction_ratio := mat.ir
		if hit.front_face {
			refraction_ratio = 1.0 / mat.ir
		}

		unit_dir := linalg.normalize(r_in.dir)
		cos_theta := min(linalg.dot(-unit_dir, hit.normal), f32(1.0))
		sin_theta := math.sqrt(1.0 - cos_theta * cos_theta)

		cannot_refract := refraction_ratio * sin_theta > 1.0
		direction: Vec3
		if cannot_refract || reflectance(cos_theta, refraction_ratio) > rand.float32() {
			direction = linalg.reflect(unit_dir, hit.normal)
		} else {
			direction = linalg.refract(unit_dir, hit.normal, refraction_ratio)
		}

		result.scattered = Ray{origin = hit.point, dir = direction}
		return result, true
	}

	return result, false
}

// Schlick's approximation for reflectance at grazing angles.
reflectance :: proc(cosine, ref_idx: f32) -> f32 {
	r0 := (1 - ref_idx) / (1 + ref_idx)
	r0 = r0 * r0
	return r0 + (1 - r0) * math.pow(1 - cosine, 5)
}

random_in_unit_sphere :: proc() -> Vec3 {
	for {
		p := Vec3{
			rand.float32_range(-1, 1),
			rand.float32_range(-1, 1),
			rand.float32_range(-1, 1),
		}
		if linalg.dot(p, p) < 1 {
			return p
		}
	}
}

random_unit_vector :: proc() -> Vec3 {
	return linalg.normalize(random_in_unit_sphere())
}

near_zero :: proc(v: Vec3) -> bool {
	s: f32 = 1e-8
	return abs(v.x) < s && abs(v.y) < s && abs(v.z) < s
}
