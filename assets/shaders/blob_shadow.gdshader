shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.72;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	if (dot(centered, centered) > 0.25) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = shadow_opacity;
}
