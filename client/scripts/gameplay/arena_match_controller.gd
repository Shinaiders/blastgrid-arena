class_name ArenaMatchController
extends Control
## Controlador de partida (Dia 13): une simulação a 20 Hz, 3 bots, ArenaRenderer, HUD competitivo,
## menu de pausa e tela de resultado da partida.

signal return_to_menu_requested
signal rematch_requested(mode: String)

const TICK_DT: float = 0.05 # 20 Hz

var game_mode: String = "practice" # "practice" | "ffa"
var bot_difficulty: String = "medium"
var local_player_id: String = "p0"
var selected_character: String = "sparky_a"
var is_online: bool = false
var rtt_ms: int = 0

var sim: WorldSim = null
var bots: Array[BotBrain] = []
var tick_accum: float = 0.0
var is_paused: bool = false
var bomb_queued: bool = false

var renderer: ArenaRenderer
var clock_label: Label
var mode_label: Label
var alive_label: Label
var conn_label: Label
var stats_label: Label
var powerups_label: Label
var roster_box: VBoxContainer
var pause_overlay: Control
var result_overlay: Control
var result_title_label: Label
var result_rows_box: VBoxContainer


func _ready() -> void:
	_build_ui()
	if sim == null:
		start_local_match(game_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty)


func start_local_match(mode: String = "practice", seed_val: int = 1337, diff: String = "medium") -> void:
	game_mode = mode
	bot_difficulty = diff
	is_online = false
	is_paused = false
	bomb_queued = false
	tick_accum = 0.0

	var ids: Array[String] = ["p0", "bot1", "bot2", "bot3"]
	sim = WorldSim.new(seed_val, ids, mode == "practice")
	var p0 := sim.get_player(local_player_id)
	if p0 != null:
		p0.character_id = selected_character

	bots = [
		BotBrain.new("bot1", "easy" if mode == "practice" else diff, seed_val + 101),
		BotBrain.new("bot2", diff, seed_val + 202),
		BotBrain.new("bot3", "hard" if mode == "ffa" else diff, seed_val + 303),
	]

	if renderer != null:
		renderer.bind_sim(sim)
	if pause_overlay != null:
		pause_overlay.visible = false
	if result_overlay != null:
		result_overlay.visible = false
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event.is_action_pressed(&"pause") and not sim.match_over:
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not is_paused and event.is_action_pressed(&"place_bomb"):
		bomb_queued = true


func toggle_pause() -> void:
	is_paused = not is_paused
	if pause_overlay != null:
		pause_overlay.visible = is_paused


func _process(delta: float) -> void:
	if sim == null:
		return
	if Input.is_action_just_pressed(&"place_bomb") and not is_paused:
		bomb_queued = true

	if not is_paused and not sim.match_over:
		tick_accum += delta
		var steps := 0
		while tick_accum >= TICK_DT and steps < 5:
			tick_accum -= TICK_DT
			steps += 1
			_advance_one_tick()

	var alpha := clampf(tick_accum / TICK_DT, 0.0, 1.0) if not is_paused else 1.0
	if renderer != null:
		renderer.step_visuals(delta, alpha)


func _advance_one_tick() -> void:
	if renderer != null:
		renderer.snapshot_positions_before_tick()

	var dir := _read_local_direction()
	sim.set_input(local_player_id, dir, bomb_queued)
	bomb_queued = false

	for b in bots:
		var cmd := b.decide(sim)
		sim.set_input(b.player_id, str(cmd["dir"]), bool(cmd["bomb"]))

	var evs := sim.step_tick()
	if renderer != null:
		renderer.on_tick_events(evs)
	_refresh_hud()

	if sim.match_over:
		_show_results()


static func _read_local_direction() -> String:
	if Input.is_action_pressed(&"move_up"):
		return "up"
	if Input.is_action_pressed(&"move_down"):
		return "down"
	if Input.is_action_pressed(&"move_left"):
		return "left"
	if Input.is_action_pressed(&"move_right"):
		return "right"
	return "none"


func _refresh_hud() -> void:
	if clock_label == null or sim == null:
		return
	var rem := sim.duration_ticks - sim.tick
	clock_label.text = HudFormatter.format_clock(rem, sim.tick_rate)
	mode_label.text = "MODO: %s" % ("TREINO (PRACTICE)" if game_mode == "practice" else "FREE FOR ALL")
	alive_label.text = "Vivos: %d / %d" % [HudFormatter.count_alive(sim.players), sim.players.size()]
	conn_label.text = HudFormatter.format_connection_badge(is_online, rtt_ms)

	var me := sim.get_player(local_player_id)
	if me != null:
		stats_label.text = "Pontos: %d   ·   Eliminações: %d   ·   Blocos: %d" % [
			me.score,
			me.kills,
			me.blocks_destroyed,
		]
		powerups_label.text = HudFormatter.format_powerups_summary(me)

	for child in roster_box.get_children():
		child.queue_free()

	for p in sim.players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = ArenaRenderer.PLAYER_COLORS[p.slot % ArenaRenderer.PLAYER_COLORS.size()]
		row.add_child(swatch)

		var lbl := Label.new()
		var p_name := ArenaRenderer.PLAYER_NAMES[p.slot % ArenaRenderer.PLAYER_NAMES.size()]
		if p.id == local_player_id:
			p_name += " (Você)"
		var st := "VIVO" if p.alive else "ELIMINADO"
		lbl.text = "%s — %s · %d pts (%d K)" % [p_name, st, p.score, p.kills]
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0) if p.alive else Color(0.55, 0.58, 0.68))
		row.add_child(lbl)
		roster_box.add_child(row)


