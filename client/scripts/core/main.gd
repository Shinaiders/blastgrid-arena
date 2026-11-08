extends Control
## Gerenciador principal de telas do BlastGrid Arena (Dias 05, 13 e 14 — PROJECT_BRIEF §9, GDD §11).
## Cobre o fluxo completo de telas:
##   1. Splash -> 2. Inicial -> 3. Login -> 4. Seleção de Personagem -> 5. Seleção de Modo ->
##   6. Lobby -> 7. Busca por Partidas -> 8. Arena (com 9. Pausa e 10. Resultado) ->
##   11. Ranking -> 12. Perfil -> 13. Configurações.

const ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right", &"place_bomb"]
const ArenaScene = preload("res://scenes/arena/arena.tscn")

enum Screen {
	SPLASH = 1,
	HOME = 2,
	LOGIN = 3,
	CHARACTER_SELECT = 4,
	MODE_SELECT = 5,
	LOBBY = 6,
	MATCHMAKING = 7,
	ARENA = 8,
	RANKING = 11,
	PROFILE = 12,
	SETTINGS = 13,
}

@onready var _info: Label = %Info
@onready var _input: Label = %InputState

var paused := false
var current_screen: int = Screen.SPLASH
var splash_elapsed: float = 0.0

var selected_character: String = "sparky_a"
var selected_mode: String = "practice"
var bot_difficulty: String = "medium"
var server_url: String = "ws://localhost:8080/ws"
var player_display_name: String = "Convidado"

var screen_layer: Control
var arena_instance: ArenaMatchController = null


func _ready() -> void:
	if _info != null:
		_info.text = PlatformInfo.summary()
	_refresh_input()
	_setup_screen_layer()
	show_screen(Screen.HOME)


func _unhandled_input(event: InputEvent) -> void:
	if current_screen == Screen.ARENA:
		return
	if current_screen == Screen.SPLASH and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		if event.is_pressed():
			show_screen(Screen.HOME)
			return
	if event.is_action_pressed(&"pause"):
		paused = not paused
		get_viewport().set_input_as_handled()
	_refresh_input()


func _process(delta: float) -> void:
	if current_screen == Screen.SPLASH:
		splash_elapsed += delta
		if splash_elapsed >= 1.2:
			show_screen(Screen.HOME)
	if current_screen != Screen.ARENA:
		_refresh_input()


## Texto com as ações pressionadas; separado para ser testável sem eventos reais (Dia 05).
static func describe_input(pressed: Array[StringName], is_paused: bool) -> String:
	if is_paused:
		return "PAUSADO — ESC/P/Start para continuar"
	if pressed.is_empty():
		return "WASD/setas para mover · Espaço para bomba · ESC para pausar"
	return "Entrada: " + ", ".join(pressed)


func _refresh_input() -> void:
	if _input == null:
		return
	var pressed: Array[StringName] = []
	for action in ACTIONS:
		if Input.is_action_pressed(action):
			pressed.append(action)
	var text := describe_input(pressed, paused)
	if _input.text != text:
		_input.text = text


func _setup_screen_layer() -> void:
	var center := get_node_or_null("Center")
	if center != null:
		center.position = Vector2(center.position.x, 16)
	screen_layer = Control.new()
	screen_layer.name = "ScreenLayer"
	screen_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen_layer)


func show_screen(scr: int) -> void:
	current_screen = scr
	if screen_layer == null:
		_setup_screen_layer()
	for child in screen_layer.get_children():
		child.queue_free()
	arena_instance = null

	var center := get_node_or_null("Center")
	if center != null:
		center.visible = (scr != Screen.ARENA)

	match scr:
		Screen.SPLASH:
			_build_splash()
		Screen.HOME:
			_build_home()
		Screen.LOGIN:
			_build_login()
		Screen.CHARACTER_SELECT:
			_build_character_select()
		Screen.MODE_SELECT:
			_build_mode_select()
		Screen.LOBBY:
			_build_lobby()
		Screen.MATCHMAKING:
			_build_matchmaking()
		Screen.ARENA:
			_build_arena()
		Screen.RANKING:
			_build_ranking()
		Screen.PROFILE:
			_build_profile()
		Screen.SETTINGS:
			_build_settings()


