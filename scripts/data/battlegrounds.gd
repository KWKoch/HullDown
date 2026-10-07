extends Node
## Autoload "Battlegrounds": seven arenas modelled on real WWII actions, none in open ocean.
## Coordinates are metres on the XZ plane, arena centred on (0, 0). Terrain parameters feed
## terrain.gd, which builds a heightmap with land ABOVE sea level and a seabed BELOW it.
##
## land features: {"pos": Vector2, "radius": m, "height": m above sea (positive)}
## banks (shoals):  {"pos": Vector2, "radius": m, "depth": m below sea (shallow = dangerous)}
## trenches: {"from": Vector2, "to": Vector2, "width": m, "depth": m}  (deep channels)
## coast: optional shoreline wall {"side": "north"/"south"/"east"/"west", "inset": m, "height": m, "cliff": bool}

const ARENA := 14000.0

var _grounds: Array = [
	{
		"id": "surigao_strait", "name": "Surigao Strait", "date": "25 Oct 1944",
		"blurb": "Night. A narrow strait between Leyte and Dinagat; the old battleships cross the T.",
		"size_m": Vector2(14000, 14000), "time_of_day": 1.5, "weather": "clear", "visibility_m": 9000,
		"factions": {"team_a": ["USA"], "team_b": ["Japan"]},
		"team_a_pool": ["us_south_dakota", "us_baltimore", "us_cleveland", "us_fletcher", "us_buckley"],
		"team_b_pool": ["jp_kongo", "jp_takao", "jp_agano", "jp_fubuki", "jp_kagero"],
		"base_depth": 55.0, "seed": 1944,
		"land": [{"pos": Vector2(-6200, 0), "radius": 4200, "height": 160}, {"pos": Vector2(6500, 800), "radius": 3600, "height": 240},
			{"pos": Vector2(5200, -4800), "radius": 900, "height": 40}],
		"banks": [{"pos": Vector2(-2400, -3600), "radius": 700, "depth": 6}, {"pos": Vector2(2800, 3400), "radius": 800, "depth": 8}],
		"trenches": [{"from": Vector2(0, -7000), "to": Vector2(0, 7000), "width": 2200, "depth": 90}],
		"spawn_a": Vector3(0, 0, 5800), "spawn_b": Vector3(0, 0, -5800),
	},
	{
		"id": "savo_island", "name": "Ironbottom Sound (Savo Island)", "date": "9 Aug 1942",
		"blurb": "Night. Savo Island splits the Allied pickets; reefs line the Guadalcanal shore.",
		"size_m": Vector2(14000, 14000), "time_of_day": 1.0, "weather": "overcast", "visibility_m": 6500,
		"factions": {"team_a": ["USA", "United Kingdom"], "team_b": ["Japan"]},
		"team_a_pool": ["us_baltimore", "us_cleveland", "us_fletcher", "uk_southampton", "uk_tribal"],
		"team_b_pool": ["jp_takao", "jp_agano", "jp_fubuki", "jp_kagero", "jp_kongo"],
		"base_depth": 120.0, "seed": 1942,
		"land": [{"pos": Vector2(0, -1200), "radius": 1500, "height": 480}, {"pos": Vector2(6000, 4800), "radius": 4600, "height": 300},
			{"pos": Vector2(-5200, 5600), "radius": 3000, "height": 220}],
		"banks": [{"pos": Vector2(2800, -3200), "radius": 900, "depth": 5}, {"pos": Vector2(4600, 2200), "radius": 700, "depth": 4},
			{"pos": Vector2(-3200, 1800), "radius": 600, "depth": 7}],
		"trenches": [{"from": Vector2(-6500, -4200), "to": Vector2(5500, 0), "width": 1800, "depth": 400}],
		"spawn_a": Vector3(1800, 0, 4400), "spawn_b": Vector3(-1800, 0, -6200),
	},
	{
		"id": "river_plate", "name": "Rio de la Plata", "date": "13 Dec 1939",
		"blurb": "Dawn. A cruiser squadron corners a pocket battleship at the shoal-strewn estuary.",
		"size_m": Vector2(14000, 14000), "time_of_day": 6.5, "weather": "haze", "visibility_m": 14000,
		"factions": {"team_a": ["United Kingdom"], "team_b": ["Germany"]},
		"team_a_pool": ["uk_york", "uk_southampton", "uk_tribal", "uk_flower"],
		"team_b_pool": ["de_graf_spee", "de_leipzig", "de_type36a"],
		"base_depth": 22.0, "seed": 1939,
		"land": [{"pos": Vector2(0, 7600), "radius": 5200, "height": 12}],
		"banks": [{"pos": Vector2(-3200, 1000), "radius": 1600, "depth": 4}, {"pos": Vector2(2800, -2400), "radius": 1900, "depth": 3},
			{"pos": Vector2(4400, 2600), "radius": 1300, "depth": 5}, {"pos": Vector2(-1200, -4200), "radius": 1100, "depth": 3}],
		"trenches": [{"from": Vector2(-1500, -7000), "to": Vector2(500, 5000), "width": 1600, "depth": 40}],
		"spawn_a": Vector3(-3800, 0, -5200), "spawn_b": Vector3(2600, 0, 3800),
	},
	{
		"id": "narvik", "name": "Ofotfjord (Narvik)", "date": "13 Apr 1940",
		"blurb": "Dawn, snow squalls. High fjord walls; German destroyers at anchor and Warspite inbound.",
		"size_m": Vector2(14000, 14000), "time_of_day": 7.0, "weather": "snow", "visibility_m": 3500,
		"factions": {"team_a": ["United Kingdom"], "team_b": ["Germany"]},
		"team_a_pool": ["uk_nelson", "uk_tribal", "uk_southampton", "uk_flower"],
		"team_b_pool": ["de_type36a", "de_s_boat", "de_leipzig"],
		"base_depth": 180.0, "seed": 1940,
		"land": [{"pos": Vector2(-5800, 0), "radius": 4800, "height": 900}, {"pos": Vector2(5800, 0), "radius": 4800, "height": 1100},
			{"pos": Vector2(0, 7000), "radius": 3500, "height": 400}, {"pos": Vector2(1500, 1200), "radius": 500, "height": 60}],
		"banks": [{"pos": Vector2(900, 3300), "radius": 600, "depth": 9}, {"pos": Vector2(-1600, -2400), "radius": 500, "depth": 7}],
		"trenches": [{"from": Vector2(0, -7000), "to": Vector2(0, 6000), "width": 1800, "depth": 280}],
		"spawn_a": Vector3(0, 0, -6000), "spawn_b": Vector3(0, 0, 4400),
	},
	{
		"id": "sunda_strait", "name": "Sunda Strait", "date": "28 Feb - 1 Mar 1942",
		"blurb": "Night. Allied cruisers stumble onto the Japanese invasion fleet; Krakatoa looms.",
		"size_m": Vector2(14000, 14000), "time_of_day": 23.5, "weather": "clear", "visibility_m": 8000,
		"factions": {"team_a": ["USA", "United Kingdom"], "team_b": ["Japan"]},
		"team_a_pool": ["us_baltimore", "uk_york", "uk_southampton", "us_fletcher"],
		"team_b_pool": ["jp_takao", "jp_agano", "jp_fubuki", "jp_kagero", "jp_kongo"],
		"base_depth": 45.0, "seed": 1942100,
		"land": [{"pos": Vector2(-6400, -1000), "radius": 4200, "height": 320}, {"pos": Vector2(6400, 600), "radius": 4500, "height": 200},
			{"pos": Vector2(1200, -300), "radius": 700, "height": 813}, {"pos": Vector2(3000, 3600), "radius": 450, "height": 90}],
		"banks": [{"pos": Vector2(-2200, 3200), "radius": 900, "depth": 6}, {"pos": Vector2(2400, -3400), "radius": 1000, "depth": 5}],
		"trenches": [{"from": Vector2(-1000, -7000), "to": Vector2(-500, 7000), "width": 1900, "depth": 110}],
		"spawn_a": Vector3(-1200, 0, -5400), "spawn_b": Vector3(1000, 0, 5600),
	},
	{
		"id": "mers_el_kebir", "name": "Mers-el-Kebir", "date": "3 Jul 1940",
		"blurb": "Dusk. Moored French battleships under a hill battery; a harbour mouth ringed with shoals.",
		"size_m": Vector2(14000, 14000), "time_of_day": 17.5, "weather": "clear", "visibility_m": 12000,
		"factions": {"team_a": ["United Kingdom"], "team_b": ["France"]},
		"team_a_pool": ["uk_king_george_v", "uk_nelson", "uk_hood", "uk_illustrious", "uk_tribal"],
		"team_b_pool": ["fr_dunkerque", "fr_algerie", "fr_le_fantasque", "fr_richelieu"],
		"base_depth": 75.0, "seed": 1940007,
		"land": [{"pos": Vector2(0, 6800), "radius": 5800, "height": 320, "fort": true}, {"pos": Vector2(-3600, 5200), "radius": 1700, "height": 130},
			{"pos": Vector2(3600, 5400), "radius": 1500, "height": 90}],
		"banks": [{"pos": Vector2(-1500, 3200), "radius": 650, "depth": 6}, {"pos": Vector2(2000, 3400), "radius": 700, "depth": 7}],
		"trenches": [{"from": Vector2(0, -7000), "to": Vector2(0, 3500), "width": 2500, "depth": 150}],
		"spawn_a": Vector3(0, 0, -6000), "spawn_b": Vector3(0, 0, 4200),
	},
	{
		"id": "normandy_omaha", "name": "Omaha Beach (Operation Neptune)", "date": "6 Jun 1944",
		"blurb": "Dawn. Old battleships and destroyers close to the cliffs; coastal batteries answer back.",
		"size_m": Vector2(14000, 14000), "time_of_day": 5.8, "weather": "overcast", "visibility_m": 7000,
		"factions": {"team_a": ["USA", "United Kingdom", "France"], "team_b": ["Germany"]},
		"team_a_pool": ["us_south_dakota", "us_baltimore", "us_fletcher", "us_buckley", "uk_southampton", "fr_dunkerque"],
		"team_b_pool": ["de_type36a", "de_s_boat", "de_leipzig"],
		"base_depth": 18.0, "seed": 1944606,
		"land": [{"pos": Vector2(0, 8200), "radius": 6200, "height": 55, "cliff": true}],
		"banks": [{"pos": Vector2(-3400, 2800), "radius": 1500, "depth": 3}, {"pos": Vector2(2400, 3600), "radius": 1200, "depth": 3},
			{"pos": Vector2(0, 4600), "radius": 2400, "depth": 2}],
		"trenches": [{"from": Vector2(-6000, -3500), "to": Vector2(6000, -3000), "width": 2600, "depth": 30}],
		"spawn_a": Vector3(0, 0, -5800), "spawn_b": Vector3(2200, 0, 3800),
	},
]


