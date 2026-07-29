shader_type spatial;

// Moving sea for water_sea_tile. Tier B2 of the 2026-07-29 environment review.
//
// Opaque on purpose. Transparent or refractive water needs a mid-frame resolve,
// which on a tiled mobile GPU is one of the most expensive things this project
// could ask for, and the review rules it out explicitly. An opaque surface with
// a vertex swell reads as water at this camera distance for almost nothing.
//
// NO UV SCROLL, which is a deliberate departure from the review's §5.6. That
// section suggests scrolling UVs inside the water cell's rect, but
// build_beach_env_kit.py paints this piece from TWO cells -- water_shallow for
// the shore band (u < 0.1) and water_deep beyond it. A fragment shader cannot
// tell which cell a given face was assigned, so one cell rect cannot bound the
// scroll for both, and any scroll wide enough to be visible drags the deep
// water into the shallow cell and repaints the sea. Motion therefore comes from
// vertex displacement, which is the dominant cue anyway, plus a brightness
// shimmer that never touches UV.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

// Two octaves: a long swell that carries the eye, and a shorter chop that keeps
// the surface from reading as one rigid sheet.
uniform float swell_amplitude_m = 0.10;
uniform float swell_speed = 0.45;
uniform float chop_amplitude_m = 0.035;
uniform float chop_speed = 1.35;
uniform float shimmer_strength : hint_range(0.0, 0.5) = 0.07;

varying vec3 world_position;

void vertex() {
	// Displace in world space so neighbouring sea tiles share one continuous
	// wave field instead of each bobbing on its own local phase, which would
	// crease visibly along every tile seam.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float swell = sin(world_position.z * 0.16 + TIME * swell_speed)
		* cos(world_position.x * 0.09 - TIME * swell_speed * 0.7);
	float chop = sin(
		world_position.x * 0.55 + world_position.z * 0.4 + TIME * chop_speed
	);

	VERTEX.y += swell * swell_amplitude_m + chop * chop_amplitude_m;
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;

	// Cell-safe highlight: modulates brightness only, so the sampled texel is
	// always the one the mesh's UVs asked for.
	float shimmer = sin(
		world_position.x * 0.7 + world_position.z * 0.5 + TIME * 1.9
	) * 0.5 + 0.5;

	ALBEDO = base * (1.0 + (shimmer - 0.5) * 2.0 * shimmer_strength);
	ROUGHNESS = roughness_value;
}
