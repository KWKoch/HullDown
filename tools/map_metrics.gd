extends Node
## Headless: how much manoeuvre room does each battleground give? Uses the exact battle terrain.
const N := 129

func _ready() -> void:
	print("start")
	var bg = get_node("/root/Battlegrounds")
	for g in bg.all_grounds():
		var h := MapData.grid(g, N)
		var size: Vector2 = g["size_m"]
		var cell := size.x / (N - 1)
		var navigable := PackedByteArray()
		navigable.resize(N * N)
		var nav_n := 0
		for i in N * N:
			var ok := h[i] < -26.0           # about a battleship's (world-scaled) draft plus margin
			navigable[i] = 1 if ok else 0
			if ok: nav_n += 1
		# Distance transform (brute force chamfer) to nearest non-navigable cell -> widest channel radius.
		var d := PackedFloat32Array(); d.resize(N * N)
		for i in N * N: d[i] = 1e9 if navigable[i] == 1 else 0.0
		for pass_i in 2:
			var rng_j := range(N) if pass_i == 0 else range(N - 1, -1, -1)
			for j in rng_j:
				var rng_i := range(N) if pass_i == 0 else range(N - 1, -1, -1)
				for i in rng_i:
					var idx: int = j * N + i
					if navigable[idx] == 0: continue
					for off in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,-1), Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1)]:
						var ni: int = i + off.x; var nj: int = j + off.y
						if ni < 0 or nj < 0 or ni >= N or nj >= N: d[idx] = minf(d[idx], 1.0); continue
						var w: float = 1.0 if off.x == 0 or off.y == 0 else 1.414
						d[idx] = minf(d[idx], d[nj * N + ni] + w)
		var mean_r := 0.0
		var wide_n := 0
		for i in N * N:
			if navigable[i] == 1:
				mean_r += d[i] * cell
				if d[i] * cell >= 1200.0: wide_n += 1
		mean_r /= maxf(nav_n, 1.0)
		var sa: Vector3 = g["spawn_a"]; var sb: Vector3 = g["spawn_b"]
		var open_km2 := nav_n * cell * cell / 1e6
		var wide_km2 := wide_n * cell * cell / 1e6
		print("%-18s navigable %4.0f%%  open %5.1f km2  deep-room(>=1.2km from shore) %5.1f km2  mean clearance %4.0f m  spawn gap %4.1f km" % [g["id"], 100.0 * nav_n / (N * N), open_km2, wide_km2, mean_r, Vector2(sa.x - sb.x, sa.z - sb.z).length() / 1000.0])
	get_tree().quit()