func _create_card(title_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 420)
	panel.position = Vector2(300, 175)
	screen_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	return vbox


func _build_splash() -> void:
	var box := _create_card("OFICINA DE FOGOS — CARREGANDO ARENA...")
	var lbl := Label.new()
	lbl.text = "Pressione qualquer tecla para iniciar"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)


func _start_mode(mode: String) -> void:
	selected_mode = mode
	show_screen(Screen.ARENA)


func _build_home() -> void:
	var box := _create_card("MENU PRINCIPAL — %s" % player_display_name)
	var btns := [
		["Jogar Agora (Seleção de Modo)", func() -> void: show_screen(Screen.MODE_SELECT)],
		["Partida Rápida (Practice vs 3 Bots)", func() -> void: _start_mode("practice")],
		["Free For All Local (1J + 3 Bots)", func() -> void: _start_mode("ffa")],
		["Selecionar Personagem (Sparkies)", func() -> void: show_screen(Screen.CHARACTER_SELECT)],
		["Multiplayer Online / Lobby", func() -> void: show_screen(Screen.LOBBY)],
		["Conta / Login", func() -> void: show_screen(Screen.LOGIN)],
		["Ranking Global", func() -> void: show_screen(Screen.RANKING)],
		["Perfil e Conquistas", func() -> void: show_screen(Screen.PROFILE)],
		["Configurações", func() -> void: show_screen(Screen.SETTINGS)],
	]
	for item: Array in btns:
		var b := Button.new()
		b.text = str(item[0])
		b.pressed.connect(item[1])
		box.add_child(b)


func _build_login() -> void:
	var box := _create_card("AUTENTICAÇÃO E SESSÃO")
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Nome de exibição (3 a 20 caracteres)"
	name_input.text = player_display_name
	box.add_child(name_input)

	var btn_guest := Button.new()
	btn_guest.text = "Entrar como Convidado"
	btn_guest.pressed.connect(func() -> void:
		if name_input.text.strip_edges().length() >= 3:
			player_display_name = name_input.text.strip_edges().left(20)
		show_screen(Screen.HOME)
	)
	box.add_child(btn_guest)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_character_select() -> void:
	var box := _create_card("SELEÇÃO DE PERSONAGEM (SPARKIES)")
	var chars := [
		["sparky_a", "Volt (Coral) — Vel 4.0 · Bombas 1 · Alcance 2"],
		["sparky_b", "Ember (Ciano) — Vel 4.0 · Bombas 1 · Alcance 2"],
		["sparky_c", "Moss (Lima) — Vel 4.0 · Bombas 1 · Alcance 2"],
		["sparky_d", "Frost (Âmbar) — Vel 4.0 · Bombas 1 · Alcance 2"],
	]
	for c: Array in chars:
		var cid := str(c[0])
		var b := Button.new()
		b.text = ("%s  [SELECIONADO]" if selected_character == cid else "%s") % str(c[1])
		b.pressed.connect(func() -> void:
			selected_character = cid
			show_screen(Screen.CHARACTER_SELECT)
		)
		box.add_child(b)

	var btn_next := Button.new()
	btn_next.text = "Escolher Modo de Jogo →"
	btn_next.pressed.connect(func() -> void: show_screen(Screen.MODE_SELECT))
	box.add_child(btn_next)

	var btn_back := Button.new()
	btn_back.text = "Voltar ao Menu"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_mode_select() -> void:
	var box := _create_card("SELEÇÃO DE MODO DE JOGO")
	var btn_practice := Button.new()
	btn_practice.text = "Practice (Treinamento — 1 Jogador + 3 Bots, sem ranking)"
	btn_practice.pressed.connect(func() -> void:
		selected_mode = "practice"
		show_screen(Screen.ARENA)
	)
	box.add_child(btn_practice)

	var btn_ffa := Button.new()
	btn_ffa.text = "Free For All (4 Participantes — Último Vivo / Maior Pontuação em 3 min)"
	btn_ffa.pressed.connect(func() -> void:
		selected_mode = "ffa"
		show_screen(Screen.ARENA)
	)
	box.add_child(btn_ffa)

	var btn_online := Button.new()
	btn_online.text = "Buscar Partida Online (Matchmaking)"
	btn_online.pressed.connect(func() -> void: show_screen(Screen.MATCHMAKING))
	box.add_child(btn_online)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_lobby() -> void:
	var box := _create_card("LOBBY DE SALA")
	var info := Label.new()
	info.text = "Servidor: %s\nPersonagem: %s · Dificuldade Bots: %s" % [server_url, selected_character, bot_difficulty]
	box.add_child(info)

	var btn_start_local := Button.new()
	btn_start_local.text = "Iniciar Sala Local (Com Bots)"
	btn_start_local.pressed.connect(func() -> void:
		selected_mode = "ffa"
		show_screen(Screen.ARENA)
	)
	box.add_child(btn_start_local)

	var btn_mm := Button.new()
	btn_mm.text = "Ir para Busca de Partidas"
	btn_mm.pressed.connect(func() -> void: show_screen(Screen.MATCHMAKING))
	box.add_child(btn_mm)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_matchmaking() -> void:
	var box := _create_card("BUSCA POR PARTIDAS")
	var lbl := Label.new()
	lbl.text = "Procurando adversários compatíveis (Web / Desktop / Steam)..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)

	var btn_fill_bots := Button.new()
	btn_fill_bots.text = "Iniciar Imediatamente com 3 Bots"
	btn_fill_bots.pressed.connect(func() -> void:
		selected_mode = "ffa"
		show_screen(Screen.ARENA)
	)
	box.add_child(btn_fill_bots)

	var btn_cancel := Button.new()
	btn_cancel.text = "Cancelar Busca"
	btn_cancel.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_cancel)


