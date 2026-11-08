extends TestCase
## Testes dos Dias 13 e 14: HUD, controlador de partida (Practice e FFA com 3 bots) e navegação de telas.

const MainScene = preload("res://scenes/main/main.tscn")
const ArenaScene = preload("res://scenes/arena/arena.tscn")


func run() -> void:
	_test_hud_formatter()
	_test_arena_match_controller_flow()
	_test_all_menus_and_screens()


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

