class_name BotBrain
extends RefCounted
## Inteligência artificial dos bots para partidas Practice e FFA offline (Dia 12 — GDD §9).
## - Mapa de perigo (bombas + reação em cadeia + chamas ativas)
## - BFS para rota de fuga segura
## - Verificação de rota de fuga antes de plantar bomba (anti-suicídio)
## - Coleta de power-ups, destruição de blocos e caça a adversários

const DIRS: Array[String] = ["up", "down", "left", "right"]

var player_id: String = ""
var difficulty: String = "medium" # "easy" | "medium" | "hard"
var rng: PRNG
var current_dir: String = "none"
var last_decision_tick: int = -100


func _init(p_id: String, p_difficulty: String = "medium", seed_val: int = 1) -> void:
	player_id = p_id
	difficulty = p_difficulty
	rng = PRNG.new(seed_val)


## Retorna {"dir": String, "bomb": bool} para o tick atual.
func decide(world: WorldSim) -> Dictionary:
	var me := world.get_player(player_id)
	if me == null or not me.alive:
		return {"dir": "none", "bomb": false}

	var danger := ArenaRenderer.compute_danger_cells(world)
	for fk: int in world.flames.keys():
		danger[fk] = 0

	var cx := me.cell_x()
	var cy := me.cell_y()
	var my_key := cy * world.grid.cols + cx

	# 1. Prioridade máxima: se estamos em célula perigosa, fugir imediatamente via BFS!
	if danger.has(my_key):
		var esc_dir := _bfs_find_safe_dir(world, me, danger)
		current_dir = esc_dir
		return {"dir": esc_dir, "bomb": false}

	# Intervalo de reação conforme dificuldade (mas nunca atrasa fuga de perigo acima)
	var react_interval := 2
	if difficulty == "easy":
		react_interval = 6
	elif difficulty == "medium":
		react_interval = 3
	else:
		react_interval = 1

	# Se está alinhando dentro da célula e a célula destino continua segura, mantém direção até o centro
	var center_x := cx * 1000 + 500
	var center_y := cy * 1000 + 500
	if (absi(me.x - center_x) > 100 or absi(me.y - center_y) > 100) and current_dir != "none":
		var dv := MovementRules.dir_vector(current_dir)
		var next_key := (cy + dv.y) * world.grid.cols + (cx + dv.x)
		if not danger.has(next_key):
			return {"dir": current_dir, "bomb": false}

	if world.tick - last_decision_tick < react_interval and current_dir != "none":
		var dv := MovementRules.dir_vector(current_dir)
		var nx := cx + dv.x
		var ny := cy + dv.y
		if _is_cell_walkable_and_safe(world, me.id, nx, ny, danger):
			return {"dir": current_dir, "bomb": false}

	last_decision_tick = world.tick

	# 2. Avalia se vale a pena plantar uma bomba aqui (há bloco destrutível ou inimigo no alcance + rota de fuga)
	if _should_place_bomb(world, me, danger):
		var escape_after_bomb := _find_escape_after_hypothetical_bomb(world, me, danger)
		if escape_after_bomb != "":
			current_dir = escape_after_bomb
			return {"dir": escape_after_bomb, "bomb": true}

	# 3. Coletar power-up seguro próximo via BFS
	var pu_dir := _bfs_toward_goal(world, me, danger, "powerup")
	if pu_dir != "":
		current_dir = pu_dir
		return {"dir": pu_dir, "bomb": false}

	# 4. Ir até célula adjacente a bloco destrutível ou adversário vivo
	var hunt_dir := _bfs_toward_goal(world, me, danger, "target")
	if hunt_dir != "":
		current_dir = hunt_dir
		return {"dir": hunt_dir, "bomb": false}

	# 5. Movimento seguro de patrulha
	var safe_dirs: Array[String] = []
	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		if _is_cell_walkable_and_safe(world, me.id, cx + dv.x, cy + dv.y, danger):
			safe_dirs.append(d)
	if safe_dirs.is_empty():
		current_dir = "none"
		return {"dir": "none", "bomb": false}
	current_dir = safe_dirs[rng.next_bound(safe_dirs.size())]
	return {"dir": current_dir, "bomb": false}


