shader_type spatial;

const float z_near = 0.05;
const float z_far = 4000.0;
uniform sampler2D depth_texture : hint_depth_texture,filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture,filter_nearest;

group_uniforms WaterSetting;
uniform vec3 water_color:source_color = vec3(0.12,0.25,0.32);
uniform vec3 border_color:source_color = vec3(0.4,0.5,0.6);
uniform float border_scale:hint_range(0.9, 0.925, 0.95) = 0.0;
uniform float roughness:hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float specular:hint_range(0.0, 2.0, 0.01) = 0.5;
uniform float fade_distance:hint_range(0.0, 10.0, 0.01) = 5.0;

group_uniforms HeightMap;
uniform sampler2D height_tex:filter_linear;
uniform vec2 move_vec;
uniform float height_strength:hint_range(0.0, 1.0, 0.01) = 0.1;

group_uniforms NormalMap;
uniform sampler2D wave_tex:filter_linear;
uniform vec2 normal_move_vec;
uniform float normal_strength:hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float refraction_value:hint_range(0.0, 0.4, 0.01) = 0.05;

group_uniforms SSRSetting;
uniform int ssr_max_travel = 24;
uniform float step_pixel_size = 6.0;
uniform float depth_tolerance = 0.2;

group_uniforms SplashSetting;
uniform sampler2D simulation;
uniform vec2 collision_size;
uniform vec2 subdivision;
uniform float splash_strength = 1.0;
uniform float depth_clip = 25.0;

vec3 uv_to_view(vec2 uv, float depth, mat4 inv_proj_m)
{
	vec4 position_ndc = vec4((uv * 2.0) - 1.0, depth, 1.0);
	vec4 view_position = inv_proj_m * position_ndc;
	return view_position.xyz / view_position.w;
}
vec3 view_to_uv(vec3 position_view_space, mat4 proj_m, out float w)
{
	vec4 position_clip_space = proj_m * vec4(position_view_space.xyz, 1.0);
	vec3 position_ndc = position_clip_space.xyz / position_clip_space.w;
	w = position_clip_space.w;
	return vec3(position_ndc.xy * 0.5 + 0.5, position_ndc.z);
}

vec4 get_depth_tested_color(vec4 pos, vec4 advance, vec2 viewport_size, mat4 inv_mat){
	vec2 pixel_size = 1.0 / viewport_size;
	vec2 init_pos = pos.xy;
	float z_from = pos.z / pos.w;
	float z_to = z_from;
	vec2 uv;
	float depth;
	for(int i = 0; i < ssr_max_travel; i++)
	{
		pos += advance;
		uv = (pos.xy - 0.5) * pixel_size;
		depth = uv_to_view(uv,texture(depth_texture,uv).r, inv_mat).z;
		
		z_from = z_to;
		z_to = pos.z / pos.w;
		
		if(depth > z_to && depth <= max(z_to, z_from) + depth_tolerance && -depth < z_far * 0.95)
		{
			if (any(bvec4(lessThan(pos.xy, vec2(1.0, 1.0)), greaterThan(pos.xy,viewport_size))) == false) {
			return vec4(texture(screen_texture, (pos.xy-0.5) * pixel_size).rgb,1.0);
			}
		}
	}
	return vec4(0.0);
}

void vertex() {
	mat3 tbn = mat3(TANGENT,BINORMAL,NORMAL);
	
	//Get normal map by Bump map(noise)
	vec2 vertex_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vertex_uv = (vertex_uv * 0.02)+(TIME * 0.03 * move_vec);
	
	float Bu = texture(height_tex,vertex_uv - vec2(0.02,0.0)).y - texture(height_tex, vertex_uv + vec2(0.02,0.0)).y;
	float Bv = texture(height_tex,vertex_uv - vec2(0.0,0.02)).y - texture(height_tex, vertex_uv + vec2(0.0,0.02)).y;
	
	vec3 normal_map = vec3(Bu*height_strength, Bv*height_strength, 1.0);
	float height = (texture(height_tex,vertex_uv).x * 2.0 -1.0) * height_strength;
	
	VERTEX.y += height;
	NORMAL = normalize(tbn*normal_map);
}

