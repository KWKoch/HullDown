class_name ShipHistory
## Service history cards and fleet roles for the Port and Shipyard.
## "year" is the launch year (it sets the ship's era row in the Shipyard tree).

const ERAS := [
	["GREAT WAR ERA", 0, 1929],
	["TREATY ERA", 1930, 1936],
	["REARMAMENT", 1937, 1940],
	["WAR PROGRAMME", 1941, 1950],
]

## The job a ship does inside a fleet. Fleet command orders will be built around these.
const ROLES := {
	"line": ["LINE OF BATTLE", "Anchors the battle line. Out-slugs anything afloat and soaks up fire so the fleet can work.", 1],
	"fast_capital": ["FAST CAPITAL SHIP", "Heavy guns with the speed to keep up with carriers: strikes, screens the carriers, and leaves on its own terms.", 2],
	"raider": ["COMMERCE RAIDER", "Out-guns anything fast enough to catch it and out-runs anything that can sink it. Hunts alone or on the flank.", 2],
	"cruiser_line": ["CRUISER LINE", "Screens the capital ships, hunts enemy cruisers and raiders, and holds the flanks of the line.", 2],
	"screen_leader": ["SCREEN LEADER", "Leads the destroyer screen. Rapid fire against light ships and aircraft; first in at night.", 2],
	"torpedo_screen": ["TORPEDO SCREEN", "Screens the fleet from torpedo attack and delivers its own: smoke, speed and a full spread at close range.", 3],
	"escort": ["ESCORT / PICKET", "Guards convoys and the fleet's edge: submarine hunting, picket duty and early warning.", 1],
	"carrier": ["CARRIER STRIKE", "The fleet's long arm. Strikes beyond gun range, but must be screened at all costs.", 3],
	"torpedo_raider": ["INSHORE TORPEDO RAIDER", "Small, fast and expendable. Night attacks from the coast and the islands' shadows.", 3],
}

const TYPE_ROLE := {
	"battleship": "line", "battlecruiser": "fast_capital", "heavy_cruiser": "cruiser_line", "light_cruiser": "screen_leader",
	"destroyer": "torpedo_screen", "escort": "escort", "carrier": "carrier", "motor_torpedo_boat": "torpedo_raider",
}

const ROLE_OVERRIDE := {
	"us_iowa": "fast_capital", "jp_kongo": "fast_capital", "de_scharnhorst": "fast_capital", "fr_dunkerque": "fast_capital",
	"de_graf_spee": "raider",
}

