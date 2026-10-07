class_name SkySea
extends RefCounted
## Shared sky + ocean + lighting for every scene. One call builds a WorldEnvironment with a
## gradient sky, a sun/moon light, matched horizon haze and a shaded ocean plane.
## Presets: "clear" (blue), "hazy" (pale blue-grey), "overcast" (grey), "dawn_overcast", "dusk", "night".

const PRESETS := {
	"clear": {
		"cloud_cover": 0.52, "cloud_dark": 0.4, "stars": 0.0,
		"sky_top": Color(0.08, 0.27, 0.68), "sky_horizon": Color(0.66, 0.78, 0.9),
		"sun_color": Color(1.0, 0.96, 0.88), "sun_energy": 1.35, "sun_pitch": -48.0, "sun_yaw": 140.0,
		"ambient_energy": 0.9, "fog": Color(0.66, 0.78, 0.9), "fog_density": 0.00004, "exposure": 1.0,
		"water_deep": Color(0.02, 0.1, 0.17), "water_shallow": Color(0.06, 0.28, 0.34), "chop": 0.7, "sun_spec": 1.0,
	},
	"hazy": {
		"cloud_cover": 0.62, "cloud_dark": 0.3, "stars": 0.0,
		"sky_top": Color(0.34, 0.5, 0.7), "sky_horizon": Color(0.72, 0.78, 0.84),
		"sun_color": Color(1.0, 0.95, 0.86), "sun_energy": 1.0, "sun_pitch": -38.0, "sun_yaw": 140.0,
		"ambient_energy": 0.95, "fog": Color(0.72, 0.78, 0.84), "fog_density": 0.00009, "exposure": 1.0,
		"water_deep": Color(0.03, 0.1, 0.15), "water_shallow": Color(0.08, 0.26, 0.3), "chop": 0.8, "sun_spec": 0.7,
	},
	"overcast": {
		"cloud_cover": 0.92, "cloud_dark": 0.38, "stars": 0.0,
		"sky_top": Color(0.42, 0.46, 0.5), "sky_horizon": Color(0.66, 0.69, 0.72),
		"sun_color": Color(0.9, 0.92, 0.95), "sun_energy": 0.55, "sun_pitch": -45.0, "sun_yaw": 140.0,
		"ambient_energy": 1.05, "fog": Color(0.62, 0.65, 0.68), "fog_density": 0.00012, "exposure": 1.0,
		"water_deep": Color(0.05, 0.09, 0.12), "water_shallow": Color(0.1, 0.18, 0.2), "chop": 1.0, "sun_spec": 0.15,
	},
	"dawn_overcast": {
		"cloud_cover": 0.82, "cloud_dark": 0.3, "stars": 0.0,
		"sky_top": Color(0.36, 0.42, 0.52), "sky_horizon": Color(0.82, 0.76, 0.7),
		"sun_color": Color(1.0, 0.82, 0.62), "sun_energy": 0.9, "sun_pitch": -9.0, "sun_yaw": 100.0,
		"ambient_energy": 0.9, "fog": Color(0.7, 0.7, 0.72), "fog_density": 0.00006, "exposure": 1.0,
		"water_deep": Color(0.04, 0.09, 0.13), "water_shallow": Color(0.09, 0.17, 0.2), "chop": 0.8, "sun_spec": 0.8,
	},
	"dusk": {
		"cloud_cover": 0.62, "cloud_dark": 0.35, "stars": 0.25,
		"sky_top": Color(0.1, 0.14, 0.3), "sky_horizon": Color(0.85, 0.5, 0.32),
		"sun_color": Color(1.0, 0.55, 0.3), "sun_energy": 0.8, "sun_pitch": -5.0, "sun_yaw": 250.0,
		"ambient_energy": 0.55, "fog": Color(0.55, 0.4, 0.38), "fog_density": 0.00008, "exposure": 1.0,
		"water_deep": Color(0.02, 0.05, 0.09), "water_shallow": Color(0.05, 0.1, 0.14), "chop": 0.7, "sun_spec": 1.0,
	},
	"night": {
		"cloud_cover": 0.45, "cloud_dark": 0.3, "stars": 1.0,
		"sky_top": Color(0.015, 0.03, 0.08), "sky_horizon": Color(0.11, 0.16, 0.27),
		"sun_color": Color(0.6, 0.7, 1.0), "sun_energy": 1.5, "sun_pitch": -35.0, "sun_yaw": 140.0,
		"ambient_energy": 1.25, "fog": Color(0.05, 0.07, 0.12), "fog_density": 0.00012, "exposure": 1.0,
		"water_deep": Color(0.01, 0.02, 0.05), "water_shallow": Color(0.02, 0.05, 0.09), "chop": 0.9, "sun_spec": 0.3,
	},
}


