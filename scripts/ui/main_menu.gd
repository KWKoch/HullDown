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
var stats: ShipStats
var ship_list: VBoxContainer
var ship_title: Label
var ship_sub: Label
var ship_desc: Label
var ship_price: Label
var select_btn: Button
var nation_filter: OptionButton
var type_filter: OptionButton
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
var vis_btn: Button


func _ready() -> void:
	GameSession.launched = false
	theme = UIKit.make_theme()
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_top()
	pages = [_build_play(), _build_fleet(), _build_maps()]
	for p in pages:
		add_child(p)
	_build_overlay()
	_browse_id = GameSession.ship_id
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
		elif a == "--launch":
			_launch.call_deferred()
		elif a.begins_with("--browse="):
			_browse(a.substr(9))


func _start_tab() -> int:
	var cl := OS.get_cmdline_user_args()
	var i := cl.find("--tab")
	if i >= 0 and i + 1 < cl.size():
		return clampi(int(cl[i + 1]), 0, 2)
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


func _build_top() -> void:
	var bar := Panel.new()
	var bb := UIKit.box(Color(0.05, 0.08, 0.13, 0.92), Color(0.03, 0.05, 0.09, 0.88), Color(1, 1, 1, 0.0), 0.0, 0.0)
	bb.border_w = 0.0
	bar.add_theme_stylebox_override("panel", bb)
	bar.position = Vector2.ZERO
	bar.size = Vector2(1920, 92)
	add_child(bar)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.85), Color(GOLD.r, GOLD.g, GOLD.b, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 512
	gt.height = 2
	var ln := TextureRect.new()
	ln.texture = gt
	ln.stretch_mode = TextureRect.STRETCH_SCALE
	ln.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ln.position = Vector2(0, 90)
	ln.size = Vector2(1920, 2)
	add_child(ln)
	var t := _lbl("HULL DOWN", 46, GOLD)
	t.position = Vector2(40, 8)
	t.add_theme_color_override("font_shadow_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
	t.add_theme_constant_override("shadow_outline_size", 12)
	add_child(t)
	var st := _lbl("SQUATCH SQUAD STUDIOS", 12, DIM)
	st.add_theme_font_override("font", UIKit.font("caps"))
	st.position = Vector2(44, 68)
	add_child(st)
	# pill tab group
	var grp := Panel.new()
	grp.add_theme_stylebox_override("panel", UIKit.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.12), 30.0, 0.0))
	grp.position = Vector2(600, 16)
	grp.size = Vector2(720, 60)
	add_child(grp)
	var names := ["PLAY", "FLEET STORE", "MAPS"]
	for k in 3:
		var b := Button.new()
		b.text = names[k]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UIKit.font("caps"))
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.position = Vector2(606 + k * 236, 22)
		b.size = Vector2(228, 48)
		b.pressed.connect(_show_tab.bind(k))
		add_child(b)
		tab_btns.append(b)
	credits_lbl = _lbl("TEST BUILD  -  ALL SHIPS UNLOCKED", 13, DIM)
	credits_lbl.add_theme_font_override("font", UIKit.font("caps"))
	credits_lbl.position = Vector2(1480, 38)
	add_child(credits_lbl)


func _show_tab(k: int) -> void:
	_tab = k
	for i in pages.size():
		pages[i].visible = (i == k)
	for i in tab_btns.size():
		var on := (i == k)
		var nb := UIKit.box(GOLD.darkened(0.15) if on else Color(0, 0, 0, 0), GOLD.darkened(0.55) if on else Color(0, 0, 0, 0),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.9) if on else Color(0, 0, 0, 0), 24.0, 0.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.45) if on else Color(0, 0, 0, 0), 8.0)
		tab_btns[i].add_theme_stylebox_override("normal", nb)
		tab_btns[i].add_theme_stylebox_override("hover", nb if on else UIKit.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.12), 24.0, 0.0, Color(0, 0, 0, 0), 8.0))
		tab_btns[i].add_theme_stylebox_override("pressed", nb)
		tab_btns[i].add_theme_color_override("font_color", Color("1a1204") if on else DIM)
		tab_btns[i].add_theme_color_override("font_hover_color", Color("1a1204") if on else Color.WHITE)
	var pg: Control = pages[k]
	pg.modulate.a = 0.0
	pg.position.y = 112
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(pg, "modulate:a", 1.0, 0.28)
	tw.tween_property(pg, "position:y", 92.0, 0.28)
	if k == 2:
		_queue_thumbs()


