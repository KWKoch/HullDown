extends Node3D
## godot --headless --path . res://tests/measure_ships.tscn : mesh instances and triangles per ship class.
func _ready() -> void:
	var tot_i := 0
	var tot_t := 0
	for e in Roster.available():
		var s := Ship.new()
		add_child(s)
		s.setup_from_class(e, 0)
		var vis := ShipVisual.new()
		s.add_child(vis)
		vis.setup(s)
		var inst := 0
		var tris := 0
		var stack: Array = [vis]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for ch in n.get_children():
				stack.append(ch)
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
				inst += 1
				var m := (n as MeshInstance3D).mesh
				for si in m.get_surface_count():
					var arr := m.surface_get_arrays(si)
					if arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
						tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			elif n is Label3D:
				inst += 1
		print("%-18s %-14s meshes %3d  tris %6d" % [e["id"], e["type"], inst, tris])
		tot_i += inst
		tot_t += tris
	print("avg meshes %d  avg tris %d" % [tot_i / Roster.available().size(), tot_t / Roster.available().size()])
	get_tree().quit()
