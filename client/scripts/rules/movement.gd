class_name MovementRules
extends RefCounted
## Regras puras de movimentação em 4 direções com corner sliding determinístico (GDD §4, ARCHITECTURE D-11).
## 1 tile = 1000 militiles; desvio máximo de esquina = 400 militiles (40% de um tile).

const TILE_SIZE: int = 1000
const HALF_TILE: int = 500
const CORNER_TOLERANCE: int = 400

const VALID_DIRS: Array[String] = ["none", "up", "down", "left", "right"]


static func is_valid_dir(d: String) -> bool:
	return VALID_DIRS.has(d)


static func dir_vector(d: String) -> Vector2i:
	match d:
		"up":
			return Vector2i(0, -1)
		"down":
			return Vector2i(0, 1)
		"left":
			return Vector2i(-1, 0)
		"right":
			return Vector2i(1, 0)
		_:
			return Vector2i.ZERO


## Avança um tick de movimento para `player` sobre `grid`.
## `blocked_cell_fn` é um Callable opcional `func(cx: int, cy: int, player_id: String) -> bool`
## usado para bombas bloqueantes (Dia 08).
static func step_player(player: PlayerState, grid: Grid, blocked_cell_fn: Callable = Callable()) -> void:
	if not player.alive or player.disconnected:
		return
	var dv := dir_vector(player.dir)
	if dv == Vector2i.ZERO:
		return
	player.facing = player.dir
	var budget := player.speed
	if budget <= 0:
		return

	if dv.x != 0:
		_move_horizontal(player, grid, dv.x, budget, blocked_cell_fn)
	else:
		_move_vertical(player, grid, dv.y, budget, blocked_cell_fn)


static func _can_enter(grid: Grid, cx: int, cy: int, player_id: String, blocked_cell_fn: Callable) -> bool:
	if grid.is_solid_tile(cx, cy):
		return false
	if blocked_cell_fn.is_valid() and bool(blocked_cell_fn.call(cx, cy, player_id)):
		return false
	return true


@warning_ignore("integer_division")
static func _move_horizontal(player: PlayerState, grid: Grid, dx: int, budget: int, blocked_cell_fn: Callable) -> void:
	var cx: int = player.x / TILE_SIZE
	var cy: int = player.y / TILE_SIZE
	var center_x: int = cx * TILE_SIZE + HALF_TILE
	var center_y: int = cy * TILE_SIZE + HALF_TILE

	var target_y: int = -1
	var can_advance_current: bool = ((center_x - player.x) * dx > 0) or _can_enter(grid, cx + dx, cy, player.id, blocked_cell_fn)
	if can_advance_current:
		target_y = center_y
	else:
		# Corner sliding ao redor de um obstáculo em (cx + dx, cy) se o desvio da esquina for ≤ 40% do tile (400 mt)
		var dist_top: int = player.y - (cy * TILE_SIZE)
		var dist_bottom: int = ((cy + 1) * TILE_SIZE) - player.y
		if dist_top <= CORNER_TOLERANCE and _can_enter(grid, cx, cy - 1, player.id, blocked_cell_fn) and _can_enter(grid, cx + dx, cy - 1, player.id, blocked_cell_fn):
			target_y = (cy - 1) * TILE_SIZE + HALF_TILE
		elif dist_bottom <= CORNER_TOLERANCE and _can_enter(grid, cx, cy + 1, player.id, blocked_cell_fn) and _can_enter(grid, cx + dx, cy + 1, player.id, blocked_cell_fn):
			target_y = (cy + 1) * TILE_SIZE + HALF_TILE

	if target_y < 0:
		return

	if player.y != target_y:
		var diff_y: int = target_y - player.y
		var step_y: int = mini(absi(diff_y), budget)
		player.y += (1 if diff_y > 0 else -1) * step_y
		budget -= step_y

	if player.y != target_y or budget <= 0:
		return

	var row_y: int = player.y / TILE_SIZE
	while budget > 0:
		var cur_cx: int = player.x / TILE_SIZE
		var cur_center_x: int = cur_cx * TILE_SIZE + HALF_TILE
		if (cur_center_x - player.x) * dx > 0:
			var dist: int = absi(cur_center_x - player.x)
			var move: int = mini(dist, budget)
			player.x += dx * move
			budget -= move
		else:
			if not _can_enter(grid, cur_cx + dx, row_y, player.id, blocked_cell_fn):
				break
			var next_center_x: int = (cur_cx + dx) * TILE_SIZE + HALF_TILE
			var dist: int = absi(next_center_x - player.x)
			var move: int = mini(dist, budget)
			player.x += dx * move
			budget -= move


@warning_ignore("integer_division")
static func _move_vertical(player: PlayerState, grid: Grid, dy: int, budget: int, blocked_cell_fn: Callable) -> void:
	var cx: int = player.x / TILE_SIZE
	var cy: int = player.y / TILE_SIZE
	var center_x: int = cx * TILE_SIZE + HALF_TILE
	var center_y: int = cy * TILE_SIZE + HALF_TILE

	var target_x: int = -1
	var can_advance_current: bool = ((center_y - player.y) * dy > 0) or _can_enter(grid, cx, cy + dy, player.id, blocked_cell_fn)
	if can_advance_current:
		target_x = center_x
	else:
		# Corner sliding ao redor de um obstáculo em (cx, cy + dy) se o desvio da esquina for ≤ 40% do tile (400 mt)
		var dist_left: int = player.x - (cx * TILE_SIZE)
		var dist_right: int = ((cx + 1) * TILE_SIZE) - player.x
		if dist_left <= CORNER_TOLERANCE and _can_enter(grid, cx - 1, cy, player.id, blocked_cell_fn) and _can_enter(grid, cx - 1, cy + dy, player.id, blocked_cell_fn):
			target_x = (cx - 1) * TILE_SIZE + HALF_TILE
		elif dist_right <= CORNER_TOLERANCE and _can_enter(grid, cx + 1, cy, player.id, blocked_cell_fn) and _can_enter(grid, cx + 1, cy + dy, player.id, blocked_cell_fn):
			target_x = (cx + 1) * TILE_SIZE + HALF_TILE

	if target_x < 0:
		return

	if player.x != target_x:
		var diff_x: int = target_x - player.x
		var step_x: int = mini(absi(diff_x), budget)
		player.x += (1 if diff_x > 0 else -1) * step_x
		budget -= step_x

	if player.x != target_x or budget <= 0:
		return

	var col_x: int = player.x / TILE_SIZE
	while budget > 0:
		var cur_cy: int = player.y / TILE_SIZE
		var cur_center_y: int = cur_cy * TILE_SIZE + HALF_TILE
		if (cur_center_y - player.y) * dy > 0:
			var dist: int = absi(cur_center_y - player.y)
			var move: int = mini(dist, budget)
			player.y += dy * move
			budget -= move
		else:
			if not _can_enter(grid, col_x, cur_cy + dy, player.id, blocked_cell_fn):
				break
			var next_center_y: int = (cur_cy + dy) * TILE_SIZE + HALF_TILE
			var dist: int = absi(next_center_y - player.y)
			var move: int = mini(dist, budget)
			player.y += dy * move
			budget -= move
