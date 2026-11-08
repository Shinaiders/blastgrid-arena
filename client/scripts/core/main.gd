extends Control
## Gerenciador principal de telas do BlastGrid Arena:
## - Criação de Conta e Login persistente (AccountStore)
## - Modo Ranqueado de Bronze até Diamante (RankedSystem)
## - Mapa Grande 19×15 para 8 Jogadores e Mapa Padrão 15×13 para 4 Jogadores
## - Suporte a Tela Grande (Maximizado) e Tela Cheia (F11 / Alt+Enter) com escala responsiva

const ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right", &"place_bomb"]
const ArenaScene = preload("res://scenes/arena/arena.tscn")
const MenuBackdrop = preload("res://scripts/ui/menu_backdrop.gd")

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
var selected_mode: String = "practice" # "practice" | "ffa" | "ffa_8p" | "ranked" | "ranked_8p"
var bot_difficulty: String = "medium"
var server_url: String = "ws://localhost:8080/ws"
var player_display_name: String = "Convidado"

var screen_layer: Control
var arena_instance: ArenaMatchController = null

var account_store: AccountStore = AccountStore.new()
var window_mode_state: String = "window_720p" # "window_720p" | "window_large" | "fullscreen"
var audio_volume: float = 1.0
var sfx_synth: SfxSynth = SfxSynth.new()
var _click_player: AudioStreamPlayer = null
var backdrop: Control = null
var _footer_input_label: Label = null
var _auth_feedback_msg: String = ""
var _auth_feedback_ok: bool = true


class SparkyPortrait extends Control:
	var character_color: Color = Color.WHITE
	var anim_t: float = 0.0

	func _process(delta: float) -> void:
		anim_t += delta
		queue_redraw()

	func _draw() -> void:
		MenuBackdrop.draw_mini_sparky(self, size * 0.5 + Vector2(0.0, 6.0), 1.35, character_color, anim_t)


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		var win := get_window()
		if win != null:
			win.content_scale_factor = 1.0
			win.content_scale_size = Vector2i(1280, 720)
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		DisplayServer.window_move_to_foreground()
	if not OS.has_feature("web"):
		sfx_synth.unlock_on_gesture()
	if _click_player == null:
		_click_player = AudioStreamPlayer.new()
		add_child(_click_player)
	if account_store != null:
		player_display_name = account_store.display_name
		selected_character = account_store.selected_character
	if _info != null:
		_info.text = PlatformInfo.summary()
	_refresh_input()
	_setup_screen_layer()
	show_screen(Screen.HOME)


func _unhandled_input(event: InputEvent) -> void:
	sfx_synth.unlock_on_gesture(event)
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k: InputEventKey = event
		if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return

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
	_update_window_scale()
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
		return "WASD/setas para mover · Espaço para bomba · ESC para pausar · F11 Tela Cheia"
	return "Entrada: " + ", ".join(pressed)


func _refresh_input() -> void:
	var pressed: Array[StringName] = []
	for action in ACTIONS:
		if Input.is_action_pressed(action):
			pressed.append(action)
	var text := describe_input(pressed, paused)
	if _input != null and _input.text != text:
		_input.text = text
	if _footer_input_label != null and _footer_input_label.text != text:
		_footer_input_label.text = text


func set_display_mode(mode_name: String) -> void:
	window_mode_state = mode_name
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win != null:
		win.content_scale_factor = 1.0
		win.content_scale_size = Vector2i(1280, 720)
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

	var screen_scale := DisplayServer.screen_get_scale()
	if screen_scale <= 0.0:
		screen_scale = 1.0

	match mode_name:
		"window_720p":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var base_sz := Vector2i(int(1280.0 * screen_scale), int(720.0 * screen_scale))
			DisplayServer.window_set_size(base_sz)
			var usable := DisplayServer.screen_get_usable_rect()
			if usable.size.x >= base_sz.x and usable.size.y >= base_sz.y:
				DisplayServer.window_set_position(usable.position + (usable.size - base_sz) / 2)
		"window_large":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var usable := DisplayServer.screen_get_usable_rect()
			if usable.size.x > 400 and usable.size.y > 300:
				var target_w := int(float(usable.size.x) * 0.94)
				var target_h := int(float(usable.size.y) * 0.92)
				var new_sz := Vector2i(target_w, target_h)
				DisplayServer.window_set_size(new_sz)
				DisplayServer.window_set_position(usable.position + (usable.size - new_sz) / 2)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if current_screen != Screen.ARENA:
		show_screen(current_screen)


func toggle_large_screen() -> void:
	if window_mode_state == "window_large":
		set_display_mode("window_720p")
	else:
		set_display_mode("window_large")


func toggle_fullscreen() -> void:
	if window_mode_state == "fullscreen":
		set_display_mode("window_large")
	else:
		set_display_mode("fullscreen")


func _update_window_scale() -> void:
	pass


