extends Control
## Main menu: PLAY (PvP / Story headers + Skirmish launcher), FLEET STORE (roster, 3D viewer,
## infographics), MAPS (thumbnails that open a 3D topographic map with waypoints and concealment).

const GOLD := UIKit.GOLD
const INK := UIKit.INK
const DIM := UIKit.DIM
const PANEL := Color(0.075, 0.11, 0.16, 0.96)

const TYPE_BLURB := {
	"battleship": "Capital ship. Heavy guns and armour; slow to turn and a big target.",
	"heavy_cruiser": "Fast, long-legged gun platform. Balanced armour, strong main battery.",
	"light_cruiser": "Rapid-fire 6-inch guns. Fast and tough for its size; weak against battleship shells.",
	"destroyer": "Small, quick and agile. Torpedoes and smoke; falls apart under heavy fire.",
	"escort": "Light escort. Slow and fragile, but cheap and hard to spot.",
	"carrier": "Aircraft carrier. Little gun power; its strength is its air group.",
	"submarine": "Stealth hunter beneath the waves.",
}

var tab_btns: Array[Button] = []
var pages: Array[Control] = []
var _tab := 0
var credits_lbl: Label

# play page
var play_map_thumb: TextureRect
var play_map_lbl: Label
var play_ship_lbl: Label
var play_ship_sub: Label

# fleet page
var viewer: ShipViewer
var ship_list: VBoxContainer
var ship_title: Label
var ship_sub: Label
var select_btn: Button
var _browse_id := ""
var _row_btns := {}

# maps page
var cards: Array[MapCard] = []
var _thumb_queue: Array[int] = []
var overlay: Control
var topo: TopoView
var topo_info: Label
var topo_pct: Label
var topo_bar: Panel
var topo_gid := ""
var maps_scroll: ScrollContainer
var vis_btn: Button


func _ready() -> void:
	GameSession.launched = false
	theme = UIKit.make_theme()
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_top()
	pages = [_build_play(), _build_fleet(), _build_yard(), _build_maps()]
	for p in pages:
		add_child(p)
	_fit_pages()
	_build_overlay()
	_browse_id = GameSession.ship_id
	_fleet_nation = "USA"
	_refresh_selection()
	_show_tab(_start_tab())
	_fill_list()
	_browse(GameSession.ship_id)
	_test_args()


var _shot_t := 0.0
var _shot_path := ""
var _shot_secs := 0.0


func _test_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var parts := a.substr(7).split(",")
			_shot_path = parts[0]
			_shot_secs = float(parts[1])
		elif a.begins_with("--topo="):
			_open_topo(a.substr(7))
		elif a.begins_with("--obs="):
			var xy := a.substr(6).split(",")
			await get_tree().create_timer(2.5).timeout
			if topo != null:
				topo.set_observer(Vector2(float(xy[0]), float(xy[1])))
		elif a.begins_with("--pick="):
			GameSession.ship_id = a.substr(7)
		elif a.begins_with("--map="):
			GameSession.ground_id = a.substr(6)
		elif a.begins_with("--scroll="):
			await get_tree().create_timer(6.0).timeout
			maps_scroll.scroll_vertical = int(a.substr(9))
		elif a == "--launch":
			_launch.call_deferred()
		elif a.begins_with("--browse="):
			_browse(a.substr(9))


func _start_tab() -> int:
	var cl := OS.get_cmdline_user_args()
	var i := cl.find("--tab")
	if i >= 0 and i + 1 < cl.size():
		return clampi(int(cl[i + 1]), 0, 3)
	return 0


# --- chrome ------------------------------------------------------------------

func _style(bg: Color, border: Color = Color(0.25, 0.35, 0.48), bw: int = 1, rad: int = 4) -> StyleBox:
	if bg.a < 0.02 and bw == 0:
		return StyleBoxEmpty.new()
	var transparent := bg.a < 0.02
	var bx := UIKit.box(Color(0, 0, 0, 0) if transparent else bg.lightened(0.08), Color(0, 0, 0, 0) if transparent else bg.darkened(0.14),
		Color(border.r, border.g, border.b, 0.9 if bw >= 2 else 0.5), 14.0, 0.0 if transparent else 0.55)
	bx.border_w = 1.8 if bw >= 2 else 1.2
	if rad == 0:
		bx.radius = 0.0
		bx.shadow = 0.0
	return bx


func _lbl(text: String, size: int, col: Color = INK, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if size >= 30:
		l.add_theme_font_override("font", UIKit.font("head"))
	elif size >= 17:
		l.add_theme_font_override("font", UIKit.font("semi"))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, accent: Color = GOLD, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", UIKit.font("caps"))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.5, 0.58))
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, UIKit.button_box(accent, st))
	b.pressed.connect(cb)
	return b


func _primary(b: Button, col: Color) -> Button:
	b.add_theme_stylebox_override("normal", UIKit.box(col.lightened(0.05), col.darkened(0.35), Color(1, 1, 1, 0.45), 14.0, 0.5, Color(col.r, col.g, col.b, 0.35), 12.0))
	b.add_theme_stylebox_override("hover", UIKit.box(col.lightened(0.2), col.darkened(0.2), Color(1, 1, 1, 0.7), 14.0, 0.5, Color(col.r, col.g, col.b, 0.6), 12.0))
	b.add_theme_stylebox_override("pressed", UIKit.box(col.darkened(0.2), col.darkened(0.5), Color(1, 1, 1, 0.5), 14.0, 0.0, Color(0, 0, 0, 0), 12.0))
	b.add_theme_color_override("font_color", Color("04140a"))
	b.add_theme_color_override("font_hover_color", Color("04140a"))
	return b


func _build_bg() -> void:
	add_child(UIKit.Backdrop.new())


## Navigation rail on the right (the old top ribbon, 30% larger, turned into vertical tabs). The
## rest of the screen, CONTENT_W wide, is the viewport each tab fills.
const RAIL_W := 340.0
const CONTENT_W := 1920.0 - RAIL_W
const MODE_COLS := [Color(0.35, 0.6, 1.0), Color(0.5, 0.85, 0.5), Color(1.0, 0.78, 0.3)]

var _mode := 2
var _mode_tiles: Array[Panel] = []
var _mode_views: Array[Control] = []


