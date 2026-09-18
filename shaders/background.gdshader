shader_type canvas_item;

// Simple animated gradient background with a subtle moving light streak
// and a soft pulsing glow near the bottom of the screen. Colors are
// exposed as uniforms so you can tweak them from the Inspector without
// touching the shader.

uniform vec4 color_top : source_color = vec4(0.051, 0.027, 0.129, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.165, 0.055, 0.239, 1.0);
uniform vec4 accent_color : source_color = vec4(0.902, 0.133, 0.475, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.35;

void fragment() {
	vec2 uv = UV;
	vec3 base = mix(color_bottom.rgb, color_top.rgb, uv.y);

	float t = TIME * speed;
	float streak = sin((uv.x + uv.y) * 12.0 - t * 3.0);
	streak = smoothstep(0.85, 1.0, streak) * 0.15;

	float pulse = 0.5 + 0.5 * sin(TIME * 2.0);
	float glow = smoothstep(1.0, 0.0, uv.y) * 0.12 * pulse;

	vec3 col = base + accent_color.rgb * (streak + glow);
	COLOR = vec4(col, 1.0);
}