func _play_ui_click() -> void:
	if not is_inside_tree() or _click_player == null or audio_volume <= 0.01:
		return
	if not sfx_synth.can_play():
		sfx_synth.unlock_on_gesture()
	_click_player.stream = sfx_synth.get_stream("ui_click")
	_click_player.volume_db = linear_to_db(clampf(audio_volume, 0.05, 1.0))
	_click_player.play()


func _setup_screen_layer() -> void:
	var center := get_node_or_null("Center")
	if center != null:
		center.visible = false
	if screen_layer == null:
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
	backdrop = null
	_footer_input_label = null

	var center := get_node_or_null("Center")
	if center != null:
		center.visible = false

	if scr != Screen.ARENA:
		backdrop = MenuBackdrop.new()
		backdrop.character_id = selected_character
		backdrop.show_character_showcase = false
		screen_layer.add_child(backdrop)

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


func _make_stylebox(bg: Color, border: Color, border_w: int = 2, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


func _make_styled_panel(highlight: bool = false, bg_alpha: float = 0.94) -> PanelContainer:
	var p := PanelContainer.new()
	var border_col := Color(1.0, 0.80, 0.22, 0.95) if highlight else Color(0.26, 0.36, 0.58, 0.90)
	var bg_col := Color(0.08, 0.10, 0.19, bg_alpha)
	p.add_theme_stylebox_override("panel", _make_stylebox(bg_col, border_col, 2, 14))
	return p


func _make_button(label_text: String, primary: bool = false, min_h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = label_text
	b.custom_minimum_size = Vector2(0.0, min_h)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		b.add_theme_stylebox_override("normal", _make_stylebox(Color(0.94, 0.33, 0.25), Color(1.0, 0.84, 0.32), 2, 10))
		b.add_theme_stylebox_override("hover", _make_stylebox(Color(1.0, 0.43, 0.33), Color(1.0, 0.92, 0.52), 2, 10))
		b.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.78, 0.24, 0.18), Color(1.0, 0.80, 0.22), 2, 10))
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", Color.WHITE)
	else:
		b.add_theme_stylebox_override("normal", _make_stylebox(Color(0.13, 0.17, 0.29), Color(0.30, 0.42, 0.68), 1, 9))
		b.add_theme_stylebox_override("hover", _make_stylebox(Color(0.20, 0.27, 0.45), Color(0.0, 0.85, 0.84), 2, 9))
		b.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.10, 0.13, 0.23), Color(1.0, 0.80, 0.22), 2, 9))
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	b.pressed.connect(_play_ui_click)
	return b


func _build_shell() -> CenterContainer:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	screen_layer.add_child(root_vbox)

	# Barra Superior Fixa (Header)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.07, 0.14, 0.92), Color(0.22, 0.30, 0.50, 0.8), 1, 0))
	root_vbox.add_child(header_panel)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	header_panel.add_child(header_hbox)

	var brand := Label.new()
	brand.text = "⚡ BLASTGRID ARENA"
	brand.add_theme_font_size_override("font_size", 20)
	brand.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	header_hbox.add_child(brand)

	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_l)

	var acc_tag := "Conta Registrada" if account_store.account_kind == "registered" else "Convidado"
	var rank_badge := RankedSystem.format_badge(account_store.rating)
	var status_pill := Label.new()
	status_pill.text = "👤 %s (%s)   ·   %s   ·   🤖 %s" % [
		player_display_name,
		acc_tag,
		rank_badge,
		MenuBackdrop.get_character_name(selected_character),
	]
	status_pill.add_theme_font_size_override("font_size", 14)
	status_pill.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	header_hbox.add_child(status_pill)

	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer_r)

	var btn_acct := _make_button("👤 Criar Conta / Login", account_store.account_kind != "registered", 32.0)
	btn_acct.pressed.connect(func() -> void: show_screen(Screen.LOGIN))
	header_hbox.add_child(btn_acct)

	var btn_large := _make_button("🗖 Tela Grande" if window_mode_state != "window_large" else "🗖 Janela 720p", window_mode_state == "window_large", 32.0)
	btn_large.pressed.connect(toggle_large_screen)
	header_hbox.add_child(btn_large)

	var btn_fs := _make_button("⛶ Tela Cheia (F11)" if window_mode_state != "fullscreen" else "⛶ Sair Tela Cheia", window_mode_state == "fullscreen", 32.0)
	btn_fs.pressed.connect(toggle_fullscreen)
	header_hbox.add_child(btn_fs)

	if current_screen != Screen.SETTINGS:
		var btn_cfg := _make_button("⚙ Opções", false, 32.0)
		btn_cfg.pressed.connect(func() -> void: show_screen(Screen.SETTINGS))
		header_hbox.add_child(btn_cfg)

	# Área Central Responsiva
	var center_area := CenterContainer.new()
	center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(center_area)

	# Barra Inferior (Footer)
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _make_stylebox(Color(0.05, 0.06, 0.12, 0.88), Color(0.18, 0.24, 0.40, 0.6), 1, 0))
	root_vbox.add_child(footer_panel)

	var footer_hbox := HBoxContainer.new()
	footer_panel.add_child(footer_hbox)

	_footer_input_label = Label.new()
	_footer_input_label.text = describe_input([], paused)
	_footer_input_label.add_theme_font_size_override("font_size", 12)
	_footer_input_label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.96))
	footer_hbox.add_child(_footer_input_label)

	var f_spacer := Control.new()
	f_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(f_spacer)

	var plat_lbl := Label.new()
	plat_lbl.text = PlatformInfo.summary()
	plat_lbl.add_theme_font_size_override("font_size", 12)
	plat_lbl.add_theme_color_override("font_color", Color(0.52, 0.60, 0.76))
	footer_hbox.add_child(plat_lbl)

	return center_area