# --- PLAY ---------------------------------------------------------------------

func _build_play() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 92)
	page.size = Vector2(1920, 988)
	var cx := 30.0
	var w := 600.0
	# PvP
	_mode_card(page, Vector2(cx, 40), w, "PVP", "FLEET BATTLES  -  15 v 15", Color(0.35, 0.6, 1.0),
		["Human captains on both sides, one ship each.", "Seasonal ladders: rank, rewards and earnings reset each season.",
		"Live matches once the player base can fill both fleets.", "Fleet and ship progression carries across seasons."],
		"SEASON 1  -  COMING SOON")
	# Story
	_mode_card(page, Vector2(cx + w + 30, 40), w, "STORY MODE", "THE WAR AT SEA  -  CAMPAIGN", Color(0.5, 0.85, 0.5),
		["Fight the war's great surface actions in sequence.", "Command a flotilla through historical scenarios.",
		"Earn commendations, refits and new hulls.", "Built on the same ships and maps as Skirmish."],
		"IN DEVELOPMENT  -  COMING SOON")
	# Skirmish
	var x3 := cx + (w + 30) * 2
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UIKit.box(Color(0.15, 0.17, 0.2, 0.92), Color(0.07, 0.085, 0.12, 0.94), Color(GOLD.r, GOLD.g, GOLD.b, 0.75), 18.0, 0.8, Color(GOLD.r, GOLD.g, GOLD.b, 0.22), 14.0))
	card.position = Vector2(x3, 40)
	card.size = Vector2(w, 880)
	page.add_child(card)
	var head := _lbl("SKIRMISH", 38, GOLD)
	head.position = Vector2(24, 18)
	card.add_child(head)
	var sub := _lbl("TEST RANGE  -  15 v 15 AGAINST AI", 16, DIM)
	sub.position = Vector2(26, 70)
	card.add_child(sub)
	play_map_thumb = TextureRect.new()
	play_map_thumb.position = Vector2(24, 110)
	play_map_thumb.size = Vector2(w - 48, 300)
	play_map_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	play_map_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card.add_child(play_map_thumb)
	play_map_lbl = _lbl("", 22, INK)
	play_map_lbl.position = Vector2(24, 422)
	play_map_lbl.size = Vector2(w - 48, 60)
	card.add_child(play_map_lbl)
	play_ship_lbl = _lbl("", 22, GOLD)
	play_ship_lbl.position = Vector2(24, 500)
	play_ship_lbl.size = Vector2(w - 48, 30)
	card.add_child(play_ship_lbl)
	play_ship_sub = _lbl("", 15, DIM)
	play_ship_sub.position = Vector2(24, 534)
	play_ship_sub.size = Vector2(w - 48, 30)
	card.add_child(play_ship_sub)
	var bm := _btn("CHANGE MAP", _show_tab.bind(2), GOLD.darkened(0.2), 18)
	bm.position = Vector2(24, 600)
	bm.size = Vector2((w - 60) * 0.5, 50)
	card.add_child(bm)
	var bs := _btn("CHANGE SHIP", _show_tab.bind(1), GOLD.darkened(0.2), 18)
	bs.position = Vector2(24 + (w - 60) * 0.5 + 12, 600)
	bs.size = Vector2((w - 60) * 0.5, 50)
	card.add_child(bs)
	var go := _primary(_btn("LAUNCH BATTLE", _launch, Color(0.4, 0.9, 0.5), 30), Color("4ade80"))
	go.position = Vector2(24, 700)
	go.size = Vector2(w - 48, 90)
	card.add_child(go)
	var note := _lbl("ESC returns to this menu during battle.", 14, DIM)
	note.position = Vector2(24, 810)
	card.add_child(note)
	return page


