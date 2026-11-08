class_name WorldSim
extends RefCounted
## Motor determinístico completo de simulação da partida (GDD §3–8, ARCHITECTURE §5, NETWORK_PROTOCOL §5.4).
## Ordem por tick:
##   1. Entradas -> 2. Movimento -> 3. Colocação de bombas -> 4. Pavios ->
##   5. Explosões / Reação em cadeia (FIFO) -> 6. Destruição de blocos e drops ->
##   7. Coleta de power-ups -> 8. Eliminações -> 9. Condição de vitória.

const DEFAULT_TICK_RATE: int = 20
const DEFAULT_DURATION_TICKS: int = 3600 # 3 min a 20 Hz

const SCORE_KILL: int = 100
const SCORE_BLOCK: int = 10
const SCORE_POWERUP: int = 5
const SCORE_WIN: int = 300
const SCORE_SELF_KILL: int = -50

var seed_value: int = 1
var tick: int = 0
var tick_rate: int = DEFAULT_TICK_RATE
var duration_ticks: int = DEFAULT_DURATION_TICKS
var fuse_ticks: int = BombState.DEFAULT_FUSE_TICKS
var flame_ticks: int = BombState.DEFAULT_FLAME_TICKS

var rng: PRNG
var grid: Grid
var players: Array[PlayerState] = []
var bombs: Array[BombState] = []
var next_bomb_id: int = 1

## Power-ups expostos no chão: chave = cy * cols + cx -> {"cx": int, "cy": int, "kind": String}
var powerups: Dictionary = {}

## Chamas ativas: chave = cy * cols + cx -> {"cx": int, "cy": int, "owner_id": String, "ticks_left": int}
var flames: Dictionary = {}

## Intenções pendentes para o próximo tick por player_id -> {"dir": String, "bomb": bool}
var pending_inputs: Dictionary = {}

var match_over: bool = false
var end_reason: String = "" # "last_alive" | "time_up" | "draw" | "aborted"
var winner_id: String = ""
var practice_mode: bool = false


func _init(p_seed: int = 1, player_ids: Array[String] = ["p0", "p1", "p2", "p3"], is_practice: bool = false, use_large_map: bool = false) -> void:
	seed_value = p_seed
	practice_mode = is_practice
	if use_large_map:
		grid = Grid.generate(seed_value, player_ids.size(), Grid.LARGE_COLS, Grid.LARGE_ROWS)
	else:
		grid = Grid.generate(seed_value, player_ids.size())
	# O PRNG de drops continua a partir de uma derivada determinística do seed da partida
	rng = PRNG.new((seed_value ^ 0x9E3779B9) & 0xFFFFFFFF)

	var spawns := Grid.get_spawns_for_size(grid.cols, grid.rows)
	for i in range(player_ids.size()):
		var spawn := spawns[i % spawns.size()]
		var p := PlayerState.new(player_ids[i], i, spawn)
		var char_idx := i % 4
		var suffix: String = ["a", "b", "c", "d"][char_idx]
		p.character_id = "sparky_%s" % suffix
		p.skin_id = "sparky_%s_default" % suffix
		players.append(p)


func get_player(player_id: String) -> PlayerState:
	for p in players:
		if p.id == player_id:
			return p
	return null


func set_input(player_id: String, dir: String, place_bomb: bool) -> void:
	var clean_dir := dir if MovementRules.is_valid_dir(dir) else "none"
	if pending_inputs.has(player_id):
		var prev: Dictionary = pending_inputs[player_id]
		pending_inputs[player_id] = {
			"dir": clean_dir,
			"bomb": bool(prev.get("bomb", false)) or place_bomb,
		}
	else:
		pending_inputs[player_id] = {
			"dir": clean_dir,
			"bomb": place_bomb,
		}


func get_bomb_at(cx: int, cy: int) -> BombState:
	for b in bombs:
		if b.cx == cx and b.cy == cy:
			return b
	return null


func count_player_bombs(player_id: String) -> int:
	var c := 0
	for b in bombs:
		if b.owner_id == player_id:
			c += 1
	return c


func is_cell_blocked_by_bomb(cx: int, cy: int, player_id: String) -> bool:
	var b := get_bomb_at(cx, cy)
	if b == null:
		return false
	return b.blocks_player(player_id)


func place_powerup(cx: int, cy: int, kind: String) -> void:
	var key := cy * grid.cols + cx
	powerups[key] = {"cx": cx, "cy": cy, "kind": kind}


func get_powerup_at(cx: int, cy: int) -> String:
	var key := cy * grid.cols + cx
	if not powerups.has(key):
		return ""
	return str(powerups[key]["kind"])


func has_flame_at(cx: int, cy: int) -> bool:
	return flames.has(cy * grid.cols + cx)


