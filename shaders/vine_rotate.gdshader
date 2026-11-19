shader_type canvas_item;
// Level 1's giant vine, turning slowly. The trunk texture (bg_vine.png)
// gives the outline and bark; wherever it has the plain inner green, the
// leaves and flowers from `surface` (bg_vine_surface.png, the whole way
// round the vine) are wrapped round a cylinder and scrolled, so they slide
// across the front and squash toward the edges like the vine is rotating.
// Works in art pixels, so it stays pixel-crisp.

uniform sampler2D surface : filter_nearest, repeat_enable;
// Size of the trunk texture and of the surface texture, in art pixels.
uniform vec2 trunk_size = vec2(124.0, 216.0);
uniform vec2 surface_size = vec2(352.0, 216.0);
// Middle of the trunk and its radius, in art pixels.
uniform float center_x = 62.0;
uniform float radius = 56.0;
// How fast it turns, in art pixels per second along the surface.
// Negative turns the other way.
uniform float speed = 10.0;
// The trunk's plain inner green (gen_bg.py GREENS[1]).
uniform vec3 fill_color : source_color = vec3(0.157, 0.204, 0.063);
// Darkening near the sides, to make it look round.
uniform float edge_shade = 0.78;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	COLOR = base;
	if (base.a > 0.5 && distance(base.rgb, fill_color) < 0.03) {
		vec2 p = floor(UV * trunk_size);
		float dx = clamp((p.x + 0.5 - center_x) / radius, -0.999, 0.999);
		float u = floor(asin(dx) * radius + TIME * speed);
		float v = mod(p.y, trunk_size.y);
		vec4 s = texture(surface, (vec2(u, v) + 0.5) / surface_size);
		vec3 col = mix(base.rgb, s.rgb, s.a);
		if (abs(dx) > 0.82) {
			col *= edge_shade;
		}
		COLOR = vec4(col, base.a);
	}
}