func _mode_card(page: Control, pos: Vector2, w: float, title: String, tag: String, col: Color, bullets: Array, status: String) -> void:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UIKit.glass(18.0, 0.8))
	card.position = pos
	card.size = Vector2(w, 880)
	page.add_child(card)
	var band := Panel.new()
	band.add_theme_stylebox_override("panel", UIKit.box(col.darkened(0.25), col.darkened(0.7), Color(col.r, col.g, col.b, 0.5), 14.0, 0.0))
	band.position = Vector2(12, 12)
	band.size = Vector2(w - 24, 124)
	card.add_child(band)
	var h := _lbl(title, 46, col.lightened(0.25))
	h.position = Vector2(32, 24)
	card.add_child(h)
	var tg := _lbl(tag, 14, INK)
	tg.add_theme_font_override("font", UIKit.font("caps"))
	tg.position = Vector2(34, 92)
	card.add_child(tg)
	var wm := _lbl("15 v 15" if title == "PVP" else "1939-45", 120, Color(col.r, col.g, col.b, 0.07))
	wm.position = Vector2(20, 560)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(wm)
	var y := 172.0
	for b in bullets:
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", UIKit.box(col.lightened(0.2), col, Color(0, 0, 0, 0), 5.0, 0.0, Color(col.r, col.g, col.b, 0.6), 0.0))
		dot.position = Vector2(32, y + 9)
		dot.size = Vector2(10, 10)
		card.add_child(dot)
		var bl := _lbl(String(b), 18, Color(0.82, 0.87, 0.93), true)
		bl.position = Vector2(54, y)
		bl.size = Vector2(w - 84, 60)
		card.add_child(bl)
		y += 78.0
	var dis := _btn(status, func(): pass, col, 22)
	dis.disabled = true
	dis.position = Vector2(30, 760)
	dis.size = Vector2(w - 60, 70)
	card.add_child(dis)


func _refresh_selection() -> void:
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


# --- FLEET STORE ----------------------------------------------------------------