func _show_results() -> void:
	if result_overlay == null or sim == null:
		return
	result_overlay.visible = true
	if sim.winner_id == "":
		result_title_label.text = "EMPATE! (%s)" % sim.end_reason.to_upper()
	elif sim.winner_id == local_player_id:
		result_title_label.text = "VITÓRIA! VOCÊ VENCEU A ARENA!"
	else:
		var w := sim.get_player(sim.winner_id)
		var w_name := ArenaRenderer.PLAYER_NAMES[w.slot % ArenaRenderer.PLAYER_NAMES.size()] if w != null else sim.winner_id
		result_title_label.text = "FIM DE PARTIDA — VENCEDOR: %s" % w_name

	for child in result_rows_box.get_children():
		child.queue_free()

	var standings := HudFormatter.build_standings(sim)
	for st in standings:
		var line := Label.new()
		line.text = "%dº  %-10s   %4d pts   |   Kills: %d   |   Blocos: %d   |   Power-ups: %d" % [
			int(st["place"]),
			str(st["name"]),
			int(st["score"]),
			int(st["kills"]),
			int(st["blocks"]),
			int(st["powerups"]),
		]
		line.add_theme_font_size_override("font_size", 16)
		result_rows_box.add_child(line)


func _build_ui() -> void:
	if renderer != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Moldura da Arena 15x13 (720x624) à esquerda
	var arena_frame := Panel.new()
	arena_frame.position = Vector2(24, 44)
	arena_frame.size = Vector2(728, 632)
	add_child(arena_frame)

	renderer = ArenaRenderer.new()
	renderer.position = Vector2(28, 48)
	add_child(renderer)

	# Painel lateral do HUD competitivo (x=772..1256)
	var hud_panel := PanelContainer.new()
	hud_panel.position = Vector2(772, 44)
	hud_panel.size = Vector2(484, 632)
	add_child(hud_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	hud_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	mode_label = Label.new()
	mode_label.add_theme_font_size_override("font_size", 16)
	mode_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	vbox.add_child(mode_label)

	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 42)
	clock_label.text = "03:00"
	vbox.add_child(clock_label)

	alive_label = Label.new()
	alive_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(alive_label)

	conn_label = Label.new()
	conn_label.add_theme_font_size_override("font_size", 13)
	conn_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.72))
	vbox.add_child(conn_label)

	vbox.add_child(HSeparator.new())

	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(stats_label)

	powerups_label = Label.new()
	powerups_label.add_theme_font_size_override("font_size", 14)
	powerups_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	powerups_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(powerups_label)

	vbox.add_child(HSeparator.new())

	var roster_title := Label.new()
	roster_title.text = "PARTICIPANTES"
	roster_title.add_theme_font_size_override("font_size", 15)
	roster_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	vbox.add_child(roster_title)

	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 8)
	vbox.add_child(roster_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var controls_hint := Label.new()
	controls_hint.text = "WASD/Setas: Mover · Espaço: Bomba · ESC/P: Pausa"
	controls_hint.add_theme_font_size_override("font_size", 13)
	controls_hint.add_theme_color_override("font_color", Color(0.65, 0.70, 0.84))
	vbox.add_child(controls_hint)

	# Overlay de Pausa
	pause_overlay = _build_modal_overlay("JOGO PAUSADO")
	var pause_box: VBoxContainer = pause_overlay.get_node("Card/Margin/VBox")
	var btn_resume := Button.new()
	btn_resume.text = "Continuar Partida (ESC)"
	btn_resume.pressed.connect(toggle_pause)
	pause_box.add_child(btn_resume)

	var btn_restart := Button.new()
	btn_restart.text = "Reiniciar Partida"
	btn_restart.pressed.connect(func() -> void:
		start_local_match(game_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty)
	)
	pause_box.add_child(btn_restart)

	var btn_menu := Button.new()
	btn_menu.text = "Voltar ao Menu Principal"
	btn_menu.pressed.connect(func() -> void: return_to_menu_requested.emit())
	pause_box.add_child(btn_menu)
	pause_overlay.visible = false
	add_child(pause_overlay)

	# Overlay de Resultado
	result_overlay = _build_modal_overlay("RESULTADO DA PARTIDA")
	var res_box: VBoxContainer = result_overlay.get_node("Card/Margin/VBox")
	result_title_label = res_box.get_node("Title")
	result_rows_box = VBoxContainer.new()
	result_rows_box.add_theme_constant_override("separation", 8)
	res_box.add_child(result_rows_box)

	var res_btns := HBoxContainer.new()
	res_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	res_btns.add_theme_constant_override("separation", 16)
	res_box.add_child(res_btns)

	var btn_again := Button.new()
	btn_again.text = "Jogar Novamente"
	btn_again.pressed.connect(func() -> void:
		start_local_match(game_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty)
		rematch_requested.emit(game_mode)
	)
	res_btns.add_child(btn_again)

	var btn_back := Button.new()
	btn_back.text = "Menu Principal"
	btn_back.pressed.connect(func() -> void: return_to_menu_requested.emit())
	res_btns.add_child(btn_back)
	result_overlay.visible = false
	add_child(result_overlay)


func _build_modal_overlay(title_text: String) -> Control:
	var root := ColorRect.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.color = Color(0.04, 0.05, 0.10, 0.78)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(560, 320)
	card.position = Vector2(360, 200)
	root.add_child(card)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	vbox.add_child(title)

	return root