func _build_top() -> void:
	var rx := 1920.0 - RAIL_W
	var bar := Panel.new()
	var bb := UIKit.box(Color(0.05, 0.08, 0.13, 0.94), Color(0.03, 0.05, 0.09, 0.92), Color(1, 1, 1, 0.0), 0.0, 0.0)
	bb.border_w = 0.0
	bar.add_theme_stylebox_override("panel", bb)
	bar.position = Vector2(rx, 0)
	bar.size = Vector2(RAIL_W, 1080)
	add_child(bar)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.85), Color(GOLD.r, GOLD.g, GOLD.b, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 2
	gt.height = 512
	var ln := TextureRect.new()
	ln.texture = gt
	ln.stretch_mode = TextureRect.STRETCH_SCALE
	ln.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ln.position = Vector2(rx, 0)
	ln.size = Vector2(2, 1080)
	add_child(ln)
	var t := _lbl("BROADSIDE", 50, GOLD)
	t.position = Vector2(rx + 26, 26)
	t.add_theme_constant_override("line_spacing", -14)
	t.add_theme_color_override("font_shadow_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
	t.add_theme_constant_override("shadow_outline_size", 12)
	add_child(t)
	var st := _lbl("SQUATCH SQUAD STUDIOS", 16, DIM)
	st.add_theme_font_override("font", UIKit.font("caps"))
	st.position = Vector2(rx + 30, 104)
	add_child(st)
	var names := ["PLAY", "PORT", "SHIPYARD", "MAPS"]
	for k in 4:
		var b := Button.new()
		b.text = names[k]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UIKit.font("caps"))
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.position = Vector2(rx + 22, 180 + k * 84)
		b.size = Vector2(RAIL_W - 44, 66)
		b.pressed.connect(_show_tab.bind(k))
		add_child(b)
		tab_btns.append(b)
	credits_lbl = _lbl("TEST BUILD\nALL SHIPS UNLOCKED", 17, DIM)
	credits_lbl.add_theme_font_override("font", UIKit.font("caps"))
	credits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_lbl.position = Vector2(rx + 20, 940)
	credits_lbl.size = Vector2(RAIL_W - 40, 50)
	add_child(credits_lbl)


## Where MobileMode puts its fullscreen button on this screen: the foot of the rail.
func fullscreen_button_pos() -> Vector2:
	return Vector2(1920.0 - RAIL_W * 0.5 - 32.0, 1000.0)


## Pages are laid out for a 1920-wide screen; the store and map pages are scaled to fit the
## viewport left of the rail (the play page is built for it directly).
func _fit_pages() -> void:
	for i in pages.size():
		var pg := pages[i]
		if i != 3:
			pg.set_meta("y0", 0.0)
			continue
		var sc := CONTENT_W / 1920.0
		pg.scale = Vector2(sc, sc)
		pg.position.x = 0.0
		pg.set_meta("y0", 0.0)
		# Stretch the tall panels so the scaled page still fills the full height.
		var delta := 1080.0 / sc - 988.0 - 20.0
		pg.size.y += delta
		for c in pg.get_children():
			var cc := c as Control
			if cc == null:
				continue
			if cc.size.y >= 880.0:
				cc.size.y += delta
				for g in cc.get_children():
					var gc := g as Control
					if gc == null:
						continue
					if gc is ScrollContainer:
						gc.size.y += delta
					elif gc.position.y >= 740.0:
						gc.position.y += delta
			elif cc.position.y >= 900.0:
				cc.position.y += delta


func _show_tab(k: int) -> void:
	_tab = k
	for i in pages.size():
		pages[i].visible = (i == k)
	for i in tab_btns.size():
		var on := (i == k)
		var nb := UIKit.box(GOLD.darkened(0.15) if on else Color(0, 0, 0, 0), GOLD.darkened(0.55) if on else Color(0, 0, 0, 0),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.9) if on else Color(1, 1, 1, 0.10), 18.0, 0.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.45) if on else Color(0, 0, 0, 0), 8.0)
		tab_btns[i].add_theme_stylebox_override("normal", nb)
		tab_btns[i].add_theme_stylebox_override("hover", nb if on else UIKit.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.16), 18.0, 0.0, Color(0, 0, 0, 0), 8.0))
		tab_btns[i].add_theme_stylebox_override("pressed", nb)
		tab_btns[i].add_theme_color_override("font_color", Color("1a1204") if on else DIM)
		tab_btns[i].add_theme_color_override("font_hover_color", Color("1a1204") if on else Color.WHITE)
	var pg: Control = pages[k]
	var y0: float = pg.get_meta("y0", 0.0)
	pg.modulate.a = 0.0
	pg.position.y = y0 + 20.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(pg, "modulate:a", 1.0, 0.28)
	tw.tween_property(pg, "position:y", y0, 0.28)
	if k == 3:
		_queue_thumbs()
	if k == 2:
		_fill_yard()


# --- PLAY ---------------------------------------------------------------------
# Three compact mode tiles across the top select what the large panel below shows.

func _build_play() -> Control:
	var page := Control.new()
	page.position = Vector2.ZERO
	page.size = Vector2(CONTENT_W, 1080)
	var m := 28.0
	var tw := (CONTENT_W - m * 4.0) / 3.0
	var th := 200.0
	var tiles := [["PVP", "FLEET BATTLES  -  15 v 15", "SEASON 1  -  COMING SOON"],
		["STORY MODE", "THE WAR AT SEA  -  CAMPAIGN", "IN DEVELOPMENT"],
		["SKIRMISH", "15 v 15 AGAINST AI", "READY"]]
	for i in 3:
		_mode_tile(page, i, Vector2(m + i * (tw + m), m), Vector2(tw, th), tiles[i][0], tiles[i][1], tiles[i][2])
	var vy := m * 2.0 + th
	var vsz := Vector2(CONTENT_W - m * 2.0, 1080.0 - vy - m)
	_mode_views.append(_mode_view(page, Vector2(m, vy), vsz, "PVP", MODE_COLS[0],
		["Human captains on both sides, one ship each.", "Seasonal ladders: rank, rewards and earnings reset each season.",
		"Live matches once the player base can fill both fleets.", "Open-water battlegrounds: Surigao, Savo, Sunda, Mers-el-Kebir, Okinawa, the Barents Sea and the North Atlantic."],
		"SEASON 1  -  COMING SOON", "15 v 15"))
	_mode_views.append(_mode_view(page, Vector2(m, vy), vsz, "STORY MODE", MODE_COLS[1],
		["Fight the war's great surface actions in sequence.", "Command a flotilla through historical scenarios.",
		"Earn commendations, refits and new hulls.", "Rank unlocks the close-quarters grounds: Narvik, the River Plate, Omaha Beach, the Gulf Coast and the Arabian Gulf."],
		"IN DEVELOPMENT  -  COMING SOON", "1939-45"))
	_mode_views.append(_skirmish_view(page, Vector2(m, vy), vsz))
	_select_mode(2)
	return page


func _mode_tile(page: Control, idx: int, pos: Vector2, sz: Vector2, title: String, tag: String, status: String) -> void:
	var col: Color = MODE_COLS[idx]
	var card := Panel.new()
	card.position = pos
	card.size = sz
	page.add_child(card)
	_mode_tiles.append(card)
	var band := Panel.new()
	band.add_theme_stylebox_override("panel", UIKit.box(col.darkened(0.25), col.darkened(0.7), Color(col.r, col.g, col.b, 0.5), 12.0, 0.0))
	band.position = Vector2(10, 10)
	band.size = Vector2(sz.x - 20, 116)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(band)
	var h := _lbl(title, 40, col.lightened(0.25))
	h.position = Vector2(26, 20)
	card.add_child(h)
	var tg := _lbl(tag, 14, INK)
	tg.add_theme_font_override("font", UIKit.font("caps"))
	tg.position = Vector2(28, 84)
	card.add_child(tg)
	var stl := _lbl(status, 16, col.lightened(0.3) if status == "READY" else DIM)
	stl.add_theme_font_override("font", UIKit.font("caps"))
	stl.position = Vector2(28, 146)
	card.add_child(stl)
	for c in card.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.position = Vector2.ZERO
	hit.size = sz
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	hit.pressed.connect(_select_mode.bind(idx))
	card.add_child(hit)