func _create_card(title_text: String, min_size: Vector2 = Vector2(760, 460), highlight: bool = false) -> VBoxContainer:
	var center_area := _build_shell()
	var panel := _make_styled_panel(highlight)
	panel.custom_minimum_size = min_size
	center_area.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	return vbox


func _build_splash() -> void:
	var box := _create_card("OFICINA DE FOGOS — CARREGANDO ARENA...", Vector2(640, 280), true)
	var lbl := Label.new()
	lbl.text = "Pressione qualquer tecla ou clique para entrar na Arena"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	box.add_child(lbl)


func _start_mode(mode: String) -> void:
	selected_mode = mode
	show_screen(Screen.ARENA)


func _build_home() -> void:
	var center_area := _build_shell()
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 20)
	center_area.add_child(main_hbox)

	# --- COLUNA ESQUERDA: Card Hero com Liga Atual, Sparky Ao Vivo e Modos Principais ---
	var hero_panel := _make_styled_panel(true, 0.90)
	hero_panel.custom_minimum_size = Vector2(400, 500)
	main_hbox.add_child(hero_panel)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 6)
	hero_panel.add_child(hero_vbox)

	var tier_info := RankedSystem.get_tier_info(account_store.rating)
	var rank_header := Label.new()
	rank_header.text = "%s LIGA ATUAL: %s (%d MMR)" % [
		str(tier_info.get("icon", "🥉")),
		str(tier_info.get("division", "Bronze I")).to_upper(),
		account_store.rating,
	]
	rank_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_header.add_theme_font_size_override("font_size", 16)
	rank_header.add_theme_color_override("font_color", tier_info.get("color", Color(1.0, 0.82, 0.25)))
	hero_vbox.add_child(rank_header)

	var prog_lbl := Label.new()
	prog_lbl.text = "Progresso até a próxima divisão: %d%%   (Rumo ao 💎 Diamante)" % int(tier_info.get("progress_pct", 0))
	prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_lbl.add_theme_font_size_override("font_size", 12)
	prog_lbl.add_theme_color_override("font_color", Color(0.75, 0.84, 0.98))
	hero_vbox.add_child(prog_lbl)

	var portrait := SparkyPortrait.new()
	portrait.character_color = MenuBackdrop.get_character_color(selected_character)
	portrait.custom_minimum_size = Vector2(340, 150)
	hero_vbox.add_child(portrait)

	var btn_swap := _make_button("🎨 Campeão: %s — Trocar Sparky" % MenuBackdrop.get_character_name(selected_character), false, 32.0)
	btn_swap.pressed.connect(func() -> void: show_screen(Screen.CHARACTER_SELECT))
	hero_vbox.add_child(btn_swap)

	hero_vbox.add_child(HSeparator.new())

	var btn_ranked := _make_button("🏆 JOGAR RANQUEADO 4J (BRONZE → DIAMANTE)", true, 42.0)
	btn_ranked.pressed.connect(func() -> void: _start_mode("ranked"))
	hero_vbox.add_child(btn_ranked)

	var btn_mega8 := _make_button("🗺️ MEGA ARENA 8 JOGADORES (MAPA GRANDE 19×15)", true, 42.0)
	btn_mega8.pressed.connect(func() -> void: _start_mode("ranked_8p"))
	hero_vbox.add_child(btn_mega8)

	var btn_quick := _make_button("▶ PARTIDA RÁPIDA (TREINO CASUAL 4J)", false, 36.0)
	btn_quick.pressed.connect(func() -> void: _start_mode("practice"))
	hero_vbox.add_child(btn_quick)

	# --- COLUNA DIREITA: Grid 2x3 de Cards de Modos, Conta, Ligas e Tela Grande ---
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	main_hbox.add_child(right_vbox)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	right_vbox.add_child(grid)

	var nav_items := [
		["🎯 Todos os Modos (4J & 8J)", "Ranqueado, Mapa Grande 19×15 (8J), FFA e Treino", func() -> void: show_screen(Screen.MODE_SELECT)],
		["👤 Criar Conta / Entrar", "Cadastre seu usuário, e-mail e senha para salvar seu Elo", func() -> void: show_screen(Screen.LOGIN)],
		["🏆 Ligas: Bronze → Diamante", "Tabela de Ligas (Bronze, Prata, Ouro, Platina, Diamante)", func() -> void: show_screen(Screen.RANKING)],
		["🎖 Perfil & Estatísticas", "Vitórias, abates, maior MMR e conquistas", func() -> void: show_screen(Screen.PROFILE)],
		["🌐 Lobby & Multiplayer", "Salas de 4 ou 8 jogadores com código de convite", func() -> void: show_screen(Screen.LOBBY)],
		["🖥 Tela Grande & Opções", "Maximizar janela, Tela Cheia (F11), Bots e Áudio", func() -> void: show_screen(Screen.SETTINGS)],
	]

	for item: Array in nav_items:
		var card := _make_styled_panel(false)
		card.custom_minimum_size = Vector2(360, 128)
		grid.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)

		var ct := Label.new()
		ct.text = str(item[0])
		ct.add_theme_font_size_override("font_size", 17)
		ct.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
		cv.add_child(ct)

		var cd := Label.new()
		cd.text = str(item[1])
		cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cd.add_theme_font_size_override("font_size", 13)
		cd.add_theme_color_override("font_color", Color(0.75, 0.82, 0.96))
		cd.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(cd)

		var cb := _make_button("Abrir →", false, 34.0)
		cb.pressed.connect(item[2])
		cv.add_child(cb)

	# Barra rápida de Status da Conta na base da coluna direita
	var acct_panel := _make_styled_panel(account_store.account_kind != "registered")
	_build_account_summary_bar(acct_panel)
	right_vbox.add_child(acct_panel)


