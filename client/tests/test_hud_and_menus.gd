extends TestCase
## Testes dos Dias 13 e 14: HUD, controlador de partida (Practice e FFA com 3 bots) e navegação de telas.

const MainScene = preload("res://scenes/main/main.tscn")
const ArenaScene = preload("res://scenes/arena/arena.tscn")


func run() -> void:
	_test_hud_formatter()
	_test_ranked_and_account_store()
	_test_arena_match_controller_flow()
	_test_all_menus_and_screens()


func _test_ranked_and_account_store() -> void:
	eq(str(RankedSystem.get_tier_info(950)["league"]), "Bronze", "950 MMR = Bronze")
	eq(str(RankedSystem.get_tier_info(1180)["league"]), "Prata", "1180 MMR = Prata")
	eq(str(RankedSystem.get_tier_info(1380)["league"]), "Ouro", "1380 MMR = Ouro")
	eq(str(RankedSystem.get_tier_info(1600)["league"]), "Platina", "1600 MMR = Platina")
	eq(str(RankedSystem.get_tier_info(1850)["league"]), "Diamante", "1850 MMR = Diamante")

	var tmp_acc := "user://test_acc_ranked.cfg"
	if FileAccess.file_exists(tmp_acc):
		DirAccess.remove_absolute(tmp_acc)
	var store := AccountStore.new(tmp_acc)
	var reg := store.register_account("Lucas", "lucas@blastgrid.com", "123456", "sparky_b")
	check(bool(reg.get("ok", false)), "cadastro de conta válido")
	eq(store.account_kind, "registered", "tipo registered")
	eq(store.display_name, "Lucas", "nome persistido")

	var store_reload := AccountStore.new(tmp_acc)
	var log_ok := store_reload.login_account("lucas@blastgrid.com", "123456")
	check(bool(log_ok.get("ok", false)), "login com email e senha funciona")
	var rec := store_reload.record_match_result(true, 1, 8, 3, 12)
	check(int(rec.get("delta", 0)) > 0, "vitória ranqueada de 8 jogadores sobe MMR")
	if FileAccess.file_exists(tmp_acc):
		DirAccess.remove_absolute(tmp_acc)


func _test_hud_formatter() -> void:
	eq(HudFormatter.format_clock(3600, 20), "03:00", "3600 ticks a 20 Hz = 03:00")
	eq(HudFormatter.format_clock(1200, 20), "01:00", "1200 ticks a 20 Hz = 01:00")
	eq(HudFormatter.format_clock(19, 20), "00:01", "arredonda para cima o último segundo")
	eq(HudFormatter.format_clock(0, 20), "00:00", "zero ticks = 00:00")

	var sim := WorldSim.new(10, ["p0", "p1", "p2", "p3"])
	sim.get_player("p1").alive = false
	sim.get_player("p0").score = 250
	sim.get_player("p2").score = 310
	eq(HudFormatter.count_alive(sim.players), 3, "3 jogadores vivos")

	var standings := HudFormatter.build_standings(sim)
	eq(standings.size(), 4, "4 linhas na classificação")
	eq(str(standings[0]["id"]), "p2", "maior pontuação viva em 1º")
	eq(int(standings[0]["place"]), 1, "place=1")
	eq(str(standings[3]["id"]), "p1", "eliminado fica por último")


func _test_arena_match_controller_flow() -> void:
	var arena: ArenaMatchController = ArenaScene.instantiate()
	arena._build_ui()
	arena.start_local_match("practice", 99, "medium")
	check(arena.sfx_synth != null, "SfxSynth instanciado no ArenaMatchController")
	eq(arena._sfx_players.size(), 4, "pool de 4 AudioStreamPlayers criado")
	eq(arena.sim.players.size(), 4, "1 jogador + 3 bots na partida")
	eq(arena.bots.size(), 3, "3 cérebros de bot ativos")
	check(not arena.is_paused, "inicia despausado")

	arena.toggle_pause()
	check(arena.is_paused, "pausa ativada")
	arena.toggle_pause()
	check(not arena.is_paused, "pausa desativada")

	for _t in range(40):
		arena._advance_one_tick()
	eq(arena.sim.tick, 40, "avançou 40 ticks com HUD e bots")

	# Testa modo Ranqueado de 8 jogadores no Mapa Grande (19x15)
	arena.start_local_match("ranked_8p", 777, "medium", 8, true)
	eq(arena.sim.players.size(), 8, "8 jogadores na Mega Arena")
	eq(arena.sim.grid.cols, 19, "mapa grande tem 19 colunas")
	eq(arena.sim.grid.rows, 15, "mapa grande tem 15 linhas")
	eq(arena.bots.size(), 7, "7 bots ativos no modo de 8 jogadores")
	arena.free()


func _test_all_menus_and_screens() -> void:
	var m: Control = MainScene.instantiate()
	m._setup_screen_layer()
	for scr in [
		m.Screen.SPLASH,
		m.Screen.HOME,
		m.Screen.LOGIN,
		m.Screen.CHARACTER_SELECT,
		m.Screen.MODE_SELECT,
		m.Screen.LOBBY,
		m.Screen.MATCHMAKING,
		m.Screen.RANKING,
		m.Screen.PROFILE,
		m.Screen.SETTINGS,
		m.Screen.ARENA,
	]:
		m.show_screen(scr)
		eq(m.current_screen, scr, "transição para tela %d" % scr)
	check(m.arena_instance != null, "tela ARENA instanciou ArenaMatchController")
	m.free()