func _build_fleet() -> Control:
	var page := Control.new()
	page.position = Vector2(0, 92)
	page.size = Vector2(1920, 988)
	var left := Panel.new()
	left.add_theme_stylebox_override("panel", UIKit.glass(18.0, 0.7))
	left.position = Vector2(24, 20)
	left.size = Vector2(420, 944)
	page.add_child(left)
	nation_filter = OptionButton.new()
	nation_filter.add_item("All nations")
	for n in Roster.nations():
		nation_filter.add_item(String(n))
	nation_filter.position = Vector2(14, 14)
	nation_filter.size = Vector2(190, 38)
	nation_filter.item_selected.connect(func(_i): _fill_list())
	left.add_child(nation_filter)
	type_filter = OptionButton.new()
	type_filter.add_item("All classes")
	for t in ["battleship", "heavy_cruiser", "light_cruiser", "destroyer", "escort", "carrier"]:
		type_filter.add_item(t.replace("_", " ").capitalize())
	type_filter.position = Vector2(216, 14)
	type_filter.size = Vector2(190, 38)
	type_filter.item_selected.connect(func(_i): _fill_list())
	left.add_child(type_filter)
	var sc := ScrollContainer.new()
	sc.position = Vector2(8, 64)
	sc.size = Vector2(404, 870)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	ship_list = VBoxContainer.new()
	ship_list.custom_minimum_size = Vector2(392, 0)
	ship_list.add_theme_constant_override("separation", 6)
	sc.add_child(ship_list)

	viewer = ShipViewer.new()
	viewer.position = Vector2(460, 20)
	viewer.size = Vector2(800, 944)
	page.add_child(viewer)
	var vframe := Panel.new()
	vframe.add_theme_stylebox_override("panel", UIKit.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(1, 1, 1, 0.2), 14.0, 0.0, Color(0, 0, 0, 0), 0.0))
	vframe.position = viewer.position
	vframe.size = viewer.size
	vframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(vframe)
	var hint := _lbl("drag to rotate  -  wheel to zoom", 13, DIM)
	hint.position = Vector2(480, 936)
	page.add_child(hint)

	var right := Panel.new()
	right.add_theme_stylebox_override("panel", UIKit.glass(18.0, 0.7))
	right.position = Vector2(1276, 20)
	right.size = Vector2(620, 944)
	page.add_child(right)
	ship_title = _lbl("", 28, GOLD, true)
	ship_title.position = Vector2(20, 14)
	ship_title.size = Vector2(580, 40)
	right.add_child(ship_title)
	ship_sub = _lbl("", 16, DIM)
	ship_sub.position = Vector2(22, 56)
	right.add_child(ship_sub)
	stats = ShipStats.new()
	stats.position = Vector2(14, 100)
	stats.size = Vector2(596, 330)
	right.add_child(stats)
	ship_desc = _lbl("", 17, Color(0.82, 0.87, 0.92), true)
	ship_desc.position = Vector2(22, 450)
	ship_desc.size = Vector2(576, 150)
	right.add_child(ship_desc)
	ship_price = _lbl("", 26, INK)
	ship_price.position = Vector2(22, 760)
	right.add_child(ship_price)
	var own := _lbl("OWNED  (test build: every ship is unlocked)", 15, Color(0.5, 1.0, 0.6))
	own.position = Vector2(22, 800)
	right.add_child(own)
	select_btn = _primary(_btn("SELECT FOR SKIRMISH", _select_ship, Color(0.4, 0.9, 0.5), 24), Color("4ade80"))
	select_btn.position = Vector2(22, 840)
	select_btn.size = Vector2(576, 78)
	right.add_child(select_btn)
	return page


func _fill_list() -> void:
	for c in ship_list.get_children():
		c.queue_free()
	_row_btns.clear()
	var nat := "" if nation_filter.selected <= 0 else nation_filter.get_item_text(nation_filter.selected)
	var typ := "" if type_filter.selected <= 0 else type_filter.get_item_text(type_filter.selected).to_lower().replace(" ", "_")
	var list: Array = Roster.available().duplicate()
	var order := ["battleship", "heavy_cruiser", "light_cruiser", "destroyer", "escort", "carrier", "submarine"]
	list.sort_custom(func(a, b):
		if a["nation"] != b["nation"]:
			return String(a["nation"]) < String(b["nation"])
		var ia := order.find(a["type"])
		var ib := order.find(b["type"])
		if ia != ib:
			return ia < ib
		return float(a["displacement_t"]) > float(b["displacement_t"]))
	for e in list:
		if nat != "" and e["nation"] != nat:
			continue
		if typ != "" and e["type"] != typ:
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(388, 66)
		var id: String = e["id"]
		b.pressed.connect(_browse.bind(id))
		var nm := Label.new()
		nm.text = String(e["name"])
		nm.add_theme_font_override("font", UIKit.font("semi"))
		nm.add_theme_font_size_override("font_size", 16)
		nm.add_theme_color_override("font_color", INK)
		nm.position = Vector2(26, 9)
		nm.size = Vector2(350, 24)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var sb := Label.new()
		sb.text = "%s  -  %s" % [String(e["type"]).replace("_", " ").to_upper(), String(e["nation"]).to_upper()]
		sb.add_theme_font_override("font", UIKit.font("caps"))
		sb.add_theme_font_size_override("font_size", 11)
		sb.add_theme_color_override("font_color", DIM)
		sb.position = Vector2(26, 37)
		sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sb)
		var nc := _nation_color(String(e["nation"]))
		var stripe := Panel.new()
		stripe.add_theme_stylebox_override("panel", UIKit.box(nc.lightened(0.15), nc.darkened(0.3), Color(0, 0, 0, 0), 3.0, 0.0, Color(nc.r, nc.g, nc.b, 0.4), 0.0))
		stripe.position = Vector2(11, 14)
		stripe.size = Vector2(5, 38)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(stripe)
		ship_list.add_child(b)
		_row_btns[id] = b
	_style_rows()


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
	for id in _row_btns:
		var b: Button = _row_btns[id]
		var sel: bool = (id == _browse_id)
		var chosen: bool = (id == GameSession.ship_id)
		var acc := GOLD if sel else (UIKit.GREEN if chosen else Color(1, 1, 1))
		var n := UIKit.box(Color(0.30, 0.22, 0.08, 0.95) if sel else Color(0.12, 0.17, 0.26, 0.85), Color(0.15, 0.11, 0.05, 0.95) if sel else Color(0.07, 0.10, 0.16, 0.85),
			Color(acc.r, acc.g, acc.b, 0.85 if (sel or chosen) else 0.13), 12.0, 0.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.3) if sel else Color(0, 0, 0, 0), 6.0)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", UIKit.box(Color(0.2, 0.28, 0.4, 0.95), Color(0.12, 0.17, 0.26, 0.95), Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.7), 12.0, 0.0, Color(UIKit.CYAN.r, UIKit.CYAN.g, UIKit.CYAN.b, 0.22), 6.0))
		b.add_theme_stylebox_override("pressed", n)