const SKY_SHADER := """
shader_type sky;

uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 ground_color : source_color;
uniform vec3 cloud_light : source_color;
uniform float cloud_cover = 0.4;
uniform float cloud_dark = 0.3;
uniform float stars = 0.0;
uniform float sun_disc = 1.0;
uniform float wind = 0.004;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.62));
	} else {
		col = mix(horizon_color, ground_color, pow(clamp(-h * 3.0, 0.0, 1.0), 0.5));
	}

	// Stars, fading in only where the sky is dark.
	if (stars > 0.0 && h > 0.0) {
		vec3 sp = floor(dir * 260.0);
		float s = step(0.9975, hash31(sp));
		col += vec3(s) * stars * smoothstep(0.02, 0.25, h) * (0.4 + 0.6 * hash31(sp + 3.0));
	}

	// Clouds projected on a flat layer; thin out and fade toward the horizon.
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.09) * 0.55 + vec2(TIME * wind, TIME * wind * 0.35);
		float n = fbm(uv);
		float lo = 1.0 - cloud_cover;
		float c = smoothstep(lo, lo + 0.28, n);
		float sun_side = 0.0;
		if (LIGHT0_ENABLED) {
			float n2 = fbm(uv + LIGHT0_DIRECTION.xz * 0.06);
			sun_side = clamp((n - n2) * 5.0 + 0.5, 0.0, 1.0);
		}
		vec3 ccol = mix(cloud_light * (1.0 - cloud_dark), cloud_light, sun_side);
		ccol = mix(ccol, cloud_light * (1.0 - cloud_dark * 1.4), smoothstep(0.55, 1.0, n) * 0.6);
		float fade = smoothstep(0.0, 0.22, h);
		col = mix(col, ccol, c * fade);
	}

	// Sun / moon disc and glow.
	if (LIGHT0_ENABLED) {
		float sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (pow(sd, 1500.0) * 30.0 * sun_disc + pow(sd, 10.0) * 0.12 + pow(sd, 3.0) * 0.03);
	}
	COLOR = col;
}
"""

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
	ROUGHNESS = clamp(0.32 + 0.2 * (1.0 - detail), 0.3, 0.55);
	SPECULAR = 0.3 * sun_spec;
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
	if MobileMode.phone:
		shadows = false          # sun shadow pass is too costly on phone GPUs

	var sun := DirectionalLight3D.new()
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sun.rotation_degrees = Vector3(p["sun_pitch"], p["sun_yaw"], 0.0)
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 2500.0
	parent.add_child(sun)

	var cover: float = float(p.get("cloud_cover", 0.4))
	var sky_mat := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = SKY_SHADER
	sky_mat.shader = ssh
	var light_scale: float = 1.0
	if preset_name == "night":
		light_scale = 0.10
	elif preset_name == "dusk":
		light_scale = 0.55
	sky_mat.set_shader_parameter("top_color", p["sky_top"])
	sky_mat.set_shader_parameter("horizon_color", p["sky_horizon"])
	sky_mat.set_shader_parameter("ground_color", (p["sky_horizon"] as Color).lerp(p["water_deep"], 0.5))
	sky_mat.set_shader_parameter("cloud_light", ((p["sky_horizon"] as Color).lerp(Color.WHITE, 0.8)) * light_scale)
	sky_mat.set_shader_parameter("cloud_cover", cover)
	sky_mat.set_shader_parameter("cloud_dark", float(p.get("cloud_dark", 0.3)))
	sky_mat.set_shader_parameter("stars", float(p.get("stars", 0.0)))
	sky_mat.set_shader_parameter("sun_disc", 0.0 if preset_name == "overcast" else 1.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if MobileMode.phone else Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL      # clouds drift slowly: refresh the reflection cubemap a face at a time

	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = p["ambient_energy"]
	if preset_name == "night":
		# A dark sky gives almost no ambient light, so give night a moonlit blue fill.
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.30, 0.38, 0.58)
		e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = p["exposure"]
	e.tonemap_white = 6.0
	e.fog_enabled = true
	e.fog_light_color = p["fog"]
	e.fog_density = p["fog_density"]
	e.fog_sky_affect = 0.08
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
	sea.sorting_offset = -100000.0    # draw the sea first so foam, wakes and spray render over it
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