const DATA := {
	# --- USA ---
	"us_iowa": {"year": 1942, "launched": "27 Aug 1942", "fate": "Museum ship at Los Angeles.",
		"actions": ["Carried President Roosevelt toward the Tehran Conference, 1943", "Fast carrier screen across the Central Pacific", "Present in Tokyo Bay for the surrender, 1945", "Recalled for Korea and again in the 1980s"]},
	"us_south_dakota": {"year": 1941, "launched": "7 Jun 1941", "fate": "Scrapped 1962.",
		"actions": ["Battle of the Santa Cruz Islands, 1942: a wall of anti-aircraft fire", "Naval Battle of Guadalcanal, Nov 1942: lost power under heavy fire while Washington sank Kirishima", "Battle of the Philippine Sea, 1944"]},
	"us_baltimore": {"year": 1942, "launched": "28 Jul 1942", "fate": "Scrapped 1972.",
		"actions": ["Lead ship of the war's largest heavy-cruiser class", "Gilberts and Marianas campaigns", "Carried President Roosevelt to Pearl Harbor and Alaska, 1944"]},
	"us_cleveland": {"year": 1941, "launched": "1 Nov 1941", "fate": "Scrapped 1960.",
		"actions": ["Operation Torch off North Africa, 1942", "Battle of Empress Augusta Bay, Nov 1943", "Battle of the Philippine Sea, 1944"]},
	"us_fletcher": {"year": 1942, "launched": "3 May 1942", "fate": "Scrapped 1972.",
		"actions": ["Lead ship of the most numerous US destroyer class", "Naval Battle of Guadalcanal and Tassafaronga, 1942", "Fifteen battle stars in the Second World War"]},
	"us_buckley": {"year": 1943, "launched": "9 Jan 1943", "fate": "Scrapped 1969.",
		"actions": ["Atlantic convoy and hunter-killer groups", "May 1944: rammed and sank U-66 after a night gun battle at point-blank range"]},
	"us_essex": {"year": 1942, "launched": "31 Jul 1942", "fate": "Scrapped 1975.",
		"actions": ["Lead ship of a 24-carrier class that won the Pacific war", "Strikes on Truk, the Philippine Sea and Leyte Gulf", "Recovered the Apollo 7 astronauts, 1968"]},
	"us_elco_pt": {"year": 1942, "launched": "20 Jun 1942", "fate": "Rammed and cut in two by the destroyer Amagiri, 2 Aug 1943.",
		"actions": ["Night patrols in the Solomons", "Commanded by Lt (jg) John F. Kennedy, who led the survivors to safety"]},
	# --- United Kingdom ---
	"uk_king_george_v": {"year": 1939, "launched": "21 Feb 1939", "fate": "Scrapped 1958.",
		"actions": ["With Rodney, sank the Bismarck, May 1941", "Arctic convoy cover", "British Pacific Fleet; present at the Japanese surrender, 1945"]},
	"uk_nelson": {"year": 1925, "launched": "3 Sep 1925", "fate": "Scrapped 1949.",
		"actions": ["All nine 16-inch guns forward of the bridge", "Torpedoed on a Malta convoy, 1941", "Italian armistice signed aboard off Malta, 1943", "Bombarded the Normandy beaches, 1944"]},
	"uk_hood": {"year": 1918, "launched": "22 Aug 1918", "fate": "Sunk by Bismarck in the Denmark Strait, 24 May 1941. Three of 1,418 men survived.",
		"actions": ["The largest warship in the world for twenty years", "Mers-el-Kebir, July 1940"]},
	"uk_york": {"year": 1928, "launched": "17 Jul 1928", "fate": "Crippled by Italian explosive motor boats at Suda Bay, Crete, March 1941.",
		"actions": ["Norway campaign, 1940", "Mediterranean convoys"]},
	"uk_southampton": {"year": 1936, "launched": "10 Mar 1936", "fate": "Dive-bombed and lost off Malta, 11 Jan 1941.",
		"actions": ["Norway campaign, 1940", "Mediterranean convoy escort"]},
	"uk_tribal": {"year": 1937, "launched": "21 Oct 1937", "fate": "Scrapped 1948.",
		"actions": ["Norway, 1940", "Escort in the hunt for the Bismarck, 1941", "Battle of Ushant against German destroyers, June 1944"]},
	"uk_flower": {"year": 1940, "launched": "Class launched 1940-44", "fate": "Nearly 300 built; many lost to U-boats.",
		"actions": ["Built to a whale-catcher design so small yards could turn them out fast", "Backbone of Atlantic convoy escort through the U-boat war"]},
	"uk_illustrious": {"year": 1939, "launched": "5 Apr 1939", "fate": "Scrapped 1956.",
		"actions": ["Taranto, Nov 1940: her Swordfish crippled the Italian battle fleet in harbour", "Survived heavy bombing off Malta in 1941 thanks to her armoured flight deck", "British Pacific Fleet, 1945"]},
	# --- Japan ---
	"jp_yamato": {"year": 1940, "launched": "8 Aug 1940", "fate": "Sunk by US carrier aircraft in Operation Ten-Go, 7 Apr 1945.",
		"actions": ["The largest battleship ever built, with 46 cm guns", "Battle off Samar, Oct 1944"]},
	"jp_kongo": {"year": 1912, "launched": "18 May 1912", "fate": "Torpedoed by the submarine USS Sealion, 21 Nov 1944.",
		"actions": ["British-built; rebuilt twice into a fast battleship", "Bombarded Henderson Field, Guadalcanal, Oct 1942", "Battle off Samar, Oct 1944"]},
	"jp_takao": {"year": 1930, "launched": "12 May 1930", "fate": "Scuttled after the war, 1946.",
		"actions": ["Night action off Guadalcanal, Nov 1942", "Torpedoed by USS Darter in the Palawan Passage, Oct 1944, and survived"]},
	"jp_agano": {"year": 1941, "launched": "22 Oct 1941", "fate": "Torpedoed by the submarine USS Skate near Truk, Feb 1944.",
		"actions": ["Destroyer-squadron flagship", "Battle of Empress Augusta Bay, Nov 1943"]},
	"jp_fubuki": {"year": 1927, "launched": "15 Nov 1927", "fate": "Sunk at the Battle of Cape Esperance, Oct 1942.",
		"actions": ["The 'Special Type' that changed destroyer design worldwide", "Java Sea and Sunda Strait campaigns, 1942"]},
	"jp_kagero": {"year": 1938, "launched": "27 Sep 1938", "fate": "Mined and bombed near Kolombangara, May 1943.",
		"actions": ["Escort for the Pearl Harbor strike force", "Midway, and the Tokyo Express runs to Guadalcanal"]},
	"jp_shokaku": {"year": 1939, "launched": "1 Jun 1939", "fate": "Torpedoed by the submarine USS Cavalla at the Philippine Sea, 19 Jun 1944.",
		"actions": ["Pearl Harbor strike, Dec 1941", "Coral Sea and Santa Cruz: badly damaged both times"]},
	# --- Germany ---
	"de_bismarck": {"year": 1939, "launched": "14 Feb 1939", "fate": "Sunk 27 May 1941 after a torpedo jammed her rudders.",
		"actions": ["Sank HMS Hood in the Denmark Strait, 24 May 1941", "Hunted across the North Atlantic by the Home Fleet"]},
	"de_scharnhorst": {"year": 1936, "launched": "3 Oct 1936", "fate": "Sunk at the Battle of the North Cape, 26 Dec 1943.",
		"actions": ["With Gneisenau, sank the carrier HMS Glorious, June 1940", "The Channel Dash, Feb 1942"]},
	"de_graf_spee": {"year": 1934, "launched": "30 Jun 1934", "fate": "Scuttled off Montevideo, 17 Dec 1939.",
		"actions": ["'Pocket battleship' raider in the South Atlantic", "Battle of the River Plate against three British cruisers, Dec 1939"]},
	"de_hipper": {"year": 1937, "launched": "6 Feb 1937", "fate": "Scuttled at Kiel, May 1945.",
		"actions": ["Rammed by the destroyer HMS Glowworm off Norway, April 1940", "Battle of the Barents Sea, Dec 1942"]},
	"de_leipzig": {"year": 1929, "launched": "18 Oct 1929", "fate": "Scuttled in the North Sea, 1946.",
		"actions": ["Torpedoed by the submarine HMS Salmon, Dec 1939", "Rammed by Prinz Eugen, Oct 1944"]},
	"de_type36a": {"year": 1939, "launched": "Class launched 1939-40", "fate": "Several lost in the Arctic and the Bay of Biscay.",
		"actions": ["Cruiser-sized 150 mm guns; the Allies called them the 'Narvik class'", "Arctic convoy battles and the Bay of Biscay, Dec 1943"]},
	"de_s_boat": {"year": 1939, "launched": "Class launched from 1939", "fate": "Many sunk in the Channel and North Sea.",
		"actions": ["The Allies' 'E-boats': fast diesel torpedo boats", "Raided English Channel convoys at night", "Exercise Tiger, April 1944: attacked a D-Day rehearsal in Lyme Bay"]},
	# --- Italy ---
	"it_littorio": {"year": 1937, "launched": "22 Aug 1937", "fate": "Surrendered at Malta, Sept 1943; scrapped after the war.",
		"actions": ["Torpedoed in harbour at Taranto, Nov 1940", "Battles of Sirte, 1941-42", "Renamed Italia, 1943"]},
	"it_conte_di_cavour": {"year": 1911, "launched": "10 Aug 1911", "fate": "Sunk at Taranto, Nov 1940; raised but never returned to service.",
		"actions": ["Rebuilt in the 1930s with new engines and guns", "Battle of Calabria, July 1940"]},
	"it_zara": {"year": 1930, "launched": "27 Apr 1930", "fate": "Sunk at night by British battleships at Cape Matapan, 29 Mar 1941.",
		"actions": ["The best-armoured Italian heavy cruiser", "Battle of Calabria, July 1940"]},
	"it_giussano": {"year": 1930, "launched": "1930", "fate": "Sunk at the Battle of Cape Bon, 13 Dec 1941.",
		"actions": ["One of the very fast, lightly armoured 'Condottieri' cruisers", "Mediterranean minelaying and convoy runs"]},
	"it_soldati": {"year": 1937, "launched": "Class launched 1937-42", "fate": "Many lost escorting North African convoys.",
		"actions": ["Workhorses of the Malta and Libya convoy war", "Battles of Sirte, 1941-42"]},
	"it_mas": {"year": 1936, "launched": "WW2 series from the mid-1930s", "fate": "Served to the end of the war.",
		"actions": ["A First World War MAS sank the Austro-Hungarian battleship Szent Istvan in 1918", "Black Sea and Mediterranean raids"]},
	# --- France ---
	"fr_richelieu": {"year": 1939, "launched": "17 Jan 1939", "fate": "Scrapped 1968.",
		"actions": ["Escaped unfinished from Brest to Dakar, June 1940", "Damaged by the British at Dakar, 1940", "Refitted in New York and joined the Allies in the Indian Ocean"]},
	"fr_dunkerque": {"year": 1935, "launched": "2 Oct 1935", "fate": "Scuttled at Toulon, Nov 1942.",
		"actions": ["Fast battleship built to catch German pocket battleships", "Badly damaged by the Royal Navy at Mers-el-Kebir, July 1940"]},
	"fr_algerie": {"year": 1932, "launched": "21 May 1932", "fate": "Scuttled at Toulon, Nov 1942.",
		"actions": ["Widely considered the best-protected treaty cruiser", "Atlantic raider hunts, 1939"]},
	"fr_le_fantasque": {"year": 1934, "launched": "15 Mar 1934", "fate": "Scrapped 1957.",
		"actions": ["Touched 45 knots on trials: among the fastest destroyers ever built", "Free French raids in the Aegean, 1943-44"]},
	# --- USSR ---
	"su_gangut": {"year": 1911, "launched": "1911 (as Petropavlovsk)", "fate": "Sunk at her moorings in Kronstadt by dive bombers, Sept 1941.",
		"actions": ["Renamed Marat in 1921", "Fought on as a floating battery in the siege of Leningrad"]},
	"su_kirov": {"year": 1936, "launched": "30 Nov 1936", "fate": "Decommissioned in the 1970s.",
		"actions": ["Built with Italian design help", "The Tallinn evacuation, Aug 1941", "Gunfire support through the siege of Leningrad"]},
	"su_gnevny": {"year": 1936, "launched": "Class launched 1936-39", "fate": "Many lost in the Baltic and Black Sea.",
		"actions": ["The Soviet 'Type 7' destroyers, Italian-influenced design", "Arctic, Baltic and Black Sea fleets"]},
}


static func get_card(id: String) -> Dictionary:
	return DATA.get(id, {})


static func year(e: Dictionary) -> int:
	return int(DATA.get(String(e["id"]), {}).get("year", 1940))


static func era_index(y: int) -> int:
	for i in ERAS.size():
		if y >= int(ERAS[i][1]) and y <= int(ERAS[i][2]):
			return i
	return ERAS.size() - 1


static func role(e: Dictionary) -> Array:
	var key: String = ROLE_OVERRIDE.get(String(e["id"]), TYPE_ROLE.get(String(e["type"]), "line"))
	return ROLES[key]
