class_name SkySea
extends RefCounted
## Shared sky + ocean + lighting for every scene. One call builds a WorldEnvironment with a
## gradient sky, a sun/moon light, matched horizon haze and a shaded ocean plane.
## Presets: "clear" (blue), "hazy" (pale blue-grey), "overcast" (grey), "dawn_overcast", "dusk", "night".

const PRESETS := {
	"clear": {
		"sky_top": Color(0.16, 0.38, 0.74), "sky_horizon": Color(0.66, 0.78, 0.9),
		"sun_color": Color(1.0, 0.96, 0.88), "sun_energy": 1.35, "sun_pitch": -48.0, "sun_yaw": 140.0,
		"ambient_energy": 0.9, "fog": Color(0.66, 0.78, 0.9), "fog_density": 0.00004, "exposure": 1.0,
		"water_deep": Color(0.02, 0.1, 0.17), "water_shallow": Color(0.06, 0.28, 0.34), "chop": 0.7, "sun_spec": 1.0,
	},
	"hazy": {
		"sky_top": Color(0.34, 0.5, 0.7), "sky_horizon": Color(0.72, 0.78, 0.84),
		"sun_color": Color(1.0, 0.95, 0.86), "sun_energy": 1.0, "sun_pitch": -38.0, "sun_yaw": 140.0,
		"ambient_energy": 0.95, "fog": Color(0.72, 0.78, 0.84), "fog_density": 0.00009, "exposure": 1.0,
		"water_deep": Color(0.03, 0.1, 0.15), "water_shallow": Color(0.08, 0.26, 0.3), "chop": 0.8, "sun_spec": 0.7,
	},
	"overcast": {
		"sky_top": Color(0.42, 0.46, 0.5), "sky_horizon": Color(0.66, 0.69, 0.72),
		"sun_color": Color(0.9, 0.92, 0.95), "sun_energy": 0.55, "sun_pitch": -45.0, "sun_yaw": 140.0,
		"ambient_energy": 1.05, "fog": Color(0.62, 0.65, 0.68), "fog_density": 0.00012, "exposure": 1.0,
		"water_deep": Color(0.05, 0.09, 0.12), "water_shallow": Color(0.1, 0.18, 0.2), "chop": 1.0, "sun_spec": 0.15,
	},
	"dawn_overcast": {
		"sky_top": Color(0.36, 0.42, 0.52), "sky_horizon": Color(0.82, 0.76, 0.7),
		"sun_color": Color(1.0, 0.82, 0.62), "sun_energy": 0.9, "sun_pitch": -9.0, "sun_yaw": 100.0,
		"ambient_energy": 0.9, "fog": Color(0.7, 0.7, 0.72), "fog_density": 0.00006, "exposure": 1.0,
		"water_deep": Color(0.04, 0.09, 0.13), "water_shallow": Color(0.09, 0.17, 0.2), "chop": 0.8, "sun_spec": 0.8,
	},
	"dusk": {
		"sky_top": Color(0.1, 0.14, 0.3), "sky_horizon": Color(0.85, 0.5, 0.32),
		"sun_color": Color(1.0, 0.55, 0.3), "sun_energy": 0.8, "sun_pitch": -5.0, "sun_yaw": 250.0,
		"ambient_energy": 0.55, "fog": Color(0.55, 0.4, 0.38), "fog_density": 0.00008, "exposure": 1.0,
		"water_deep": Color(0.02, 0.05, 0.09), "water_shallow": Color(0.05, 0.1, 0.14), "chop": 0.7, "sun_spec": 1.0,
	},
	"night": {
		"sky_top": Color(0.01, 0.02, 0.05), "sky_horizon": Color(0.06, 0.09, 0.16),
		"sun_color": Color(0.6, 0.7, 1.0), "sun_energy": 0.35, "sun_pitch": -35.0, "sun_yaw": 140.0,
		"ambient_energy": 0.7, "fog": Color(0.05, 0.07, 0.12), "fog_density": 0.00012, "exposure": 1.0,
		"water_deep": Color(0.01, 0.02, 0.05), "water_shallow": Color(0.02, 0.05, 0.09), "chop": 0.9, "sun_spec": 0.3,
	},
}

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 deep_color : source_color;
uniform vec3 shallow_color : source_color;
uniform vec3 sky_color : source_color;
uniform vec3 horizon_color : source_color;
uniform float chop = 0.8;
uniform float sun_spec = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Sum of directional waves; returns the surface gradient (dh/dx, dh/dz).
vec2 wave_grad(vec2 p, float t, float detail) {
	vec2 g = vec2(0.0);
	// direction.xy, wavenumber, amplitude, speed
	vec4 w0 = vec4(0.92, 0.38, 0.045, 0.55);
	vec4 w1 = vec4(-0.4, 0.92, 0.07, 0.34);
	vec4 w2 = vec4(0.7, -0.7, 0.11, 0.22);
	vec4 w3 = vec4(0.1, 1.0, 0.19, 0.12);
	vec4 w4 = vec4(-0.95, 0.3, 0.33, 0.07);
	vec4 w5 = vec4(0.5, 0.86, 0.6, 0.04);
	vec4 ws[6] = vec4[6](w0, w1, w2, w3, w4, w5);
	for (int i = 0; i < 6; i++) {
		vec2 d = normalize(ws[i].xy);
		float k = ws[i].z;
		float a = ws[i].w;
		float fade = (i >= 3) ? detail : 1.0;
		float ph = dot(d, p) * k + t * sqrt(k * 9.81);
		g += d * cos(ph) * k * a * fade;
	}
	return g;
}

