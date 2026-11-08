class_name BombState
extends RefCounted
## Estado puro de uma bomba ativa na arena (GDD §5, ARCHITECTURE D-13).

const DEFAULT_FUSE_TICKS: int = 50 # 2,5 s a 20 Hz
const DEFAULT_FLAME_TICKS: int = 10 # 0,5 s a 20 Hz

var id: int = 0
var owner_id: String = ""
var cx: int = 0
var cy: int = 0
var fuse: int = DEFAULT_FUSE_TICKS
var bomb_range: int = 2

## IDs de jogadores que estavam sobrepondo (cx, cy) quando a bomba foi plantada.
## Podem atravessar esta célula até saírem completamente dela (anti-prisão, GDD §5).
var pass_through_ids: Dictionary = {}


func _init(p_id: int = 1, p_owner: String = "", p_cx: int = 1, p_cy: int = 1, p_fuse: int = DEFAULT_FUSE_TICKS, p_range: int = 2) -> void:
	id = p_id
	owner_id = p_owner
	cx = p_cx
	cy = p_cy
	fuse = p_fuse
	bomb_range = p_range


func blocks_player(player_id: String) -> bool:
	return not pass_through_ids.has(player_id)


func update_pass_through(players: Array[PlayerState]) -> void:
	if pass_through_ids.is_empty():
		return
	var to_remove: Array[String] = []
	for pid: String in pass_through_ids.keys():
		var still_overlapping := false
		for p in players:
			if p.id == pid and p.alive and p.overlaps_cell(cx, cy):
				still_overlapping = true
				break
		if not still_overlapping:
			to_remove.append(pid)
	for pid in to_remove:
		pass_through_ids.erase(pid)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner_id,
		"cx": cx,
		"cy": cy,
		"fuse": fuse,
		"range": bomb_range,
	}

