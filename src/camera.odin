package main

Camera :: struct {
	origin:            Vec3,
	lower_left_corner: Vec3,
	horizontal:        Vec3,
	vertical:          Vec3,
}

camera_init :: proc(width, height: int) -> Camera {
	aspect_ratio := f32(width) / f32(height)
	viewport_height: f32 = 2.0
	viewport_width := aspect_ratio * viewport_height
	focal_length: f32 = 1.0

	origin := Vec3{0, 0, 0}
	horizontal := Vec3{viewport_width, 0, 0}
	vertical := Vec3{0, viewport_height, 0}
	lower_left := origin - horizontal * 0.5 - vertical * 0.5 - Vec3{0, 0, focal_length}

	return Camera{
		origin            = origin,
		lower_left_corner = lower_left,
		horizontal        = horizontal,
		vertical          = vertical,
	}
}

camera_get_ray :: proc(cam: Camera, u, v: f32) -> Ray {
	return Ray{
		origin = cam.origin,
		dir    = cam.lower_left_corner + u * cam.horizontal + v * cam.vertical - cam.origin,
	}
}
