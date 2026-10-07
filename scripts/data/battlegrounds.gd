extends Node
## Autoload "Battlegrounds": arenas modelled on real WWII actions and plausible what-ifs, from tight fjords to
## open ocean (ship hydrodynamics - steerage way, shoal squat, swell - now make open water a real place to fight).
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
	{
		"id": "okinawa", "name": "Okinawa (Operation Ten-Go)", "date": "What-if: 7 Apr 1945",
		"blurb": "Day, open sea. Yamato's sortie meets the Allied fleet west of Okinawa - and this time nobody is on a one-way trip.",
		"size_m": Vector2(14000, 14000), "time_of_day": 9.5, "weather": "clear", "visibility_m": 15000,
		"factions": {"team_a": ["USA", "United Kingdom"], "team_b": ["Japan"]},
		"team_a_pool": ["us_iowa", "us_south_dakota", "us_baltimore", "us_cleveland", "us_fletcher", "uk_king_george_v", "uk_southampton", "us_buckley"],
		"team_b_pool": ["jp_yamato", "jp_kongo", "jp_takao", "jp_agano", "jp_fubuki", "jp_kagero"],
		"base_depth": 420.0, "seed": 1945407,
		"land": [{"pos": Vector2(-8000, -300), "radius": 3600, "height": 320}, {"pos": Vector2(-7600, 3500), "radius": 2600, "height": 450},
			{"pos": Vector2(-7800, -3400), "radius": 2200, "height": 170}, {"pos": Vector2(-4300, 4600), "radius": 520, "height": 170},
			{"pos": Vector2(-3000, -2800), "radius": 450, "height": 190}, {"pos": Vector2(-2300, -3500), "radius": 330, "height": 140},
			{"pos": Vector2(-3600, -4200), "radius": 300, "height": 120}, {"pos": Vector2(-1900, -2500), "radius": 220, "height": 90}],
		"banks": [{"pos": Vector2(-4300, -300), "radius": 1600, "depth": 9}, {"pos": Vector2(-2800, -3300), "radius": 1500, "depth": 14},
			{"pos": Vector2(-4300, 4600), "radius": 1100, "depth": 10}],
		"trenches": [{"from": Vector2(5200, -7000), "to": Vector2(5200, 7000), "width": 3000, "depth": 1100}],
		"spawn_a": Vector3(-1200, 0, -5800), "spawn_b": Vector3(2200, 0, 5800),
	},
	{
		"id": "gulf_coast", "name": "Galveston Coast (Gulf of Mexico)", "date": "What-if: Oct 1942",
		"blurb": "Haze. An Axis raiding fleet storms the Texas coast; Galveston's barrier islands and the Gulf shoals favour the defenders.",
		"size_m": Vector2(14000, 14000), "time_of_day": 14.5, "weather": "haze", "visibility_m": 11000,
		"factions": {"team_a": ["USA"], "team_b": ["Germany", "Italy"]},
		"team_a_pool": ["us_south_dakota", "us_iowa", "us_baltimore", "us_cleveland", "us_fletcher", "us_buckley"],
		"team_b_pool": ["de_scharnhorst", "de_hipper", "de_leipzig", "it_littorio", "it_zara", "it_soldati", "de_type36a"],
		"base_depth": 34.0, "seed": 1942101,
		"land": [{"pos": Vector2(0, 10700), "radius": 5100, "height": 16},
			{"pos": Vector2(5200, 3400), "radius": 520, "height": 10},
			{"pos": Vector2(4300, 3570), "radius": 520, "height": 10},
			{"pos": Vector2(3400, 3740), "radius": 520, "height": 10},
			{"pos": Vector2(2500, 3910), "radius": 520, "height": 10},
			{"pos": Vector2(1600, 4080), "radius": 520, "height": 10},
			{"pos": Vector2(700, 4250), "radius": 520, "height": 10},
			{"pos": Vector2(-200, 4420), "radius": 520, "height": 10},
			{"pos": Vector2(-1100, 4590), "radius": 520, "height": 10},
			{"pos": Vector2(-2900, 4880), "radius": 520, "height": 10},
			{"pos": Vector2(-3800, 5050), "radius": 520, "height": 10},
			{"pos": Vector2(-4700, 5220), "radius": 520, "height": 10},
			{"pos": Vector2(-5600, 5390), "radius": 520, "height": 10},
			{"pos": Vector2(-6500, 5560), "radius": 520, "height": 10}],
		"banks": [{"pos": Vector2(-3000, 1200), "radius": 900, "depth": 9}, {"pos": Vector2(-6000, 2400), "radius": 1200, "depth": 7},
			{"pos": Vector2(3200, -3800), "radius": 1100, "depth": 14}, {"pos": Vector2(-1800, 3200), "radius": 900, "depth": 8}],
		"trenches": [{"from": Vector2(-7000, -6600), "to": Vector2(7000, -5600), "width": 4200, "depth": 160},
			{"from": Vector2(-1650, -1500), "to": Vector2(-2000, 4400), "width": 800, "depth": 58}],
		"spawn_a": Vector3(1200, 0, 2400), "spawn_b": Vector3(-1000, 0, -5800),
	},
	{
		"id": "barents_arctic", "name": "Barents Sea (Arctic Convoy)", "date": "What-if: 31 Dec 1942",
		"blurb": "Polar twilight, snow. Convoy JW 51B's escorts meet Tirpitz and Scharnhorst between the pack ice and the cliffs of Norway.",
		"size_m": Vector2(14000, 14000), "time_of_day": 7.0, "weather": "snow", "visibility_m": 3800, "land_theme": "snow",
		"factions": {"team_a": ["United Kingdom", "USSR"], "team_b": ["Germany"]},
		"team_a_pool": ["uk_king_george_v", "uk_york", "uk_southampton", "uk_tribal", "su_kirov", "su_gnevny", "uk_nelson"],
		"team_b_pool": ["de_bismarck", "de_scharnhorst", "de_hipper", "de_leipzig", "de_type36a"],
		"base_depth": 260.0, "seed": 1942123,
		"land": [{"pos": Vector2(0, -10400), "radius": 5200, "height": 420, "cliff": true}, {"pos": Vector2(3000, -6200), "radius": 1200, "height": 300, "cliff": true},
			{"pos": Vector2(4800, 5200), "radius": 1100, "height": 380, "cliff": true}, {"pos": Vector2(0, 11000), "radius": 5200, "height": 10},
			{"pos": Vector2(2200, 3800), "radius": 420, "height": 10}, {"pos": Vector2(-1500, 4400), "radius": 520, "height": 10}, {"pos": Vector2(3600, 2600), "radius": 300, "height": 10}, {"pos": Vector2(-3300, 3300), "radius": 380, "height": 10}, {"pos": Vector2(900, 5200), "radius": 640, "height": 10}, {"pos": Vector2(-4800, 5000), "radius": 560, "height": 10}, {"pos": Vector2(5600, 3900), "radius": 450, "height": 10}, {"pos": Vector2(-2500, 6000), "radius": 700, "height": 10}, {"pos": Vector2(-5800, 2600), "radius": 350, "height": 10}, {"pos": Vector2(1500, 2800), "radius": 260, "height": 10}],
		"banks": [{"pos": Vector2(4600, 3600), "radius": 1300, "depth": 22}, {"pos": Vector2(-4500, -3600), "radius": 1200, "depth": 30}],
		"trenches": [{"from": Vector2(-7000, -1000), "to": Vector2(7000, 1500), "width": 3500, "depth": 420}],
		"spawn_a": Vector3(-2500, 0, 2200), "spawn_b": Vector3(3500, 0, -4300),
	},
	{
		"id": "arabian_gulf", "name": "Arabian Gulf (Kharg Approaches)", "date": "What-if: 1942",
		"blurb": "Blazing haze. An Axis fleet strikes the Gulf oilfields; the banks are shallow and only the dredged channels let big ships manoeuvre.",
		"size_m": Vector2(14000, 14000), "time_of_day": 13.0, "weather": "haze", "visibility_m": 9000, "land_theme": "desert",
		"factions": {"team_a": ["United Kingdom", "USA"], "team_b": ["Germany", "Italy"]},
		"team_a_pool": ["uk_nelson", "uk_southampton", "uk_tribal", "us_baltimore", "us_fletcher", "us_cleveland", "us_buckley"],
		"team_b_pool": ["de_hipper", "de_leipzig", "it_littorio", "it_zara", "it_giussano", "it_soldati", "de_type36a"],
		"base_depth": 40.0, "seed": 1942777,
		"land": [{"pos": Vector2(0, 10200), "radius": 4800, "height": 160}, {"pos": Vector2(1200, 4300), "radius": 1300, "height": 65},
			{"pos": Vector2(2600, 3800), "radius": 260, "height": 25}, {"pos": Vector2(0, -10400), "radius": 5200, "height": 40},
			{"pos": Vector2(-1200, -3000), "radius": 1300, "height": 60}, {"pos": Vector2(-3800, 800), "radius": 300, "height": 22},
			{"pos": Vector2(2800, -800), "radius": 360, "height": 20}, {"pos": Vector2(-8200, 2600), "radius": 3000, "height": 500, "cliff": true}],
		"banks": [{"pos": Vector2(3000, 1800), "radius": 1300, "depth": 10}, {"pos": Vector2(-2200, -800), "radius": 1100, "depth": 8},
			{"pos": Vector2(-5000, -600), "radius": 1000, "depth": 11}, {"pos": Vector2(4500, -3300), "radius": 1000, "depth": 7},
			{"pos": Vector2(700, -1800), "radius": 900, "depth": 10}, {"pos": Vector2(-3800, 800), "radius": 900, "depth": 6}],
		"trenches": [{"from": Vector2(4000, -1500), "to": Vector2(-5500, 3000), "width": 2600, "depth": 72}],
		"spawn_a": Vector3(-3800, 0, -1400), "spawn_b": Vector3(5000, 0, 2200),
	},
	{
		"id": "north_atlantic", "name": "North Atlantic (Rockall Bank)", "date": "What-if: 12 Nov 1941",
		"blurb": "Storm. No land, no cover: two fleets meet in the open Atlantic with a heavy swell running.",
		"size_m": Vector2(14000, 14000), "time_of_day": 11.0, "weather": "overcast", "visibility_m": 9000,
		"factions": {"team_a": ["United Kingdom", "USA"], "team_b": ["Germany", "Italy"]},
		"team_a_pool": ["uk_king_george_v", "uk_hood", "uk_nelson", "uk_york", "uk_southampton", "uk_tribal", "us_fletcher"],
		"team_b_pool": ["de_bismarck", "de_scharnhorst", "de_hipper", "de_leipzig", "de_type36a", "it_littorio"],
		"base_depth": 1800.0, "seed": 1941112,
		"land": [{"pos": Vector2(-5800, -4400), "radius": 130, "height": 30}],
		"banks": [{"pos": Vector2(-5800, -4400), "radius": 2400, "depth": 55}, {"pos": Vector2(5500, 5200), "radius": 2800, "depth": 80}],
		"trenches": [],
		"spawn_a": Vector3(-1500, 0, -5800), "spawn_b": Vector3(1500, 0, 5800),
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
	"okinawa": [
		{"n": "Allied Task Force", "p": Vector2(-1200, -5800), "k": "start_a"},
		{"n": "Yamato Sortie", "p": Vector2(2200, 5800), "k": "start_b"},
		{"n": "Hagushi Landing Beaches", "p": Vector2(-5000, -300), "k": "objective"},
		{"n": "Okinawa - Mount Yaedake", "p": Vector2(-6500, 3500), "k": "land"},
		{"n": "Shuri Heights", "p": Vector2(-6500, -3300), "k": "land"},
		{"n": "Ie Shima", "p": Vector2(-4300, 4600), "k": "land"},
		{"n": "Kerama Retto", "p": Vector2(-2800, -3300), "k": "hazard"},
		{"n": "Okinawa Trough", "p": Vector2(5200, 0), "k": "channel"},
	],
	"gulf_coast": [
		{"n": "Coastal Defence Squadron", "p": Vector2(1200, 2400), "k": "start_a"},
		{"n": "Axis Raiding Fleet", "p": Vector2(-1000, -5800), "k": "start_b"},
		{"n": "Galveston Island", "p": Vector2(2400, 3700), "k": "land"},
		{"n": "Bolivar Roads", "p": Vector2(-2000, 4760), "k": "channel"},
		{"n": "Bolivar Peninsula", "p": Vector2(-4700, 5220), "k": "land"},
		{"n": "Galveston Ship Channel", "p": Vector2(-1750, 1500), "k": "channel"},
		{"n": "Houston Ship Channel (to Houston)", "p": Vector2(-2500, 7600), "k": "objective"},
		{"n": "Heald Bank", "p": Vector2(-3000, 1200), "k": "hazard"},
		{"n": "Sabine Bank", "p": Vector2(-6000, 2400), "k": "hazard"},
		{"n": "Flower Garden Banks", "p": Vector2(3200, -3800), "k": "hazard"},
	],
	"barents_arctic": [
		{"n": "Convoy JW 51B Escort", "p": Vector2(-2500, 2200), "k": "start_a"},
		{"n": "Kriegsmarine Strike Group", "p": Vector2(3500, -4300), "k": "start_b"},
		{"n": "Nordkapp (North Cape)", "p": Vector2(3000, -6200), "k": "land"},
		{"n": "Bear Island (Bjornoya)", "p": Vector2(4800, 5200), "k": "land"},
		{"n": "Pack Ice Edge", "p": Vector2(0, 4600), "k": "hazard"},
		{"n": "Bear Island Trough", "p": Vector2(0, 250), "k": "channel"},
		{"n": "Altafjord (Tirpitz Base)", "p": Vector2(6200, -6000), "k": "objective"},
		{"n": "Nordkyn Bank", "p": Vector2(-4500, -3600), "k": "hazard"},
		{"n": "Kola Coast (to Murmansk)", "p": Vector2(-6000, -6400), "k": "land"},
	],
	"arabian_gulf": [
		{"n": "Gulf Squadron", "p": Vector2(-3800, -1400), "k": "start_a"},
		{"n": "Axis Strike Fleet", "p": Vector2(5000, 2200), "k": "start_b"},
		{"n": "Kharg Island (oil terminal)", "p": Vector2(1200, 4300), "k": "objective"},
		{"n": "Bahrain", "p": Vector2(-1200, -3000), "k": "land"},
		{"n": "Farsi Island Shoals", "p": Vector2(-3800, 800), "k": "hazard"},
		{"n": "Arabi Island", "p": Vector2(2800, -800), "k": "land"},
		{"n": "Strait of Hormuz", "p": Vector2(-5500, 1500), "k": "channel"},
		{"n": "Musandam Peninsula", "p": Vector2(-6500, 3300), "k": "land"},
		{"n": "Ras Tanura", "p": Vector2(3500, -5500), "k": "objective"},
		{"n": "Bushehr Coast", "p": Vector2(5200, 5800), "k": "land"},
	],
	"north_atlantic": [
		{"n": "Escort Group", "p": Vector2(-1500, -5800), "k": "start_a"},
		{"n": "Raider Squadron", "p": Vector2(1500, 5800), "k": "start_b"},
		{"n": "Rockall", "p": Vector2(-5800, -4400), "k": "land"},
		{"n": "Rockall Bank", "p": Vector2(-5000, -3300), "k": "hazard"},
		{"n": "Hatton Bank", "p": Vector2(5500, 5200), "k": "hazard"},
		{"n": "Mid-Atlantic Air Gap", "p": Vector2(0, 0), "k": "channel"},
		{"n": "Convoy HX Route", "p": Vector2(-3500, 1800), "k": "channel"},
	],
}


