shader_type canvas_item;

uniform bool highlighted = false;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_width : hint_range(1.0, 2.0) = 1.0;

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

// Reusable alpha silhouette dilation. Textures are padded by the shared widget
// so outline pixels outside the original bounds are not clipped.
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float neighborhood = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			neighborhood = max(neighborhood, texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * outline_width).a);
		}
	}
	float edge = highlighted ? max(neighborhood - source.a, 0.0) : 0.0;
	float alpha = source.a + edge * outline_color.a;
	vec3 rgb = alpha > 0.0 ? (source.rgb * source.a + outline_color.rgb * edge * outline_color.a) / alpha : vec3(0.0);
	COLOR = item_modulate * vec4(rgb, alpha);
}
