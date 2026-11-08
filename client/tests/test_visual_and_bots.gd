extends TestCase
## Testes dos Dias 11 e 12: Renderizador visual original (ArenaRenderer) e IA de Bots (BotBrain).


func run() -> void:
	_test_arena_renderer_danger_and_visuals()
	_test_bot_escapes_bomb()
	_test_bot_never_traps_itself()
	_test_bot_collects_nearby_powerup()
	_test_three_bots_play_simulation()


func _test_arena_renderer_danger_and_visuals() -> void:
	var sim := WorldSim.new(42, ["p0", "p1", "p2", "p3"])
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.bombs.append(BombState.new(1, "p0", 1, 1, 25, 2))

	var danger := ArenaRenderer.compute_danger_cells(sim)
	check(danger.has(1 * 15 + 1), "célula da bomba (1,1) marcada no mapa de perigo")
	check(danger.has(1 * 15 + 2), "célula (2,1) no alcance da bomba marcada no mapa de perigo")

	var renderer := ArenaRenderer.new()
	renderer.bind_sim(sim)
	check(renderer.player_anim.has("p0"), "player_anim inicializado para p0")
	renderer.snapshot_positions_before_tick()
	var evs := sim.step_tick()
	renderer.on_tick_events(evs)
	renderer.step_visuals(0.05, 0.5)
	eq(ArenaRenderer.PLAYER_COLORS.size(), 8, "8 cores distintas para até 8 jogadores")

	# Testa screen shake e partículas sob explosão
	renderer.on_tick_events([{"k": "explosion", "cells": [[1, 1]]}])
	check(renderer.shake_trauma >= 0.5, "screen shake trauma ativado na explosão")
	check(renderer.particles.size() > 0, "partículas geradas na explosão")
	renderer.step_visuals(0.05, 0.5)
	check(renderer.player_anim["p0"].has("walk_phase"), "walk_phase rastreado no jogador")
	check(renderer.player_anim["p0"].has("move_blend"), "move_blend rastreado no jogador")
	check(renderer.player_anim["p0"].has("ant_offset"), "ant_offset com mola rastreado")
	renderer.free()


func _test_bot_escapes_bomb() -> void:
	var sim := WorldSim.new(1, ["bot0", "p1"])
	var bot_p := sim.get_player("bot0")
	# Limpa o canto L: (1,1), (2,1), (1,2)
	sim.grid.set_tile(1, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(1, 2, Grid.Tile.EMPTY)
	sim.grid.set_tile(2, 3, Grid.Tile.EMPTY)
	sim.grid.set_tile(1, 3, Grid.Tile.BLOCK)
	sim.grid.set_tile(3, 1, Grid.Tile.BLOCK)

	# Planta uma bomba em (1,1) e deixa o bot fugir pela esquina L: (1,1) -> (2,1) ou (1,2) -> ?
	# Espera: em (1,1), (2,2) é pilar, então para fugir de uma bomba em (2,1), (1,1)->(1,2) é seguro!
	sim.bombs.append(BombState.new(1, "p1", 2, 1, 45, 2))
	var brain := BotBrain.new("bot0", "hard", 1)

	for _t in range(46):
		var cmd := brain.decide(sim)
		sim.set_input("bot0", str(cmd["dir"]), bool(cmd["bomb"]))
		sim.step_tick()

	check(bot_p.alive, "bot fugiu da explosão em (2,1) deslocando-se para (1,2)")
	eq(bot_p.cell(), Vector2i(1, 2), "bot abrigado em (1,2) fora da linha de tiro de (2,1)")


func _test_bot_never_traps_itself() -> void:
	var sim := WorldSim.new(1, ["bot0", "p1"])
	# Canto (1,1) cercado em (3,1) e (1,3) por blocos: como (2,2) é pilar, uma bomba em (1,1) atinge (2,1) e (1,2), sem rota de fuga!
	sim.grid.set_tile(1, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(1, 2, Grid.Tile.EMPTY)
	sim.grid.set_tile(3, 1, Grid.Tile.BLOCK)
	sim.grid.set_tile(1, 3, Grid.Tile.BLOCK)

	var brain := BotBrain.new("bot0", "hard", 1)
	var cmd := brain.decide(sim)
	eq(bool(cmd["bomb"]), false, "bot não planta bomba em (1,1) quando (2,1) e (1,2) não têm saída fora da cruz")


func _test_bot_collects_nearby_powerup() -> void:
	var sim := WorldSim.new(1, ["bot0", "p1"])
	var bot_p := sim.get_player("bot0")
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.place_powerup(2, 1, PowerUpDef.KIND_SPEED_UP)

	var brain := BotBrain.new("bot0", "hard", 1)
	for _t in range(6):
		var cmd := brain.decide(sim)
		sim.set_input("bot0", str(cmd["dir"]), false)
		sim.step_tick()
	eq(bot_p.powerups_collected, 1, "bot caminhou até (2,1) e coletou o power-up")


func _test_three_bots_play_simulation() -> void:
	var sim := WorldSim.new(77, ["p0", "bot1", "bot2", "bot3"], true)
	var brains: Array[BotBrain] = [
		BotBrain.new("bot1", "easy", 101),
		BotBrain.new("bot2", "medium", 202),
		BotBrain.new("bot3", "hard", 303),
	]
	for _t in range(120):
		for b in brains:
			var cmd := b.decide(sim)
			sim.set_input(b.player_id, str(cmd["dir"]), bool(cmd["bomb"]))
		sim.step_tick()
	check(sim.tick == 120, "simulação com 3 bots rodou 120 ticks sem erros")

