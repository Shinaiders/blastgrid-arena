class_name ArenaRenderer
extends Node2D
## Renderizador 2D do BlastGrid Arena (Overhaul Visual e de Animação).
## Desenha arena 15×13 com profundidade 3D, petardos com pavio dinâmico, feixes de chamas
## conectados em cruz, e os robôs-mascote "Sparkies" com animações completas e expressivas.

const TILE_PX: float = 48.0
const MILITILE_TO_PX: float = TILE_PX / 1000.0

## Cores dos 8 slots (GDD §2: coral, ciano, lima, âmbar, violeta, rosa, azul, branco).
const PLAYER_COLORS: Array[Color] = [
	Color(1.00, 0.37, 0.35, 1.0), # 0: Volt (Coral)
	Color(0.00, 0.85, 0.84, 1.0), # 1: Ember (Ciano)
	Color(0.55, 0.91, 0.45, 1.0), # 2: Moss (Lima)
	Color(1.00, 0.78, 0.15, 1.0), # 3: Frost (Âmbar)
	Color(0.70, 0.58, 0.99, 1.0), # 4: Violeta
	Color(0.97, 0.51, 0.68, 1.0), # 5: Rosa
	Color(0.30, 0.67, 0.97, 1.0), # 6: Azul
	Color(0.96, 0.97, 0.99, 1.0), # 7: Branco
]

const PLAYER_NAMES: Array[String] = [
	"Volt", "Ember", "Moss", "Frost", "Nova", "Pulse", "Bolt", "Glint"
]

var sim: WorldSim = null
var interp_alpha: float = 1.0
var anim_time: float = 0.0
var prev_player_pos: Dictionary = {} # player_id -> Vector2 (militiles)
var particles: Array[Dictionary] = []

## Estado de animação rica por jogador e impacto visual de screen shake
var player_anim: Dictionary = {} # player_id -> Dictionary
var shake_trauma: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var base_position: Vector2 = Vector2(28, 48)
var fit_offset: Vector2 = Vector2.ZERO

var _round_box_sb: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	if position != Vector2.ZERO:
		base_position = position


func bind_sim(world: WorldSim) -> void:
	sim = world
	prev_player_pos.clear()
	particles.clear()
	player_anim.clear()
	shake_trauma = 0.0
	shake_offset = Vector2.ZERO
	if sim != null:
		var map_w := float(sim.grid.cols) * TILE_PX
		var map_h := float(sim.grid.rows) * TILE_PX
		var fit_s := minf(720.0 / map_w, 624.0 / map_h)
		scale = Vector2(fit_s, fit_s)
		fit_offset = Vector2((720.0 - map_w * fit_s) * 0.5, (624.0 - map_h * fit_s) * 0.5)
		for p in sim.players:
			prev_player_pos[p.id] = Vector2(p.x, p.y)
			_get_player_anim(p.id)
	position = base_position + fit_offset
	queue_redraw()


func snapshot_positions_before_tick() -> void:
	if sim == null:
		return
	for p in sim.players:
		prev_player_pos[p.id] = Vector2(p.x, p.y)


func _get_player_anim(p_id: String) -> Dictionary:
	if not player_anim.has(p_id):
		player_anim[p_id] = {
			"walk_phase": 0.0,
			"move_blend": 0.0,
			"lean": Vector2.ZERO,
			"squash": 1.0,
			"ant_vel": Vector2.ZERO,
			"ant_offset": Vector2.ZERO,
			"death_time": 0.0,
			"dust_timer": 0.0,
			"was_alive": true,
		}
	return player_anim[p_id]


func on_tick_events(events: Array[Dictionary]) -> void:
	for e in events:
		var k := str(e.get("k", ""))
		if k == "explosion":
			shake_trauma = minf(shake_trauma + 0.55, 1.0)
			var cells: Array = e.get("cells", [])
			for c: Array in cells:
				var cx := int(c[0])
				var cy := int(c[1])
				_spawn_explosion_particles(cx, cy)
		elif k == "block_destroyed":
			var bx := int(e.get("cx", 0))
			var by := int(e.get("cy", 0))
			_spawn_block_particles(bx, by)
		elif k == "powerup_collected":
			var px := int(e.get("cx", 0))
			var py := int(e.get("cy", 0))
			_spawn_powerup_particles(px, py)


func _spawn_explosion_particles(cx: int, cy: int) -> void:
	var center := Vector2((cx + 0.5) * TILE_PX, (cy + 0.5) * TILE_PX)
	# 1. Fogo brilhante e plasma
	for i in range(5):
		var angle := randf_range(0.0, TAU)
		var spd := randf_range(32.0, 78.0)
		var col := Color(1.0, 0.42, 0.10, 0.95).lerp(Color(1.0, 0.90, 0.25, 0.95), randf())
		particles.append({
			"pos": center + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)),
			"vel": Vector2(cos(angle), sin(angle)) * spd,
			"color": col,
			"life": randf_range(0.24, 0.38),
			"max_life": 0.38,
			"size": randf_range(7.0, 13.0),
			"drag": 2.2,
			"grav": 0.0,
			"shape": "circle",
		})
	# 2. Faíscas rápidas incandescentes
	for i in range(6):
		var angle := randf_range(0.0, TAU)
		var spd := randf_range(75.0, 135.0)
		particles.append({
			"pos": center,
			"vel": Vector2(cos(angle), sin(angle)) * spd,
			"color": Color(1.0, 0.96, 0.75, 1.0),
			"life": randf_range(0.16, 0.28),
			"max_life": 0.28,
			"size": randf_range(2.0, 3.5),
			"drag": 1.2,
			"grav": 40.0,
			"shape": "box",
		})
	# 3. Fumaça escura que sobe suavemente
	for i in range(3):
		var spd := randf_range(14.0, 30.0)
		particles.append({
			"pos": center + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)),
			"vel": Vector2(randf_range(-14.0, 14.0), -spd),
			"color": Color(0.22, 0.19, 0.27, 0.62),
			"life": randf_range(0.40, 0.62),
			"max_life": 0.62,
			"size": randf_range(8.0, 16.0),
			"drag": 1.0,
			"grav": -12.0,
			"shape": "circle",
		})