func _select_mode(i: int) -> void:
	_mode = i
	for k in _mode_tiles.size():
		var col: Color = MODE_COLS[k]
		var on := k == i
		if on:
			_mode_tiles[k].add_theme_stylebox_override("panel", UIKit.box(Color(0.15, 0.17, 0.2, 0.94), Color(0.07, 0.085, 0.12, 0.96),
				Color(col.r, col.g, col.b, 0.95), 16.0, 0.8, Color(col.r, col.g, col.b, 0.30), 14.0))
		else:
			_mode_tiles[k].add_theme_stylebox_override("panel", UIKit.glass(16.0, 0.6))
		_mode_tiles[k].modulate = Color(1, 1, 1, 1.0 if on else 0.72)
	for k in _mode_views.size():
		_mode_views[k].visible = k == i


func _mode_view(page: Control, pos: Vector2, sz: Vector2, title: String, col: Color, bullets: Array, status: String, watermark: String) -> Control:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UIKit.glass(18.0, 0.8))
	card.position = pos
	card.size = sz
	page.add_child(card)
	var wm := _lbl(watermark, 220, Color(col.r, col.g, col.b, 0.06))
	wm.position = Vector2(sz.x - 1000.0, sz.y - 330.0)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wm)
	var h := _lbl(title, 46, col.lightened(0.25))
	h.position = Vector2(44, 30)
	card.add_child(h)
	var y := 130.0
	for b in bullets:
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", UIKit.box(col.lightened(0.2), col, Color(0, 0, 0, 0), 6.0, 0.0, Color(col.r, col.g, col.b, 0.6), 0.0))
		dot.position = Vector2(46, y + 12)
		dot.size = Vector2(12, 12)
		card.add_child(dot)
		var bl := _lbl(String(b), 24, Color(0.82, 0.87, 0.93), true)
		bl.position = Vector2(74, y)
		bl.size = Vector2(sz.x - 140, 70)
		card.add_child(bl)
		y += 92.0
	var dis := _btn(status, func(): pass, col, 22)
	dis.disabled = true
	dis.position = Vector2(44, sz.y - 110)
	dis.size = Vector2(620, 70)
	card.add_child(dis)
	return card


func _skirmish_view(page: Control, pos: Vector2, sz: Vector2) -> Control:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UIKit.box(Color(0.15, 0.17, 0.2, 0.92), Color(0.07, 0.085, 0.12, 0.94), Color(GOLD.r, GOLD.g, GOLD.b, 0.75), 18.0, 0.8, Color(GOLD.r, GOLD.g, GOLD.b, 0.22), 14.0))
	card.position = pos
	card.size = sz
	page.add_child(card)
	var pad := 30.0
	var tw := sz.x * 0.58
	play_map_thumb = TextureRect.new()
	play_map_thumb.position = Vector2(pad, pad)
	play_map_thumb.size = Vector2(tw, sz.y - pad * 2.0)
	play_map_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	play_map_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card.add_child(play_map_thumb)
	var rx := pad * 2.0 + tw
	var rw := sz.x - rx - pad
	var head := _lbl("SKIRMISH", 44, GOLD)
	head.position = Vector2(rx, pad - 6.0)
	card.add_child(head)
	var sub := _lbl("TEST RANGE  -  15 v 15 AGAINST AI", 16, DIM)
	sub.position = Vector2(rx + 2.0, pad + 54.0)
	card.add_child(sub)
	play_map_lbl = _lbl("", 26, INK)
	play_map_lbl.position = Vector2(rx, 130)
	play_map_lbl.size = Vector2(rw, 70)
	card.add_child(play_map_lbl)
	play_ship_lbl = _lbl("", 26, GOLD)
	play_ship_lbl.position = Vector2(rx, 222)
	play_ship_lbl.size = Vector2(rw, 34)
	card.add_child(play_ship_lbl)
	play_ship_sub = _lbl("", 17, DIM)
	play_ship_sub.position = Vector2(rx, 260)
	play_ship_sub.size = Vector2(rw, 30)
	card.add_child(play_ship_sub)
	var bm := _btn("CHANGE MAP", _show_tab.bind(3), GOLD.darkened(0.2), 18)
	bm.position = Vector2(rx, 320)
	bm.size = Vector2((rw - 12.0) * 0.5, 56)
	card.add_child(bm)
	var bs := _btn("CHANGE SHIP", _show_tab.bind(1), GOLD.darkened(0.2), 18)
	bs.position = Vector2(rx + (rw - 12.0) * 0.5 + 12.0, 320)
	bs.size = Vector2((rw - 12.0) * 0.5, 56)
	card.add_child(bs)
	var go := _primary(_btn("LAUNCH BATTLE", _launch, Color(0.4, 0.9, 0.5), 32), Color("4ade80"))
	go.position = Vector2(rx, sz.y - pad - 150.0)
	go.size = Vector2(rw, 110)
	card.add_child(go)
	var note := _lbl("ESC returns to this menu during battle.", 14, DIM)
	note.position = Vector2(rx, sz.y - pad - 28.0)
	card.add_child(note)
	return card


func _refresh_selection() -> void:
	if not Progress.is_unlocked(GameSession.ground_id):
		GameSession.ground_id = "surigao_strait"
	var g := Battlegrounds.get_ground(GameSession.ground_id)
	var e := Roster.get_entry(GameSession.ship_id)
	if play_map_thumb != null and not g.is_empty():
		play_map_thumb.texture = MapData.thumbnail(g)
		play_map_lbl.text = "%s\n%s" % [g["name"], g["date"]]
	if play_ship_lbl != null and not e.is_empty():
		play_ship_lbl.text = String(e["name"])
		play_ship_sub.text = "%s  -  %s" % [String(e["type"]).replace("_", " ").capitalize(), e["nation"]]
	for c in cards:
		c.selected = (c.ground["id"] == GameSession.ground_id)
		c.queue_redraw()


func _launch() -> void:
	GameSession.launch(GameSession.ground_id, GameSession.ship_id, get_tree())


# --- PORT (your ships) and SHIPYARD (the unlock tree) -----------------------------

const CLASS_ORDER := ["battleship", "battlecruiser", "carrier", "heavy_cruiser", "light_cruiser", "destroyer", "escort", "motor_torpedo_boat", "submarine"]
const CLASS_NAMES := {"battleship": "BATTLESHIP", "battlecruiser": "BATTLECRUISER", "carrier": "CARRIER", "heavy_cruiser": "HEAVY CRUISER",
	"light_cruiser": "LIGHT CRUISER", "destroyer": "DESTROYER", "escort": "ESCORT", "motor_torpedo_boat": "TORPEDO BOAT", "submarine": "SUBMARINE"}

