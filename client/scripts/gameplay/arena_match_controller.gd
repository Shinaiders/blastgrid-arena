class_name ArenaMatchController
extends Control
## Controlador de partida (Dia 13): une simulação a 20 Hz, 3 bots, ArenaRenderer, HUD competitivo,
## menu de pausa e tela de resultado da partida.

signal return_to_menu_requested
signal rematch_requested(mode: String)

const TICK_DT: float = 0.05 # 20 Hz

var game_mode: String = "practice" # "practice" | "ffa" | "ffa_8p" | "ranked" | "ranked_8p"
var bot_difficulty: String = "medium"
var local_player_id: String = "p0"
var selected_character: String = "sparky_a"
var is_online: bool = false
var rtt_ms: int = 0
var player_count: int = 4
var use_large_map: bool = false
var is_ranked: bool = false
var account_store: AccountStore = null
var _result_recorded: bool = false

var sim: WorldSim = null
var bots: Array[BotBrain] = []
var tick_accum: float = 0.0
var is_paused: bool = false
var bomb_queued: bool = false

var renderer: ArenaRenderer
var arena_frame: Panel
var hud_panel: PanelContainer
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

var sfx_synth: SfxSynth = SfxSynth.new()
var _sfx_players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	if not OS.has_feature("web"):
		sfx_synth.unlock_on_gesture()
	_build_ui()
	if sim == null:
		start_local_match(game_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty)


func start_local_match(mode: String = "practice", seed_val: int = 1337, diff: String = "medium", p_count: int = 0, large_map: bool = false) -> void:
	if not OS.has_feature("web"):
		sfx_synth.unlock_on_gesture()
	game_mode = mode
	is_ranked = (mode == "ranked" or mode == "ranked_8p")
	if p_count <= 0:
		player_count = 8 if (mode == "ffa_8p" or mode == "ranked_8p") else 4
	else:
		player_count = p_count
	use_large_map = large_map or (player_count > 4) or (mode == "ffa_8p" or mode == "ranked_8p")

	if is_ranked and account_store != null:
		bot_difficulty = RankedSystem.bot_difficulty_for_mmr(account_store.rating)
	else:
		bot_difficulty = diff

	is_online = false
	is_paused = false
	bomb_queued = false
	_result_recorded = false
	tick_accum = 0.0

	var ids: Array[String] = ["p0"]
	for i in range(1, player_count):
		ids.append("bot%d" % i)

	sim = WorldSim.new(seed_val, ids, mode == "practice", use_large_map)
	var p0 := sim.get_player(local_player_id)
	if p0 != null:
		p0.character_id = selected_character

	bots.clear()
	for i in range(1, player_count):
		var b_diff := bot_difficulty
		if mode == "practice" and i == 1:
			b_diff = "easy"
		elif (mode == "ffa" or is_ranked) and i == player_count - 1:
			b_diff = "hard"
		bots.append(BotBrain.new("bot%d" % i, b_diff, seed_val + i * 101))

	if renderer != null:
		renderer.bind_sim(sim)
	if pause_overlay != null:
		pause_overlay.visible = false
	if result_overlay != null:
		result_overlay.visible = false
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if sfx_synth != null:
		sfx_synth.unlock_on_gesture(event)
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


func _toggle_arena_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


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
	_update_arena_layout()
	if renderer != null:
		renderer.step_visuals(delta, alpha)


func _update_arena_layout() -> void:
	if not is_inside_tree():
		return
	var vp_sz := get_viewport_rect().size
	var offset_x := maxf((vp_sz.x - 1280.0) * 0.5, 0.0)
	var offset_y := maxf((vp_sz.y - 720.0) * 0.5, 0.0)
	var off := Vector2(offset_x, offset_y)
	if arena_frame != null:
		arena_frame.position = Vector2(24, 44) + off
	if renderer != null:
		renderer.base_position = Vector2(28, 48) + off
	if hud_panel != null:
		hud_panel.position = Vector2(772, 44) + off
	if pause_overlay != null and pause_overlay.has_node("Card"):
		var pcard: Control = pause_overlay.get_node("Card")
		pcard.position = Vector2(360, 200) + off
	if result_overlay != null and result_overlay.has_node("Card"):
		var rcard: Control = result_overlay.get_node("Card")
		rcard.position = Vector2(360, 200) + off


