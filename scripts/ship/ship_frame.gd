class_name ShipFrame
extends RefCounted
## The standard coordinate frame every ship is built in.
##
##   Origin  : midships (station 10 of 20), on the centerline, at the design waterline (DWL).
##   +Z      : toward the bow.        -Z : toward the stern.
##   +X      : to PORT (the engine's right-handed axes: looking toward +Z, +X is on the left).
##   +Y      : up.   y = 0 is the waterline, y = -draft is the keel, y = +freeboard is the main deck.
##   Units   : metres.
##
## Longitudinal positions can be given as a naval-architecture STATION (0 = after perpendicular,
## 10 = midships, 20 = forward perpendicular), as a FRACTION of length from midships
## (-0.5 stern .. +0.5 bow; what the rosters use), or as metres.
##
## Vertical positions are named DECKS, so the same description works for a destroyer and a
## battleship:  keel, inner_bottom, platform, main (weather deck), d01, d02, d03 ...
## A compartment is a box between two decks (or heights), at a position and width.
## Everything is derived from the roster entry, so the scale of a ship drives the layout.

var length: float
var beam: float
var draft: float
var freeboard: float
var deck_height: float                  ## height of one superstructure deck
var decks: Dictionary = {}              ## name -> y (metres above waterline)


static func for_entry(e: Dictionary) -> ShipFrame:
	var f := ShipFrame.new()
	f.length = e["length_m"]
	f.beam = e["beam_m"]
	f.draft = e["draft_m"]
	var fb_ratio := 0.03
	match String(e.get("type", "")):
		"carrier":
			fb_ratio = 0.055
		"motor_torpedo_boat":
			fb_ratio = 0.045
		"submarine":
			fb_ratio = 0.02
	f.freeboard = clampf(f.length * fb_ratio, 1.6, 15.0)
	f.deck_height = clampf(f.length * 0.011, 2.2, 3.2)
	f.decks = {
		"keel": -f.draft,
		"inner_bottom": -f.draft * 0.86,
		"platform": -f.draft * 0.5,
		"waterline": 0.0,
		"main": f.freeboard,
	}
	for i in range(1, 7):
		f.decks["d%02d" % i] = f.freeboard + f.deck_height * i
	return f


# --- Longitudinal --------------------------------------------------------------------

func z_station(station: float) -> float:
	return (station - 10.0) / 20.0 * length


func z_frac(frac_from_midships: float) -> float:
	return frac_from_midships * length


func station_of(z: float) -> float:
	return 10.0 + z / length * 20.0


# --- Vertical --------------------------------------------------------------------------

func deck(name_or_height) -> float:
	if name_or_height is String:
		return decks[name_or_height]
	return float(name_or_height)


# --- Hull form -------------------------------------------------------------------------

## Half-breadth of the hull (metres) at longitudinal position z, at the waterline.
## A parallel mid-body, a fine bow and a fuller stern ending in a transom.
func half_breadth(z: float) -> float:
	var u := clampf(z / (length * 0.5), -1.0, 1.0)      # -1 stern .. +1 bow
	var hb := beam * 0.5
	if u > 0.3:
		var t := (u - 0.3) / 0.7
		return maxf(hb * (1.0 - pow(t, 1.7)), hb * 0.05)
	if u < -0.5:
		var t2 := (-u - 0.5) / 0.5
		return hb * (1.0 - 0.45 * t2 * t2)
	return hb


# --- Spaces ------------------------------------------------------------------------------

## A box from z0..z1 (metres, forward positive), between two decks/heights, centred at x
## (port positive) with total `width`. Returns {"center": Vector3, "half": Vector3}.
func space(z0: float, z1: float, lo, hi, x: float, width: float) -> Dictionary:
	var zl := minf(z0, z1)
	var zh := maxf(z0, z1)
	var y0 := deck(lo)
	var y1 := deck(hi)
	return {
		"center": Vector3(x, (y0 + y1) * 0.5, (zl + zh) * 0.5),
		"half": Vector3(width * 0.5, absf(y1 - y0) * 0.5, (zh - zl) * 0.5),
	}


## Same, but given as centre + length.
func space_at(z: float, length_m: float, lo, hi, x: float, width: float) -> Dictionary:
	return space(z - length_m * 0.5, z + length_m * 0.5, lo, hi, x, width)


# --- Lofted hull surface --------------------------------------------------------------------

