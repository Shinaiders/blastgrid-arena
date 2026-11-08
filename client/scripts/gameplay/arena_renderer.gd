class_name ArenaRenderer
extends Node2D
## Renderizador 2D original do BlastGrid Arena (Dia 11 — GDD §2, PLATFORM_COMPATIBILITY §6).
## Desenha arena 15×13 (tiles de 48 px = 720×624), pilares com lanternas, caixotes de confete,
## petardos com pavio, área de perigo prevista, robôs-mascote "Sparkies" animados e partículas.

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


func bind_sim(world: WorldSim) -> void:
	sim = world
	prev_player_pos.clear()
	particles.clear()
	if sim != null:
		for p in sim.players:
			prev_player_pos[p.id] = Vector2(p.x, p.y)
	queue_redraw()


func snapshot_positions_before_tick() -> void:
	if sim == null:
		return
	for p in sim.players:
		prev_player_pos[p.id] = Vector2(p.x, p.y)


func on_tick_events(events: Array[Dictionary]) -> void:
	for e in events:
		var k := str(e.get("k", ""))
		if k == "explosion":
			var cells: Array = e.get("cells", [])
			for c: Array in cells:
				_spawn_burst(int(c[0]), int(c[1]), Color(1.0, 0.72, 0.2, 1.0), 5)
		elif k == "block_destroyed":
			_spawn_burst(int(e.get("cx", 0)), int(e.get("cy", 0)), Color(0.95, 0.45, 0.65, 1.0), 8)
		elif k == "powerup_collected":
			_spawn_burst(int(e.get("cx", 0)), int(e.get("cy", 0)), Color(0.4, 0.95, 1.0, 1.0), 6)


func _spawn_burst(cx: int, cy: int, base_color: Color, count: int) -> void:
	var center := Vector2((cx + 0.5) * TILE_PX, (cy + 0.5) * TILE_PX)
	for i in range(count):
		var angle := (TAU * float(i)) / float(maxi(count, 1)) + anim_time * 1.7
		var speed := 38.0 + float((i * 19) % 45)
		particles.append({
			"pos": center,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"color": base_color.lightened(float(i % 3) * 0.12),
			"life": 0.35,
			"max_life": 0.35,
			"size": 5.0 + float(i % 3),
		})


func step_visuals(delta: float, alpha: float) -> void:
	anim_time += delta
	interp_alpha = clampf(alpha, 0.0, 1.0)
	var alive_particles: Array[Dictionary] = []
	for pt in particles:
		var life: float = float(pt["life"]) - delta
		if life > 0.0:
			pt["life"] = life
			pt["pos"] = (pt["pos"] as Vector2) + (pt["vel"] as Vector2) * delta
			alive_particles.append(pt)
	particles = alive_particles
	queue_redraw()


static func compute_danger_cells(world: WorldSim) -> Dictionary:
	## Retorna Dictionary (cy * cols + cx) -> menor fuse em ticks até explosão (considerando cadeia).
	var danger := {}
	if world == null or world.bombs.is_empty():
		return danger

	# Propaga fuses por cadeia: se bomba A atinge bomba B, fuse efetivo de B <= fuse de A
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


func _draw() -> void:
	if sim == null:
		return

	var cols := sim.grid.cols
	var rows := sim.grid.rows
	var danger := compute_danger_cells(sim)

	# 1. Piso e paredes/caixotes
	for cy in range(rows):
		for cx in range(cols):
			var rect := Rect2(cx * TILE_PX, cy * TILE_PX, TILE_PX, TILE_PX)
			var is_alt := (cx + cy) % 2 == 0
			var floor_col := Color(0.10, 0.12, 0.21, 1.0) if is_alt else Color(0.12, 0.15, 0.25, 1.0)
			draw_rect(rect, floor_col, true)

			var key := cy * cols + cx
			if danger.has(key) and sim.grid.get_tile(cx, cy) == Grid.Tile.EMPTY:
				var pulse := 0.16 + 0.10 * sin(anim_time * 10.0)
				draw_rect(rect.grow(-2.0), Color(1.0, 0.28, 0.22, pulse), true)

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

	# 4. Chamas ativas
	for key: int in sim.flames.keys():
		var f: Dictionary = sim.flames[key]
		_draw_flame(int(f["cx"]), int(f["cy"]), int(f["ticks_left"]))

	# 5. Jogadores ("Sparkies")
	for p in sim.players:
		_draw_sparky(p)

	# 6. Partículas de confete e faísca
	for pt in particles:
		var ratio: float = float(pt["life"]) / float(pt["max_life"])
		var col: Color = pt["color"]
		col.a = ratio
		var sz: float = float(pt["size"]) * ratio
		var pos: Vector2 = pt["pos"]
		draw_rect(Rect2(pos - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), col, true)


