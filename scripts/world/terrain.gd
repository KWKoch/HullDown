class_name BattleTerrain
extends Node3D
## Deformable heightmap terrain. Height is in metres relative to sea level (0):
## positive = land above the surface, negative = seabed below. Built from a
## Battlegrounds entry and rebuilt chunk-by-chunk when shells change it.
##
## Terrain damage model:
##  - Shell blasts carve craters (land and seabed). Underwater bursts only reach the seabed
##    when the water is shallow; deep water just attenuates the blast.
##  - Cliffs collapse: material above a blast slumps downhill (landslide), widening the damage.
##  - Shoals can be gouged open, creating new channels (and new ways to ground a ship).
##  - Fortified hills ("fort" features) hold hardpoints that other systems can destroy.

signal terrain_changed(chunk_min: Vector2i, chunk_max: Vector2i)

const GRID := 513              ## samples per side (512 cells)
const CHUNK := 64              ## cells per chunk edge
const SEA_LEVEL := 0.0

var size := Vector2(14000, 14000)
var heights := PackedFloat32Array()
var cell := Vector2.ONE
var ground: Dictionary = {}
var cliff_cells := PackedByteArray()      ## 1 where steep cliff material (can slump)
var chunk_nodes := {}                     ## Vector2i -> MeshInstance3D
var sea_material: Material
var land_material: Material
var forts: Array[Dictionary] = []         ## {pos: Vector3, hp: float, alive: bool}


func build(p_ground: Dictionary) -> void:
	ground = p_ground
	size = ground["size_m"]
	cell = size / float(GRID - 1)
	heights.resize(GRID * GRID)
	cliff_cells.resize(GRID * GRID)
	_generate()
	_build_all_chunks()


# --- Generation -----------------------------------------------------------

func _generate() -> void:
	var noise := make_noise(ground)
	for j in GRID:
		for i in GRID:
			var r := sample(ground, noise, _cell_to_world(i, j))
			heights[j * GRID + i] = r.x
			if r.y > 0.5:
				cliff_cells[j * GRID + i] = 1
	for l in ground.get("land", []):
		if l.get("fort", false):
			var pos2: Vector2 = l["pos"]
			var peak := Vector3(pos2.x - 600.0, height_at(pos2.x - 600.0, pos2.y - 2200.0), pos2.y - 2200.0)
			forts.append({"pos": peak, "hp": 800.0, "alive": true})


static func make_noise(g: Dictionary) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = g["seed"]
	noise.frequency = 0.0006
	noise.fractal_octaves = 5
	return noise


