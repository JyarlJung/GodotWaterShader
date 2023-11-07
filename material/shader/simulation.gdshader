//reference : https://github.com/CBerry22/Godot-Water-Ripple-Simulation-Shader/tree/master
shader_type canvas_item;

uniform sampler2D sim_tex;
uniform sampler2D col_tex;
uniform sampler2D rain_tex;

uniform float phase = 0.3;
uniform float attenuation = 0.996;
uniform float deltaUV = 0.5;

void fragment() {
	float dv = 1.0 / 512.0;
	float du = 1.0 / 512.0;
	vec3 duv = vec3(du, dv, 0) * deltaUV;

	vec3 c = texture(sim_tex, UV).rgb;

	float p = (2.0 * c.r - c.g + phase * (
		texture(sim_tex, fract(1.0 + UV - duv.zy)).r +
		texture(sim_tex, fract(UV + duv.zy)).r +
		texture(sim_tex, fract(1.0 + UV - duv.xz)).r +
		texture(sim_tex, fract(UV + duv.xz)).r - 4.0 * c.r)) * attenuation - 0.0002;
		
	vec2 col_uv = vec2(UV.x, 1.0 - UV.y);
	float col = texture(col_tex, col_uv).r + texture(rain_tex, col_uv).r ;
	float prevCol = texture(sim_tex, UV).b;
	
	if (col > 0.0 && prevCol == 0.0) {
		p += col * 0.5;
	}
	
	if (prevCol > 0.0 && col == 0.0) {
		p -= prevCol * 0.5;
	}

	COLOR = vec4(p, c.r, col, 1);
}