static func _is_cell_walkable(world: WorldSim, pid: String, cx: int, cy: int) -> bool:
	if world.grid.is_solid_tile(cx, cy):
		return false
	if world.is_cell_blocked_by_bomb(cx, cy, pid):
		return false
	if world.has_flame_at(cx, cy):
		return false
	return true


static func _is_cell_walkable_and_safe(world: WorldSim, pid: String, cx: int, cy: int, danger: Dictionary) -> bool:
	if not _is_cell_walkable(world, pid, cx, cy):
		return false
	var key := cy * world.grid.cols + cx
	return not danger.has(key)


static func _bfs_find_safe_dir(world: WorldSim, me: PlayerState, danger: Dictionary) -> String:
	var cols := world.grid.cols
	var start := Vector2i(me.cell_x(), me.cell_y())
	var visited := {start.y * cols + start.x: true}
	var queue: Array[Dictionary] = []

	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		var nx := start.x + dv.x
		var ny := start.y + dv.y
		if not _is_cell_walkable(world, me.id, nx, ny):
			continue
		var nkey := ny * cols + nx
		# Precisa ter tempo suficiente antes da detonação (~5 ticks por célula)
		var fuse_at_cell: int = int(danger.get(nkey, 999999))
		if fuse_at_cell <= 6:
			continue
		if not danger.has(nkey):
			return d
		visited[nkey] = true
		queue.append({"pos": Vector2i(nx, ny), "first_dir": d, "dist": 1})

	var q_idx := 0
	while q_idx < queue.size():
		var cur: Dictionary = queue[q_idx]
		q_idx += 1
		var pos: Vector2i = cur["pos"]
		var first_dir: String = cur["first_dir"]
		var dist: int = int(cur["dist"])
		if dist >= 8:
			continue
		for d in DIRS:
			var dv := MovementRules.dir_vector(d)
			var nx := pos.x + dv.x
			var ny := pos.y + dv.y
			var nkey := ny * cols + nx
			if visited.has(nkey) or not _is_cell_walkable(world, me.id, nx, ny):
				continue
			var req_ticks := (dist + 1) * 6
			if int(danger.get(nkey, 999999)) <= req_ticks:
				continue
			if not danger.has(nkey):
				return first_dir
			visited[nkey] = true
			queue.append({"pos": Vector2i(nx, ny), "first_dir": first_dir, "dist": dist + 1})

	# Se não achou célula 100% fora da cruz, escolhe vizinha caminhável com maior fuse restante
	var best_dir := "none"
	var best_fuse := -1
	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		var nx := start.x + dv.x
		var ny := start.y + dv.y
		if _is_cell_walkable(world, me.id, nx, ny):
			var f := int(danger.get(ny * cols + nx, 999999))
			if f > best_fuse:
				best_fuse = f
				best_dir = d
	return best_dir


func _should_place_bomb(world: WorldSim, me: PlayerState, danger: Dictionary) -> bool:
	if world.count_player_bombs(me.id) >= me.max_bombs:
		return false
	var cx := me.cell_x()
	var cy := me.cell_y()
	if world.get_bomb_at(cx, cy) != null:
		return false
	if danger.has(cy * world.grid.cols + cx):
		return false

	# Verifica se há bloco destrutível adjacente ou adversário na linha de tiro
	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		for step in range(1, me.bomb_range + 1):
			var nx := cx + dv.x * step
			var ny := cy + dv.y * step
			var t := world.grid.get_tile(nx, ny)
			if t == Grid.Tile.WALL:
				break
			if t == Grid.Tile.BLOCK:
				return true
			for other in world.players:
				if other.id != me.id and other.alive and other.cell_x() == nx and other.cell_y() == ny:
					return true
	return false