func _build_account_summary_bar(parent_panel: PanelContainer) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	parent_panel.add_child(hb)

	var kind_str := "Conta Registrada ✔" if account_store.account_kind == "registered" else "Modo Convidado (Crie sua conta para salvar seu ranking!)"
	var lbl := Label.new()
	lbl.text = "👤 %s  ·  %s  ·  %d Partidas (%d Vitórias)" % [
		player_display_name,
		kind_str,
		account_store.matches_played,
		account_store.wins,
	]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 14)
	hb.add_child(lbl)

	var btn_login := _make_button("✨ Criar Conta / Login" if account_store.account_kind != "registered" else "🔑 Gerenciar Conta", account_store.account_kind != "registered", 34.0)
	btn_login.pressed.connect(func() -> void: show_screen(Screen.LOGIN))
	hb.add_child(btn_login)


func _build_login() -> void:
	var box := _create_card("👤 CONTA DO JOGADOR — CRIAR CONTA OU ENTRAR", Vector2(1060, 520), true)

	if not _auth_feedback_msg.is_empty():
		var fb := Label.new()
		fb.text = _auth_feedback_msg
		fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.add_theme_font_size_override("font_size", 15)
		fb.add_theme_color_override("font_color", Color(0.35, 0.96, 0.55) if _auth_feedback_ok else Color(1.0, 0.42, 0.38))
		box.add_child(fb)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	# --- COLUNA ESQUERDA: CRIAR NOVA CONTA (CADASTRO COMPLETO) ---
	var reg_card := _make_styled_panel(true)
	reg_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(reg_card)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	reg_card.add_child(rv)

	var rt := Label.new()
	rt.text = "✨ CRIAR NOVA CONTA"
	rt.add_theme_font_size_override("font_size", 19)
	rt.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
	rv.add_child(rt)

	var rdesc := Label.new()
	rdesc.text = "Cadastre sua conta para salvar seu MMR nas ligas Bronze até Diamante:"
	rdesc.add_theme_font_size_override("font_size", 13)
	rdesc.add_theme_color_override("font_color", Color(0.75, 0.84, 0.98))
	rv.add_child(rdesc)

	var reg_name := LineEdit.new()
	reg_name.placeholder_text = "Nome de Usuário (3 a 20 caracteres)"
	reg_name.text = player_display_name if player_display_name != "Convidado" else ""
	reg_name.custom_minimum_size = Vector2(0, 38)
	rv.add_child(reg_name)

	var reg_email := LineEdit.new()
	reg_email.placeholder_text = "Seu E-mail (ex: jogador@blastgrid.com)"
	reg_email.text = account_store.email
	reg_email.custom_minimum_size = Vector2(0, 38)
	rv.add_child(reg_email)

	var reg_pass := LineEdit.new()
	reg_pass.placeholder_text = "Crie uma Senha (mínimo 4 caracteres)"
	reg_pass.secret = true
	reg_pass.custom_minimum_size = Vector2(0, 38)
	rv.add_child(reg_pass)

	var btn_register := _make_button("✨ CADASTRAR MINHA CONTA E ENTRAR", true, 46.0)
	btn_register.pressed.connect(func() -> void:
		var res := account_store.register_account(
			reg_name.text.strip_edges(),
			reg_email.text.strip_edges(),
			reg_pass.text,
			selected_character
		)
		if bool(res.get("ok", false)):
			player_display_name = account_store.display_name
			_auth_feedback_ok = true
			_auth_feedback_msg = "✔ Conta '%s' criada com sucesso! Você iniciou em %s." % [
				player_display_name,
				RankedSystem.format_badge(account_store.rating),
			]
			show_screen(Screen.HOME)
		else:
			_auth_feedback_ok = false
			_auth_feedback_msg = "⚠ " + str(res.get("error", "Verifique os dados informados."))
			show_screen(Screen.LOGIN)
	)
	rv.add_child(btn_register)

	# --- COLUNA DIREITA: ENTRAR EM CONTA EXISTENTE OU CONVIDADO ---
	var log_card := _make_styled_panel(false)
	log_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(log_card)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	log_card.add_child(lv)

	var lt := Label.new()
	lt.text = "🔑 JÁ TENHO CONTA (LOGIN)"
	lt.add_theme_font_size_override("font_size", 19)
	lt.add_theme_color_override("font_color", Color(0.0, 0.85, 0.84))
	lv.add_child(lt)

	var log_user := LineEdit.new()
	log_user.placeholder_text = "Seu E-mail ou Nome de Usuário"
	log_user.custom_minimum_size = Vector2(0, 38)
	lv.add_child(log_user)

	var log_pass := LineEdit.new()
	log_pass.placeholder_text = "Sua Senha"
	log_pass.secret = true
	log_pass.custom_minimum_size = Vector2(0, 38)
	lv.add_child(log_pass)

	var btn_do_login := _make_button("🔑 ENTRAR NA CONTA", false, 44.0)
	btn_do_login.pressed.connect(func() -> void:
		var res := account_store.login_account(log_user.text.strip_edges(), log_pass.text)
		if bool(res.get("ok", false)):
			player_display_name = account_store.display_name
			selected_character = account_store.selected_character
			_auth_feedback_ok = true
			_auth_feedback_msg = "✔ Bem-vindo de volta, %s!" % player_display_name
			show_screen(Screen.HOME)
		else:
			_auth_feedback_ok = false
			_auth_feedback_msg = "⚠ " + str(res.get("error", "Credenciais inválidas."))
			show_screen(Screen.LOGIN)
	)
	lv.add_child(btn_do_login)

	lv.add_child(HSeparator.new())

	var gt := Label.new()
	gt.text = "⚡ ENTRADA RÁPIDA COMO CONVIDADO"
	gt.add_theme_font_size_override("font_size", 15)
	gt.add_theme_color_override("font_color", Color(0.82, 0.88, 0.98))
	lv.add_child(gt)

	var guest_name := LineEdit.new()
	guest_name.placeholder_text = "Apelido rápido (3 a 20 caracteres)"
	guest_name.text = player_display_name
	guest_name.custom_minimum_size = Vector2(0, 36)
	lv.add_child(guest_name)

	var btn_guest := _make_button("Continuar como Convidado →", false, 38.0)
	btn_guest.pressed.connect(func() -> void:
		account_store.login_guest(guest_name.text.strip_edges())
		player_display_name = account_store.display_name
		_auth_feedback_msg = ""
		show_screen(Screen.HOME)
	)
	lv.add_child(btn_guest)

	var btn_back := _make_button("← Voltar ao Menu Principal", false, 40.0)
	btn_back.pressed.connect(func() -> void:
		_auth_feedback_msg = ""
		show_screen(Screen.HOME)
	)
	box.add_child(btn_back)


