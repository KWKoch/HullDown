extends Node
## Autoload "Progress": the player's career. Story Mode raises the commission rank, and rank opens
## the close-quarters battlegrounds. Saved to user://progress.cfg. Launch with --unlock-all to test.

const PATH := "user://progress.cfg"

var rank := 0                       ## index into Battlegrounds.RANKS
var unlock_all := false
var viewed := {}                    ## ship ids looked at this session (drives the NEW badge)


func _ready() -> void:
	unlock_all = OS.get_cmdline_user_args().has("--unlock-all")
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		rank = clampi(int(cf.get_value("career", "rank", 0)), 0, Battlegrounds.RANKS.size() - 1)


func rank_name() -> String:
	return Battlegrounds.RANKS[rank]


func set_rank(r: int) -> void:
	rank = clampi(r, 0, Battlegrounds.RANKS.size() - 1)
	var cf := ConfigFile.new()
	cf.set_value("career", "rank", rank)
	cf.save(PATH)


## Open-water grounds are always available; the rest need the commission rank from Story Mode.
func is_unlocked(ground_id: String) -> bool:
	return unlock_all or Battlegrounds.is_pvp(ground_id) or rank >= Battlegrounds.unlock_rank(ground_id)


## Ships the player owns. Test build: every ship. (Currencies and unlocking come later.)
func ship_owned(_id: String) -> bool:
	return true
