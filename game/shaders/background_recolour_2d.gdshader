// A generic 2D "background-recolour" blend (issue #64): wherever a sprite's own alpha channel carries
// a nonzero level (0-31, the convention tools/build_pack.py and importer/pack_builder.gd use for every
// PRE0 3/4/5 effect mask they extract), this replaces the pixel already on screen there with a brightened
// copy of itself -- `new = clamp(old + (level + 1) * recolour_step, 0, 1)` per channel -- instead of drawing
// any colour of its own. `recolour_step` is read from the sprite's own pack data (its `recolour_step`
// field), never hardcoded here, so a different pack's own masks can use a different strength or decline the
// effect entirely (recolour_step <= 0.0 draws nothing). See the project wiki, documents 9 and 80, for the
// real formula this reproduces (FUN_00424420's "brighten" translation table).
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;
uniform float recolour_step = 0.0;

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float level = m.a * 255.0;
	if (level < 0.5 || recolour_step <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 bg = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
		COLOR = vec4(clamp(bg + vec3((level + 1.0) * recolour_step), 0.0, 1.0), 1.0);
	}
}