func waypoints(id: String) -> Array:
	return WAYPOINTS.get(id, [])


## Where each ground may be fought. Measured with tools/map_metrics.tscn (km2 of water at least
## 1.2 km off any shore that a battleship can float in): the open grounds give a 15 v 15 fleet room
## to manoeuvre; the close-quarters ones are too cramped or shallow for a ladder match, so they are
## Story Mode grounds, unlocked by commission rank the way a commander would earn the command.
## "rank" is the rank index in RANKS at which Story Mode opens the ground.
const RANKS := ["Lieutenant", "Lieutenant Commander", "Commander", "Captain", "Commodore"]
const MODE_INFO := {
	"surigao_strait": {"pvp": true},
	"savo_island": {"pvp": true},
	"sunda_strait": {"pvp": true},
	"mers_el_kebir": {"pvp": true},
	"narvik": {"pvp": false, "rank": 1, "why": "Fjord: under 11 km2 of open water; destroyer-flotilla action",
		"chapter": "Story: the Narvik destroyer flotilla"},
	"river_plate": {"pvp": false, "rank": 2, "why": "Shallow estuary: no deep water for capital ships; cruiser-squadron action",
		"chapter": "Story: the hunt for the raider"},
	"okinawa": {"pvp": true}, "barents_arctic": {"pvp": true}, "north_atlantic": {"pvp": true},
	"gulf_coast": {"pvp": false, "rank": 3, "why": "Shallow shelf behind barrier islands: little deep water for a fleet duel",
		"chapter": "Story: defence of the home coast"},
	"arabian_gulf": {"pvp": false, "rank": 4, "why": "Shoals everywhere: only the dredged channels float a capital ship",
		"chapter": "Story: the oil campaign"},
	"normandy_omaha": {"pvp": false, "rank": 3, "why": "Shoals under the cliffs: bombardment group, not a fleet duel",
		"chapter": "Story: the bombardment group"},
}


## Swell on the water, 0 flat .. 5 rough (drives ship roll/pitch, see Hydro).
const SEA_STATE := {"surigao_strait": 1.0, "savo_island": 2.0, "river_plate": 3.0, "narvik": 2.0,
	"sunda_strait": 2.0, "mers_el_kebir": 1.0, "normandy_omaha": 4.0, "okinawa": 3.0, "gulf_coast": 2.0,
	"barents_arctic": 5.0, "arabian_gulf": 1.0, "north_atlantic": 5.0}


func sea_state(id: String) -> float:
	return float(SEA_STATE.get(id, 1.5))


func is_pvp(id: String) -> bool:
	return bool(MODE_INFO.get(id, {}).get("pvp", true))


func unlock_rank(id: String) -> int:
	return int(MODE_INFO.get(id, {}).get("rank", 0))


func unlock_text(id: String) -> String:
	var m: Dictionary = MODE_INFO.get(id, {})
	if m.get("pvp", true):
		return ""
	return "Unlocks at %s  -  %s" % [RANKS[int(m["rank"])], m["chapter"]]