void fragment() {
	vec3 V = normalize(VIEW);
	float dist = length(wpos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float detail = clamp(1.0 - dist / 700.0, 0.0, 1.0);        // fine ripples fade with distance (anti-aliasing)
	vec2 g = wave_grad(wpos.xz, TIME, detail) * chop * 2.2;
	g *= 1.0 / (1.0 + 0.6 * length(g));
	vec2 pr = mat2(vec2(0.62, 0.78), vec2(-0.78, 0.62)) * wpos.xz;       // rotated copy breaks up the regular grid
	g += wave_grad(pr * 1.7 + 31.0, TIME * 1.3, detail) * 0.3 * chop;
	g += wave_grad(mat2(vec2(-0.34, 0.94), vec2(-0.94, -0.34)) * wpos.xz * 3.7 + 7.0, TIME * 1.7, detail) * 0.1 * chop;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	// to view space for NORMAL
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float ndv = clamp(dot(n_world, normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz)), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	// Reflection colour: blend toward the horizon haze at grazing angles.
	vec3 refl = mix(sky_color, horizon_color, pow(1.0 - ndv, 2.0));
	float depth_mix = 0.35 + 0.65 * ndv;
	vec3 body = mix(deep_color, shallow_color, depth_mix * 0.45 * (0.5 + 0.5 * g.x * 2.0));
	ALBEDO = body;
	EMISSION = refl * fres * 0.85;
	ROUGHNESS = clamp(0.22 + 0.2 * (1.0 - detail), 0.2, 0.45);
	SPECULAR = 0.5 * sun_spec;
	METALLIC = 0.0;
	ALPHA = mix(0.9, 1.0, fres);
	// whitecaps on the steepest crests
	float crest = smoothstep(0.55, 1.0, length(g) * 1.2) * detail;
	ALBEDO = mix(ALBEDO, vec3(0.85, 0.9, 0.92), crest * 0.5);
}
"""


## Builds the sky, light and sea under `parent`. Returns {sun, env, sea, preset}.
static func build(parent: Node3D, preset_name: String, sea_size: Vector2, shadows: bool = true) -> Dictionary:
	var p: Dictionary = PRESETS.get(preset_name, PRESETS["clear"])

	var sun := DirectionalLight3D.new()
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sun.rotation_degrees = Vector3(p["sun_pitch"], p["sun_yaw"], 0.0)
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 2500.0
	parent.add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = p["sky_top"]
	sky_mat.sky_horizon_color = p["sky_horizon"]
	sky_mat.sky_curve = 0.18
	sky_mat.ground_horizon_color = (p["sky_horizon"] as Color).lerp(p["water_deep"], 0.35)
	sky_mat.ground_bottom_color = p["water_deep"]
	sky_mat.ground_curve = 0.02
	sky_mat.sun_angle_max = 18.0 if preset_name != "overcast" else 40.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = p["ambient_energy"]
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = p["exposure"]
	e.tonemap_white = 6.0
	e.fog_enabled = true
	e.fog_light_color = p["fog"]
	e.fog_density = p["fog_density"]
	e.fog_sky_affect = 0.6
	var we := WorldEnvironment.new()
	we.environment = e
	parent.add_child(we)

	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = sea_size
	sea.mesh = pm
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("deep_color", p["water_deep"])
	m.set_shader_parameter("shallow_color", p["water_shallow"])
	m.set_shader_parameter("sky_color", p["sky_top"])
	m.set_shader_parameter("horizon_color", p["sky_horizon"])
	m.set_shader_parameter("chop", p["chop"])
	m.set_shader_parameter("sun_spec", p["sun_spec"])
	sea.material_override = m
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sea)

	return {"sun": sun, "env": e, "sea": sea, "preset": preset_name}


## Picks a preset from time of day (hours), the battleground's weather tag and visibility.
static func preset_for(time_of_day: float, weather: String, visibility_m: float) -> String:
	var day := clampf(sin((time_of_day - 6.0) / 12.0 * PI), 0.0, 1.0)
	if day < 0.08:
		return "night"
	if day < 0.3:
		return "dusk" if time_of_day > 12.0 else "dawn_overcast"
	match weather:
		"overcast", "snow", "rain", "fog":
			return "overcast"
		"haze":
			return "hazy"
	if visibility_m < 6000.0:
		return "overcast"
	return "clear"