## Terrain height at a world XZ point (x = height in m, y = 1.0 if cliff material). Pure function
## of the ground definition, so the menu's topographic map uses exactly the same formula.
static func sample(g: Dictionary, noise: FastNoiseLite, p: Vector2) -> Vector2:
	var cliff := 0.0
	var base: float = g["base_depth"]
	var h := -base * (0.75 + 0.25 * noise.get_noise_2d(p.x, p.y))
	# Seabed trenches (deep shipping channels).
	for t in g.get("trenches", []):
		var d := _seg_dist(p, t["from"], t["to"])
		var w: float = t["width"] * 0.5
		if d < w * 1.6:
			var k := 1.0 - smoothstep(w * 0.4, w * 1.6, d)
			h = minf(h, lerpf(h, -t["depth"], k))
	# Shoals / banks (shallow patches).
	for b in g.get("banks", []):
		var d2 := p.distance_to(b["pos"])
		var r: float = b["radius"]
		if d2 < r * 1.5:
			var k2 := 1.0 - smoothstep(r * 0.3, r * 1.5, d2)
			h = maxf(h, lerpf(h, -b["depth"], k2))
	# Land masses.
	for l in g.get("land", []):
		var d3 := p.distance_to(l["pos"])
		var r2: float = l["radius"]
		if d3 < r2 * 1.35:
			var edge := 1.0 - smoothstep(r2 * 0.55 if not l.get("cliff", false) else r2 * 0.88, r2 * 1.35, d3)
			var rough := 0.65 + 0.35 * noise.get_noise_2d(p.x * 3.1, p.y * 3.1)
			var land_h: float = l["height"] * edge * rough
			# Continuous with the seabed: land rises out of the water.
			h = maxf(h, lerpf(h, land_h - 4.0, edge))
			if l.get("cliff", false) and edge > 0.2 and edge < 0.9 and h > 2.0:
				cliff = 1.0
	return Vector2(h, cliff)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _cell_to_world(i: int, j: int) -> Vector2:
	return Vector2((float(i) / (GRID - 1) - 0.5) * size.x, (float(j) / (GRID - 1) - 0.5) * size.y)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Queries --------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var fx := (x / size.x + 0.5) * (GRID - 1)
	var fz := (z / size.y + 0.5) * (GRID - 1)
	fx = clampf(fx, 0.0, GRID - 1.001)
	fz = clampf(fz, 0.0, GRID - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * GRID + i]
	var h10 := heights[j * GRID + i + 1]
	var h01 := heights[(j + 1) * GRID + i]
	var h11 := heights[(j + 1) * GRID + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func hardness_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	if h > 0.0:
		return 0.9                   # rock / packed earth
	if h > -12.0:
		return 0.45                  # sand / mud bars give a little
	return 0.8                       # rocky seabed / reef


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > SEA_LEVEL


# --- Damage ---------------------------------------------------------------

## he_kg: explosive filler; caliber_mm scales the crater. `burst_y` is the world height of
## the detonation (negative = underwater).
func apply_blast(world_pos: Vector3, he_kg: float, caliber_mm: float, burst_y: float = 0.0) -> void:
	var ground_h := height_at(world_pos.x, world_pos.z)
	var above_ground := burst_y - ground_h
	if above_ground > 25.0:
		return                        # airburst well clear of terrain
	var depth_water := maxf(-ground_h, 0.0) if ground_h < 0.0 else 0.0
	if ground_h < 0.0 and depth_water > 30.0 + caliber_mm * 0.05:
		return                        # too deep: water absorbs the blast
	var radius := clampf(pow(he_kg, 0.33) * 3.0 + caliber_mm * 0.04, 4.0, 90.0)
	var depth := radius * (0.30 if ground_h > 0.0 else 0.18)
	# Reduce crater effect when the burst is above ground.
	depth *= clampf(1.0 - above_ground / 25.0, 0.1, 1.0)
	_carve(world_pos, radius, depth)
	if ground_h > 4.0:
		_slump(world_pos, radius * 2.5, depth)
	if ground_h > 0.0:
		_damage_forts(world_pos, radius, he_kg)


func _carve(p: Vector3, radius: float, depth: float) -> void:
	var cmin := Vector2i(GRID, GRID)
	var cmax := Vector2i(-1, -1)
	var ci := int(((p.x / size.x) + 0.5) * (GRID - 1))
	var cj := int(((p.z / size.y) + 0.5) * (GRID - 1))
	var rc := int(ceil(radius / minf(cell.x, cell.y))) + 1
	for j in range(maxi(cj - rc, 0), mini(cj + rc + 1, GRID)):
		for i in range(maxi(ci - rc, 0), mini(ci + rc + 1, GRID)):
			var w := _cell_to_world(i, j)
			var d := Vector2(w.x - p.x, w.y - p.z).length()
			if d <= radius:
				var k := 1.0 - (d / radius)
				var bowl := depth * k * k
				heights[j * GRID + i] -= bowl
				# Rim berm just outside the crater lip.
			elif d <= radius * 1.3:
				var k2 := 1.0 - (d - radius) / (radius * 0.3)
				heights[j * GRID + i] += depth * 0.12 * k2
			else:
				continue
			cmin = Vector2i(mini(cmin.x, i / CHUNK), mini(cmin.y, j / CHUNK))
			cmax = Vector2i(maxi(cmax.x, i / CHUNK), maxi(cmax.y, j / CHUNK))
			cliff_cells[j * GRID + i] = 0
	if cmax.x >= 0:
		_rebuild_chunks(cmin, cmax)


## Landslide: land above the blast slides downhill, flattening steep slopes nearby.
func _slump(p: Vector3, radius: float, depth: float) -> void:
	var ci := int(((p.x / size.x) + 0.5) * (GRID - 1))
	var cj := int(((p.z / size.y) + 0.5) * (GRID - 1))
	var rc := int(ceil(radius / minf(cell.x, cell.y)))
	var max_slope := 0.9 # m per m before material slumps
	var cmin := Vector2i(GRID, GRID)
	var cmax := Vector2i(-1, -1)
	for iter in 3:
		for j in range(maxi(cj - rc, 1), mini(cj + rc, GRID - 1)):
			for i in range(maxi(ci - rc, 1), mini(ci + rc, GRID - 1)):
				var h := heights[j * GRID + i]
				if h <= 0.0:
					continue
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: int = (j + off.y) * GRID + (i + off.x)
					var dh := h - heights[n]
					if dh > max_slope * cell.x:
						var move := (dh - max_slope * cell.x) * 0.25 * minf(1.0, depth / 6.0 + 0.3)
						heights[j * GRID + i] -= move
						heights[n] += move
						cmin = Vector2i(mini(cmin.x, i / CHUNK), mini(cmin.y, j / CHUNK))
						cmax = Vector2i(maxi(cmax.x, i / CHUNK), maxi(cmax.y, j / CHUNK))
	if cmax.x >= 0:
		_rebuild_chunks(cmin, cmax)


func _damage_forts(p: Vector3, radius: float, he_kg: float) -> void:
	for f in forts:
		if f["alive"] and (f["pos"] as Vector3).distance_to(p) < radius * 2.0 + 15.0:
			f["hp"] -= he_kg * 8.0
			if f["hp"] <= 0.0:
				f["alive"] = false


# --- Meshing --------------------------------------------------------------

func _build_all_chunks() -> void:
	var n := (GRID - 1) / CHUNK
	_rebuild_chunks(Vector2i(0, 0), Vector2i(n - 1, n - 1))


func _rebuild_chunks(cmin: Vector2i, cmax: Vector2i) -> void:
	for cy in range(cmin.y, cmax.y + 1):
		for cx in range(cmin.x, cmax.x + 1):
			_build_chunk(Vector2i(cx, cy))
	terrain_changed.emit(cmin, cmax)


func _build_chunk(c: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var i0 := c.x * CHUNK
	var j0 := c.y * CHUNK
	for j in range(j0, j0 + CHUNK):
		for i in range(i0, i0 + CHUNK):
			var v00 := _vertex(i, j)
			var v10 := _vertex(i + 1, j)
			var v01 := _vertex(i, j + 1)
			var v11 := _vertex(i + 1, j + 1)
			_tri(st, v00, v01, v10)
			_tri(st, v10, v01, v11)
	st.generate_normals()
	var mesh := st.commit()
	var mi: MeshInstance3D = chunk_nodes.get(c)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "chunk_%d_%d" % [c.x, c.y]
		add_child(mi)
		chunk_nodes[c] = mi
	mi.mesh = mesh
	if land_material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		land_material = m
	mi.material_override = land_material


func _vertex(i: int, j: int) -> Dictionary:
	var w := _cell_to_world(i, j)
	var h := heights[j * GRID + i]
	return {"p": Vector3(w.x, h, w.y), "c": _color_for(h, cliff_cells[j * GRID + i] == 1)}


func _tri(st: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	for v in [a, b, c]:
		st.set_color(v["c"])
		st.add_vertex(v["p"])


func _color_for(h: float, cliff: bool) -> Color:
	if h > 2.0:
		if cliff:
			return Color(0.45, 0.42, 0.38)       # exposed rock face
		return Color(0.20, 0.30, 0.15).lerp(Color(0.38, 0.36, 0.30), clampf(h / 400.0, 0.0, 1.0))
	if h > -1.0:
		return Color(0.76, 0.70, 0.52)            # beach / tidal
	if h > -15.0:
		return Color(0.55, 0.60, 0.50).lerp(Color(0.20, 0.30, 0.38), clampf(-h / 15.0, 0.0, 1.0))
	return Color(0.08, 0.14, 0.20)