var _fleet_nation := "USA"
var _nation_btns := {}
var _class_pick := {}            ## type -> index of the ship shown for that class
var _class_ships := {}           ## type -> Array of entries, biggest first
var ship_count_lbl: Label
var role_lbl: Label
var role_desc: Label
var _badges: HBoxContainer
var scores: ShipScores
var history_box: VBoxContainer
var _info_tab := 0
var _info_btns: Array[Button] = []
var compare_btn: Button
var _compare_id := ""
var _yard_nation := "USA"
var _yard_btns := {}
var _yard_area: Control


func _nation_chips(page: Control, y: float, cb: Callable, store: Dictionary) -> void:
	var m := 24.0
	var cap := _lbl("SELECT FLEET", 16, DIM)
	cap.add_theme_font_override("font", UIKit.font("caps"))
	cap.position = Vector2(m + 4, y + 20)
	page.add_child(cap)
	var navs: Array = Roster.nations()
	navs.sort_custom(func(x, z): return (0 if x == "USA" else 1) < (0 if z == "USA" else 1) or ((x == "USA") == (z == "USA") and String(x) < String(z)))
	var x := m + 170.0
	var cw := (CONTENT_W - x - m - 10.0 * (navs.size() - 1)) / float(navs.size())
	for n in navs:
		var nb := Button.new()
		nb.text = "UK" if String(n) == "United Kingdom" else String(n).to_upper()
		nb.focus_mode = Control.FOCUS_NONE
		nb.add_theme_font_override("font", UIKit.font("caps"))
		nb.add_theme_font_size_override("font_size", 20)
		nb.position = Vector2(x, y)
		nb.size = Vector2(cw, 64)
		nb.pressed.connect(cb.bind(String(n)))
		page.add_child(nb)
		store[String(n)] = nb
		x += cw + 10.0


func _style_chips(store: Dictionary, current: String) -> void:
	for nn in store:
		var on: bool = nn == current
		var col := _nation_color(nn)
		var bx := UIKit.box(col.darkened(0.1) if on else Color(1, 1, 1, 0.05), col.darkened(0.55) if on else Color(1, 1, 1, 0.02),
			Color(col.r, col.g, col.b, 0.95) if on else Color(1, 1, 1, 0.14), 16.0, 0.0, Color(col.r, col.g, col.b, 0.35) if on else Color(0, 0, 0, 0), 8.0)
		var nbt: Button = store[nn]
		for st in ["normal", "hover", "pressed"]:
			nbt.add_theme_stylebox_override(st, bx)
		nbt.add_theme_color_override("font_color", Color.WHITE if on else DIM)
		nbt.add_theme_color_override("font_hover_color", Color.WHITE)


## PORT: the ships you own. Pick a navy, one tile per class (tap again for the next ship of that
## class), the ship big in the middle with its fleet role, and Capabilities / History on the right.
func _build_fleet() -> Control:
	var page := Control.new()
	page.position = Vector2.ZERO
	page.size = Vector2(CONTENT_W, 1080)
	var m := 24.0
	_nation_chips(page, m, _set_fleet, _nation_btns)
	var top := m * 2.0 + 64.0
	var h := 1080.0 - top - m
	ship_list = VBoxContainer.new()
	ship_list.position = Vector2(m, top)
	ship_list.size = Vector2(360, h)
	ship_list.add_theme_constant_override("separation", 10)
	page.add_child(ship_list)
	# Centre: the ship.
	var cx := m * 2.0 + 360.0
	var cwid := 640.0
	ship_title = _lbl("", 40, GOLD, true)
	ship_title.position = Vector2(cx + 4, top - 8)
	ship_title.size = Vector2(cwid, 52)
	page.add_child(ship_title)
	role_lbl = _lbl("", 18, UIKit.CYAN)
	role_lbl.add_theme_font_override("font", UIKit.font("caps"))
	role_lbl.position = Vector2(cx + 6, top + 48)
	page.add_child(role_lbl)
	_badges = HBoxContainer.new()
	_badges.add_theme_constant_override("separation", 8)
	_badges.position = Vector2(cx + 6, top + 78)
	page.add_child(_badges)
	viewer = ShipViewer.new()
	viewer.position = Vector2(cx, top + 118)
	viewer.size = Vector2(cwid, 520)
	page.add_child(viewer)
	var vframe := Panel.new()
	vframe.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(1, 1, 1, 0.2), 14.0, 0.0, Color(0, 0, 0, 0), 0.0))
	vframe.position = viewer.position
	vframe.size = viewer.size
	vframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(vframe)
	for d in [-1, 1]:
		var ab := _btn("<" if d < 0 else ">", _step_ship.bind(d), Color(1, 1, 1), 34)
		ab.size = Vector2(64, 120)
		ab.position = viewer.position + Vector2(10.0 if d < 0 else cwid - 74.0, 200)
		page.add_child(ab)
	ship_count_lbl = _lbl("", 14, DIM)
	ship_count_lbl.add_theme_font_override("font", UIKit.font("caps"))
	ship_count_lbl.position = viewer.position + Vector2(16, viewer.size.y - 30)
	page.add_child(ship_count_lbl)
	role_desc = _lbl("", 19, Color(0.84, 0.89, 0.94), true)
	role_desc.position = Vector2(cx + 4, top + 650)
	role_desc.size = Vector2(cwid - 8, 90)
	page.add_child(role_desc)
	compare_btn = _btn("COMPARE", _toggle_compare, UIKit.CYAN, 18)
	compare_btn.position = Vector2(cx, 1080 - m - 90)
	compare_btn.size = Vector2(230, 90)
	page.add_child(compare_btn)
	select_btn = _primary(_btn("SELECT FOR BATTLE", _select_ship, Color(0.4, 0.9, 0.5), 24), Color("4ade80"))
	select_btn.position = Vector2(cx + 242, 1080 - m - 90)
	select_btn.size = Vector2(cwid - 242, 90)
	page.add_child(select_btn)
	# Right: Capabilities / History.
	var rx := cx + cwid + m
	var right := Panel.new()
	right.add_theme_stylebox_override("panel", UIKit.glass(18.0, 0.7))
	right.position = Vector2(rx, top)
	right.size = Vector2(CONTENT_W - rx - m, h)
	page.add_child(right)
	var tw := (right.size.x - 36.0) * 0.5
	for i in 2:
		var tb := Button.new()
		tb.text = ["CAPABILITIES", "HISTORY"][i]
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_override("font", UIKit.font("caps"))
		tb.add_theme_font_size_override("font_size", 18)
		tb.position = Vector2(12 + i * (tw + 12), 12)
		tb.size = Vector2(tw, 54)
		tb.pressed.connect(_set_info_tab.bind(i))
		right.add_child(tb)
		_info_btns.append(tb)
	scores = ShipScores.new()
	scores.position = Vector2(20, 84)
	scores.size = Vector2(right.size.x - 40, h - 100)
	right.add_child(scores)
	history_box = VBoxContainer.new()
	history_box.position = Vector2(24, 84)
	history_box.size = Vector2(right.size.x - 48, h - 100)
	history_box.add_theme_constant_override("separation", 8)
	right.add_child(history_box)
	_set_info_tab(0)
	return page