func _find_escape_after_hypothetical_bomb(world: WorldSim, me: PlayerState, current_danger: Dictionary) -> String:
	var hyp_danger := current_danger.duplicate()
	var cols := world.grid.cols
	var cx := me.cell_x()
	var cy := me.cell_y()
	hyp_danger[cy * cols + cx] = world.fuse_ticks
	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		for step in range(1, me.bomb_range + 1):
			var nx := cx + dv.x * step
			var ny := cy + dv.y * step
			var t := world.grid.get_tile(nx, ny)
			if t == Grid.Tile.WALL:
				break
			var k := ny * cols + nx
			hyp_danger[k] = mini(int(hyp_danger.get(k, 999999)), world.fuse_ticks)
			if t == Grid.Tile.BLOCK:
				break

	var esc := _bfs_find_safe_dir(world, me, hyp_danger)
	if esc == "none":
		return ""
	# Confirma que a rota encontrada realmente chega numa célula fora de hyp_danger
	var start := Vector2i(cx, cy)
	var visited := {cy * cols + cx: true}
	var queue: Array[Dictionary] = [{"pos": start, "dist": 0}]
	var q_idx := 0
	var has_true_safe := false
	while q_idx < queue.size():
		var cur: Dictionary = queue[q_idx]
		q_idx += 1
		var pos: Vector2i = cur["pos"]
		var dist: int = int(cur["dist"])
		var key := pos.y * cols + pos.x
		if not hyp_danger.has(key):
			has_true_safe = true
			break
		if dist >= 6:
			continue
		for d in DIRS:
			var dv := MovementRules.dir_vector(d)
			var nx := pos.x + dv.x
			var ny := pos.y + dv.y
			var nkey := ny * cols + nx
			if visited.has(nkey) or not _is_cell_walkable(world, me.id, nx, ny):
				continue
			visited[nkey] = true
			queue.append({"pos": Vector2i(nx, ny), "dist": dist + 1})

	return esc if has_true_safe else ""


func _bfs_toward_goal(world: WorldSim, me: PlayerState, danger: Dictionary, mode: String) -> String:
	var cols := world.grid.cols
	var start := Vector2i(me.cell_x(), me.cell_y())
	var visited := {start.y * cols + start.x: true}
	var queue: Array[Dictionary] = []

	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		var nx := start.x + dv.x
		var ny := start.y + dv.y
		if not _is_cell_walkable_and_safe(world, me.id, nx, ny, danger):
			continue
		var nkey := ny * cols + nx
		if _is_goal_cell(world, me, nx, ny, mode):
			return d
		visited[nkey] = true
		queue.append({"pos": Vector2i(nx, ny), "first_dir": d, "dist": 1})

	var q_idx := 0
	while q_idx < queue.size():
		var cur: Dictionary = queue[q_idx]
		q_idx += 1
		var pos: Vector2i = cur["pos"]
		var first_dir: String = cur["first_dir"]
		var dist: int = int(cur["dist"])
		if dist >= 16:
			continue
		for d in DIRS:
			var dv := MovementRules.dir_vector(d)
			var nx := pos.x + dv.x
			var ny := pos.y + dv.y
			var nkey := ny * cols + nx
			if visited.has(nkey) or not _is_cell_walkable_and_safe(world, me.id, nx, ny, danger):
				continue
			if _is_goal_cell(world, me, nx, ny, mode):
				return first_dir
			visited[nkey] = true
			queue.append({"pos": Vector2i(nx, ny), "first_dir": first_dir, "dist": dist + 1})

	return ""


static func _is_goal_cell(world: WorldSim, me: PlayerState, cx: int, cy: int, mode: String) -> bool:
	if mode == "powerup":
		return world.get_powerup_at(cx, cy) != ""
	# mode == "target": adjacente a bloco destrutível ou adversário vivo
	for d in DIRS:
		var dv := MovementRules.dir_vector(d)
		var nx := cx + dv.x
		var ny := cy + dv.y
		if world.grid.get_tile(nx, ny) == Grid.Tile.BLOCK:
			return true
		for other in world.players:
			if other.id != me.id and other.alive and other.cell_x() == nx and other.cell_y() == ny:
				return true
	return false