func _build_character_select() -> void:
	var box := _create_card("ESCOLHA SEU SPARKY — CAMPEÕES DA ARENA", Vector2(1100, 520), true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	var chars := [
		["sparky_a", "VOLT", "Coral Elétrico", "Especialista equilibrado da Oficina de Fogos."],
		["sparky_b", "EMBER", "Ciano Criogênico", "Robô ágil com visor de alta precisão."],
		["sparky_c", "MOSS", "Lima Botânico", "Mestre em reação em cadeia e armadilhas."],
		["sparky_d", "FROST", "Âmbar Solar", "Blindagem reluzente e propulsor turbo."],
	]

	for c: Array in chars:
		var cid := str(c[0])
		var is_sel := (selected_character == cid)
		var card := _make_styled_panel(is_sel)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)

		var cname := Label.new()
		cname.text = str(c[1])
		cname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cname.add_theme_font_size_override("font_size", 20)
		cname.add_theme_color_override("font_color", MenuBackdrop.get_character_color(cid))
		cv.add_child(cname)

		var csub := Label.new()
		csub.text = str(c[2])
		csub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		csub.add_theme_font_size_override("font_size", 12)
		csub.add_theme_color_override("font_color", Color(0.72, 0.80, 0.95))
		cv.add_child(csub)

		var portrait := SparkyPortrait.new()
		portrait.character_color = MenuBackdrop.get_character_color(cid)
		portrait.custom_minimum_size = Vector2(180, 170)
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(portrait)

		var cdesc := Label.new()
		cdesc.text = str(c[3])
		cdesc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cdesc.add_theme_font_size_override("font_size", 12)
		cdesc.add_theme_color_override("font_color", Color(0.82, 0.88, 0.98))
		cv.add_child(cdesc)

		var b := _make_button("★ SELECIONADO" if is_sel else "Escolher %s" % str(c[1]), is_sel, 40.0)
		b.pressed.connect(func() -> void:
			selected_character = cid
			account_store.selected_character = cid
			account_store.save_account()
			show_screen(Screen.CHARACTER_SELECT)
		)
		cv.add_child(b)

	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 16)
	box.add_child(nav_row)

	var btn_back := _make_button("← Voltar ao Menu", false, 44.0)
	btn_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	nav_row.add_child(btn_back)

	var btn_next := _make_button("Escolher Modo de Jogo →", true, 44.0)
	btn_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_next.pressed.connect(func() -> void: show_screen(Screen.MODE_SELECT))
	nav_row.add_child(btn_next)