func _set_info_tab(i: int) -> void:
	_info_tab = i
	scores.visible = i == 0
	history_box.visible = i == 1
	for k in _info_btns.size():
		var on := k == i
		var bx := UIKit.box(GOLD.darkened(0.15) if on else Color(1, 1, 1, 0.04), GOLD.darkened(0.55) if on else Color(1, 1, 1, 0.02),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.9) if on else Color(1, 1, 1, 0.12), 14.0, 0.0, Color(0, 0, 0, 0), 6.0)
		for st in ["normal", "hover", "pressed"]:
			_info_btns[k].add_theme_stylebox_override(st, bx)
		_info_btns[k].add_theme_color_override("font_color", Color("1a1204") if on else DIM)
		_info_btns[k].add_theme_color_override("font_hover_color", Color("1a1204") if on else Color.WHITE)


func _set_fleet(n: String) -> void:
	_fleet_nation = n
	_fill_list()
	var cur := Roster.get_entry(_browse_id)
	if cur.is_empty() or cur["nation"] != n:
		for t in CLASS_ORDER:
			if _class_ships.has(t):
				_browse(String(_class_ships[t][int(_class_pick.get(t, 0))]["id"]))
				return
	_style_rows()


## The navy's ships in class order, for the < > arrows.
func _nation_order() -> Array:
	var out: Array = []
	for t in CLASS_ORDER:
		if _class_ships.has(t):
			out.append_array(_class_ships[t])
	return out


func _step_ship(d: int) -> void:
	var all := _nation_order()
	if all.is_empty():
		return
	var i := 0
	for k in all.size():
		if all[k]["id"] == _browse_id:
			i = k
	_browse(String(all[posmod(i + d, all.size())]["id"]))


func _toggle_compare() -> void:
	_compare_id = "" if _compare_id != "" else _browse_id
	_update_compare()


func _update_compare() -> void:
	var ce := Roster.get_entry(_compare_id)
	scores.set_compare(ce)
	if ce.is_empty():
		compare_btn.text = "COMPARE"
	else:
		compare_btn.text = "VS %s\nTAP TO CLEAR" % String(ce["name"]).get_slice(" (", 0).to_upper()


func _fill_list() -> void:
	for c in ship_list.get_children():
		c.queue_free()
	_row_btns.clear()
	_class_ships.clear()
	for e in Roster.by_nation(_fleet_nation):
		if not Progress.ship_owned(String(e["id"])):
			continue
		var t: String = e["type"]
		if not _class_ships.has(t):
			_class_ships[t] = []
		_class_ships[t].append(e)
	for t in _class_ships:
		(_class_ships[t] as Array).sort_custom(func(x, z): return float(x["displacement_t"]) > float(z["displacement_t"]))
	var n := 0
	for t in CLASS_ORDER:
		if _class_ships.has(t):
			n += 1
	var th := clampf((ship_list.size.y - 10.0 * (n - 1)) / maxf(n, 1), 96.0, 140.0)
	for t in CLASS_ORDER:
		if not _class_ships.has(t):
			continue
		var list: Array = _class_ships[t]
		var idx: int = clampi(int(_class_pick.get(t, 0)), 0, list.size() - 1)
		var e: Dictionary = list[idx]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(360, th)
		b.pressed.connect(_class_tapped.bind(t))
		var nc := _nation_color(_fleet_nation)
		var stripe := Panel.new()
		stripe.add_theme_stylebox_override("panel", UIKit.box(nc.lightened(0.15), nc.darkened(0.3), Color(0, 0, 0, 0), 3.0, 0.0, Color(nc.r, nc.g, nc.b, 0.4), 0.0))
		stripe.position = Vector2(12, 16)
		stripe.size = Vector2(6, th - 32)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(stripe)
		var cl := Label.new()
		cl.text = CLASS_NAMES.get(t, t.to_upper())
		cl.add_theme_font_override("font", UIKit.font("caps"))
		cl.add_theme_font_size_override("font_size", 16)
		cl.add_theme_color_override("font_color", DIM)
		cl.position = Vector2(32, th * 0.5 - 36)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cl)
		var nm := Label.new()
		nm.text = String(e["name"]).get_slice(" (", 0)
		nm.add_theme_font_override("font", UIKit.font("semi"))
		nm.add_theme_font_size_override("font_size", 26)
		nm.add_theme_color_override("font_color", INK)
		nm.position = Vector2(32, th * 0.5 - 14)
		nm.size = Vector2(316, 34)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		if list.size() > 1:
			var more := Label.new()
			more.text = "%d of %d  >" % [idx + 1, list.size()]
			more.add_theme_font_override("font", UIKit.font("caps"))
			more.add_theme_font_size_override("font_size", 14)
			more.add_theme_color_override("font_color", Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.85))
			more.position = Vector2(270, th * 0.5 - 36)
			more.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(more)
		ship_list.add_child(b)
		_row_btns[t] = b
	_style_chips(_nation_btns, _fleet_nation)
	_style_rows()


## Tap a class tile: show its ship; tap the tile that is already showing to step to the next ship.
func _class_tapped(t: String) -> void:
	var list: Array = _class_ships.get(t, [])
	if list.is_empty():
		return
	var idx: int = int(_class_pick.get(t, 0))
	var cur := Roster.get_entry(_browse_id)
	if not cur.is_empty() and cur["type"] == t and cur["nation"] == _fleet_nation and list.size() > 1:
		idx = (idx + 1) % list.size()
	_class_pick[t] = idx
	_fill_list()
	_browse(String(list[idx]["id"]))


func _nation_color(n: String) -> Color:
	match n:
		"USA": return Color("4a86e8")
		"Japan": return Color("ef4b4b")
		"United Kingdom": return Color("d9453d")
		"Germany": return Color("9aa4b2")
		"Italy": return Color("4cb87a")
		"France": return Color("6fb7ff")
		"USSR": return Color("e0484d")
	return Color("8fa3bd")


func _style_rows() -> void:
	var cur := Roster.get_entry(_browse_id)
	var chosen := Roster.get_entry(GameSession.ship_id)
	for t in _row_btns:
		var b: Button = _row_btns[t]
		var sel: bool = not cur.is_empty() and cur["type"] == t and cur["nation"] == _fleet_nation
		var has_chosen: bool = not chosen.is_empty() and chosen["type"] == t and chosen["nation"] == _fleet_nation
		var acc := GOLD if sel else (UIKit.GREEN if has_chosen else Color(1, 1, 1))
		var n := UIKit.box(Color(0.30, 0.22, 0.08, 0.95) if sel else Color(0.12, 0.17, 0.26, 0.85), Color(0.15, 0.11, 0.05, 0.95) if sel else Color(0.07, 0.10, 0.16, 0.85),
			Color(acc.r, acc.g, acc.b, 0.85 if (sel or has_chosen) else 0.13), 14.0, 0.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.3) if sel else Color(0, 0, 0, 0), 6.0)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", UIKit.box(Color(0.2, 0.28, 0.4, 0.95), Color(0.12, 0.17, 0.26, 0.95), Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.7), 14.0, 0.0, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.22), 6.0))
		b.add_theme_stylebox_override("pressed", n)


