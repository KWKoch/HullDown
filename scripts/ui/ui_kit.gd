class_name UIKit
extends RefCounted
## Shared look for the menu: Inter fonts, rounded gradient style boxes with soft shadows and glows,
## a global Theme, and a backdrop. Everything is drawn anti-aliased so edges stay crisp at any scale.

const GOLD := Color("f6b93b")
const CYAN := Color("4cc9f0")
const GREEN := Color("4ade80")
const RED := Color("fb6a5e")
const INK := Color("e9eff8")
const DIM := Color("8fa3bd")

static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"semi":
			f = load("res://assets/fonts/Inter-SemiBold.otf")
		"head":
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/fonts/InterDisplay-ExtraBold.otf")
			fv.spacing_glyph = 1
			f = fv
		"caps":
			var fv2 := FontVariation.new()
			fv2.base_font = load("res://assets/fonts/Inter-SemiBold.otf")
			fv2.spacing_glyph = 2
			f = fv2
		_:
			f = load("res://assets/fonts/Inter-Medium.otf")
	_fonts[kind] = f
	return f


## Rounded-rectangle outline points (clockwise from top-left).
static func rrect(r: Rect2, rad: float, seg: int = 8) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	if rad <= 0.5:
		pts.append(r.position)
		pts.append(Vector2(r.end.x, r.position.y))
		pts.append(r.end)
		pts.append(Vector2(r.position.x, r.end.y))
		return pts
	var cs := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for c in 4:
		for k in seg + 1:
			var a := -PI * 0.5 + (c + float(k) / seg) * PI * 0.5
			pts.append(cs[c] + Vector2(cos(a), sin(a)) * rad)
	return pts


class GradBox extends StyleBox:
	var top := Color(0.13, 0.18, 0.27, 0.92)
	var bottom := Color(0.07, 0.10, 0.16, 0.92)
	var border_top := Color(1, 1, 1, 0.16)
	var border_bottom := Color(1, 1, 1, 0.04)
	var border_w := 1.3
	var radius := 14.0
	var shadow := 0.0              ## 0..1 strength of the drop shadow
	var glow := Color(0, 0, 0, 0)  ## outer glow colour (alpha = strength)

	func _draw(ci: RID, rect: Rect2) -> void:
		if shadow > 0.0:
			for k in range(1, 8):
				var g := rect.grow(k * 2.5)
				g.position.y += 7.0
				var pts := UIKit.rrect(g, radius + k * 2.5, 6)
				var cols := PackedColorArray()
				cols.resize(pts.size())
				cols.fill(Color(0, 0, 0, shadow * 0.055 * (8 - k) / 7.0))
				RenderingServer.canvas_item_add_polygon(ci, pts, cols)
		if glow.a > 0.0:
			for k in range(1, 8):
				var g2 := rect.grow(k * 2.0)
				var pts2 := UIKit.rrect(g2, radius + k * 2.0, 6)
				var cols2 := PackedColorArray()
				cols2.resize(pts2.size())
				cols2.fill(Color(glow.r, glow.g, glow.b, glow.a * 0.09 * (8 - k) / 7.0))
				RenderingServer.canvas_item_add_polygon(ci, pts2, cols2)
		var outline := UIKit.rrect(rect, radius, 8)
		var fill := PackedColorArray()
		var edge := PackedColorArray()
		for p in outline:
			var t := clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
			fill.append(top.lerp(bottom, t))
			edge.append(border_top.lerp(border_bottom, t))
		RenderingServer.canvas_item_add_polygon(ci, outline, fill)
		# soft sheen across the upper third
		if top.a > 0.05 and rect.size.y > 30.0:
			var sh := Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2, rect.size.y * 0.38))
			var sp := UIKit.rrect(sh, maxf(radius - 1.0, 0.0), 6)
			var sc := PackedColorArray()
			for p2 in sp:
				var tt := clampf((p2.y - sh.position.y) / maxf(sh.size.y, 1.0), 0.0, 1.0)
				sc.append(Color(1, 1, 1, 0.055 * (1.0 - tt)))
			RenderingServer.canvas_item_add_polygon(ci, sp, sc)
		if border_w > 0.0:
			var loop := outline.duplicate()
			loop.append(outline[0])
			edge.append(edge[0])
			RenderingServer.canvas_item_add_polyline(ci, loop, edge, border_w, true)


static func box(top: Color, bottom: Color, border: Color = Color(1, 1, 1, 0.14), radius: float = 14.0,
		shadow: float = 0.0, glow: Color = Color(0, 0, 0, 0), margin: float = 12.0) -> GradBox:
	var b := GradBox.new()
	b.top = top
	b.bottom = bottom
	b.border_top = border
	b.border_bottom = Color(border.r, border.g, border.b, border.a * 0.3)
	b.radius = radius
	b.shadow = shadow
	b.glow = glow
	b.set_content_margin_all(margin)
	return b


