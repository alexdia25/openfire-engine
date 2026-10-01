// The 3D counterpart of background_recolour_2d.gdshader (issue #64/#37): the same per-pixel brighten
// formula, for a world-space quad sampling the screen behind it instead of a 2D UI layer in front of one.
// `mask_tex`'s alpha channel carries the raw 0-31 level the same way every extracted PRE0 3/4/5 effect
// mask does; `recolour_step` comes from that sprite's own pack data, read by whoever sets up the material
// (never hardcoded in this shader). See documents 9 and 80 on the project wiki.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D mask_tex : filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float recolour_step = 0.0;

void fragment() {
	vec4 m = texture(mask_tex, UV);
	float level = m.a * 255.0;
	if (level < 0.5 || recolour_step <= 0.0) {
		discard;
	}
	vec3 bg = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	ALBEDO = clamp(bg + vec3((level + 1.0) * recolour_step), 0.0, 1.0);
	ALPHA = 1.0;
}
