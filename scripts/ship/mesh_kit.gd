class_name MeshKit
extends RefCounted
## Small procedural-modelling toolkit: accumulates flat-shaded, vertex-coloured solids (boxes,
## tapered and raked blocks, cylinders, cones, lofted prisms) into one ArrayMesh. A transform can be
## pushed so a part (a gun barrel, a raked mast leg) can be built upright and then tilted.

var st := SurfaceTool.new()
var xf := Transform3D.IDENTITY
var _stack: Array[Transform3D] = []
var tris := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t


func pop() -> void:
	xf = _stack.pop_back()


func commit() -> ArrayMesh:
	return st.commit()


## One triangle, wound so its front faces `outward`; flat normal.
func tri(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var n := (pb - pa).cross(pc - pa)
	if n.length_squared() < 1e-12:
		return
	var o := xf.basis * outward
	if n.dot(o) > 0.0:
		var t := pb
		pb = pc
		pc = t
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(pa)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(pb)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(pc)
	tris += 1


## A planar quad a-b-c-d (any winding); `centre` is a point inside the solid (to decide the outside).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3, col: Color) -> void:
	var out := (a + b + c + d) * 0.25 - centre
	tri(a, b, c, out, col)
	tri(a, c, d, out, col)


## Axis-aligned box.
func box(c: Vector3, half: Vector3, col: Color, top_col: Color = Color(0, 0, 0, 0)) -> void:
	var h := half
	var tc := col if top_col.a == 0.0 else top_col
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	quad(p[4], p[5], p[6], p[7], c, tc)      # top
	quad(p[0], p[1], p[2], p[3], c, col)     # bottom
	quad(p[0], p[1], p[5], p[4], c, col)     # aft
	quad(p[3], p[2], p[6], p[7], c, col)     # fore
	quad(p[0], p[3], p[7], p[4], c, col)     # starboard
	quad(p[1], p[2], p[6], p[5], c, col)     # port


## A block between a bottom rectangle and a smaller/shifted top rectangle (a rake, a taper, a sloped face).
## Bottom/top are centred at (cx, y, cz) with half-sizes (hx, hz); zb/zt give separate aft/fore edges.
func block(y0: float, y1: float, bot: Rect2, top: Rect2, col: Color, top_col: Color = Color(0, 0, 0, 0)) -> void:
	## Rect2: position = (x_min, z_min), size = (x_extent, z_extent)
	var tc := col if top_col.a == 0.0 else top_col
	var b0 := Vector3(bot.position.x, y0, bot.position.y)
	var b1 := Vector3(bot.end.x, y0, bot.position.y)
	var b2 := Vector3(bot.end.x, y0, bot.end.y)
	var b3 := Vector3(bot.position.x, y0, bot.end.y)
	var t0 := Vector3(top.position.x, y1, top.position.y)
	var t1 := Vector3(top.end.x, y1, top.position.y)
	var t2 := Vector3(top.end.x, y1, top.end.y)
	var t3 := Vector3(top.position.x, y1, top.end.y)
	var c := (b0 + b2 + t0 + t2) * 0.25
	quad(t0, t1, t2, t3, c, tc)
	quad(b0, b1, b2, b3, c, col)
	quad(b0, b1, t1, t0, c, col)
	quad(b3, b2, t2, t3, c, col)
	quad(b0, b3, t3, t0, c, col)
	quad(b1, b2, t2, t1, c, col)


## Upright elliptical cylinder / cone frustum from y0 to y1; the top ring can be shifted along z (rake).
func cyl(centre: Vector3, r0: Vector2, r1: Vector2, h: float, seg: int, col: Color, top_shift: Vector3 = Vector3.ZERO,
		cap_top: bool = true, cap_col: Color = Color(0, 0, 0, 0)) -> void:
	var cc := col if cap_col.a == 0.0 else cap_col
	var top_c := centre + Vector3(0, h, 0) + top_shift
	var prev_b := centre + Vector3(r0.x, 0, 0)
	var prev_t := top_c + Vector3(r1.x, 0, 0)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / seg
		var cb := centre + Vector3(cos(a) * r0.x, 0, sin(a) * r0.y)
		var ct := top_c + Vector3(cos(a) * r1.x, 0, sin(a) * r1.y)
		var ac := (a + TAU * float(i - 1) / seg) * 0.5
		var out := Vector3(cos(ac), 0, sin(ac))
		tri(prev_b, cb, ct, out, col)
		tri(prev_b, ct, prev_t, out, col)
		if cap_top and r1.x > 0.0:
			tri(top_c, prev_t, ct, Vector3.UP, cc)
		prev_b = cb
		prev_t = ct


## Cylinder along +Z (a gun barrel, a torpedo tube): from z0 to z1 at (x, y), radii at each end.
func tube(x: float, y: float, z0: float, z1: float, r0: float, r1: float, seg: int, col: Color) -> void:
	var prev0 := Vector3(x + r0, y, z0)
	var prev1 := Vector3(x + r1, y, z1)
	var c0 := Vector3(x, y, z0)
	var c1 := Vector3(x, y, z1)
	for i in range(1, seg + 1):
		var a := TAU * float(i) / seg
		var p0 := Vector3(x + cos(a) * r0, y + sin(a) * r0, z0)
		var p1 := Vector3(x + cos(a) * r1, y + sin(a) * r1, z1)
		var ac := (a + TAU * float(i - 1) / seg) * 0.5
		var out := Vector3(cos(ac), sin(ac), 0)
		tri(prev0, p0, p1, out, col)
		tri(prev0, p1, prev1, out, col)
		tri(c1, prev1, p1, Vector3(0, 0, 1), col)
		tri(c0, prev0, p0, Vector3(0, 0, -1), col)
		prev0 = p0
		prev1 = p1


## Cylinder along X (a yardarm, a rangefinder): from x0 to x1 at (y, z).
func tube_x(y: float, z: float, x0: float, x1: float, r: float, seg: int, col: Color) -> void:
	push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))      # local +Z -> world +X, local +X -> world -Z
	tube(-z, y, x0, x1, r, r, seg, col)
	pop()


## A thin slab between two points (a rail, a strut, a stay), with a square section of side `w`.
func strut(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		return
	var z := d / l
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	push(Transform3D(Basis(x, y, z), (a + b) * 0.5))
	box(Vector3.ZERO, Vector3(w * 0.5, w * 0.5, l * 0.5), col)
	pop()