func _draw_wall_tile(rect: Rect2, cx: int, cy: int, cols: int, rows: int) -> void:
	draw_rect(rect, Color(0.18, 0.22, 0.36, 1.0), true)
	var top_rect := rect.grow(-3.0)
	draw_rect(top_rect, Color(0.25, 0.30, 0.47, 1.0), true)
	draw_rect(top_rect, Color(0.36, 0.42, 0.62, 1.0), false, 2.0)
	# Lanterna luminosa nos pilares internos
	if cx > 0 and cx < cols - 1 and cy > 0 and cy < rows - 1:
		var center := rect.get_center()
		var glow := 0.75 + 0.25 * sin(anim_time * 4.0 + float(cx + cy))
		draw_circle(center, 6.5, Color(1.0, 0.78, 0.28, 0.35 * glow))
		draw_circle(center, 3.5, Color(1.0, 0.90, 0.55, 1.0))


func _draw_block_tile(rect: Rect2, cx: int, cy: int) -> void:
	var box := rect.grow(-3.0)
	draw_rect(box, Color(0.46, 0.28, 0.16, 1.0), true)
	draw_rect(box.grow(-3.0), Color(0.58, 0.36, 0.20, 1.0), true)
	# Faixa de confete festiva
	var ribbon_col := Color(0.98, 0.38, 0.42, 1.0) if (cx + cy) % 2 == 0 else Color(0.22, 0.82, 0.68, 1.0)
	draw_rect(Rect2(box.position.x, box.get_center().y - 4.0, box.size.x, 8.0), ribbon_col, true)
	draw_rect(Rect2(box.get_center().x - 4.0, box.position.y, 8.0, box.size.y), ribbon_col, true)
	draw_rect(box, Color(0.28, 0.16, 0.08, 1.0), false, 2.0)


func _draw_powerup(cx: int, cy: int, kind: String) -> void:
	var bob := sin(anim_time * 5.0 + float(cx * 3 + cy)) * 2.5
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

	draw_circle(center, 15.0, Color(col.r, col.g, col.b, 0.28))
	draw_circle(center, 12.0, col)
	draw_arc(center, 12.0, 0.0, TAU, 20, Color.WHITE, 2.0)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, center + Vector2(-9.0, 5.0), label, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 12, Color(0.08, 0.1, 0.16, 1.0))


func _draw_bomb(b: BombState) -> void:
	var center := Vector2((b.cx + 0.5) * TILE_PX, (b.cy + 0.5) * TILE_PX)
	var urgency := 1.0 - clampf(float(b.fuse) / 50.0, 0.0, 1.0)
	var pulse := 1.0 + sin(anim_time * (8.0 + urgency * 18.0)) * (0.06 + urgency * 0.10)
	var radius := 15.0 * pulse

	var body_col := Color(0.20, 0.22, 0.30, 1.0).lerp(Color(0.95, 0.26, 0.20, 1.0), urgency * 0.65)
	draw_circle(center + Vector2(0.0, 2.0), radius, body_col)
	draw_circle(center + Vector2(-5.0, -4.0), radius * 0.28, Color(1.0, 1.0, 1.0, 0.35))
	# Pavio e faísca
	var tip := center + Vector2(6.0, -radius - 4.0)
	draw_line(center + Vector2(0.0, -radius + 2.0), tip, Color(0.95, 0.85, 0.65, 1.0), 2.5)
	draw_circle(tip, 4.5, Color(1.0, 0.85, 0.25, 1.0))