## Executa 1 tick completo da simulação e retorna a lista de eventos gerados no tick.
func step_tick() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if match_over:
		return events

	tick += 1

	# Atualiza timers de escudo, invulnerabilidade pós-escudo e chamas existentes
	for p in players:
		if p.shield_ticks > 0:
			p.shield_ticks -= 1
		if p.invulnerable_ticks > 0:
			p.invulnerable_ticks -= 1

	var expired_flames: Array[int] = []
	for k: int in flames.keys():
		var f: Dictionary = flames[k]
		f["ticks_left"] = int(f["ticks_left"]) - 1
		if int(f["ticks_left"]) <= 0:
			expired_flames.append(k)
	for k in expired_flames:
		flames.erase(k)

	# 1. Entradas & 2. Movimento
	var bomb_requests: Array[PlayerState] = []
	for p in players:
		if not p.alive or p.disconnected:
			continue
		if pending_inputs.has(p.id):
			var inp: Dictionary = pending_inputs[p.id]
			p.dir = str(inp.get("dir", p.dir))
			if bool(inp.get("bomb", false)):
				bomb_requests.append(p)
		MovementRules.step_player(p, grid, Callable(self, "is_cell_blocked_by_bomb"))

	pending_inputs.clear()

	# Atualiza anti-prisão das bombas existentes após o movimento
	for b in bombs:
		b.update_pass_through(players)

	# 4. Pavios das bombas que já estavam plantadas antes deste tick
	var detonate_queue: Array[BombState] = []
	var queued_ids: Dictionary = {}
	for b in bombs:
		b.fuse -= 1
		if b.fuse <= 0:
			detonate_queue.append(b)
			queued_ids[b.id] = true

	# 3. Colocação de novas bombas (nascem com fuse = fuse_ticks no fim deste tick)
	for p in bomb_requests:
		var cx := p.cell_x()
		var cy := p.cell_y()
		if grid.get_tile(cx, cy) != Grid.Tile.EMPTY:
			continue
		if get_bomb_at(cx, cy) != null:
			continue
		if count_player_bombs(p.id) >= p.max_bombs:
			continue
		var nb := BombState.new(next_bomb_id, p.id, cx, cy, fuse_ticks, p.bomb_range)
		next_bomb_id += 1
		for other in players:
			if other.alive and other.overlaps_cell(cx, cy):
				nb.pass_through_ids[other.id] = true
		bombs.append(nb)
		events.append({
			"k": "bomb_placed",
			"id": nb.id,
			"owner": p.id,
			"cx": cx,
			"cy": cy,
		})

	# 5. Explosões e reação em cadeia (FIFO determinístico por ordem de acionamento e id)
	var destroyed_blocks: Dictionary = {} # key (cy*cols+cx) -> {"cx": int, "cy": int, "owner_id": String}
	var tick_flame_cells: Dictionary = {} # key (cy*cols+cx) -> {"cx": int, "cy": int, "owner_id": String}
	var detonated_ids: Dictionary = {}

	var q_idx := 0
	while q_idx < detonate_queue.size():
		var b: BombState = detonate_queue[q_idx]
		q_idx += 1
		detonated_ids[b.id] = true

		var blast_cells: Array = [[b.cx, b.cy]]
		var center_key := b.cy * grid.cols + b.cx
		if not tick_flame_cells.has(center_key):
			tick_flame_cells[center_key] = {"cx": b.cx, "cy": b.cy, "owner_id": b.owner_id}
		flames[center_key] = {"cx": b.cx, "cy": b.cy, "owner_id": b.owner_id, "ticks_left": flame_ticks}

		# Verifica se há outra bomba na mesma célula (improvável, mas seguro)
		var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		var newly_triggered: Array[BombState] = []

		for d in dirs:
			for step in range(1, b.bomb_range + 1):
				var nx := b.cx + d.x * step
				var ny := b.cy + d.y * step
				var t := grid.get_tile(nx, ny)
				if t == Grid.Tile.WALL:
					break
				var key := ny * grid.cols + nx
				blast_cells.append([nx, ny])
				if not tick_flame_cells.has(key):
					tick_flame_cells[key] = {"cx": nx, "cy": ny, "owner_id": b.owner_id}
				flames[key] = {"cx": nx, "cy": ny, "owner_id": b.owner_id, "ticks_left": flame_ticks}

				if t == Grid.Tile.BLOCK:
					if not destroyed_blocks.has(key):
						destroyed_blocks[key] = {"cx": nx, "cy": ny, "owner_id": b.owner_id}
					break

				var other_bomb := get_bomb_at(nx, ny)
				if other_bomb != null and not queued_ids.has(other_bomb.id):
					other_bomb.fuse = 0
					queued_ids[other_bomb.id] = true
					newly_triggered.append(other_bomb)

		# Ordena bombas acionadas por esta explosão por id crescente (GDD §6)
		newly_triggered.sort_custom(func(a: BombState, c: BombState) -> bool: return a.id < c.id)
		for tb in newly_triggered:
			detonate_queue.append(tb)

		events.append({
			"k": "explosion",
			"bomb_id": b.id,
			"owner": b.owner_id,
			"cells": blast_cells,
		})

	if not detonated_ids.is_empty():
		var remaining_bombs: Array[BombState] = []
		for b in bombs:
			if not detonated_ids.has(b.id):
				remaining_bombs.append(b)
		bombs = remaining_bombs

	# 6. Destruição de power-ups já expostos + destruição de blocos e geração de drops
	var exposed_keys: Array = tick_flame_cells.keys()
	exposed_keys.sort()
	for key: int in exposed_keys:
		if powerups.has(key):
			var pu: Dictionary = powerups[key]
			powerups.erase(key)
			events.append({
				"k": "powerup_destroyed",
				"cx": int(pu["cx"]),
				"cy": int(pu["cy"]),
			})

	var block_keys: Array = destroyed_blocks.keys()
	block_keys.sort()
	for key: int in block_keys:
		var info: Dictionary = destroyed_blocks[key]
		var bx: int = info["cx"]
		var by: int = info["cy"]
		var owner_id: String = info["owner_id"]
		grid.set_tile(bx, by, Grid.Tile.EMPTY)
		var owner_p := get_player(owner_id)
		if owner_p != null:
			owner_p.blocks_destroyed += 1
			owner_p.score += SCORE_BLOCK
		var drop_kind := PowerUpDef.roll_drop(rng)
		if drop_kind != "":
			place_powerup(bx, by, drop_kind)
		events.append({
			"k": "block_destroyed",
			"cx": bx,
			"cy": by,
			"drop": drop_kind if drop_kind != "" else null,
		})

	# 7. Coleta de power-ups
	for p in players:
		if not p.alive:
			continue
		var cx := p.cell_x()
		var cy := p.cell_y()
		var key := cy * grid.cols + cx
		if powerups.has(key):
			var pu: Dictionary = powerups[key]
			var kind := str(pu["kind"])
			powerups.erase(key)
			PowerUpDef.apply_kind(p, kind)
			p.powerups_collected += 1
			p.score += SCORE_POWERUP
			events.append({
				"k": "powerup_collected",
				"player": p.id,
				"cx": cx,
				"cy": cy,
				"kind": kind,
			})

	# 8. Eliminações (por chamas ativas na célula do jogador)
	for p in players:
		if not p.alive:
			continue
		var key := p.cell_y() * grid.cols + p.cell_x()
		if not flames.has(key):
			continue
		if p.invulnerable_ticks > 0:
			continue
		if p.shield_ticks > 0:
			p.shield_ticks = 0
			p.invulnerable_ticks = flame_ticks
			events.append({
				"k": "shield_broken",
				"player": p.id,
			})
			continue

		var f: Dictionary = flames[key]
		var by_id := str(f.get("owner_id", ""))
		p.alive = false
		p.deaths += 1
		if by_id == p.id:
			p.score += SCORE_SELF_KILL
		else:
			var killer := get_player(by_id)
			if killer != null:
				killer.kills += 1
				killer.score += SCORE_KILL
		events.append({
			"k": "player_eliminated",
			"player": p.id,
			"by": by_id,
		})

	# 9. Condição de vitória
	_check_victory()

	return events