func _build_mode_select() -> void:
	var box := _create_card("SELEÇÃO DE MODO — 4 JOGADORES (15×13) & 8 JOGADORES (MAPA GRANDE 19×15)", Vector2(1140, 510), true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	var modes := [
		[
			"🏆 RANQUEADO 4J (15×13)",
			"Suba de 🥉 Bronze até 💎 Diamante!\n• 4 Participantes (Mapa Padrão 15×13)\n• Vale pontos de Liga (MMR)\n• Bots escalam com a sua Liga atual\n• Bônus de +4 MMR por eliminação",
			func() -> void: _start_mode("ranked"),
			"Jogar Ranqueado 4J ▶",
			true,
		],
		[
			"🗺️ RANQUEADO 8J (MAPA GRANDE)",
			"Batalha massiva para 8 Jogadores!\n• Mapa Grande Expandido 19×15\n• 8 Spawns simétricos nos cantos e bordas\n• Até +48 MMR pela 1ª colocação\n• Caos competitivo de 8 Sparkies",
			func() -> void: _start_mode("ranked_8p"),
			"Ranqueado 8J (19×15) ▶",
			true,
		],
		[
			"🔥 MEGA ARENA CASUAL 8J",
			"Partida casual no Mapa Grande 19×15 para 8 Jogadores sem risco de perder MMR.\n• 1 Jogador + 7 Bots\n• Mapa 19×15 completo\n• Excelente para treinar contra 7 rivais",
			func() -> void: _start_mode("ffa_8p"),
			"Mega Arena 8J Casual ▶",
			false,
		],
		[
			"🎯 TREINO CLÁSSICO 4J",
			"Aquecimento rápido na Arena 15×13.\n• 1 Jogador + 3 Bots\n• Sem alteração de MMR\n• Ideal para testar power-ups e combos",
			func() -> void: _start_mode("practice"),
			"Iniciar Treino 4J ▶",
			false,
		],
	]

	for m: Array in modes:
		var card := _make_styled_panel(bool(m[4]))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 10)
		card.add_child(cv)

		var mt := Label.new()
		mt.text = str(m[0])
		mt.add_theme_font_size_override("font_size", 16)
		mt.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
		cv.add_child(mt)

		var md := Label.new()
		md.text = str(m[1])
		md.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		md.size_flags_vertical = Control.SIZE_EXPAND_FILL
		md.add_theme_font_size_override("font_size", 13)
		md.add_theme_color_override("font_color", Color(0.82, 0.88, 0.98))
		cv.add_child(md)

		var mb := _make_button(str(m[3]), bool(m[4]), 44.0)
		mb.pressed.connect(m[2])
		cv.add_child(mb)

	var btn_back := _make_button("← Voltar ao Menu Principal", false, 40.0)
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_lobby() -> void:
	var box := _create_card("LOBBY DE SALA — 4 OU 8 JOGADORES", Vector2(800, 450), true)
	var info := Label.new()
	info.text = "Servidor: %s\nJogador: %s (%s)   ·   Campeão: %s" % [
		server_url,
		player_display_name,
		RankedSystem.format_badge(account_store.rating),
		MenuBackdrop.get_character_name(selected_character),
	]
	info.add_theme_font_size_override("font_size", 15)
	box.add_child(info)

	var btn_4p := _make_button("▶ Iniciar Sala 4 Jogadores (Mapa Padrão 15×13)", true, 46.0)
	btn_4p.pressed.connect(func() -> void: _start_mode("ranked"))
	box.add_child(btn_4p)

	var btn_8p := _make_button("🗺️ Iniciar Sala 8 Jogadores (Mapa Grande 19×15)", true, 46.0)
	btn_8p.pressed.connect(func() -> void: _start_mode("ranked_8p"))
	box.add_child(btn_8p)

	var btn_mm := _make_button("⚡ Ir para Busca Automática (Matchmaking)", false, 42.0)
	btn_mm.pressed.connect(func() -> void: show_screen(Screen.MATCHMAKING))
	box.add_child(btn_mm)

	var btn_back := _make_button("← Voltar ao Menu Principal", false, 40.0)
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_matchmaking() -> void:
	var box := _create_card("BUSCA POR PARTIDAS RANQUEADAS", Vector2(740, 400), true)
	var lbl := Label.new()
	lbl.text = "Sua Liga Atual: %s\nEscolha o formato da fila para iniciar imediatamente:" % RankedSystem.format_badge(account_store.rating)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	box.add_child(lbl)

	var btn_r4 := _make_button("🏆 Fila Ranqueada 4 Jogadores (Mapa 15×13)", true, 48.0)
	btn_r4.pressed.connect(func() -> void: _start_mode("ranked"))
	box.add_child(btn_r4)

	var btn_r8 := _make_button("🗺️ Fila Ranqueada 8 Jogadores (Mapa Grande 19×15)", true, 48.0)
	btn_r8.pressed.connect(func() -> void: _start_mode("ranked_8p"))
	box.add_child(btn_r8)

	var btn_cancel := _make_button("← Cancelar e Voltar", false, 40.0)
	btn_cancel.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_cancel)


