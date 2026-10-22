shader_type canvas_item;

// Simple animated gradient background with a subtle moving light streak
// and a soft pulsing glow near the bottom of the screen. Colors are
// exposed as uniforms so you can tweak them from the Inspector without
// touching the shader.
//
// pixel_size and color_steps give it a retro look: the image is sampled
// in pixel_size blocks and quantized to color_steps levels per channel,
// with ordered (Bayer) dithering between levels. Both are off at their
// defaults (1.0 and 0.0), so existing users of the shader are unchanged.

uniform vec4 color_top : source_color = vec4(0.051, 0.027, 0.129, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.165, 0.055, 0.239, 1.0);
uniform vec4 accent_color : source_color = vec4(0.902, 0.133, 0.475, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.35;
uniform float pixel_size : hint_range(1.0, 16.0, 1.0) = 1.0;
uniform float color_steps : hint_range(0.0, 32.0, 1.0) = 0.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / pixel_size);
	vec2 uv = UV;
	if (pixel_size > 1.0) {
		// Snap UV to the block grid so every block is a single flat color.
		vec2 uv_per_px = fwidth(UV);
		vec2 block = uv_per_px * pixel_size;
		uv = (floor(UV / block) + 0.5) * block;
	}
	vec3 base = mix(color_bottom.rgb, color_top.rgb, uv.y);

	float t = TIME * speed;
	float streak = sin((uv.x + uv.y) * 12.0 - t * 3.0);
	streak = smoothstep(0.85, 1.0, streak) * 0.15;

	float pulse = 0.5 + 0.5 * sin(TIME * 2.0);
	float glow = smoothstep(1.0, 0.0, uv.y) * 0.12 * pulse;

	vec3 col = base + accent_color.rgb * (streak + glow);
	if (color_steps > 0.0) {
		float d = bayer4(cell) - 0.5;
		col = floor(col * color_steps + 0.5 + d) / color_steps;
	}
	COLOR = vec4(col, 1.0);
}