func _spawn_block_particles(cx: int, cy: int) -> void:
	var center := Vector2((cx + 0.5) * TILE_PX, (cy + 0.5) * TILE_PX)
	var confetti_cols: Array[Color] = [
		Color(0.98, 0.35, 0.45, 1.0),
		Color(0.25, 0.85, 0.70, 1.0),
		Color(1.00, 0.82, 0.20, 1.0),
		Color(0.62, 0.45, 0.95, 1.0),
	]
	for i in range(8):
		var angle := (TAU * float(i)) / 8.0 + randf_range(-0.3, 0.3)
		var spd := randf_range(35.0, 85.0)
		particles.append({
			"pos": center,
			"vel": Vector2(cos(angle), sin(angle)) * spd,
			"color": confetti_cols[i % confetti_cols.size()],
			"life": randf_range(0.35, 0.52),
			"max_life": 0.52,
			"size": randf_range(4.0, 7.0),
			"drag": 1.6,
			"grav": 35.0,
			"shape": "box",
		})


func _spawn_powerup_particles(cx: int, cy: int) -> void:
	var center := Vector2((cx + 0.5) * TILE_PX, (cy + 0.5) * TILE_PX)
	for i in range(6):
		var angle := (TAU * float(i)) / 6.0 + anim_time * 2.0
		var spd := randf_range(28.0, 55.0)
		particles.append({
			"pos": center,
			"vel": Vector2(cos(angle), sin(angle)) * spd,
			"color": Color(0.35, 0.95, 1.0, 1.0).lerp(Color(1.0, 0.9, 0.3, 1.0), float(i % 2)),
			"life": 0.35,
			"max_life": 0.35,
			"size": randf_range(3.5, 6.0),
			"drag": 2.0,
			"grav": -20.0,
			"shape": "box",
		})


func _spawn_foot_dust(pos: Vector2, facing: String) -> void:
	var feet_pos := pos + Vector2(0.0, 13.0)
	var back_dir := Vector2.ZERO
	match facing:
		"up": back_dir = Vector2(0.0, 1.0)
		"down": back_dir = Vector2(0.0, -1.0)
		"left": back_dir = Vector2(1.0, 0.0)
		"right": back_dir = Vector2(-1.0, 0.0)
	for i in range(2):
		var rand_offset := Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0))
		var v := back_dir * randf_range(10.0, 22.0) + Vector2(randf_range(-6.0, 6.0), randf_range(-8.0, -2.0))
		particles.append({
			"pos": feet_pos + rand_offset,
			"vel": v,
			"color": Color(0.82, 0.86, 0.95, 0.36),
			"life": 0.22,
			"max_life": 0.22,
			"size": randf_range(3.0, 5.0),
			"drag": 3.0,
			"grav": -10.0,
			"shape": "circle",
		})


func step_visuals(delta: float, alpha: float) -> void:
	anim_time += delta
	interp_alpha = clampf(alpha, 0.0, 1.0)

	# Decaimento do screen shake
	shake_trauma = maxf(shake_trauma - delta * 2.8, 0.0)
	if shake_trauma > 0.001:
		var intensity := shake_trauma * shake_trauma * 9.0
		shake_offset = Vector2(
			sin(anim_time * 68.0) * intensity,
			cos(anim_time * 84.0) * intensity
		)
	else:
		shake_offset = Vector2.ZERO
	position = base_position + fit_offset + shake_offset

	# Atualização do ciclo de animação e física dos personagens
	if sim != null:
		for p in sim.players:
			var panim := _get_player_anim(p.id)
			var curr_mt := Vector2(p.x, p.y)
			var prev_mt: Vector2 = prev_player_pos.get(p.id, curr_mt)
			var is_moving: bool = p.dir != "none" or curr_mt.distance_to(prev_mt) > 2.0
			var target_blend := 1.0 if (is_moving and p.alive) else 0.0
			panim["move_blend"] = lerpf(float(panim["move_blend"]), target_blend, clampf(delta * 14.0, 0.0, 1.0))
			var blend: float = float(panim["move_blend"])

			if blend > 0.02:
				panim["walk_phase"] = float(panim["walk_phase"]) + delta * 18.0 * blend
			else:
				var wp: float = float(panim["walk_phase"])
				var target_wp := roundf(wp / TAU) * TAU
				panim["walk_phase"] = move_toward(wp, target_wp, delta * 10.0)

			# Inclinação do corpo (lean)
			var target_lean := Vector2.ZERO
			match p.facing:
				"up": target_lean = Vector2(0.0, -1.8)
				"down": target_lean = Vector2(0.0, 1.2)
				"left": target_lean = Vector2(-2.2, 0.0)
				"right": target_lean = Vector2(2.2, 0.0)
			target_lean *= blend
			panim["lean"] = (panim["lean"] as Vector2).lerp(target_lean, clampf(delta * 12.0, 0.0, 1.0))

			# Squash & stretch dinâmico
			var target_squash := 1.0
			if not p.alive:
				target_squash = 1.0
			elif sim.match_over and sim.winner_id == p.id:
				target_squash = 1.0 + sin(anim_time * 14.0) * 0.16
			elif blend > 0.1:
				target_squash = 1.0 + sin(float(panim["walk_phase"]) * 2.0) * 0.08 * blend
			panim["squash"] = lerpf(float(panim["squash"]), target_squash, clampf(delta * 15.0, 0.0, 1.0))

			# Física de mola na ponta da antena
			var target_ant: Vector2 = -(panim["lean"] as Vector2) * 1.6
			var k := 160.0
			var d := 14.0
			var ant_offset: Vector2 = panim["ant_offset"]
			var ant_vel: Vector2 = panim["ant_vel"]
			var diff := ant_offset - target_ant
			var force := -k * diff - d * ant_vel
			ant_vel += force * delta
			ant_offset += ant_vel * delta
			panim["ant_vel"] = ant_vel
			panim["ant_offset"] = ant_offset.limit_length(7.0)

			# Tempo de derrota
			if not p.alive:
				panim["death_time"] = float(panim["death_time"]) + delta
			else:
				panim["death_time"] = 0.0

			# Emissão suave de poeira nos pés ao correr
			if p.alive and blend > 0.45:
				var dt: float = float(panim["dust_timer"]) + delta
				if dt >= 0.11:
					dt = 0.0
					var interp_mt := prev_mt.lerp(curr_mt, interp_alpha)
					var p_pos := interp_mt * MILITILE_TO_PX
					_spawn_foot_dust(p_pos, p.facing)
				panim["dust_timer"] = dt
			else:
				panim["dust_timer"] = 0.0

	# Atualização e limpeza de partículas
	var alive_particles: Array[Dictionary] = []
	for pt in particles:
		var life: float = float(pt["life"]) - delta
		if life > 0.0:
			pt["life"] = life
			var vel: Vector2 = pt.get("vel", Vector2.ZERO)
			var drag: float = float(pt.get("drag", 0.0))
			if drag > 0.0:
				vel = vel.move_toward(Vector2.ZERO, vel.length() * drag * delta)
				pt["vel"] = vel
			var grav: float = float(pt.get("grav", 0.0))
			if grav != 0.0:
				vel.y += grav * delta
				pt["vel"] = vel
			pt["pos"] = (pt["pos"] as Vector2) + vel * delta
			alive_particles.append(pt)
	if alive_particles.size() > 250:
		alive_particles = alive_particles.slice(alive_particles.size() - 250)
	particles = alive_particles
	queue_redraw()


