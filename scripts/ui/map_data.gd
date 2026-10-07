class_name MapData
extends RefCounted
## Menu-side terrain sampling for the topographic maps. Uses BattleTerrain.sample, so it shows the
## same land and seabed the battle will be fought on. Heights are cached per ground and grid size.

static var _cache := {}

const LAND_EXAG := 4.0       ## vertical exaggeration of land in the 3D topo view
const SEA_EXAG := 0.15       ## seabed is compressed so deep trenches don't swallow the view


## n x n heights over the arena (row = z, column = x), same layout as BattleTerrain.
static func grid(g: Dictionary, n: int) -> PackedFloat32Array:
	var key := "%s_%d" % [g["id"], n]
	if _cache.has(key):
		return _cache[key]
	var noise := BattleTerrain.make_noise(g)
	var size: Vector2 = g["size_m"]
	var out := PackedFloat32Array()
	out.resize(n * n)
	for j in n:
		for i in n:
			var p := Vector2((float(i) / (n - 1) - 0.5) * size.x, (float(j) / (n - 1) - 0.5) * size.y)
			out[j * n + i] = BattleTerrain.sample(g, noise, p).x
	_cache[key] = out
	return out


static func exag(h: float) -> float:
	return h * LAND_EXAG if h > 0.0 else h * SEA_EXAG


static func tint(h: float) -> Color:
	if h > 0.5:
		var t := clampf(h / 700.0, 0.0, 1.0)
		var c := Color(0.30, 0.46, 0.22).lerp(Color(0.64, 0.57, 0.38), smoothstep(0.0, 0.5, t))
		return c.lerp(Color(0.93, 0.93, 0.95), smoothstep(0.55, 1.0, t))
	if h > -1.0:
		return Color(0.80, 0.74, 0.55)
	var c2 := Color(0.36, 0.76, 0.72).lerp(Color(0.13, 0.36, 0.56), smoothstep(0.0, 40.0, -h))
	return c2.lerp(Color(0.04, 0.10, 0.22), smoothstep(40.0, 250.0, -h))


## Top-down shaded-relief image, north up and east right (game compass: +Z north, -X east).
static func thumbnail(g: Dictionary, n: int = 96) -> ImageTexture:
	var hs := grid(g, n)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var size: Vector2 = g["size_m"]
	var cellm := size.x / (n - 1)
	for sy in n:
		for sx in n:
			var i := n - 1 - sx           # east (-X) on the right
			var j := n - 1 - sy           # north (+Z) at the top
			var h := hs[j * n + i]
			var hl := hs[j * n + maxi(i - 1, 0)]
			var hr := hs[j * n + mini(i + 1, n - 1)]
			var hd := hs[maxi(j - 1, 0) * n + i]
			var hu := hs[mini(j + 1, n - 1) * n + i]
			# light from the north-west
			var slope := ((hl - hr) * 0.7 + (hu - hd) * 0.7) / (2.0 * cellm)
			var shade := 1.0 + clampf(slope * (6.0 if h > 0.0 else 1.5), -0.45, 0.45)
			var c := tint(h)
			img.set_pixel(sx, sy, Color(c.r * shade, c.g * shade, c.b * shade))
	return ImageTexture.create_from_image(img)


## Unit-square position (north up, east right) of a world XZ point.
static func to_card(p: Vector2, size: Vector2) -> Vector2:
	return Vector2(0.5 - p.x / size.x, 0.5 - p.y / size.y)


static func kind_color(k: String) -> Color:
	match k:
		"start_a": return Color(0.35, 0.65, 1.0)
		"start_b": return Color(1.0, 0.35, 0.3)
		"hazard": return Color(1.0, 0.62, 0.15)
		"objective": return Color(1.0, 0.9, 0.25)
		"channel": return Color(0.3, 0.95, 0.95)
	return Color(0.95, 0.95, 0.9)


static func kind_label(k: String) -> String:
	match k:
		"start_a": return "Team A start"
		"start_b": return "Team B start"
		"hazard": return "Shoal / reef"
		"objective": return "Objective"
		"channel": return "Deep channel"
	return "Landmass"


## Which cells of an n x n grid can an observer see? Returns n*n bytes (255 = visible, 0 = hidden).
## `eye_m` is the observer's height above the sea; `target_m` the height of what must be seen
## (a ship's superstructure on water, the ground itself on land).
static func visibility(hs: PackedFloat32Array, n: int, size: Vector2, obs: Vector2, eye_m: float, target_m: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n * n)
	var oi := clampf((obs.x / size.x + 0.5) * (n - 1), 0.0, n - 1.0)
	var oj := clampf((obs.y / size.y + 0.5) * (n - 1), 0.0, n - 1.0)
	var oh := maxf(hs[int(oj) * n + int(oi)], 0.0) + eye_m
	for j in n:
		for i in n:
			var th := hs[j * n + i]
			var tz := (maxf(th, 0.0) + (target_m if th <= 0.0 else 1.0))
			var steps := int(maxf(absf(i - oi), absf(j - oj))) + 1
			steps = mini(steps, 64)
			var seen := true
			for s in range(1, steps):
				var f := float(s) / steps
				var ci := int(lerpf(oi, i, f) + 0.5)
				var cj := int(lerpf(oj, j, f) + 0.5)
				if hs[cj * n + ci] > lerpf(oh, tz, f):
					seen = false
					break
			out[j * n + i] = 255 if seen else 0
	return out