## Height of the weather deck at z, rising toward the bow (sheer) and slightly aft.
func deck_y(z: float) -> float:
	var u := clampf(z / (length * 0.5), -1.0, 1.0)
	return freeboard * (1.0 + 0.3 * pow(maxf(u, 0.0), 2.0) + 0.1 * pow(maxf(-u, 0.0), 2.0))


## Half-width of the hull at height y (relative to the waterline) for the section at z:
## flare above the waterline, a rounded bilge and a flat keel below it.
func half_width_at(z: float, y: float) -> float:
	var hb := half_breadth(z)
	if y >= 0.0:
		return hb * (1.0 + 0.05 * clampf(y / maxf(freeboard, 0.1), 0.0, 1.5))
	var d := clampf(-y / draft, 0.0, 1.0)
	return hb * (1.0 - 0.72 * pow(d, 2.4))


## Builds the hull as a single smooth mesh (vertex-coloured: red below the waterline, grey above).
func hull_mesh(topside: Color = Color(0.46, 0.49, 0.51), bottom: Color = Color(0.36, 0.13, 0.11),
		deck_color: Color = Color(0.34, 0.33, 0.31)) -> ArrayMesh:
	var stations := 40
	var level_fracs := [-1.0, -0.9, -0.7, -0.45, -0.2, 0.0]     # fractions of draft below the waterline (keel first)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Ring per station: starboard top -> keel -> port top (open at the top; the deck closes it).
	var rings: Array = []
	for i in stations:
		var z := -length * 0.5 + length * float(i) / (stations - 1)
		var top := deck_y(z)
		var ys: Array[float] = []
		for fr in level_fracs:
			ys.append(fr * draft)
		ys.append(top * 0.5)
		ys.append(top)
		var port: Array[Vector3] = []
		for y in ys:
			port.append(Vector3(half_width_at(z, y), y, z))
		var ring: Array[Vector3] = []
		for k in range(port.size() - 1, -1, -1):
			var p := port[k]
			ring.append(Vector3(-p.x, p.y, p.z))               # starboard, top down to keel
		for k in port.size():
			ring.append(port[k])                                # port, keel up to top
		rings.append(ring)
	var n: int = (rings[0] as Array).size()
	# Sides.
	for i in stations - 1:
		for j in n - 1:
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i + 1][j]
			var c: Vector3 = rings[i + 1][j + 1]
			var d: Vector3 = rings[i][j + 1]
			_quad(st, a, b, c, d, true, topside, bottom)
	# Deck.
	for i in stations - 1:
		var ps: Vector3 = rings[i][0]            # starboard top
		var pp: Vector3 = rings[i][n - 1]        # port top
		var ns: Vector3 = rings[i + 1][0]
		var np: Vector3 = rings[i + 1][n - 1]
		_quad(st, ps, ns, np, pp, false, deck_color, deck_color, Vector3.UP)
	# End caps (transom aft, stem forward).
	for end in [0, stations - 1]:
		var ring: Array = rings[end]
		var mid := Vector3(0.0, 0.0, 0.0)
		for p in ring:
			mid += p
		mid /= ring.size()
		var hint := Vector3(0, 0, -1.0 if end == 0 else 1.0)
		for k in ring.size():
			var p0: Vector3 = ring[k]
			var p1: Vector3 = ring[(k + 1) % ring.size()]
			_tri(st, mid, p0, p1, hint, topside, bottom, true)
	st.generate_normals()
	return st.commit()


func _vcol(p: Vector3, topside: Color, bottom: Color) -> Color:
	if p.y >= 0.0:
		return topside
	return bottom.lerp(topside, clampf(1.0 + p.y / 0.4, 0.0, 1.0) * 0.0)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3, topside: Color, bottom: Color,
		smooth: bool) -> void:
	# Godot front faces wind clockwise: if the counter-clockwise normal points along `hint`, swap.
	var n := (b - a).cross(c - a)
	var pts: Array[Vector3] = [a, b, c]
	if n.dot(hint) > 0.0:
		pts = [a, c, b]
	st.set_smooth_group(0 if smooth else -1)
	for p in pts:
		st.set_color(_vcol(p, topside, bottom))
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, side: bool, topside: Color,
		bottom: Color, hint_override: Vector3 = Vector3.ZERO) -> void:
	var centre := (a + b + c + d) * 0.25
	var hint := hint_override
	if hint == Vector3.ZERO:
		hint = centre - Vector3(0.0, (deck_y(centre.z) - draft) * 0.5, centre.z)   # away from the keel-deck axis
		hint.z = 0.0
	_tri(st, a, b, c, hint, topside, bottom, side)
	_tri(st, a, c, d, hint, topside, bottom, side)