static func compute_danger_cells(world: WorldSim) -> Dictionary:
	## Retorna Dictionary (cy * cols + cx) -> menor fuse em ticks até explosão (considerando cadeia).
	var danger := {}
	if world == null or world.bombs.is_empty():
		return danger

	var eff_fuse := {}
	for b in world.bombs:
		eff_fuse[b.id] = b.fuse

	var changed := true
	while changed:
		changed = false
		for b in world.bombs:
			var f_b: int = eff_fuse[b.id]
			var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
			for d in dirs:
				for step in range(1, b.bomb_range + 1):
					var nx := b.cx + d.x * step
					var ny := b.cy + d.y * step
					var t := world.grid.get_tile(nx, ny)
					if t == Grid.Tile.WALL or t == Grid.Tile.BLOCK:
						break
					var other := world.get_bomb_at(nx, ny)
					if other != null and int(eff_fuse[other.id]) > f_b:
						eff_fuse[other.id] = f_b
						changed = true

	for b in world.bombs:
		var f: int = eff_fuse[b.id]
		var ckey := b.cy * world.grid.cols + b.cx
		danger[ckey] = mini(int(danger.get(ckey, 999999)), f)
		var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
		for d in dirs:
			for step in range(1, b.bomb_range + 1):
				var nx := b.cx + d.x * step
				var ny := b.cy + d.y * step
				var t := world.grid.get_tile(nx, ny)
				if t == Grid.Tile.WALL:
					break
				var key := ny * world.grid.cols + nx
				danger[key] = mini(int(danger.get(key, 999999)), f)
				if t == Grid.Tile.BLOCK:
					break
	return danger


func _draw_rounded_box(rect: Rect2, radius: float, fill_col: Color, outline_col: Color = Color(0, 0, 0, 0), outline_w: float = 0.0) -> void:
	var r := int(round(radius))
	var bw := int(round(outline_w))
	_round_box_sb.bg_color = fill_col
	_round_box_sb.corner_radius_top_left = r
	_round_box_sb.corner_radius_top_right = r
	_round_box_sb.corner_radius_bottom_left = r
	_round_box_sb.corner_radius_bottom_right = r
	_round_box_sb.border_width_left = bw
	_round_box_sb.border_width_top = bw
	_round_box_sb.border_width_right = bw
	_round_box_sb.border_width_bottom = bw
	_round_box_sb.border_color = outline_col
	draw_style_box(_round_box_sb, rect)


func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int = 16) -> void:
	if rx <= 0.1 or ry <= 0.1 or col.a <= 0.001:
		return
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in range(segments):
		var th := float(i) * TAU / float(segments)
		pts[i] = center + Vector2(cos(th) * rx, sin(th) * ry)
	draw_colored_polygon(pts, col)


func _draw() -> void:
	if sim == null:
		return

	var cols := sim.grid.cols
	var rows := sim.grid.rows
	var danger := compute_danger_cells(sim)

	# 1. Piso da Arena com ladrilhos chanfrados e células de perigo
	for cy in range(rows):
		for cx in range(cols):
			var rect := Rect2(cx * TILE_PX, cy * TILE_PX, TILE_PX, TILE_PX)
			var is_alt := (cx + cy) % 2 == 0
			var floor_col := Color(0.09, 0.11, 0.19, 1.0) if is_alt else Color(0.12, 0.15, 0.24, 1.0)
			draw_rect(rect, floor_col, true)

			# Borda de ladrilho suave
			draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(0.18, 0.22, 0.34, 0.22), 1.0)
			draw_line(rect.position, rect.position + Vector2(0, rect.size.y), Color(0.18, 0.22, 0.34, 0.22), 1.0)

			# Destaque nos cantos de spawn
			var is_spawn := (cx == 1 and cy == 1) or (cx == cols - 2 and cy == 1) or (cx == 1 and cy == rows - 2) or (cx == cols - 2 and cy == rows - 2)
			if is_spawn and sim.grid.get_tile(cx, cy) == Grid.Tile.EMPTY:
				draw_arc(rect.get_center(), 14.0, 0.0, TAU, 16, Color(0.2, 0.85, 1.0, 0.18), 1.5)

			var key := cy * cols + cx
			if danger.has(key) and sim.grid.get_tile(cx, cy) == Grid.Tile.EMPTY:
				var pulse := 0.20 + 0.14 * sin(anim_time * 12.0)
				draw_rect(rect.grow(-2.0), Color(1.0, 0.24, 0.18, pulse), true)
				draw_rect(rect.grow(-2.0), Color(1.0, 0.45, 0.25, pulse * 1.4), false, 1.5)

			var tile := sim.grid.get_tile(cx, cy)
			if tile == Grid.Tile.WALL:
				_draw_wall_tile(rect, cx, cy, cols, rows)
			elif tile == Grid.Tile.BLOCK:
				_draw_block_tile(rect, cx, cy)

	# 2. Power-ups expostos
	for key: int in sim.powerups.keys():
		var pu: Dictionary = sim.powerups[key]
		_draw_powerup(int(pu["cx"]), int(pu["cy"]), str(pu["kind"]))

	# 3. Bombas ("Petardos")
	for b in sim.bombs:
		_draw_bomb(b)

	# 4. Chamas em cruz conectadas
	for key: int in sim.flames.keys():
		var f: Dictionary = sim.flames[key]
		_draw_flame(int(f["cx"]), int(f["cy"]), int(f["ticks_left"]))

	# 5. Robôs-Mascote Sparkies articulados
	for p in sim.players:
		_draw_sparky(p)

	# 6. Partículas de fogo, confete, faíscas e poeira
	for pt in particles:
		var ratio: float = clampf(float(pt["life"]) / float(pt["max_life"]), 0.0, 1.0)
		var col: Color = pt["color"]
		col.a = col.a * ratio
		var sz: float = float(pt["size"]) * (0.35 + 0.65 * ratio)
		var pos: Vector2 = pt["pos"]
		var shape: String = str(pt.get("shape", "box"))
		if shape == "circle":
			draw_circle(pos, sz * 0.5, col)
		else:
			draw_rect(Rect2(pos - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), col, true)


