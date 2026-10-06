class_name TrackProjection
extends MeshInstance3D
## A ribbon laid on the water showing where the ship will go over the next 200 yards, bent by the
## ORDERED helm and engine call (once they are answered) using the same turning model as
## Ship._move. Ticks every 50 yards. When going astern it projects from the stern.

const YARD := 0.9144
const LENGTH_M := 200.0 * YARD
const SEGMENTS := 28
const HALF_WIDTH := 5.0
const COLOR := Color(0.30, 0.86, 0.90)

var _mat: StandardMaterial3D


func _init() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = false
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## `ordered_rudder` is the helm order (-1..1); `ordered_throttle` the engine order (-0.3..1).
func update_for(ship: Ship, ordered_rudder: float, ordered_throttle: float) -> void:
	if ship == null or ship.sunk:
		mesh = null
		return
	# Speed the ship is heading for: the ordered one, or what she still carries if the order is STOP.
	var ordered_speed := ordered_throttle * ship.max_speed_ms * ship.propulsion_fraction()
	var vel := ordered_speed if absf(ordered_throttle) > 0.01 else ship.speed_ms
	var reverse := vel < -0.3
	var dir_sign := -1.0 if reverse else 1.0
	var h := ship.heading
	var pos := Vector2(ship.global_position.x, ship.global_position.z) + Vector2(sin(h), cos(h)) * dir_sign * ship.wlen() * 0.5
	var speed := maxf(absf(vel), 1.0)
	var speed_factor := clampf(absf(vel) / maxf(ship.max_speed_ms, 0.01), 0.0, 1.0)
	var steer := ordered_rudder * ship.steering_fraction()
	var dpsi_dt := steer * ship.turn_rate_rad * ship.handling_fraction() * speed_factor * signf(vel if vel != 0.0 else 1.0)
	var ds := LENGTH_M / SEGMENTS
	var pts: Array[Vector2] = [pos]
	var tangents: Array[Vector2] = []
	for i in SEGMENTS:
		var fwd := Vector2(sin(h), cos(h)) * dir_sign
		tangents.append(fwd)
		pos += fwd * ds
		h += dpsi_dt * (ds / speed)
		pts.append(pos)
	tangents.append(tangents[tangents.size() - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 1.6
	for i in SEGMENTS:
		var a := 0.85 - 0.5 * float(i) / SEGMENTS
		var c := Color(COLOR.r, COLOR.g, COLOR.b, a)
		var na := Vector2(-tangents[i].y, tangents[i].x) * HALF_WIDTH
		var nb := Vector2(-tangents[i + 1].y, tangents[i + 1].x) * HALF_WIDTH
		var p0 := Vector3(pts[i].x + na.x, y, pts[i].y + na.y)
		var p1 := Vector3(pts[i].x - na.x, y, pts[i].y - na.y)
		var p2 := Vector3(pts[i + 1].x - nb.x, y, pts[i + 1].y - nb.y)
		var p3 := Vector3(pts[i + 1].x + nb.x, y, pts[i + 1].y + nb.y)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.set_color(c)
			st.add_vertex(v)
	# Range ticks every 50 yards (the last one, at 200, is brighter and wider).
	for k in range(1, 5):
		var idx := int(round(float(SEGMENTS) * k / 4.0))
		var tg := tangents[mini(idx, tangents.size() - 1)]
		var nrm := Vector2(-tg.y, tg.x)
		var hw := 7.0 if k == 4 else 5.0
		var len2 := 1.4
		var cc := Color(1.0, 1.0, 1.0, 0.95 if k == 4 else 0.7)
		var c0 := pts[idx] + nrm * hw
		var c1 := pts[idx] - nrm * hw
		var c2 := c1 + tg * len2
		var c3 := c0 + tg * len2
		for v2 in [c0, c1, c2, c0, c2, c3]:
			st.set_color(cc)
			st.add_vertex(Vector3(v2.x, y + 0.05, v2.y))
	mesh = st.commit()
	global_transform = Transform3D.IDENTITY
