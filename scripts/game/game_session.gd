extends Node
## Autoload "GameSession": what the menu hands to the battle scene.

var launched := false          ## true when a battle was started from the menu
var mode := "skirmish"         ## "skirmish" (15v15 vs AI); "pvp" and "story" are future modes
var ground_id := "surigao_strait"
var ship_id := "us_baltimore"


func launch(p_ground: String, p_ship: String, tree: SceneTree) -> void:
	ground_id = p_ground
	ship_id = p_ship
	launched = true
	tree.change_scene_to_file("res://scenes/testbed.tscn")


func back_to_menu(tree: SceneTree) -> void:
	launched = false
	tree.change_scene_to_file("res://scenes/main_menu.tscn")