func _draw_wall_tile(rect: Rect2, cx: int, cy: int, cols: int, rows: int) -> void:
	# Sombra inferior e extrusão 3D
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y - 6.0, rect.size.x, 6.0), Color(0.06, 0.08, 0.14), true)
	draw_rect(Rect2(rect.position.x, rect.position.y + 10.0, rect.size.x, rect.size.y - 10.0), Color(0.14, 0.17, 0.28), true)

	# Topo chanfrado do pilar
	var top_rect := Rect2(rect.position.x + 2.0, rect.position.y + 2.0, rect.size.x - 4.0, rect.size.y - 12.0)
	_draw_rounded_box(top_rect, 4.0, Color(0.24, 0.29, 0.45), Color(0.38, 0.45, 0.66), 1.5)
	draw_line(top_rect.position + Vector2(3.0, 2.0), top_rect.position + Vector2(top_rect.size.x - 3.0, 2.0), Color(0.55, 0.65, 0.88, 0.6), 1.5)

	# Lanterna mágica nos pilares internos
	if cx > 0 and cx < cols - 1 and cy > 0 and cy < rows - 1:
		var center := top_rect.get_center()
		var glow := 0.70 + 0.30 * sin(anim_time * 4.0 + float(cx * 3 + cy * 5))
		draw_circle(center, 9.0, Color(1.0, 0.75, 0.25, 0.22 * glow))
		draw_circle(center, 5.5, Color(1.0, 0.82, 0.32, 0.55 * glow))
		draw_circle(center, 3.2, Color(1.0, 0.95, 0.70, 1.0))


func _draw_block_tile(rect: Rect2, cx: int, cy: int) -> void:
	# Sombra no chão
	draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + rect.size.y - 5.0, rect.size.x - 4.0, 5.0), Color(0.04, 0.06, 0.10, 0.5), true)

	var box := Rect2(rect.position.x + 2.0, rect.position.y + 2.0, rect.size.x - 4.0, rect.size.y - 7.0)
	_draw_rounded_box(box, 3.5, Color(0.42, 0.25, 0.14), Color(0.20, 0.11, 0.06), 1.5)

	# Ripas chanfradas de madeira
	var plank_h := (box.size.y - 4.0) / 3.0
	for i in range(3):
		var plank_rect := Rect2(box.position.x + 2.0, box.position.y + 2.0 + i * plank_h, box.size.x - 4.0, plank_h - 1.0)
		draw_rect(plank_rect, Color(0.58, 0.36, 0.20), true)

	# Fita cruzada festiva
	var ribbon_col := Color(0.98, 0.36, 0.42, 1.0) if (cx + cy) % 2 == 0 else Color(0.20, 0.85, 0.70, 1.0)
	draw_rect(Rect2(box.position.x, box.get_center().y - 3.5, box.size.x, 7.0), ribbon_col, true)
	draw_rect(Rect2(box.get_center().x - 3.5, box.position.y, 7.0, box.size.y), ribbon_col, true)

	# Broche central dourado
	draw_circle(box.get_center(), 4.2, Color(1.0, 0.85, 0.25, 1.0))
	draw_circle(box.get_center(), 2.0, Color.WHITE)

	# Rebites metálicos nos 4 cantos
	var r_col := Color(0.78, 0.72, 0.65)
	draw_circle(box.position + Vector2(4.0, 4.0), 1.2, r_col)
	draw_circle(box.position + Vector2(box.size.x - 4.0, 4.0), 1.2, r_col)
	draw_circle(box.position + Vector2(4.0, box.size.y - 4.0), 1.2, r_col)
	draw_circle(box.position + Vector2(box.size.x - 4.0, box.size.y - 4.0), 1.2, r_col)


func _draw_powerup(cx: int, cy: int, kind: String) -> void:
	var bob := sin(anim_time * 5.0 + float(cx * 3 + cy)) * 3.0
	var center := Vector2((cx + 0.5) * TILE_PX, (cy + 0.5) * TILE_PX + bob)
	var col := Color(1.0, 0.55, 0.2, 1.0)
	var label := "R+"
	match kind:
		PowerUpDef.KIND_RANGE_UP:
			col = Color(1.0, 0.52, 0.18, 1.0)
			label = "R+"
		PowerUpDef.KIND_BOMB_UP:
			col = Color(0.25, 0.78, 1.0, 1.0)
			label = "B+"
		PowerUpDef.KIND_SPEED_UP:
			col = Color(0.35, 0.95, 0.45, 1.0)
			label = "S+"
		PowerUpDef.KIND_SHIELD:
			col = Color(0.85, 0.45, 1.0, 1.0)
			label = "SH"

	# Halo exterior e orbe arredondado
	draw_circle(center, 16.0 + sin(anim_time * 6.0) * 2.0, Color(col.r, col.g, col.b, 0.28))
	_draw_rounded_box(Rect2(center - Vector2(12.0, 12.0), Vector2(24.0, 24.0)), 6.0, col, Color(1.0, 1.0, 1.0, 0.9), 2.0)
	_draw_rounded_box(Rect2(center - Vector2(9.0, 9.0), Vector2(7.0, 3.0)), 1.5, Color(1.0, 1.0, 1.0, 0.55))

	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, center + Vector2(-11.0, 4.5), label, HORIZONTAL_ALIGNMENT_CENTER, 22.0, 12, Color(0.06, 0.08, 0.14))