func _build_arena() -> void:
	arena_instance = ArenaScene.instantiate()
	arena_instance.selected_character = selected_character
	arena_instance.bot_difficulty = bot_difficulty
	arena_instance.game_mode = selected_mode
	arena_instance.account_store = account_store
	arena_instance.return_to_menu_requested.connect(func() -> void: show_screen(Screen.HOME))
	screen_layer.add_child(arena_instance)
	var p_count := 8 if (selected_mode == "ffa_8p" or selected_mode == "ranked_8p") else 4
	var is_large := (p_count == 8)
	arena_instance.start_local_match(selected_mode, int(Time.get_ticks_msec()) & 0x7FFFFFFF, bot_difficulty, p_count, is_large)


func _build_ranking() -> void:
	var box := _create_card("🏆 LIGAS RANQUEADAS (BRONZE → DIAMANTE) & TOP JOGADORES", Vector2(1040, 520), true)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)

	# Esquerda: Tabela das 5 Ligas (Bronze até Diamante)
	var leagues_card := _make_styled_panel(false)
	leagues_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(leagues_card)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	leagues_card.add_child(lv)

	var lt := Label.new()
	lt.text = "ESCALA DE LIGAS OFICIAIS"
	lt.add_theme_font_size_override("font_size", 17)
	lt.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
	lv.add_child(lt)

	var my_tier := RankedSystem.get_tier_info(account_store.rating)
	for lg: Dictionary in RankedSystem.all_leagues_summary():
		var is_my_league := (str(lg.get("league", "")) == str(my_tier.get("league", "")))
		var row_p := _make_styled_panel(is_my_league)
		var rl := Label.new()
		var suffix := "   ◀ SUA LIGA ATUAL" if is_my_league else ""
		rl.text = "%s  %-10s   %s%s" % [
			str(lg.get("icon", "🏆")),
			str(lg.get("league", "")).to_upper(),
			str(lg.get("range_text", "")),
			suffix,
		]
		rl.add_theme_font_size_override("font_size", 14)
		rl.add_theme_color_override("font_color", lg.get("color", Color.WHITE))
		row_p.add_child(rl)
		lv.add_child(row_p)

	# Direita: Top Leaderboard da Temporada
	var top_card := _make_styled_panel(false)
	top_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(top_card)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	top_card.add_child(tv)

	var tt := Label.new()
	tt.text = "TOP COMPETIDORES — TEMPORADA 1"
	tt.add_theme_font_size_override("font_size", 17)
	tt.add_theme_color_override("font_color", Color(0.0, 0.85, 0.84))
	tv.add_child(tt)

	var leaders := [
		["💎 Diamante I", "VoltMaster", 1980, "42 V"],
		["💠 Platina I", "SparkQueen", 1690, "31 V"],
		["🥇 Ouro II", "GridBomber", 1410, "24 V"],
		["🥈 Prata I", "PyroBot", 1245, "15 V"],
		[
			"%s %s" % [str(my_tier.get("icon", "🥉")), str(my_tier.get("division", "Bronze I"))],
			"%s (Você)" % player_display_name,
			account_store.rating,
			"%d V" % account_store.wins,
		],
	]

	for entry: Array in leaders:
		var is_me := str(entry[1]).contains("(Você)")
		var rp := _make_styled_panel(is_me)
		var ll := Label.new()
		ll.text = "%-15s   %-18s   %4d MMR   (%s)" % [
			str(entry[0]),
			str(entry[1]),
			int(entry[2]),
			str(entry[3]),
		]
		ll.add_theme_font_size_override("font_size", 14)
		rp.add_child(ll)
		tv.add_child(rp)

	var btn_back := _make_button("← Voltar ao Menu Principal", false, 42.0)
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_profile() -> void:
	var box := _create_card("🎖 PERFIL DO JOGADOR — %s" % player_display_name, Vector2(820, 470), true)
	var tier := RankedSystem.get_tier_info(account_store.rating)
	var peak_tier := RankedSystem.get_tier_info(account_store.peak_rating)
	var lbl := Label.new()
	lbl.text = (
		"Status da Conta: %s   ·   E-mail: %s\n"
		+ "Liga Atual: %s %s (%d MMR)   ·   Maior MMR Alcançado: %s %s (%d MMR)\n"
		+ "Partidas Disputadas: %d   ·   Vitórias: %d   ·   Eliminações: %d   ·   Blocos Destruídos: %d\n"
		+ "Campeão Favorito: %s   ·   Plataforma: %s\n\n"
		+ "Conquistas da Conta:\n"
		+ "• 🏆 FIRST_WIN — Vencer uma partida (%s)\n"
		+ "• 💥 CHAIN_MASTER_3 — Reação em cadeia de 3+ bombas\n"
		+ "• ⚡ COLLECTOR_50 — Coletar 50 power-ups"
	) % [
		"Registrada ✔" if account_store.account_kind == "registered" else "Convidado",
		account_store.email if not account_store.email.is_empty() else "Não cadastrado",
		str(tier.get("icon", "🥉")),
		str(tier.get("division", "Bronze I")),
		account_store.rating,
		str(peak_tier.get("icon", "🥉")),
		str(peak_tier.get("division", "Bronze I")),
		account_store.peak_rating,
		account_store.matches_played,
		account_store.wins,
		account_store.kills_total,
		account_store.blocks_total,
		MenuBackdrop.get_character_name(selected_character),
		PlatformInfo.platform_name(),
		"DESBLOQUEADA ✔" if account_store.wins > 0 else "Em progresso",
	]
	lbl.add_theme_font_size_override("font_size", 15)
	box.add_child(lbl)

	var btn_back := _make_button("← Voltar ao Menu Principal", false, 44.0)
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)