func _browse(id: String) -> void:
	var e := Roster.get_entry(id)
	if e.is_empty():
		return
	_browse_id = id
	ship_title.text = String(e["name"])
	ship_sub.text = "%s  -  %s  -  %s" % [e["nation"], String(e["type"]).replace("_", " ").capitalize(), "launched class"]
	ship_sub.text = "%s  -  %s" % [e["nation"], String(e["type"]).replace("_", " ").capitalize()]
	stats.show_entry(e)
	ship_desc.text = String(TYPE_BLURB.get(e["type"], "")) + "\n\n" + _detail(e)
	ship_price.text = "PRICE   %s credits  (placeholder)" % _price_str(e)
	viewer.show_ship(e)
	_style_rows()
	_update_select_btn()


func _detail(e: Dictionary) -> String:
	var g: Dictionary = e["main_gun"]
	var turrets := (e["turret_z"] as Array).size()
	return "%d turrets x %d guns, %d mm shells of %d kg at %d m/s. %d boiler rooms, %d engine rooms, %d screws, %d funnel(s)." % [
		turrets, int(g["barrels_per_turret"]), int(g["caliber_mm"]), int(g["shell_kg"]), int(g["muzzle_ms"]),
		int(e.get("boiler_rooms", 0)), int(e.get("engine_rooms", 0)), int(e.get("screws", 2)), int(e.get("funnels", 1))]


func _price_str(e: Dictionary) -> String:
	var mult := {"battleship": 3.2, "heavy_cruiser": 2.2, "light_cruiser": 1.6, "destroyer": 1.0, "escort": 0.7, "carrier": 3.0}
	var p := int(round(pow(float(e["displacement_t"]), 0.8) * float(mult.get(e["type"], 1.5)) / 50.0)) * 50
	var s := str(p)
	if s.length() > 3:
		s = s.insert(s.length() - 3, ",")
	return s


func _select_ship() -> void:
	GameSession.ship_id = _browse_id
	_refresh_selection()
	_style_rows()
	_update_select_btn()


func _update_select_btn() -> void:
	var on := (_browse_id == GameSession.ship_id)
	select_btn.text = "SELECTED FOR SKIRMISH" if on else "SELECT FOR SKIRMISH"
	select_btn.disabled = on


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
	for chip in [String(g["date"]), String(g.get("weather", "clear")).capitalize(), tod]:
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
	var bl := _lbl(String(g["blurb"]), 15, Color(0.82, 0.87, 0.93), true)
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
	var dep := _primary(_btn("USE FOR SKIRMISH", _use_map, Color(0.4, 0.9, 0.5), 18), Color("4ade80"))
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