func _badge(text: String, col: Color) -> void:
	var pc := PanelContainer.new()
	var bx := UIKit.box(Color(col.r, col.g, col.b, 0.28), Color(col.r, col.g, col.b, 0.16), Color(col.r, col.g, col.b, 0.85), 10.0, 0.0, Color(0, 0, 0, 0), 0.0)
	bx.content_margin_left = 12
	bx.content_margin_right = 12
	bx.content_margin_top = 3
	bx.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", bx)
	var l := _lbl(text, 13, col.lightened(0.35))
	l.add_theme_font_override("font", UIKit.font("caps"))
	pc.add_child(l)
	_badges.add_child(pc)


func _browse(id: String) -> void:
	var e := Roster.get_entry(id)
	if e.is_empty():
		return
	_browse_id = id
	if e["nation"] != _fleet_nation:
		_fleet_nation = String(e["nation"])
		_fill_list()
	var cls: Array = _class_ships.get(String(e["type"]), [])
	for i in cls.size():
		if cls[i]["id"] == id:
			_class_pick[String(e["type"])] = i
	if cls.size() > 1:
		_fill_list()
	var all := _nation_order()
	var pos := 0
	for k in all.size():
		if all[k]["id"] == id:
			pos = k
	ship_count_lbl.text = "%d / %d IN THIS FLEET" % [pos + 1, all.size()]
	ship_title.text = String(e["name"])
	var r := ShipHistory.role(e)
	var stars := ""
	for i in 3:
		stars += "★" if i < int(r[2]) else "☆"
	role_lbl.text = "%s   %s   %s" % [String(r[0]), stars, "%s  -  %s" % [String(e["nation"]).to_upper(), CLASS_NAMES.get(String(e["type"]), "")]]
	role_desc.text = String(r[1])
	for c in _badges.get_children():
		c.queue_free()
	_badge("OWNED" if Progress.ship_owned(id) else "LOCKED", UIKit.GREEN if Progress.ship_owned(id) else DIM)
	if not Progress.viewed.has(id):
		_badge("NEW", UIKit.CYAN)
	if id == GameSession.ship_id:
		_badge("IN BATTLE", GOLD)
	Progress.viewed[id] = true
	scores.show_entry(e)
	_fill_history(e)
	viewer.show_ship(e)
	_style_rows()
	_update_select_btn()
	_update_compare()


func _fill_history(e: Dictionary) -> void:
	for c in history_box.get_children():
		c.queue_free()
	var card := ShipHistory.get_card(String(e["id"]))
	var w := history_box.size.x
	var add := func(text: String, size: int, col: Color, caps: bool = false) -> void:
		var l := _lbl(text, size, col, true)
		l.custom_minimum_size = Vector2(w, 0)
		if caps:
			l.add_theme_font_override("font", UIKit.font("caps"))
		history_box.add_child(l)
	if card.is_empty():
		add.call("No service record yet.", 18, DIM)
		return
	add.call("LAUNCHED", 14, DIM, true)
	add.call(String(card["launched"]), 26, INK)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	history_box.add_child(sp)
	add.call("SERVICE", 14, DIM, true)
	for line in card["actions"]:
		add.call("•  " + String(line), 19, Color(0.86, 0.9, 0.95))
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 8)
	history_box.add_child(sp2)
	add.call("FATE", 14, DIM, true)
	add.call(String(card["fate"]), 20, Color(1.0, 0.86, 0.6))


func _select_ship() -> void:
	GameSession.ship_id = _browse_id
	_refresh_selection()
	_browse(_browse_id)


func _update_select_btn() -> void:
	var on := (_browse_id == GameSession.ship_id)
	select_btn.text = "SELECTED FOR BATTLE" if on else "SELECT FOR BATTLE"
	select_btn.disabled = on


## SHIPYARD: each navy's unlock tree. Columns are ship classes, rows are eras, oldest at the top;
## the unlock path runs down each column. Tap a ship to look at it in the Port.
func _build_yard() -> Control:
	var page := Control.new()
	page.position = Vector2.ZERO
	page.size = Vector2(CONTENT_W, 1080)
	_nation_chips(page, 24.0, _set_yard, _yard_btns)
	var note := _lbl("Unlock path runs down each column, oldest to newest. Unlocking arrives with progression; this test build has every ship open.", 15, DIM)
	note.position = Vector2(28, 98)
	page.add_child(note)
	_yard_area = Control.new()
	_yard_area.position = Vector2(24, 130)
	_yard_area.size = Vector2(CONTENT_W - 48, 1080 - 130 - 24)
	_yard_area.draw.connect(_draw_yard_lines)
	page.add_child(_yard_area)
	return page


func _set_yard(n: String) -> void:
	_yard_nation = n
	_fill_yard()


var _yard_nodes: Array = []      ## [column, Rect2] for the connecting lines


func _fill_yard() -> void:
	for c in _yard_area.get_children():
		c.queue_free()
	_yard_nodes.clear()
	_style_chips(_yard_btns, _yard_nation)
	var ships := Roster.by_nation(_yard_nation)
	var cols: Array = []
	for t in CLASS_ORDER:
		for e in ships:
			if e["type"] == t and not cols.has(t):
				cols.append(t)
	if cols.is_empty():
		return
	# Rows are steps along each class's unlock path (oldest first); the era shows on each card.
	var paths := {}
	var depth := 1
	for t in cols:
		var list: Array = ships.filter(func(e): return e["type"] == t)
		list.sort_custom(func(x, z): return ShipHistory.year(x) < ShipHistory.year(z) or (ShipHistory.year(x) == ShipHistory.year(z) and float(x["displacement_t"]) < float(z["displacement_t"])))
		paths[t] = list
		depth = maxi(depth, list.size())
	var lw := 120.0
	var hh := 50.0
	var A := _yard_area.size
	var cw := (A.x - lw) / float(cols.size())
	var rh := minf((A.y - hh) / float(depth), 300.0)
	var numerals := ["I", "II", "III", "IV", "V", "VI"]
	for r in depth:
		var band := Panel.new()
		band.add_theme_stylebox_override("panel", UIKit.box(Color(1, 1, 1, 0.035 if r % 2 == 0 else 0.015), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.0), 10.0, 0.0))
		band.position = Vector2(0, hh + r * rh)
		band.size = Vector2(A.x, rh - 8)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_yard_area.add_child(band)
		var el := _lbl("TIER " + String(numerals[mini(r, numerals.size() - 1)]), 18, GOLD)
		el.add_theme_font_override("font", UIKit.font("caps"))
		el.position = Vector2(16, hh + r * rh + rh * 0.5 - 18)
		_yard_area.add_child(el)
	for ci in cols.size():
		var t: String = cols[ci]
		var hl := _lbl(CLASS_NAMES.get(t, t.to_upper()), 15, DIM)
		hl.add_theme_font_override("font", UIKit.font("caps"))
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hl.position = Vector2(lw + ci * cw, 10)
		hl.size = Vector2(cw, 30)
		_yard_area.add_child(hl)
		var list: Array = paths[t]
		for k in list.size():
			var rect := Rect2(lw + ci * cw + 8.0, hh + k * rh + 14.0, cw - 16.0, minf(rh - 36.0, 190.0))
			_yard_node(list[k], rect)
			_yard_nodes.append([ci, rect])
	_yard_area.queue_redraw()


