shader_type canvas_item;

uniform sampler2D simulation;

void fragment() {
	COLOR = texture(simulation,UV);
}