func _draw_flame(cx: int, cy: int, ticks_left: int) -> void:
	var rect := Rect2(cx * TILE_PX, cy * TILE_PX, TILE_PX, TILE_PX)
	var ratio := clampf(float(ticks_left) / float(BombState.DEFAULT_FLAME_TICKS), 0.2, 1.0)
	draw_rect(rect.grow(-3.0), Color(1.0, 0.38, 0.12, 0.85 * ratio), true)
	draw_rect(rect.grow(-10.0), Color(1.0, 0.92, 0.45, 0.95 * ratio), true)


func _draw_sparky(p: PlayerState) -> void:
	var curr_mt := Vector2(p.x, p.y)
	var prev_mt: Vector2 = prev_player_pos.get(p.id, curr_mt)
	var interp_mt := prev_mt.lerp(curr_mt, interp_alpha)
	var pos := interp_mt * MILITILE_TO_PX

	var col := PLAYER_COLORS[p.slot % PLAYER_COLORS.size()]
	if not p.alive:
		# Animação de derrota: silhueta translúcida com olhos em X
		draw_circle(pos, 13.0, Color(col.r, col.g, col.b, 0.25))
		draw_line(pos + Vector2(-6, -4), pos + Vector2(-2, 0), Color.WHITE, 2.0)
		draw_line(pos + Vector2(-2, -4), pos + Vector2(-6, 0), Color.WHITE, 2.0)
		draw_line(pos + Vector2(2, -4), pos + Vector2(6, 0), Color.WHITE, 2.0)
		draw_line(pos + Vector2(6, -4), pos + Vector2(2, 0), Color.WHITE, 2.0)
		return

	var is_moving := p.dir != "none"
	var walk_bob := sin(anim_time * 16.0) * 2.5 if is_moving else sin(anim_time * 3.5) * 1.0
	if sim.match_over and sim.winner_id == p.id:
		walk_bob = -absf(sin(anim_time * 10.0)) * 8.0 # Pulo de vitória

	var body_center := pos + Vector2(0.0, walk_bob)

	# Sombra no chão
	draw_circle(pos + Vector2(0.0, 14.0), 11.0, Color(0.0, 0.0, 0.0, 0.35))

	# Cabeça/corpo de robô-mascote "Sparky"
	var head_rect := Rect2(body_center - Vector2(14.0, 14.0), Vector2(28.0, 26.0))
	draw_rect(head_rect, col, true)
	draw_rect(head_rect, Color(0.10, 0.12, 0.20, 1.0), false, 2.0)

	# Antena luminosa no topo
	var ant_top := body_center + Vector2(0.0, -19.0)
	draw_line(body_center + Vector2(0.0, -14.0), ant_top, Color.WHITE, 2.0)
	draw_circle(ant_top, 3.5, Color(1.0, 0.90, 0.30, 1.0))

	# Visor direcional
	var visor_offset := Vector2.ZERO
	match p.facing:
		"up":
			visor_offset = Vector2(0.0, -4.0)
		"down":
			visor_offset = Vector2(0.0, 2.0)
		"left":
			visor_offset = Vector2(-4.0, 0.0)
		"right":
			visor_offset = Vector2(4.0, 0.0)

	var visor_rect := Rect2(body_center - Vector2(9.0, 5.0) + visor_offset, Vector2(18.0, 9.0))
	draw_rect(visor_rect, Color(0.10, 0.14, 0.24, 1.0), true)
	if p.facing != "up":
		draw_circle(visor_rect.position + Vector2(5.0, 4.5), 2.2, Color(0.45, 0.98, 1.0, 1.0))
		draw_circle(visor_rect.position + Vector2(13.0, 4.5), 2.2, Color(0.45, 0.98, 1.0, 1.0))

	# Bolha de escudo ativa
	if p.shield_ticks > 0:
		draw_arc(body_center, 20.0, 0.0, TAU, 24, Color(0.75, 0.50, 1.0, 0.85), 2.5)

	# Tag de identificação acima do personagem
	var font := ThemeDB.fallback_font
	if font != null:
		var tag := PLAYER_NAMES[p.slot % PLAYER_NAMES.size()]
		draw_string(font, body_center + Vector2(-22.0, -23.0), tag, HORIZONTAL_ALIGNMENT_CENTER, 44.0, 11, col.lightened(0.35))