func _advance_one_tick() -> void:
	if renderer != null:
		renderer.snapshot_positions_before_tick()

	var dir := _read_local_direction()
	sim.set_input(local_player_id, dir, bomb_queued)
	bomb_queued = false

	for b in bots:
		var cmd := b.decide(sim)
		sim.set_input(b.player_id, str(cmd["dir"]), bool(cmd["bomb"]))

	var was_match_over := sim.match_over
	var evs := sim.step_tick()
	if renderer != null:
		renderer.on_tick_events(evs)
	_handle_sfx_events(evs)
	_refresh_hud()

	if sim.match_over:
		if not was_match_over:
			_play_sfx("victory")
		_show_results()


func _handle_sfx_events(events: Array[Dictionary]) -> void:
	var played_bomb := false
	var played_exp := false
	var played_pu := false
	for e in events:
		var k := str(e.get("k", ""))
		if k == "bomb_placed" and not played_bomb:
			_play_sfx("bomb_place")
			played_bomb = true
		elif k == "explosion" and not played_exp:
			_play_sfx("explosion")
			played_exp = true
		elif k == "powerup_collected" and not played_pu:
			_play_sfx("powerup")
			played_pu = true


func _play_sfx(sound_id: String) -> void:
	if not is_inside_tree():
		return
	if sfx_synth == null or not sfx_synth.can_play():
		return
	var stream := sfx_synth.get_stream(sound_id)
	if stream == null:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	if not _sfx_players.is_empty():
		_sfx_players[0].stream = stream
		_sfx_players[0].play()


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
	var map_tag := "%dx%d" % [sim.grid.cols, sim.grid.rows]
	match game_mode:
		"practice":
			mode_label.text = "MODO: TREINO (%s)" % map_tag
		"ranked":
			mode_label.text = "🏆 RANQUEADO 4J (%s)" % map_tag
		"ranked_8p":
			mode_label.text = "🏆 RANQUEADO 8J · MAPA GRANDE (%s)" % map_tag
		"ffa_8p":
			mode_label.text = "🗺️ MEGA ARENA 8J · MAPA GRANDE (%s)" % map_tag
		_:
			mode_label.text = "MODO: FREE FOR ALL (%s)" % map_tag
	alive_label.text = "Vivos: %d / %d" % [HudFormatter.count_alive(sim.players), sim.players.size()]
	if account_store != null:
		conn_label.text = "%s  ·  %s" % [
			RankedSystem.format_badge(account_store.rating),
			HudFormatter.format_connection_badge(is_online, rtt_ms),
		]
	else:
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
	var my_place := sim.players.size()
	var my_kills := 0
	var my_blocks := 0
	for st in standings:
		if str(st["id"]) == local_player_id:
			my_place = int(st["place"])
			my_kills = int(st["kills"])
			my_blocks = int(st["blocks"])

	if account_store != null and not _result_recorded:
		_result_recorded = true
		var rec := account_store.record_match_result(is_ranked, my_place, sim.players.size(), my_kills, my_blocks)
		var delta_mmr := int(rec.get("delta", 0))
		var new_tier: Dictionary = rec.get("new_tier", RankedSystem.get_tier_info(account_store.rating))
		var sign_str := "+%d" % delta_mmr if delta_mmr >= 0 else "%d" % delta_mmr
		var rank_banner := Label.new()
		if is_ranked:
			var promo_txt := "   🎉 PROMOVIDO DE DIVISÃO!" if bool(rec.get("promoted", false)) else ""
			rank_banner.text = "%s %s — %d MMR (%s MMR) · Progresso: %d%%%s" % [
				str(new_tier.get("icon", "🏆")),
				str(new_tier.get("division", "Bronze I")),
				int(rec.get("new_rating", account_store.rating)),
				sign_str,
				int(new_tier.get("progress_pct", 0)),
				promo_txt,
			]
		else:
			rank_banner.text = "Conta: %s  ·  Liga Atual: %s (Partida Casual — MMR mantido)" % [
				account_store.display_name,
				RankedSystem.format_badge(account_store.rating),
			]
		rank_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_banner.add_theme_font_size_override("font_size", 16)
		rank_banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.28) if delta_mmr >= 0 else Color(1.0, 0.55, 0.45))
		result_rows_box.add_child(rank_banner)
		result_rows_box.add_child(HSeparator.new())

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
		line.add_theme_font_size_override("font_size", 14 if sim.players.size() > 4 else 16)
		result_rows_box.add_child(line)


