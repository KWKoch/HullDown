extends Node
## Autoload "Roster": merges every nation file into one lookup.

## Submarines are part of the roster but disabled in the surface-only testbed.
## Flip this once the subsurface warfare layer (sonar / thermal layers / no visuals) lands.
var include_subs: bool = false

var _by_id: Dictionary = {}
var _all: Array = []


func _ready() -> void:
	for list in [RosterUS.entries(), RosterJapan.entries(), RosterUK.entries(),
			RosterGermany.entries(), RosterItaly.entries(), RosterFranceUSSR.entries()]:
		for e in list:
			_by_id[e["id"]] = e
			_all.append(e)


func get_entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


func all_entries() -> Array:
	return _all


## Entries usable in the current build (respects include_subs and the testbed flag).
func available() -> Array:
	var out: Array = []
	for e in _all:
		if e["type"] == "submarine" and not include_subs:
			continue
		if not e.get("testbed", true) and e["type"] != "submarine":
			continue
		out.append(e)
	return out


func by_nation(nation: String) -> Array:
	return available().filter(func(e): return e["nation"] == nation)


func by_type(type: String) -> Array:
	return available().filter(func(e): return e["type"] == type)


func nations() -> Array:
	var seen := {}
	for e in available():
		seen[e["nation"]] = true
	return seen.keys()