func all_grounds() -> Array:
	return _grounds


func get_ground(id: String) -> Dictionary:
	for g in _grounds:
		if g["id"] == id:
			return g
	return {}


## Named places on each map, matched to the real geography the arena is modelled on.
## kind: land | objective | start_a | start_b | hazard | channel
## In-game compass: +Z is north, -X is east (the HUD bearing convention).
const WAYPOINTS := {
	"surigao_strait": [
		{"n": "Dinagat Island", "p": Vector2(-6200, 0), "k": "land"},
		{"n": "Leyte (Panaon coast)", "p": Vector2(6500, 800), "k": "land"},
		{"n": "Hibuson Island", "p": Vector2(5200, -4800), "k": "land"},
		{"n": "Oldendorf's Battle Line", "p": Vector2(0, 5800), "k": "start_a"},
		{"n": "Nishimura's Southern Force", "p": Vector2(0, -5800), "k": "start_b"},
		{"n": "Surigao Strait Channel", "p": Vector2(0, 0), "k": "channel"},
		{"n": "Panaon Shoal", "p": Vector2(-2400, -3600), "k": "hazard"},
		{"n": "Leyte Gulf Entrance Shoal", "p": Vector2(2800, 3400), "k": "hazard"},
	],
	"savo_island": [
		{"n": "Savo Island", "p": Vector2(0, -1200), "k": "land"},
		{"n": "Guadalcanal", "p": Vector2(6000, 4800), "k": "land"},
		{"n": "Florida Island (Tulagi)", "p": Vector2(-5200, 5600), "k": "land"},
		{"n": "Crutchley's Southern Picket", "p": Vector2(1800, 4400), "k": "start_a"},
		{"n": "Mikawa's Striking Force", "p": Vector2(-1800, -6200), "k": "start_b"},
		{"n": "Ironbottom Sound Deep", "p": Vector2(-500, -2000), "k": "channel"},
		{"n": "Lunga Reef", "p": Vector2(4600, 2200), "k": "hazard"},
		{"n": "Savo Shoal", "p": Vector2(2800, -3200), "k": "hazard"},
	],
	"river_plate": [
		{"n": "Montevideo (Uruguayan coast)", "p": Vector2(0, 7000), "k": "land"},
		{"n": "Commodore Harwood's Force G", "p": Vector2(-3800, -5200), "k": "start_a"},
		{"n": "Admiral Graf Spee", "p": Vector2(2600, 3800), "k": "start_b"},
		{"n": "English Bank", "p": Vector2(-3200, 1000), "k": "hazard"},
		{"n": "Ortiz Bank", "p": Vector2(2800, -2400), "k": "hazard"},
		{"n": "Rouen Bank", "p": Vector2(4400, 2600), "k": "hazard"},
		{"n": "Archimedes Shoal", "p": Vector2(-1200, -4200), "k": "hazard"},
		{"n": "Main Shipping Channel", "p": Vector2(-500, 0), "k": "channel"},
	],
	"narvik": [
		{"n": "Ofotfjord South Wall", "p": Vector2(-5800, 0), "k": "land"},
		{"n": "Ofotfjord North Wall", "p": Vector2(5800, 0), "k": "land"},
		{"n": "Narvik (fjord head)", "p": Vector2(0, 7000), "k": "land"},
		{"n": "Ofotfjord Islet", "p": Vector2(1500, 1200), "k": "land"},
		{"n": "Warspite & Destroyer Flotilla", "p": Vector2(0, -6000), "k": "start_a"},
		{"n": "German Destroyers at Anchor", "p": Vector2(0, 4400), "k": "start_b"},
		{"n": "Narvik Harbour Shoal", "p": Vector2(900, 3300), "k": "hazard"},
		{"n": "Ofotfjord Deep", "p": Vector2(0, -1000), "k": "channel"},
	],
	"sunda_strait": [
		{"n": "Krakatoa", "p": Vector2(1200, -300), "k": "land"},
		{"n": "Java (Banten coast)", "p": Vector2(-6400, -1000), "k": "land"},
		{"n": "Sumatra (Lampung coast)", "p": Vector2(6400, 600), "k": "land"},
		{"n": "Sebuku Island", "p": Vector2(3000, 3600), "k": "land"},
		{"n": "Allied Cruiser Squadron", "p": Vector2(-1200, -5400), "k": "start_a"},
		{"n": "Japanese Invasion Fleet", "p": Vector2(1000, 5600), "k": "start_b"},
		{"n": "Sunda Strait Channel", "p": Vector2(-700, 0), "k": "channel"},
		{"n": "Banten Shoal", "p": Vector2(-2200, 3200), "k": "hazard"},
	],
	"mers_el_kebir": [
		{"n": "Djebel Murdjadjo (Oran massif)", "p": Vector2(0, 6800), "k": "land"},
		{"n": "Fort de Santon Battery", "p": Vector2(-600, 4600), "k": "objective"},
		{"n": "Cap Falcon", "p": Vector2(-3600, 5200), "k": "land"},
		{"n": "Cap de l'Aiguille", "p": Vector2(3600, 5400), "k": "land"},
		{"n": "Admiral Somerville's Force H", "p": Vector2(0, -6000), "k": "start_a"},
		{"n": "French Fleet at the Mole", "p": Vector2(0, 4200), "k": "start_b"},
		{"n": "Harbour Mouth Shoal", "p": Vector2(-1500, 3200), "k": "hazard"},
		{"n": "Gulf of Oran Deep", "p": Vector2(0, -2000), "k": "channel"},
	],
	"normandy_omaha": [
		{"n": "Omaha Beach Bluffs", "p": Vector2(0, 6800), "k": "land"},
		{"n": "Pointe du Hoc", "p": Vector2(4400, 4600), "k": "objective"},
		{"n": "Colleville-sur-Mer Exit", "p": Vector2(-3000, 4800), "k": "objective"},
		{"n": "Bombardment Squadron (TF 124)", "p": Vector2(0, -5800), "k": "start_a"},
		{"n": "German Coastal Flank", "p": Vector2(2200, 3800), "k": "start_b"},
		{"n": "Calvados Reef", "p": Vector2(-3400, 2800), "k": "hazard"},
		{"n": "Omaha Shallows", "p": Vector2(0, 4600), "k": "hazard"},
		{"n": "Transport Area Channel", "p": Vector2(0, -3200), "k": "channel"},
	],
}


func waypoints(id: String) -> Array:
	return WAYPOINTS.get(id, [])