func _build_ui() -> void:
	if renderer != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_sfx_players.clear()
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		add_child(player)
		_sfx_players.append(player)

	# Moldura da Arena 15x13 (720x624) à esquerda
	arena_frame = Panel.new()
	arena_frame.position = Vector2(24, 44)
	arena_frame.size = Vector2(728, 632)
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.05, 0.07, 0.14, 0.96)
	frame_sb.border_color = Color(1.0, 0.80, 0.22, 0.90)
	frame_sb.set_border_width_all(2)
	frame_sb.set_corner_radius_all(8)
	arena_frame.add_theme_stylebox_override("panel", frame_sb)
	add_child(arena_frame)

	renderer = ArenaRenderer.new()
	renderer.position = Vector2(28, 48)
	add_child(renderer)

	# Painel lateral do HUD competitivo (x=772..1256)
	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(772, 44)
	hud_panel.size = Vector2(484, 632)
	var hud_sb := StyleBoxFlat.new()
	hud_sb.bg_color = Color(0.08, 0.10, 0.19, 0.95)
	hud_sb.border_color = Color(0.26, 0.38, 0.62, 0.92)
	hud_sb.set_border_width_all(2)
	hud_sb.set_corner_radius_all(12)
	hud_panel.add_theme_stylebox_override("panel", hud_sb)
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

	var quick_btns := HBoxContainer.new()
	quick_btns.add_theme_constant_override("separation", 10)
	vbox.add_child(quick_btns)

	var btn_hud_pause := Button.new()
	btn_hud_pause.text = "⏸ Pausar (ESC)"
	btn_hud_pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hud_pause.pressed.connect(toggle_pause)
	quick_btns.add_child(btn_hud_pause)

	var btn_hud_screen := Button.new()
	btn_hud_screen.text = "⛶ Tela Cheia (F11)"
	btn_hud_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hud_screen.pressed.connect(_toggle_arena_fullscreen)
	quick_btns.add_child(btn_hud_screen)

	var controls_hint := Label.new()
	controls_hint.text = "WASD/Setas: Mover · Espaço: Bomba · ESC: Pausa · F11: Tela"
	controls_hint.add_theme_font_size_override("font_size", 12)
	controls_hint.add_theme_color_override("font_color", Color(0.65, 0.70, 0.84))
	vbox.add_child(controls_hint)

	# Overlay de Pausa
	pause_overlay = _build_modal_overlay("JOGO PAUSADO")
	var pause_box: VBoxContainer = pause_overlay.get_node("Card/Margin/VBox")
	var btn_resume := Button.new()
	btn_resume.text = "▶ Continuar Partida (ESC)"
	btn_resume.pressed.connect(toggle_pause)
	pause_box.add_child(btn_resume)

	var btn_fs_pause := Button.new()
	btn_fs_pause.text = "⛶ Alternar Tela Cheia / Grande (F11)"
	btn_fs_pause.pressed.connect(_toggle_arena_fullscreen)
	pause_box.add_child(btn_fs_pause)

	var btn_restart := Button.new()
	btn_restart.text = "↻ Reiniciar Partida"
	btn_restart.pressed.connect(func() -> void:
		start_local_match(game_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty)
	)
	pause_box.add_child(btn_restart)

	var btn_menu := Button.new()
	btn_menu.text = "← Voltar ao Menu Principal"
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