func _build_settings() -> void:
	var box := _create_card("🖥 CONFIGURAÇÕES — TELA GRANDE, BOTS E ÁUDIO", Vector2(880, 500), true)

	# 1. Seção Tela Grande / Resolução
	var sec_disp := Label.new()
	sec_disp.text = "MODO DE EXIBIÇÃO E TAMANHO DA TELA (Atalho Global: F11)"
	sec_disp.add_theme_font_size_override("font_size", 16)
	sec_disp.add_theme_color_override("font_color", Color(0.0, 0.85, 0.84))
	box.add_child(sec_disp)

	var disp_row := HBoxContainer.new()
	disp_row.add_theme_constant_override("separation", 12)
	box.add_child(disp_row)

	var disp_modes := [
		["window_720p", "🗔 Janela Padrão (1280×720)"],
		["window_large", "🗖 TELA GRANDE (Janela Maximizada)"],
		["fullscreen", "⛶ TELA CHEIA (Fullscreen — F11)"],
	]
	for dm: Array in disp_modes:
		var mid := str(dm[0])
		var active := (window_mode_state == mid)
		var b := _make_button(("%s  ✓" if active else "%s") % str(dm[1]), active, 46.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: set_display_mode(mid))
		disp_row.add_child(b)

	box.add_child(HSeparator.new())

	# 2. Seção Dificuldade dos Bots
	var sec_bots := Label.new()
	sec_bots.text = "INTELIGÊNCIA ARTIFICIAL DOS BOTS (MODOS CASUAIS)"
	sec_bots.add_theme_font_size_override("font_size", 16)
	sec_bots.add_theme_color_override("font_color", Color(0.0, 0.85, 0.84))
	box.add_child(sec_bots)

	var bots_row := HBoxContainer.new()
	bots_row.add_theme_constant_override("separation", 12)
	box.add_child(bots_row)

	var diffs := [
		["easy", "FÁCIL (Iniciante)"],
		["medium", "MÉDIO (Equilibrado)"],
		["hard", "DIFÍCIL (Estrategista BFS)"],
	]
	for d: Array in diffs:
		var did := str(d[0])
		var active := (bot_difficulty == did)
		var b := _make_button(("%s  ✓" if active else "%s") % str(d[1]), active, 44.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			bot_difficulty = did
			show_screen(Screen.SETTINGS)
		)
		bots_row.add_child(b)

	box.add_child(HSeparator.new())

	# 3. Seção Volume de Áudio
	var sec_audio := Label.new()
	sec_audio.text = "EFEITOS SONOROS PROCEDURAIS (SFX)"
	sec_audio.add_theme_font_size_override("font_size", 16)
	sec_audio.add_theme_color_override("font_color", Color(0.0, 0.85, 0.84))
	box.add_child(sec_audio)

	var audio_row := HBoxContainer.new()
	audio_row.add_theme_constant_override("separation", 12)
	box.add_child(audio_row)

	for vol_item: Array in [[0.0, "🔇 Mudo (0%)"], [0.5, "🔉 Médio (50%)"], [1.0, "🔊 Máximo (100%)"]]:
		var v_val: float = float(vol_item[0])
		var active := absf(audio_volume - v_val) < 0.1
		var b := _make_button(("%s  ✓" if active else "%s") % str(vol_item[1]), active, 42.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			audio_volume = v_val
			show_screen(Screen.SETTINGS)
		)
		audio_row.add_child(b)

	var btn_back := _make_button("← Concluir e Voltar ao Menu Principal", true, 46.0)
	btn_back.pressed.connect(func() -> void: show_screen(Screen.HOME))
	box.add_child(btn_back)