func _check_victory() -> void:
	if match_over:
		return
	var alive_list: Array[PlayerState] = []
	for p in players:
		if p.alive and not p.disconnected:
			alive_list.append(p)

	if players.size() > 1 and alive_list.size() <= 1:
		match_over = true
		if alive_list.size() == 1:
			winner_id = alive_list[0].id
			end_reason = "last_alive"
			alive_list[0].score += SCORE_WIN
		else:
			winner_id = ""
			end_reason = "draw"
		return

	if tick >= duration_ticks:
		match_over = true
		if alive_list.is_empty():
			winner_id = ""
			end_reason = "draw"
			return
		var best_score := -999999999
		var best_players: Array[PlayerState] = []
		for p in alive_list:
			if p.score > best_score:
				best_score = p.score
				best_players = [p]
			elif p.score == best_score:
				best_players.append(p)
		if best_players.size() == 1:
			winner_id = best_players[0].id
			end_reason = "time_up"
			best_players[0].score += SCORE_WIN
		else:
			winner_id = ""
			end_reason = "draw"


func to_state_dict(full: bool = false) -> Dictionary:
	var p_arr: Array = []
	for p in players:
		p_arr.append(p.to_dict())
	var b_arr: Array = []
	for b in bombs:
		b_arr.append(b.to_dict())
	var out := {
		"tick": tick,
		"full": full,
		"players": p_arr,
		"bombs": b_arr,
	}
	if full:
		out["grid"] = grid.to_compact_string()
		var pu_arr: Array = []
		var keys := powerups.keys()
		keys.sort()
		for k in keys:
			pu_arr.append(powerups[k])
		out["powerups"] = pu_arr
	return out