func _draw_bomb(b: BombState) -> void:
	var center := Vector2((b.cx + 0.5) * TILE_PX, (b.cy + 0.5) * TILE_PX)
	var urgency := 1.0 - clampf(float(b.fuse) / 50.0, 0.0, 1.0)
	var pulse_freq := 8.0 + urgency * 22.0
	var pulse_amp := 0.05 + urgency * 0.12
	var squash := 1.0 + sin(anim_time * pulse_freq) * pulse_amp
	var radius := 14.0 * squash

	# Sombra no chão
	_draw_ellipse(center + Vector2(0.0, 13.0), 12.0 * squash, 5.0, Color(0.03, 0.04, 0.08, 0.45))

	# Corpo metálico que esquenta para vermelho vivo
	var body_col := Color(0.18, 0.22, 0.35, 1.0).lerp(Color(0.98, 0.22, 0.15, 1.0), urgency)
	draw_circle(center + Vector2(0.0, 1.0), radius + 1.8, Color(0.06, 0.08, 0.12))
	draw_circle(center + Vector2(0.0, 1.0), radius, body_col)

	# Gradiente de volume 3D
	_draw_ellipse(center + Vector2(2.0, 5.0), radius * 0.7, radius * 0.4, Color(0.0, 0.0, 0.0, 0.25))

	# Brilho especular duplo
	_draw_ellipse(center + Vector2(-4.5, -4.5), radius * 0.42, radius * 0.28, Color(1.0, 1.0, 1.0, 0.38))
	draw_circle(center + Vector2(-5.5, -5.5), 1.8, Color(1.0, 1.0, 1.0, 0.85))

	# Bocal metálico
	var nozzle_rect := Rect2(center.x - 3.5, center.y - radius - 2.5, 7.0, 4.5)
	_draw_rounded_box(nozzle_rect, 1.5, Color(0.65, 0.68, 0.75), Color(0.15, 0.18, 0.25), 1.0)

	# Pavio curvo que encurta conforme b.fuse diminui
	var fuse_ratio := clampf(float(b.fuse) / 50.0, 0.15, 1.0)
	var fuse_start := center + Vector2(0.0, -radius - 2.0)
	var fuse_len := 10.0 * fuse_ratio
	var tip := fuse_start + Vector2(sin(anim_time * 6.0) * 2.0 + 5.0 * fuse_ratio, -fuse_len)
	var mid := fuse_start + Vector2(2.0, -fuse_len * 0.5)
	draw_polyline(PackedVector2Array([fuse_start, mid, tip]), Color(0.92, 0.82, 0.60), 2.4)

	# Faísca estrelada soltando luz
	draw_circle(tip, 5.0 + sin(anim_time * 30.0) * 1.5, Color(1.0, 0.55, 0.1, 0.45))
	draw_circle(tip, 3.0, Color(1.0, 0.9, 0.25, 1.0))
	draw_circle(tip, 1.5, Color.WHITE)
	var ray_len := 4.0 + sin(anim_time * 40.0) * 2.0
	draw_line(tip + Vector2(-ray_len, 0), tip + Vector2(ray_len, 0), Color(1.0, 0.95, 0.6, 0.8), 1.2)
	draw_line(tip + Vector2(0, -ray_len), tip + Vector2(0, ray_len), Color(1.0, 0.95, 0.6, 0.8), 1.2)


func _draw_flame(cx: int, cy: int, ticks_left: int) -> void:
	var cols := sim.grid.cols
	var has_left := sim.flames.has(cy * cols + (cx - 1))
	var has_right := sim.flames.has(cy * cols + (cx + 1))
	var has_up := sim.flames.has((cy - 1) * cols + cx)
	var has_down := sim.flames.has((cy + 1) * cols + cx)

	var center := Vector2((cx + 0.5) * TILE_PX, (cy + 0.5) * TILE_PX)
	var half_tile := TILE_PX * 0.5
	var ratio := clampf(float(ticks_left) / float(BombState.DEFAULT_FLAME_TICKS), 0.2, 1.0)
	var pulse := 1.0 + sin(anim_time * 20.0 + float(cx * 5 + cy * 7)) * 0.08

	# Desenha camadas de plasma em feixes contínuos conectados
	var layers: Array[Dictionary] = [
		{"width": 18.0 * pulse * ratio, "col": Color(1.0, 0.30, 0.08, 0.88 * ratio)},
		{"width": 11.0 * pulse * ratio, "col": Color(1.0, 0.85, 0.18, 0.95 * ratio)},
		{"width": 5.0 * pulse * ratio, "col": Color(1.0, 1.0, 0.90, ratio)},
	]

	var is_horiz := has_left or has_right
	var is_vert := has_up or has_down
	var is_cross := (is_horiz and is_vert) or (not is_horiz and not is_vert)

	for lay in layers:
		var w: float = lay["width"]
		var col: Color = lay["col"]
		draw_circle(center, w * (1.12 if is_cross else 1.0), col)

		if is_horiz or is_cross:
			var len_l := half_tile if has_left else (half_tile - 5.0)
			draw_line(center, center + Vector2(-len_l, 0.0), col, w * 2.0)
			if not has_left:
				draw_circle(center + Vector2(-len_l, 0.0), w, col)

			var len_r := half_tile if has_right else (half_tile - 5.0)
			draw_line(center, center + Vector2(len_r, 0.0), col, w * 2.0)
			if not has_right:
				draw_circle(center + Vector2(len_r, 0.0), w, col)

		if is_vert or is_cross:
			var len_u := half_tile if has_up else (half_tile - 5.0)
			draw_line(center, center + Vector2(0.0, -len_u), col, w * 2.0)
			if not has_up:
				draw_circle(center + Vector2(0.0, -len_u), w, col)

			var len_d := half_tile if has_down else (half_tile - 5.0)
			draw_line(center, center + Vector2(0.0, len_d), col, w * 2.0)
			if not has_down:
				draw_circle(center + Vector2(0.0, len_d), w, col)


