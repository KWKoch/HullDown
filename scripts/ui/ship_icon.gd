class_name ShipIcon
extends RefCounted
## Class map-icons: a top-down silhouette per ship type, drawn as polygons so they stay crisp
## at any size. `fwd` is the on-screen forward direction (unit vector), `px` is icon length.

# Each shape: [outline points as Vector2(lateral, forward) in units of length, turret dots].
const SHAPES := {
	"battleship": [[Vector2(0, 0.5), Vector2(0.11, 0.3), Vector2(0.14, 0.0), Vector2(0.125, -0.42), Vector2(-0.125, -0.42),
		Vector2(-0.14, 0.0), Vector2(-0.11, 0.3)], [Vector2(0, 0.27), Vector2(0, 0.14), Vector2(0, -0.30)]],
	"battlecruiser": [[Vector2(0, 0.5), Vector2(0.09, 0.3), Vector2(0.115, 0.0), Vector2(0.1, -0.42), Vector2(-0.1, -0.42),
		Vector2(-0.115, 0.0), Vector2(-0.09, 0.3)], [Vector2(0, 0.26), Vector2(0, -0.3)]],
	"heavy_cruiser": [[Vector2(0, 0.5), Vector2(0.085, 0.3), Vector2(0.105, 0.0), Vector2(0.09, -0.42), Vector2(-0.09, -0.42),
		Vector2(-0.105, 0.0), Vector2(-0.085, 0.3)], [Vector2(0, 0.25), Vector2(0, -0.28)]],
	"light_cruiser": [[Vector2(0, 0.5), Vector2(0.07, 0.3), Vector2(0.085, 0.0), Vector2(0.075, -0.42), Vector2(-0.075, -0.42),
		Vector2(-0.085, 0.0), Vector2(-0.07, 0.3)], [Vector2(0, 0.25)]],
	"destroyer": [[Vector2(0, 0.5), Vector2(0.05, 0.28), Vector2(0.06, -0.1), Vector2(0.05, -0.45), Vector2(-0.05, -0.45),
		Vector2(-0.06, -0.1), Vector2(-0.05, 0.28)], [Vector2(0, 0.2)]],
	"escort": [[Vector2(0, 0.5), Vector2(0.045, 0.25), Vector2(0.05, -0.1), Vector2(0.04, -0.45), Vector2(-0.04, -0.45),
		Vector2(-0.05, -0.1), Vector2(-0.045, 0.25)], []],
	"carrier": [[Vector2(0, 0.5), Vector2(0.12, 0.36), Vector2(0.14, -0.45), Vector2(-0.14, -0.45), Vector2(-0.12, 0.36)],
		[Vector2(0.1, 0.05)]],
	"motor_torpedo_boat": [[Vector2(0, 0.45), Vector2(0.09, -0.35), Vector2(-0.09, -0.35)], []],
	"submarine": [[Vector2(0, 0.5), Vector2(0.05, 0.38), Vector2(0.055, -0.4), Vector2(0, -0.5), Vector2(-0.055, -0.4),
		Vector2(-0.05, 0.38)], []],
}
const SIZE_PX := {
	"battleship": 24.0, "battlecruiser": 23.0, "heavy_cruiser": 21.0, "light_cruiser": 19.0, "destroyer": 16.0,
	"escort": 14.0, "carrier": 25.0, "motor_torpedo_boat": 11.0, "submarine": 15.0,
}


static func default_px(type: String) -> float:
	return float(SIZE_PX.get(type, 16.0))


static func draw(ci: CanvasItem, pos: Vector2, fwd: Vector2, type: String, px: float, fill: Color,
		outline: Color = Color(0, 0, 0, 0.85), hollow: bool = false) -> void:
	var shape: Array = SHAPES.get(type, SHAPES["destroyer"])
	var r := Vector2(-fwd.y, fwd.x)
	var pts := PackedVector2Array()
	for p in shape[0]:
		var q: Vector2 = p
		pts.append(pos + r * q.x * px + fwd * q.y * px)
	var closed := pts.duplicate()
	closed.append(pts[0])
	if hollow:
		ci.draw_polyline(closed, fill, 1.6)
	else:
		ci.draw_colored_polygon(pts, fill)
		ci.draw_polyline(closed, outline, 1.2)
		for d in shape[1]:
			var q2: Vector2 = d
			ci.draw_circle(pos + r * q2.x * px + fwd * q2.y * px, maxf(px * 0.045, 1.0), outline)