func _yard_node(e: Dictionary, rect: Rect2) -> void:
	var id: String = e["id"]
	var owned := Progress.ship_owned(id)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.position = rect.position
	b.size = rect.size
	var col := UIKit.GREEN if owned else DIM
	var sel := id == GameSession.ship_id
	var bx := UIKit.box(Color(0.14, 0.19, 0.28, 0.95), Color(0.08, 0.11, 0.17, 0.95), Color(GOLD.r, GOLD.g, GOLD.b, 0.9) if sel else Color(col.r, col.g, col.b, 0.45), 12.0, 0.4, Color(0, 0, 0, 0), 6.0)
	for st in ["normal", "pressed"]:
		b.add_theme_stylebox_override(st, bx)
	b.add_theme_stylebox_override("hover", UIKit.box(Color(0.2, 0.28, 0.4, 0.95), Color(0.12, 0.17, 0.26, 0.95), Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.8), 12.0, 0.4, Color(0, 0, 0, 0), 6.0))
	b.pressed.connect(func() -> void:
		_show_tab(1)
		_browse(id))
	_yard_area.add_child(b)
	var nm := _lbl(String(e["name"]).get_slice(" (", 0), 20, INK, true)
	nm.position = Vector2(12, 10)
	nm.size = Vector2(rect.size.x - 24, 54)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	var yr := ShipHistory.year(e)
	var info := _lbl("LAUNCHED %d" % yr, 13, DIM)
	info.add_theme_font_override("font", UIKit.font("caps"))
	info.position = Vector2(12, rect.size.y - 74)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(info)
	var rl := _lbl(String(ShipHistory.role(e)[0]), 13, UIKit.CYAN)
	rl.add_theme_font_override("font", UIKit.font("caps"))
	rl.position = Vector2(12, rect.size.y - 52)
	rl.size = Vector2(rect.size.x - 20, 20)
	rl.clip_text = true
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(rl)
	var sub := _lbl("OWNED" if owned else "LOCKED", 13, col)
	sub.add_theme_font_override("font", UIKit.font("caps"))
	sub.position = Vector2(12, rect.size.y - 30)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub)


func _draw_yard_lines() -> void:
	# Unlock path: connect consecutive ships down each column.
	var by_col := {}
	for n in _yard_nodes:
		if not by_col.has(n[0]):
			by_col[n[0]] = []
		by_col[n[0]].append(n[1])
	for c in by_col:
		var rs: Array = by_col[c]
		rs.sort_custom(func(x, z): return (x as Rect2).position.y < (z as Rect2).position.y)
		for i in rs.size() - 1:
			var a: Rect2 = rs[i]
			var b: Rect2 = rs[i + 1]
			var p0 := Vector2(a.get_center().x, a.end.y)
			var p1 := Vector2(b.get_center().x, b.position.y)
			_yard_area.draw_line(p0, p1, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 3.0, true)
			_yard_area.draw_colored_polygon(PackedVector2Array([p1, p1 + Vector2(-7, -10), p1 + Vector2(7, -10)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.8))


# --- MAPS -----------------------------------------------------------------------

func _build_maps() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 92)
	page.size = Vector2(1920, 988)
	var title := _lbl("BATTLEGROUNDS  -  click a map for the 3D topographic view", 20, DIM)
	title.position = Vector2(36, 14)
	page.add_child(title)
	var sc := ScrollContainer.new()
	sc.position = Vector2(24, 54)
	sc.size = Vector2(1872, 920)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	maps_scroll = sc
	page.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	sc.add_child(grid)
	for g in Battlegrounds.all_grounds():
		var c := MapCard.new()
		c.setup(g)
		c.opened.connect(_open_topo)
		grid.add_child(c)
		cards.append(c)
	return page


func _queue_thumbs() -> void:
	_thumb_queue.clear()
	for i in cards.size():
		if cards[i].tex == null:
			_thumb_queue.append(i)


func _process(d: float) -> void:
	if _shot_path != "":
		_shot_t += d
		if _shot_t > _shot_secs:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
	if _tab == 2 and not _thumb_queue.is_empty() and not overlay.visible:
		var i: int = _thumb_queue.pop_front()
		cards[i].set_texture(MapData.thumbnail(cards[i].ground))


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)