func _draw_sparky(p: PlayerState) -> void:
	var curr_mt := Vector2(p.x, p.y)
	var prev_mt: Vector2 = prev_player_pos.get(p.id, curr_mt)
	var interp_mt := prev_mt.lerp(curr_mt, interp_alpha)
	var pos := interp_mt * MILITILE_TO_PX
	var panim := _get_player_anim(p.id)
	var col := PLAYER_COLORS[p.slot % PLAYER_COLORS.size()]

	# --- ANIMAÇÃO DE DERROTA (Fantasma robô flutuante) ---
	if not p.alive:
		var death_time: float = float(panim["death_time"])
		var float_rise := minf(death_time * 16.0, 20.0)
		var bob := sin(anim_time * 4.0 + float(p.slot)) * 4.0
		var g_pos := pos + Vector2(0.0, -float_rise + bob)

		# Sombra desvanecendo no chão
		var shadow_fade := maxf(0.35 - death_time * 0.15, 0.10)
		_draw_ellipse(pos + Vector2(0.0, 14.0), 10.0, 4.0, Color(0.0, 0.0, 0.0, shadow_fade))

		# Aura ectoplásmica suave
		_draw_ellipse(g_pos, 16.0, 18.0, Color(col.r, col.g, col.b, 0.20))

		# Corpo translúcido do fantasminha
		_draw_rounded_box(Rect2(g_pos - Vector2(11.0, 12.0), Vector2(22.0, 20.0)), 10.0, Color(col.r, col.g, col.b, 0.48), Color(1, 1, 1, 0.65), 1.5)

		# Ondulações da cauda
		draw_circle(g_pos + Vector2(-6.0, 8.0 + sin(anim_time * 7.0) * 1.5), 3.0, Color(col.r, col.g, col.b, 0.48))
		draw_circle(g_pos + Vector2(0.0, 9.0 + cos(anim_time * 7.0) * 1.5), 3.0, Color(col.r, col.g, col.b, 0.48))
		draw_circle(g_pos + Vector2(6.0, 8.0 - sin(anim_time * 7.0) * 1.5), 3.0, Color(col.r, col.g, col.b, 0.48))

		# Olhinhos em X piscantes
		var blink := fmod(anim_time * 3.0, 1.0) > 0.18
		if blink:
			draw_line(g_pos + Vector2(-6, -3), g_pos + Vector2(-2, 1), Color.WHITE, 2.0)
			draw_line(g_pos + Vector2(-2, -3), g_pos + Vector2(-6, 1), Color.WHITE, 2.0)
			draw_line(g_pos + Vector2(2, -3), g_pos + Vector2(6, 1), Color.WHITE, 2.0)
			draw_line(g_pos + Vector2(6, -3), g_pos + Vector2(2, 1), Color.WHITE, 2.0)

		# Auréola brilhante flutuando acima da cabeça
		draw_arc(g_pos + Vector2(0.0, -17.0), 7.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.4, 0.7), 2.0)

		var font := ThemeDB.fallback_font
		if font != null:
			var tag := PLAYER_NAMES[p.slot % PLAYER_NAMES.size()] + " (KO)"
			draw_string(font, g_pos + Vector2(-26.0, -22.0), tag, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 11, Color(0.65, 0.70, 0.80, 0.65))
		return

	# --- PERSONAGEM VIVO: ANIMAÇÃO ARTICULADA COMPLETA ---
	var blend: float = float(panim["move_blend"])
	var wp: float = float(panim["walk_phase"])
	var lean: Vector2 = panim["lean"]
	var squash_val: float = float(panim["squash"])
	var is_winner := sim.match_over and sim.winner_id == p.id

	var hop: float = 0.0
	if is_winner:
		hop = absf(sin(anim_time * 10.0)) * 8.5
	elif blend > 0.05:
		hop = absf(sin(wp)) * 3.5 * blend
	else:
		hop = sin(anim_time * 3.0) * 0.8

	var char_origin := pos
	var body_center := char_origin + Vector2(0.0, -hop) + lean

	# 1. Sombra elíptica dinâmica no chão
	var shadow_factor := clampf(1.0 - hop / 22.0, 0.45, 1.0)
	_draw_ellipse(char_origin + Vector2(0.0, 14.0), 13.0 * shadow_factor, 5.5 * shadow_factor, Color(0.03, 0.04, 0.08, 0.42 * shadow_factor))

	# 2. Anel de destaque sob os pés para o jogador local (p0)
	if p.id == "p0":
		var ring_glow := 0.65 + 0.35 * sin(anim_time * 6.0)
		draw_arc(char_origin + Vector2(0.0, 14.0), 16.5, 0.0, TAU, 24, Color(1.0, 0.82, 0.20, 0.75 * ring_glow), 2.0)
		draw_arc(char_origin + Vector2(0.0, 14.0), 19.0, 0.0, TAU, 24, Color(0.30, 0.90, 1.0, 0.45 * ring_glow), 1.0)

	# 3. Pés articulados (passadas cíclicas)
	var lf_pos := Vector2.ZERO
	var rf_pos := Vector2.ZERO
	if p.facing == "left" or p.facing == "right":
		var lift_l := maxf(0.0, -sin(wp)) * 4.0
		var lift_r := maxf(0.0, sin(wp)) * 4.0
		lf_pos = char_origin + Vector2(-6.0 + sin(wp) * 5.0 * blend, 12.0 - lift_l * blend)
		rf_pos = char_origin + Vector2(6.0 - sin(wp) * 5.0 * blend, 12.0 - lift_r * blend)
	elif p.facing == "up" or p.facing == "down":
		lf_pos = char_origin + Vector2(-6.0, 12.0 + sin(wp) * 4.0 * blend)
		rf_pos = char_origin + Vector2(6.0, 12.0 - sin(wp) * 4.0 * blend)
	else:
		lf_pos = char_origin + Vector2(-6.0, 12.0 - hop * 0.35)
		rf_pos = char_origin + Vector2(6.0, 12.0 - hop * 0.35)

	# Desenha pé esquerdo e sola iluminada
	_draw_rounded_box(Rect2(lf_pos - Vector2(4.0, 3.0), Vector2(8.0, 6.0)), 3.0, Color(0.12, 0.14, 0.22), Color(0.06, 0.07, 0.12), 1.0)
	draw_line(lf_pos + Vector2(-3.0, 2.5), lf_pos + Vector2(3.0, 2.5), col.lightened(0.2), 1.5)

	# Desenha pé direito e sola iluminada
	_draw_rounded_box(Rect2(rf_pos - Vector2(4.0, 3.0), Vector2(8.0, 6.0)), 3.0, Color(0.12, 0.14, 0.22), Color(0.06, 0.07, 0.12), 1.0)
	draw_line(rf_pos + Vector2(-3.0, 2.5), rf_pos + Vector2(3.0, 2.5), col.lightened(0.2), 1.5)

	# 4. Propulsor / Mochila Traseira (se olhando para cima)
	if p.facing == "up":
		var jetpack_rect := Rect2(body_center.x - 9.0, body_center.y - 6.0, 18.0, 15.0)
		_draw_rounded_box(jetpack_rect, 4.0, Color(0.18, 0.22, 0.32), Color(0.08, 0.10, 0.16), 1.5)
		var jet_pulse := 0.75 + 0.25 * sin(anim_time * 24.0)
		draw_circle(body_center + Vector2(-5.5, 9.0), 3.0 * jet_pulse, Color(0.25, 0.85, 1.0, 0.9))
		draw_circle(body_center + Vector2(5.5, 9.0), 3.0 * jet_pulse, Color(0.25, 0.85, 1.0, 0.9))
		draw_circle(body_center + Vector2(-5.5, 9.0), 1.5, Color.WHITE)
		draw_circle(body_center + Vector2(5.5, 9.0), 1.5, Color.WHITE)

	# 5. Tronco arredondado e cinto luminoso
	var torso_rect := Rect2(body_center.x - 7.5, body_center.y + 1.0, 15.0, 8.5)
	_draw_rounded_box(torso_rect, 3.0, Color(0.15, 0.18, 0.28), Color(0.08, 0.09, 0.15), 1.2)
	draw_line(body_center + Vector2(-6.5, 6.0), body_center + Vector2(6.5, 6.0), Color(0.25, 0.30, 0.42), 2.0)
	draw_circle(body_center + Vector2(0.0, 6.0), 2.0, col.lightened(0.3))

	# 6. Braços e Mãos articuladas
	var lh_pos := Vector2.ZERO
	var rh_pos := Vector2.ZERO
	if is_winner:
		lh_pos = body_center + Vector2(-13.0, -14.0 + sin(anim_time * 24.0) * 2.0)
		rh_pos = body_center + Vector2(13.0, -14.0 - sin(anim_time * 24.0) * 2.0)
	elif blend > 0.05:
		var arm_swing := -sin(wp) * 4.5 * blend
		lh_pos = body_center + Vector2(-13.0, 4.0 + arm_swing)
		rh_pos = body_center + Vector2(13.0, 4.0 - arm_swing)
	else:
		var breath := sin(anim_time * 3.0) * 0.8
		lh_pos = body_center + Vector2(-12.5, 4.0 + breath)
		rh_pos = body_center + Vector2(12.5, 4.0 + breath)

	draw_circle(lh_pos, 3.6, Color(0.08, 0.09, 0.15))
	draw_circle(lh_pos, 2.6, Color(0.92, 0.94, 0.98))
	draw_circle(lh_pos + Vector2(-0.8, -0.8), 1.0, Color.WHITE)

	draw_circle(rh_pos, 3.6, Color(0.08, 0.09, 0.15))
	draw_circle(rh_pos, 2.6, Color(0.92, 0.94, 0.98))
	draw_circle(rh_pos + Vector2(-0.8, -0.8), 1.0, Color.WHITE)

	# 7. Capacete Chibi Arredondado com Volume 3D e Squash & Stretch
	var head_w := 28.0 * (2.0 - squash_val)
	var head_h := 23.0 * squash_val
	var head_rect := Rect2(body_center.x - head_w * 0.5, body_center.y - 15.0 + (23.0 - head_h), head_w, head_h)

	# Fones / rebites laterais
	var ear_y := head_rect.position.y + head_h * 0.52
	_draw_rounded_box(Rect2(head_rect.position.x - 3.5, ear_y - 4.5, 4.5, 9.0), 2.2, Color(0.14, 0.16, 0.25), Color(0.07, 0.08, 0.14), 1.0)
	_draw_rounded_box(Rect2(head_rect.position.x + head_w - 1.0, ear_y - 4.5, 4.5, 9.0), 2.2, Color(0.14, 0.16, 0.25), Color(0.07, 0.08, 0.14), 1.0)
	draw_circle(Vector2(head_rect.position.x - 1.0, ear_y), 1.2, col.lightened(0.4))
	draw_circle(Vector2(head_rect.position.x + head_w + 1.0, ear_y), 1.2, col.lightened(0.4))

	# Base do capacete (sombra de volume)
	_draw_rounded_box(Rect2(head_rect.position.x, head_rect.position.y + 3.0, head_w, head_h - 3.0), 8.0, col.darkened(0.28), Color(0.07, 0.08, 0.14), 2.0)
	# Capacete principal
	_draw_rounded_box(head_rect, 8.0, col, Color(0.07, 0.08, 0.14), 2.0)
	# Brilho especular no topo
	_draw_rounded_box(Rect2(head_rect.position.x + 3.5, head_rect.position.y + 2.5, head_w * 0.4, 4.0), 2.0, Color(1.0, 1.0, 1.0, 0.35))

	# 8. Antena com Física de Mola
	var ant_offset: Vector2 = panim["ant_offset"]
	var ant_root := Vector2(head_rect.get_center().x, head_rect.position.y + 1.0)
	var mid_seg := ant_root + Vector2(ant_offset.x * 0.4, -5.0)
	var tip_seg := ant_root + Vector2(ant_offset.x, -13.0 + ant_offset.y)

	draw_line(ant_root, mid_seg, Color(0.10, 0.12, 0.18), 3.0)
	draw_line(mid_seg, tip_seg, Color(0.10, 0.12, 0.18), 2.5)
	draw_line(ant_root, mid_seg, Color(0.85, 0.88, 0.95), 1.6)
	draw_line(mid_seg, tip_seg, Color(0.85, 0.88, 0.95), 1.4)

	var ant_pulse := 0.75 + 0.25 * sin(anim_time * 8.0 + float(p.slot))
	draw_circle(tip_seg, 5.0 * ant_pulse, Color(1.0, 0.85, 0.25, 0.32))
	draw_circle(tip_seg, 3.2, Color(1.0, 0.88, 0.32, 1.0))
	draw_circle(tip_seg + Vector2(-0.8, -0.8), 1.2, Color.WHITE)

	# 9. Visor LED Expressivo
	if p.facing != "up":
		var visor_shift := Vector2.ZERO
		match p.facing:
			"down": visor_shift = Vector2(0.0, 2.0)
			"left": visor_shift = Vector2(-3.5, 0.0)
			"right": visor_shift = Vector2(3.5, 0.0)

		var visor_w := 19.0
		var visor_h := 10.0
		var visor_pos := Vector2(head_rect.get_center().x - visor_w * 0.5 + visor_shift.x, head_rect.position.y + 8.5 + visor_shift.y)
		var visor_rect := Rect2(visor_pos, Vector2(visor_w, visor_h))

		_draw_rounded_box(visor_rect, 4.5, Color(0.06, 0.08, 0.15), Color(0.03, 0.04, 0.08), 1.2)
		draw_line(visor_pos + Vector2(2.5, 8.0), visor_pos + Vector2(8.5, 2.0), Color(1.0, 1.0, 1.0, 0.22), 1.2)

		# Olhos de LED com expressões vivas
		var is_blinking: bool = fmod(anim_time + float(p.slot) * 0.7, 3.2) < 0.12
		var p_cell_key := p.cell_y() * sim.grid.cols + p.cell_x()
		var danger_map := compute_danger_cells(sim)
		var in_danger: bool = danger_map.has(p_cell_key)

		if is_blinking:
			draw_line(visor_pos + Vector2(3.2, 5.0), visor_pos + Vector2(6.8, 5.0), Color(0.4, 0.95, 1.0, 0.9), 1.8)
			draw_line(visor_pos + Vector2(12.2, 5.0), visor_pos + Vector2(15.8, 5.0), Color(0.4, 0.95, 1.0, 0.9), 1.8)
		elif is_winner:
			draw_arc(visor_pos + Vector2(5.0, 6.0), 2.5, PI + 0.3, TAU - 0.3, 8, Color(0.4, 0.98, 1.0, 1.0), 2.0)
			draw_arc(visor_pos + Vector2(14.0, 6.0), 2.5, PI + 0.3, TAU - 0.3, 8, Color(0.4, 0.98, 1.0, 1.0), 2.0)
		elif in_danger:
			draw_line(visor_pos + Vector2(3.5, 3.8), visor_pos + Vector2(6.8, 5.8), Color(1.0, 0.92, 0.3, 1.0), 2.2)
			draw_line(visor_pos + Vector2(15.5, 3.8), visor_pos + Vector2(12.2, 5.8), Color(1.0, 0.92, 0.3, 1.0), 2.2)
		else:
			var eye_look := visor_shift * 0.25
			var eye_col := Color(0.25, 0.95, 1.0, 1.0)
			draw_circle(visor_pos + Vector2(5.0, 5.0), 3.2, Color(eye_col.r, eye_col.g, eye_col.b, 0.35))
			_draw_ellipse(visor_pos + Vector2(5.0, 5.0) + eye_look, 2.2, 2.6, eye_col)
			draw_circle(visor_pos + Vector2(5.0, 5.0) + eye_look + Vector2(-0.6, -0.6), 0.9, Color.WHITE)

			draw_circle(visor_pos + Vector2(14.0, 5.0), 3.2, Color(eye_col.r, eye_col.g, eye_col.b, 0.35))
			_draw_ellipse(visor_pos + Vector2(14.0, 5.0) + eye_look, 2.2, 2.6, eye_col)
			draw_circle(visor_pos + Vector2(14.0, 5.0) + eye_look + Vector2(-0.6, -0.6), 0.9, Color.WHITE)

	# 10. Bolha de Escudo Ativa
	if p.shield_ticks > 0:
		var shield_glow := 0.80 + 0.20 * sin(anim_time * 10.0)
		draw_arc(body_center, 22.0, 0.0, TAU, 28, Color(0.85, 0.55, 1.0, 0.90 * shield_glow), 2.5)
		draw_arc(body_center, 24.5, 0.0, TAU, 28, Color(0.55, 0.85, 1.0, 0.45 * shield_glow), 1.2)
		draw_circle(body_center, 22.0, Color(0.75, 0.45, 1.0, 0.12 * shield_glow))

	# 11. Coroa / Indicador do Jogador Local (p0)
	if p.id == "p0":
		var crown_bob := sin(anim_time * 6.0) * 2.5
		var crown_pos := body_center + Vector2(0.0, -32.0 + crown_bob)
		var crown_pts := PackedVector2Array([
			crown_pos + Vector2(-6.0, -5.0),
			crown_pos + Vector2(-4.0, 0.0),
			crown_pos + Vector2(0.0, -6.0),
			crown_pos + Vector2(4.0, 0.0),
			crown_pos + Vector2(6.0, -5.0),
			crown_pos + Vector2(4.0, 2.5),
			crown_pos + Vector2(-4.0, 2.5),
		])
		draw_colored_polygon(crown_pts, Color(1.0, 0.85, 0.15, 1.0))
		draw_polyline(crown_pts, Color(0.35, 0.25, 0.05, 1.0), 1.2)
		draw_circle(crown_pos + Vector2(0.0, -6.0), 1.2, Color(1.0, 1.0, 0.7, 1.0))

	# 12. Tag de Identificação com Nome
	var font := ThemeDB.fallback_font
	if font != null:
		var tag := PLAYER_NAMES[p.slot % PLAYER_NAMES.size()]
		var tag_y := -23.0
		var tag_col := Color.WHITE if p.id == "p0" else col.lightened(0.45)
		draw_string(font, body_center + Vector2(-24.0, tag_y), tag, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11, tag_col)
