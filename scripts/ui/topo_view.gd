class_name TopoView
extends SubViewportContainer
## Interactive 3D topographic map of a battleground: hypsometric tint, depth-shaded sea with shoal
## warnings, contour lines, soft relief, crisp 2D landmark pills, compass and scale bar, and a
## line-of-sight overlay that shows what a spotter (click anywhere) can and cannot see -- i.e. where
## there is cover and concealment. Left-drag orbits, right-drag pans, wheel zooms, click a landmark to fly to it.

signal observer_changed(pos: Vector2)

const N := 129
const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D vis_tex : filter_linear;
uniform float arena = 14000.0;
uniform float show_vis = 1.0;
uniform float land_exag = 3.0;
uniform float sea_exag = 0.15;
varying float vh;
varying vec2 wuv;
varying float up;
void vertex() {
	float y = VERTEX.y;
	vh = y > 0.0 ? y / land_exag : y / sea_exag;
	wuv = VERTEX.xz / arena + 0.5;
	up = NORMAL.y;
}
float line_at(float f, float w) {
	return 1.0 - smoothstep(0.0, w * 1.5, abs(fract(f - 0.5) - 0.5));
}
void fragment() {
	vec3 col;
	float land = 0.0;
	if (vh > 0.6) {
		land = 1.0;
		float t = clamp(vh / 900.0, 0.0, 1.0);
		col = mix(vec3(0.84, 0.78, 0.60), vec3(0.27, 0.50, 0.26), smoothstep(2.0, 22.0, vh));
		col = mix(col, vec3(0.47, 0.56, 0.31), smoothstep(80.0, 260.0, vh));
		col = mix(col, vec3(0.56, 0.50, 0.42), smoothstep(250.0, 520.0, vh));
		col = mix(col, vec3(0.94, 0.95, 0.97), smoothstep(620.0, 980.0, vh));
		float steep = smoothstep(0.80, 0.55, up);
		col = mix(col, vec3(0.42, 0.38, 0.34), steep * 0.75);
	} else {
		float d = max(-vh, 0.0);
		col = mix(vec3(0.42, 0.88, 0.82), vec3(0.14, 0.58, 0.72), smoothstep(2.0, 14.0, d));
		col = mix(col, vec3(0.07, 0.30, 0.55), smoothstep(14.0, 60.0, d));
		col = mix(col, vec3(0.025, 0.10, 0.26), smoothstep(60.0, 200.0, d));
		col = mix(col, vec3(0.80, 0.64, 0.38), (1.0 - smoothstep(1.5, 6.5, d)) * 0.38);
	}
	float interval = vh > 0.0 ? 50.0 : (vh > -60.0 ? 10.0 : 50.0);
	float f = vh / interval;
	float w = fwidth(f) + 0.0008;
	float fade = clamp(1.0 / (w * 45.0), 0.0, 1.0);
	float minor = line_at(f, w) * fade;
	float major = line_at(f / 5.0, w / 5.0) * fade;
	float lk = land > 0.5 ? 0.30 : 0.16;
	col = mix(col, col * 0.35, minor * lk + major * (lk + 0.22));
	float foam = (1.0 - smoothstep(0.0, 1.4, abs(vh + 0.3))) * 0.85;
	col = mix(col, vec3(1.0), foam);
	if (show_vis > 0.5) {
		float v = texture(vis_tex, wuv).r;
		vec3 hid = mix(col, vec3(0.10, 0.05, 0.28), 0.62) * 0.62;
		vec3 vis = mix(col, vec3(1.0, 0.80, 0.30), 0.07) * 1.10;
		float e = 1.0 - smoothstep(0.0, 0.20, abs(v - 0.5));
		col = mix(hid, vis, smoothstep(0.3, 0.7, v)) + vec3(1.0, 0.82, 0.35) * e * 0.35;
	}
	ALBEDO = col;
	ROUGHNESS = land > 0.5 ? 1.0 : 0.55;
	SPECULAR = land > 0.5 ? 0.0 : 0.25;
}
"""

var ground: Dictionary = {}
var vp: SubViewport
var cam: Camera3D
var terrain_mi: MeshInstance3D
var mat: ShaderMaterial
var vis_img: Image
var vis_tex: ImageTexture
var vis_on := true
var observer := Vector2.ZERO
var hs := PackedFloat32Array()
var size_m := Vector2(14000, 14000)
var yaw := 0.0
var pitch := 0.75
var dist := 17000.0
var target := Vector3.ZERO
var overlay: Control
var _drag_start := Vector2.ZERO
var _dragging := false
var _panning := false
var _moved := false
var _pills: Array = []          ## [{rect: Rect2, p: Vector2}] from the last overlay draw
var _view_tween: Tween


func _init() -> void:
	stretch = true
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.045, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.76, 0.86)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.025, 0.045, 0.08)
	env.fog_density = 0.000018
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 150, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.near = 200.0
	cam.far = 120000.0
	cam.fov = 42.0
	vp.add_child(cam)
	overlay = Overlay.new()
	overlay.tv = self
	add_child(overlay)
	resized.connect(func(): overlay.queue_redraw())


func setup(g: Dictionary) -> void:
	ground = g
	size_m = g["size_m"]
	hs = _smooth(_smooth(MapData.grid(g, N)))
	_build_mesh()
	vis_img = Image.create(N, N, false, Image.FORMAT_R8)
	vis_tex = ImageTexture.create_from_image(vis_img)
	mat.set_shader_parameter("vis_tex", vis_tex)
	var sa: Vector3 = g["spawn_a"]
	set_observer(Vector2(sa.x, sa.z), false)
	if OS.get_cmdline_user_args().has("--novis"):
		set_vis_on(false)
	reset_camera()


func _smooth(src: PackedFloat32Array) -> PackedFloat32Array:
	var out := src.duplicate()
	for j in range(1, N - 1):
		for i in range(1, N - 1):
			var k := j * N + i
			out[k] = (src[k] * 4.0 + (src[k - 1] + src[k + 1] + src[k - N] + src[k + N]) * 2.0
				+ src[k - N - 1] + src[k - N + 1] + src[k + N - 1] + src[k + N + 1]) / 16.0
	return out


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vtx: Array[Vector3] = []
	for j in N:
		for i in N:
			vtx.append(Vector3((float(i) / (N - 1) - 0.5) * size_m.x, MapData.exag(hs[j * N + i]), (float(j) / (N - 1) - 0.5) * size_m.y))
	for j in N - 1:
		for i in N - 1:
			var a := vtx[j * N + i]
			var b := vtx[j * N + i + 1]
			var c := vtx[(j + 1) * N + i]
			var d := vtx[(j + 1) * N + i + 1]
			for v in [a, b, c, b, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	terrain_mi = MeshInstance3D.new()
	terrain_mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("arena", size_m.x)
	mat.set_shader_parameter("land_exag", MapData.LAND_EXAG)
	mat.set_shader_parameter("sea_exag", MapData.SEA_EXAG)
	terrain_mi.material_override = mat
	vp.add_child(terrain_mi)


func surface_h(p: Vector2) -> float:
	var fi := clampf((p.x / size_m.x + 0.5) * (N - 1), 0.0, N - 1.001)
	var fj := clampf((p.y / size_m.y + 0.5) * (N - 1), 0.0, N - 1.001)
	var i := int(fi)
	var j := int(fj)
	var tx := fi - i
	var tz := fj - j
	return lerpf(lerpf(hs[j * N + i], hs[j * N + i + 1], tx), lerpf(hs[(j + 1) * N + i], hs[(j + 1) * N + i + 1], tx), tz)


func ground_point(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, maxf(MapData.exag(surface_h(p)), 0.0) + lift, p.y)


func set_vis_on(on: bool) -> void:
	vis_on = on
	mat.set_shader_parameter("show_vis", 1.0 if on else 0.0)
	overlay.queue_redraw()


func set_observer(p: Vector2, announce: bool = true) -> void:
	observer = p
	var bytes := MapData.visibility(hs, N, size_m, p, 25.0, 14.0)
	vis_img = Image.create_from_data(N, N, false, Image.FORMAT_R8, bytes)
	vis_tex.update(vis_img)
	overlay.queue_redraw()
	if announce:
		observer_changed.emit(p)


## Percentage of open water the observer can see (for the info panel).
func exposed_water_pct() -> float:
	var bytes := vis_img.get_data()
	var sea := 0
	var seen := 0
	for k in N * N:
		if hs[k] <= 0.0:
			sea += 1
			if bytes[k] > 127:
				seen += 1
	return 100.0 * seen / maxf(sea, 1)


func reset_camera() -> void:
	_set_view(Vector3.ZERO, size_m.x * 1.2, 0.0, 0.75)


func zoom(f: float) -> void:
	dist = clampf(dist * f, 1500.0, size_m.x * 2.4)
	_apply_cam()


## Smoothly fly the camera to look at a map point.
func focus(p: Vector2) -> void:
	_set_view(ground_point(p, 0.0) * 0.6, minf(dist, size_m.x * 0.35), yaw, pitch)


func _set_view(t: Vector3, d: float, y: float, pt: float) -> void:
	if _view_tween != null and _view_tween.is_valid():
		_view_tween.kill()
	var t0 := target
	var d0 := dist
	var y0 := yaw
	var p0 := pitch
	_view_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_view_tween.tween_method(func(k: float):
		target = t0.lerp(t, k)
		dist = lerpf(d0, d, k)
		yaw = lerp_angle(y0, y, k)
		pitch = lerpf(p0, pt, k)
		_apply_cam(), 0.0, 1.0, 0.55)


func _apply_cam() -> void:
	# yaw 0 looks north (+Z) from the south, so east (-X) is on the right of the screen.
	var d := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	cam.position = target + d * dist
	cam.look_at(target, Vector3.UP)
	overlay.queue_redraw()


func _pick(pos: Vector2) -> Variant:
	var o := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var t := 0.0
	var prev := 0.0
	while t < 90000.0:
		var p := o + dir * t
		if absf(p.x) < size_m.x * 0.5 and absf(p.z) < size_m.y * 0.5:
			if p.y <= maxf(MapData.exag(surface_h(Vector2(p.x, p.z))), 0.0):
				var lo := prev
				var hi := t
				for k in 12:
					var mid := (lo + hi) * 0.5
					var q := o + dir * mid
					if q.y <= maxf(MapData.exag(surface_h(Vector2(q.x, q.z))), 0.0):
						hi = mid
					else:
						lo = mid
				var r := o + dir * hi
				return Vector2(r.x, r.z)
		prev = t
		t += 80.0
	return null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging = true
				_panning = mb.button_index != MOUSE_BUTTON_LEFT
				_moved = false
				_drag_start = mb.position
			else:
				if _dragging and not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
					for pl in _pills:
						if (pl["rect"] as Rect2).grow(4).has_point(mb.position):
							focus(pl["p"])
							_dragging = false
							return
					var hit: Variant = _pick(mb.position)
					if hit != null:
						set_observer(hit)
				_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.88)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.14)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_start) > 6.0:
			_moved = true
		if _moved:
			if _panning:
				var right := cam.global_transform.basis.x
				var fwd := Vector3(cam.global_transform.basis.z.x, 0, cam.global_transform.basis.z.z).normalized()
				var k := dist * 0.0013
				target += (-right * mm.relative.x + fwd * mm.relative.y) * k
				target.x = clampf(target.x, -size_m.x * 0.5, size_m.x * 0.5)
				target.z = clampf(target.z, -size_m.y * 0.5, size_m.y * 0.5)
			else:
				yaw -= mm.relative.x * 0.006
				pitch = clampf(pitch + mm.relative.y * 0.005, 0.12, 1.5)
			_apply_cam()
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.1))


## Crisp 2D layer over the 3D view: landmark pills, spotter marker, legend, compass and scale bar.
class Overlay extends Control:
	var tv: TopoView

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if tv == null or tv.hs.is_empty():
			return
		var fsemi := UIKit.font("semi")
		var fcaps := UIKit.font("caps")
		var rect := Rect2(Vector2.ZERO, size)
		tv._pills.clear()
		var placed: Array[Rect2] = []
		# project waypoints, nearest (lowest on screen) first so the foreground wins declutter
		var items: Array = []
		for wp in Battlegrounds.waypoints(tv.ground["id"]):
			var w3 := tv.ground_point(wp["p"], 10.0)
			if tv.cam.is_position_behind(w3):
				continue
			var sp := tv.cam.unproject_position(w3)
			if not rect.grow(40).has_point(sp):
				continue
			items.append({"wp": wp, "sp": sp})
		items.sort_custom(func(a, b): return a["sp"].y > b["sp"].y)
		for it in items:
			var wp: Dictionary = it["wp"]
			var sp: Vector2 = it["sp"]
			var col := MapData.kind_color(wp["k"])
			var name := String(wp["n"])
			var tw := fsemi.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var pw := tw + 38.0
			var lift := 30.0
			var pr := Rect2(sp.x - pw * 0.5, sp.y - lift - 26.0, pw, 26.0)
			var tries := 0
			while tries < 8:
				var hit := false
				for o in placed:
					if o.grow(3).intersects(pr):
						hit = true
						break
				if not hit:
					break
				pr.position.y -= 30.0
				tries += 1
			placed.append(pr)
			# leader + marker
			draw_line(sp, Vector2(sp.x, pr.end.y), Color(col.r, col.g, col.b, 0.85), 1.6, true)
			draw_circle(sp, 13.0, Color(col.r, col.g, col.b, 0.16))
			draw_circle(sp, 7.5, Color(0, 0, 0, 0.45))
			draw_circle(sp, 6.2, Color(1, 1, 1, 0.97))
			draw_circle(sp, 4.2, col)
			# pill
			var sb := UIKit.box(Color(0.10, 0.14, 0.21, 0.92), Color(0.04, 0.06, 0.10, 0.92), Color(col.r, col.g, col.b, 0.85), 13.0, 0.7, Color(col.r, col.g, col.b, 0.14), 0.0)
			draw_style_box(sb, pr)
			draw_circle(Vector2(pr.position.x + 14, pr.position.y + 13), 4.2, col)
			draw_string(fsemi, Vector2(pr.position.x + 25, pr.position.y + 18.5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.INK)
			tv._pills.append({"rect": pr, "p": wp["p"]})
		# spotter marker
		var o3 := tv.ground_point(tv.observer, 6.0)
		if not tv.cam.is_position_behind(o3):
			var op := tv.cam.unproject_position(o3)
			var amber := Color("ffc44d")
			draw_circle(op, 22.0, Color(amber.r, amber.g, amber.b, 0.14))
			draw_arc(op, 15.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 4.0, true)
			draw_arc(op, 15.0, 0.0, TAU, 40, amber, 2.2, true)
			for a in 4:
				var dv := Vector2.from_angle(a * PI * 0.5)
				draw_line(op + dv * 9.0, op + dv * 24.0, amber, 2.0, true)
			draw_circle(op, 3.0, amber)
			var lab := "SPOTTER"
			var lw := fcaps.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var lr := Rect2(op.x - lw * 0.5 - 8, op.y + 28, lw + 16, 20)
			draw_style_box(UIKit.box(Color(0.25, 0.18, 0.05, 0.9), Color(0.15, 0.10, 0.03, 0.9), Color(amber.r, amber.g, amber.b, 0.8), 10.0, 0.0, Color(0, 0, 0, 0), 0.0), lr)
			draw_string(fcaps, Vector2(lr.position.x + 8, lr.position.y + 14), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, amber)
		_draw_legend(fcaps)
		_draw_compass(fcaps)
		_draw_scale(fsemi)

	func _draw_legend(fcaps: Font) -> void:
		if not tv.vis_on:
			return
		var x := 18.0
		var y := 18.0
		var items := [["EXPOSED TO SPOTTER", Color("ffc44d")], ["CONCEALED", Color("6a4fd6")]]
		var total := 0.0
		for it in items:
			total += fcaps.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 38.0
		var bg := Rect2(x, y, total + 10.0, 32)
		draw_style_box(UIKit.box(Color(0.08, 0.12, 0.19, 0.88), Color(0.04, 0.06, 0.10, 0.88), Color(1, 1, 1, 0.16), 16.0, 0.6, Color(0, 0, 0, 0), 0.0), bg)
		var cx := x + 14.0
		for it in items:
			var c: Color = it[1]
			UIKit.fill_round(self, Rect2(cx, y + 9, 14, 14), 4.0, c.lightened(0.15), c.darkened(0.2))
			draw_string(fcaps, Vector2(cx + 22, y + 20), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.INK)
			cx += fcaps.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 38.0

	func _draw_compass(fcaps: Font) -> void:
		var c := Vector2(size.x - 64, size.y - 64)
		draw_circle(c + Vector2(0, 3), 44.0, Color(0, 0, 0, 0.3))
		draw_circle(c, 42.0, Color(0.08, 0.12, 0.19, 0.88))
		draw_arc(c, 42.0, 0.0, TAU, 48, Color(1, 1, 1, 0.2), 1.4, true)
		var base := tv.target
		var dirs := {"N": Vector3(0, 0, 1), "E": Vector3(-1, 0, 0), "S": Vector3(0, 0, -1), "W": Vector3(1, 0, 0)}
		var p0 := tv.cam.unproject_position(base)
		for k in dirs:
			var p1 := tv.cam.unproject_position(base + (dirs[k] as Vector3) * 2000.0)
			var d := (p1 - p0)
			if d.length() < 0.001:
				continue
			d = d.normalized()
			var col := UIKit.GOLD if k == "N" else UIKit.DIM
			draw_line(c + d * 10.0, c + d * 28.0, col, 2.4 if k == "N" else 1.4, true)
			if k == "N":
				var tip := c + d * 30.0
				var side := Vector2(-d.y, d.x)
				draw_colored_polygon(PackedVector2Array([tip + d * 4.0, tip - d * 6.0 + side * 5.0, tip - d * 6.0 - side * 5.0]), UIKit.GOLD)
			var lp := c + d * 34.0 - Vector2(4, -4)
			if k == "N":
				lp = c + d * 44.0 - Vector2(4, -4)
			draw_string(UIKit.font("semi"), lp, k, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

	func _draw_scale(fsemi: Font) -> void:
		var half := tv.cam.position.distance_to(tv.target) * tan(deg_to_rad(tv.cam.fov * 0.5))
		var mpp := (half * 2.0) / maxf(size.y, 1.0)
		var want := 150.0 * mpp
		var nice := 500.0
		for cand in [200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0]:
			nice = cand
			if cand >= want * 0.7:
				break
		var px := nice / mpp
		var x := 22.0
		var y := size.y - 30.0
		draw_line(Vector2(x, y), Vector2(x + px, y), Color(0, 0, 0, 0.55), 5.0, true)
		draw_line(Vector2(x, y), Vector2(x + px, y), UIKit.INK, 2.2, true)
		draw_line(Vector2(x, y - 7), Vector2(x, y + 7), UIKit.INK, 2.0, true)
		draw_line(Vector2(x + px, y - 7), Vector2(x + px, y + 7), UIKit.INK, 2.0, true)
		var lab := "%d m" % int(nice) if nice < 1000.0 else "%d km" % int(nice / 1000.0)
		draw_string(fsemi, Vector2(x, y - 12), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.INK)