static func glass(radius: float = 16.0, shadow: float = 0.7) -> GradBox:
	return box(Color(0.12, 0.17, 0.26, 0.90), Color(0.055, 0.08, 0.13, 0.93), Color(1, 1, 1, 0.17), radius, shadow)


static func button_box(accent: Color, state: String) -> GradBox:
	match state:
		"hover":
			return box(accent.darkened(0.25).lerp(Color(0.2, 0.26, 0.36), 0.5), accent.darkened(0.55).lerp(Color(0.1, 0.14, 0.2), 0.5),
				Color(accent.r, accent.g, accent.b, 0.85), 12.0, 0.4, Color(accent.r, accent.g, accent.b, 0.55), 12.0)
		"pressed":
			return box(accent.darkened(0.55), accent.darkened(0.7), Color(accent.r, accent.g, accent.b, 0.9), 12.0, 0.0, Color(0, 0, 0, 0), 12.0)
		"disabled":
			return box(Color(0.10, 0.12, 0.16, 0.8), Color(0.07, 0.085, 0.11, 0.8), Color(1, 1, 1, 0.07), 12.0, 0.0, Color(0, 0, 0, 0), 12.0)
	return box(Color(0.17, 0.23, 0.33, 0.95), Color(0.09, 0.12, 0.19, 0.95), Color(accent.r, accent.g, accent.b, 0.45), 12.0, 0.45, Color(0, 0, 0, 0), 12.0)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	# option buttons / popups
	for st in ["normal", "hover", "pressed", "focus"]:
		var b := button_box(CYAN, "normal" if st == "normal" else ("hover" if st == "hover" else "pressed"))
		if st == "focus":
			b = box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(CYAN.r, CYAN.g, CYAN.b, 0.8), 12.0, 0.0, Color(0, 0, 0, 0), 10.0)
		t.set_stylebox(st, "OptionButton", b)
	t.set_color("font_color", "OptionButton", INK)
	t.set_font("font", "OptionButton", font("semi"))
	t.set_stylebox("panel", "PopupMenu", box(Color(0.1, 0.14, 0.21, 0.98), Color(0.06, 0.09, 0.14, 0.98), Color(1, 1, 1, 0.2), 12.0, 0.8, Color(0, 0, 0, 0), 8.0))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.25, 0.33, 0.47, 0.9), Color(0.2, 0.27, 0.4, 0.9), Color(0, 0, 0, 0), 8.0, 0.0, Color(0, 0, 0, 0), 6.0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# slim scrollbars
	var track := box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 5.0, 0.0, Color(0, 0, 0, 0), 4.0)
	var grab := box(Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 5.0, 0.0, Color(0, 0, 0, 0), 4.0)
	var grab_h := box(Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.38), Color(0, 0, 0, 0), 5.0, 0.0, Color(0, 0, 0, 0), 4.0)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, track)
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab_h)
		t.set_stylebox("grabber_pressed", sb, grab_h)
	return t


## Full-screen backdrop: deep gradient, two soft colour glows and a faint chart grid.
class Backdrop extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)])
		var cols := PackedColorArray([Color("0e1b2e"), Color("0b1523"), Color("04070d"), Color("060b14")])
		RenderingServer.canvas_item_add_polygon(get_canvas_item(), pts, cols)
		_glow(Vector2(size.x * 0.18, size.y * 0.05), 900.0, Color(0.15, 0.45, 0.85, 0.20))
		_glow(Vector2(size.x * 0.92, size.y * 1.0), 800.0, Color(0.95, 0.65, 0.2, 0.10))
		var step := 96.0
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.6, 0.75, 1.0, 0.025), 1.0)
			x += step
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.6, 0.75, 1.0, 0.025), 1.0)
			y += step

	func _glow(c: Vector2, rad: float, col: Color) -> void:
		for k in range(14, 0, -1):
			var f := float(k) / 14.0
			draw_circle(c, rad * f, Color(col.r, col.g, col.b, col.a * (1.0 - f) * 0.35))


## Anti-aliased rounded rect helper for custom-drawn controls.
static func fill_round(ci_owner: CanvasItem, r: Rect2, rad: float, c0: Color, c1: Color) -> void:
	var pts := rrect(r, rad, 6)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(c0.lerp(c1, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	RenderingServer.canvas_item_add_polygon(ci_owner.get_canvas_item(), pts, cols)