void fragment() {
	mat3 tbn = mat3(TANGENT,BINORMAL,NORMAL);
	
	//Set surface normal map(noise)
	vec3 normal_map = texture(wave_tex,UV+(TIME * 0.05 * normal_move_vec)).xyz * 2.0 - 1.0;
	normal_map = vec3(normal_map.xy * normal_strength, 1.0);
	
	//Set splash normal map
	vec2 splash_uv = UV * subdivision;
	splash_uv.y=-splash_uv.y;
	vec2 duv = vec2(1.0 /collision_size.x,1.0 /collision_size.y);
	
	float Bu = texture(simulation,splash_uv - vec2(duv.x,0.0)).y - texture(simulation, splash_uv + vec2(duv.x,0.0)).y;
	float Bv = texture(simulation,splash_uv - vec2(0.0,duv.y)).y - texture(simulation, splash_uv + vec2(0.0,duv.y)).y;
	vec3 bump_vec = -depth_clip < VERTEX.z ? vec3(Bu*splash_strength, Bv*splash_strength, 1.0) : vec3(0.0);
	
	//Apply normal maps
	vec3 normal = normalize(tbn * (normal_map+bump_vec));
	
	vec2 pixel_size = 1.0 / VIEWPORT_SIZE;
	vec3 vertex = VERTEX;
	
	//Calculate SSR line advence
	vec3 view_dir = normalize(vertex);
	vec3 ray_dir = normalize(reflect(view_dir,normal));
	
	float ray_len = (vertex.z + ray_dir.z * z_far) > - z_near ? (-z_near - vertex.z) / ray_dir.z : z_far;
	vec3 ray_end = vertex + ray_dir * ray_len;
	
	float w_begin;
	vec3 vp_line_begin = view_to_uv(vertex,PROJECTION_MATRIX,w_begin);
	float w_end;
	vec3 vp_line_end = view_to_uv(ray_end,PROJECTION_MATRIX,w_end);
	vec2 vp_line_dir = vp_line_end.xy - vp_line_begin.xy;
	
	w_begin = 1.0 / w_begin;
	w_end = 1.0 / w_end;
	
	float z_begin = vertex.z * w_begin;
	float z_end = ray_end.z * w_end;
	
	vec2 line_begin = vp_line_begin.xy / pixel_size;
	vec2 line_dir = vp_line_dir / pixel_size;
	float z_dir = z_end - z_begin;
	float w_dir = w_end - w_begin;
	
	float scale_max_x = min(1.0, 0.99 * (1.0 - vp_line_begin.x) / max(1e-5, vp_line_dir.x));
	float scale_max_y = min(1.0, 0.99 * (1.0 - vp_line_begin.y) / max(1e-5, vp_line_dir.y));
	float scale_min_x = min(1.0, 0.99 * vp_line_begin.x / max(1e-5, -vp_line_dir.x));
	float scale_min_y = min(1.0, 0.99 * vp_line_begin.y / max(1e-5, -vp_line_dir.y));
	float line_clip = min(scale_max_x,scale_max_y) * min(scale_min_x,scale_min_y);
	
	line_dir *= line_clip;
	z_dir *= line_clip;
	w_dir *= line_clip;
	
	float advance_angle_adj = 1.0 / max(abs(normalize(line_dir).x), abs(normalize(line_dir).y));
	float step_size = step_pixel_size / length(line_dir);
	vec4 line_advance = vec4(line_dir, z_dir, w_dir) * advance_angle_adj * step_size;
	vec4 init_pos = vec4(line_begin, z_begin, w_begin);	//calculated SSR line advence
	
	//get SSR
	vec4 reflect_color = get_depth_tested_color(init_pos, line_advance, VIEWPORT_SIZE, INV_PROJECTION_MATRIX);
	float reflect_amount = reflect_color.a * pow(1.0-dot(normal,VIEW),3.0);
	
	//simple normal map refract
	vec2 refract_uv = normal_map.xy * refraction_value;
	float depth_is_back = sign(texture(depth_texture,SCREEN_UV + refract_uv).r-FRAGCOORD.z);
	refract_uv = SCREEN_UV + (clamp(depth_is_back,0.0,1.0) * refract_uv);
	
	vec3 refract_screen_pos = uv_to_view(refract_uv,texture(depth_texture,refract_uv).r, INV_PROJECTION_MATRIX);
	float water_depth = sign(vertex.z - refract_screen_pos.z) * length(vertex - refract_screen_pos);
	water_depth = clamp(water_depth / fade_distance,0.0,1.0);
	water_depth = pow(water_depth, 1.0);
	
	//get refract color
	vec3 refract_color = texture(screen_texture,refract_uv).rgb;
	refract_color = mix(refract_color.rgb*border_color, refract_color.rgb, clamp(water_depth / border_scale,0.5,1.0));
	
	//proximity fade by water depth
	vec3 surface_color = mix(vec3(0.0),water_color,water_depth);
	surface_color = mix(surface_color, vec3(0.0), reflect_amount);
	
	float final_specular = specular * pow(1.0-dot(normal,VIEW),3.0);
	final_specular = mix(final_specular, 0.0, reflect_amount);
	
	vec3 emission = mix(refract_color.rgb,vec3(0.0),water_depth);
	emission = mix(emission, reflect_color.rgb, reflect_amount);

	ALBEDO = surface_color;
	ROUGHNESS = roughness;
	SPECULAR = final_specular;
	NORMAL = normal;
	EMISSION = emission;
}