func _open_topo(gid: String) -> void:
	topo_gid = gid
	var g := Battlegrounds.get_ground(gid)
	for c in overlay.get_children():
		if c is ColorRect:
			continue
		c.queue_free()
	overlay.visible = true
	var wait := _lbl("Building 3D terrain...", 28, GOLD)
	wait.position = Vector2(780, 500)
	overlay.add_child(wait)
	await get_tree().process_frame
	await get_tree().process_frame
	# map card: opaque rounded panel that clips the 3D view to its corners
	var holder := Panel.new()
	holder.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.05, 0.09, 1), Color(0.03, 0.05, 0.09, 1), Color(0, 0, 0, 0), 20.0, 0.9, Color(0, 0, 0, 0), 0.0))
	holder.position = Vector2(24, 24)
	holder.size = Vector2(1316, 1032)
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	overlay.add_child(holder)
	topo = TopoView.new()
	topo.position = Vector2.ZERO
	topo.size = holder.size
	holder.add_child(topo)
	topo.setup(g)
	topo.observer_changed.connect(func(_p): _update_topo_info())
	wait.queue_free()
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(1, 1, 1, 0.22), 20.0, 0.0, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.10), 0.0))
	frame.position = holder.position
	frame.size = holder.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(frame)
	# ---- side panel ----
	var side := Panel.new()
	side.add_theme_stylebox_override("panel", UIKit.glass(20.0, 0.8))
	side.position = Vector2(1356, 24)
	side.size = Vector2(540, 1032)
	overlay.add_child(side)
	var t := _lbl(String(g["name"]), 30, GOLD, true)
	t.position = Vector2(24, 18)
	t.size = Vector2(492, 80)
	side.add_child(t)
	var tod := "Night" if float(g["time_of_day"]) < 5.0 or float(g["time_of_day"]) > 20.0 else ("Dawn" if float(g["time_of_day"]) < 8.0 else ("Dusk" if float(g["time_of_day"]) > 16.5 else "Day"))
	var cx := 24.0
	var mode_chip := "PVP READY" if Battlegrounds.is_pvp(gid) else "CAMPAIGN"
	for chip in [String(g["date"]), String(g.get("weather", "clear")).capitalize(), tod, mode_chip]:
		var cw := UIKit.font("body").get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22.0
		var cp := Panel.new()
		cp.add_theme_stylebox_override("panel", UIKit.box(Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.14), 12.0, 0.0, Color(0, 0, 0, 0), 0.0))
		cp.position = Vector2(cx, 96)
		cp.size = Vector2(cw, 26)
		side.add_child(cp)
		var cl := _lbl(chip, 13, Color(0.78, 0.86, 0.96))
		cl.position = Vector2(11, 3)
		cp.add_child(cl)
		cx += cw + 8.0
	var blurb_txt := String(g["blurb"])
	if not Battlegrounds.is_pvp(gid):
		blurb_txt += "\nCampaign ground. " + String(Battlegrounds.MODE_INFO[gid]["why"]) + "."
	var bl := _lbl(blurb_txt, 15, Color(0.82, 0.87, 0.93), true)
	bl.position = Vector2(24, 136)
	bl.size = Vector2(492, 70)
	side.add_child(bl)
	# landmarks card
	var wps: Array = Battlegrounds.waypoints(gid)
	var lcard := Panel.new()
	lcard.add_theme_stylebox_override("panel", UIKit.box(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.10), 14.0, 0.0, Color(0, 0, 0, 0), 0.0))
	lcard.position = Vector2(18, 214)
	lcard.size = Vector2(504, 52 + wps.size() * 32)
	side.add_child(lcard)
	var lh := _lbl("LANDMARKS  -  click to fly there", 11, DIM)
	lh.add_theme_font_override("font", UIKit.font("caps"))
	lh.position = Vector2(18, 14)
	lcard.add_child(lh)
	var ry := 40.0
	for wp in wps:
		var rb := Button.new()
		rb.flat = true
		rb.focus_mode = Control.FOCUS_NONE
		rb.position = Vector2(8, ry)
		rb.size = Vector2(488, 30)
		var hov := UIKit.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 8.0, 0.0, Color(0, 0, 0, 0), 0.0)
		rb.add_theme_stylebox_override("hover", hov)
		rb.add_theme_stylebox_override("pressed", hov)
		rb.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		var wpp: Vector2 = wp["p"]
		rb.pressed.connect(func(): if topo != null: topo.focus(wpp))
		lcard.add_child(rb)
		var kc := MapData.kind_color(wp["k"])
		var sw := Panel.new()
		sw.add_theme_stylebox_override("panel", UIKit.box(kc.lightened(0.1), kc.darkened(0.25), Color(1, 1, 1, 0.5), 7.0, 0.0, Color(kc.r, kc.g, kc.b, 0.55), 0.0))
		sw.position = Vector2(10, 9)
		sw.size = Vector2(12, 12)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rb.add_child(sw)
		var wl := _lbl(String(wp["n"]), 15, INK)
		wl.position = Vector2(32, 4)
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rb.add_child(wl)
		var kl := _lbl(MapData.kind_label(wp["k"]).to_upper(), 10, DIM)
		kl.add_theme_font_override("font", UIKit.font("caps"))
		kl.position = Vector2(488 - 8 - UIKit.font("caps").get_string_size(MapData.kind_label(wp["k"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x - 4, 8)
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rb.add_child(kl)
		ry += 32.0
	# spotter card
	var sy := lcard.position.y + lcard.size.y + 14.0
	var scard := Panel.new()
	scard.add_theme_stylebox_override("panel", UIKit.box(Color(0.30, 0.22, 0.08, 0.55), Color(0.12, 0.09, 0.04, 0.55), Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, 0.45), 14.0, 0.0, Color(0, 0, 0, 0), 0.0))
	scard.position = Vector2(18, sy)
	scard.size = Vector2(504, 176)
	side.add_child(scard)
	var sh := _lbl("SPOTTER EXPOSURE", 11, UIKit.GOLD)
	sh.add_theme_font_override("font", UIKit.font("caps"))
	sh.position = Vector2(18, 14)
	scard.add_child(sh)
	topo_pct = _lbl("--", 56, Color("ffe2a0"))
	topo_pct.position = Vector2(16, 28)
	scard.add_child(topo_pct)
	var of := _lbl("of the open water is in his line of sight", 13, DIM)
	of.position = Vector2(150, 62)
	of.size = Vector2(340, 40)
	of.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scard.add_child(of)
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.08), 6.0, 0.0, Color(0, 0, 0, 0), 0.0))
	track.position = Vector2(18, 106)
	track.size = Vector2(468, 12)
	scard.add_child(track)
	topo_bar = Panel.new()
	topo_bar.add_theme_stylebox_override("panel", UIKit.box(Color("ffd77a"), Color("e8962a"), Color(0, 0, 0, 0), 6.0, 0.0, Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, 0.4), 0.0))
	topo_bar.position = Vector2(18, 106)
	topo_bar.size = Vector2(10, 12)
	scard.add_child(topo_bar)
	topo_info = _lbl("", 14, Color(1.0, 0.9, 0.65), true)
	topo_info.position = Vector2(18, 128)
	topo_info.size = Vector2(468, 40)
	scard.add_child(topo_info)
	_update_topo_info()
	var hint := _lbl("Click the map to move the spotter. Dark violet = hidden behind land: cover for an ambush.", 13, DIM, true)
	hint.position = Vector2(24, sy + 188.0)
	hint.size = Vector2(492, 40)
	side.add_child(hint)
	# controls
	vis_btn = _btn("CONCEALMENT OVERLAY: ON", _toggle_vis, Color(1.0, 0.72, 0.15), 15)
	vis_btn.position = Vector2(18, 846)
	vis_btn.size = Vector2(504, 48)
	side.add_child(vis_btn)
	var bw := (504.0 - 24.0) / 3.0
	var ctl := [["ZOOM +", func(): topo.zoom(0.8)], ["ZOOM -", func(): topo.zoom(1.25)], ["RESET VIEW", func(): topo.reset_camera()]]
	for k in 3:
		var cb := _btn(ctl[k][0], ctl[k][1], UIKit.CYAN, 14)
		cb.position = Vector2(18 + k * (bw + 12), 904)
		cb.size = Vector2(bw, 44)
		side.add_child(cb)
	var open_g := Progress.is_unlocked(gid)
	var dep := _primary(_btn("USE FOR SKIRMISH" if open_g else "CAMPAIGN GROUND  -  LOCKED", _use_map, Color(0.4, 0.9, 0.5), 18 if open_g else 14), Color("4ade80"))
	dep.disabled = not open_g
	dep.position = Vector2(18, 962)
	dep.size = Vector2(304, 54)
	side.add_child(dep)
	var cl := _btn("CLOSE", _close_topo, Color("fb6a5e"), 18)
	cl.position = Vector2(334, 962)
	cl.size = Vector2(188, 54)
	side.add_child(cl)


func _update_topo_info() -> void:
	if topo == null or topo_info == null:
		return
	var near := ""
	var best := 1e9
	for wp in Battlegrounds.waypoints(topo_gid):
		var dd: float = (wp["p"] as Vector2).distance_to(topo.observer)
		if dd < best:
			best = dd
			near = wp["n"]
	var pct := topo.exposed_water_pct()
	topo_pct.text = "%d%%" % int(pct)
	topo_bar.size.x = maxf(468.0 * pct / 100.0, 10.0)
	topo_info.text = "Spotter near %s (%.1f km away)" % [near, best / 1000.0]


func _toggle_vis() -> void:
	topo.set_vis_on(not topo.vis_on)
	vis_btn.text = "CONCEALMENT OVERLAY: " + ("ON" if topo.vis_on else "OFF")


func _use_map() -> void:
	if not Progress.is_unlocked(topo_gid):
		return
	GameSession.ground_id = topo_gid
	_refresh_selection()
	_close_topo()


func _close_topo() -> void:
	overlay.visible = false
	topo = null
	for c in overlay.get_children():
		if not c is ColorRect:
			c.queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and overlay.visible:
		_close_topo()