func _build_arena() -> void:
	arena_instance = ArenaScene.instantiate()
	arena_instance.selected_character = selected_character
	arena_instance.bot_difficulty = bot_difficulty
	arena_instance.game_mode = selected_mode
	arena_instance.return_to_menu_requested.connect(func() -> void: show_screen(Screen.HOME))
	screen_layer.add_child(arena_instance)
	arena_instance.start_local_match(selected_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty)


func _build_ranking() -> void:
	var box := _create_card("RANKING — TEMPORADA 1 (FFA)")
	var sample := [
		"1º  VoltMaster      1420 MMR   (28 V / 35 J)",
		"2º  SparkQueen      1365 MMR   (22 V / 30 J)",
		"3º  GridBomber      1290 MMR   (19 V / 29 J)",
		"4º  %s              1000 MMR   (Conta Local)" % player_display_name,
	]
	for line in sample:
		var l := Label.new()
		l.text = line
		box.add_child(l)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_profile() -> void:
	var box := _create_card("PERFIL DO JOGADOR — %s" % player_display_name)
	var lbl := Label.new()
	lbl.text = "Personagem favorito: %s\nPlataforma: %s\nConquistas: Primeira Vitória · Efeito Dominó · Colecionador" % [
		selected_character,
		PlatformInfo.platform_name(),
	]
	box.add_child(lbl)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_settings() -> void:
	var box := _create_card("CONFIGURAÇÕES")
	for diff in ["easy", "medium", "hard"]:
		var b := Button.new()
		b.text = ("Dificuldade dos Bots: %s [ATIVO]" if bot_difficulty == diff else "Dificuldade dos Bots: %s") % diff.to_upper()
		b.pressed.connect(func() -> void:
			bot_difficulty = diff
			show_screen(Screen.SETTINGS)
		)
		box.add_child(b)

	var btn_fs := Button.new()
	btn_fs.text = "Alternar Tela Cheia (Fullscreen)"
	btn_fs.pressed.connect(func() -> void:
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	box.add_child(btn_fs)

	var btn_back := Button.new()
	btn_back.text = "Voltar"
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)
