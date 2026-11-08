extends TestCase
## Testes dos Dias 08 e 09: Bombas (limite, pavio 50 ticks, anti-prisão) e Explosões (cruz, paredes, blocos, cadeia FIFO, eliminação e vitória).


func run() -> void:
	_test_bomb_placement_and_limits()
	_test_anti_trap_pass_through()
	_test_cross_explosion_and_block_destruction()
	_test_chain_reaction_fifo()
	_test_elimination_and_victory()
	_test_conformance_scenarios()


func _test_bomb_placement_and_limits() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	var p0 := sim.get_player("p0")
	eq(p0.max_bombs, 1, "limite base de 1 bomba")

	sim.set_input("p0", "none", true)
	var evs := sim.step_tick()
	eq(sim.bombs.size(), 1, "bomba plantada")
	eq(sim.bombs[0].fuse, 50, "pavio inicial de 50 ticks (2,5s a 20Hz)")
	eq(evs.size(), 1, "evento bomb_placed emitido")
	eq(str(evs[0]["k"]), "bomb_placed", "tipo bomb_placed")

	# Tentar plantar segunda bomba na mesma célula ou em célula vizinha com max_bombs=1
	sim.set_input("p0", "right", true)
	for _i in range(5):
		sim.step_tick()
	eq(p0.cell(), Vector2i(2, 1), "p0 caminhou para (2,1)")
	sim.set_input("p0", "none", true)
	sim.step_tick()
	eq(sim.bombs.size(), 1, "não pode exceder max_bombs=1")


func _test_anti_trap_pass_through() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	var p0 := sim.get_player("p0")
	var p1 := sim.get_player("p1")
	# Coloca p1 também sobrepondo (1,1) no momento da colocação
	p1.x = 1700
	p1.y = 1500
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(3, 1, Grid.Tile.EMPTY)

	sim.set_input("p0", "none", true)
	sim.step_tick()
	var b := sim.bombs[0]
	check(not b.blocks_player("p0"), "dono pode sair da bomba recém-plantada")
	check(not b.blocks_player("p1"), "outro jogador que já sobrepunha a célula também não fica preso")

	# p0 sai completamente para (2,1) (5 ticks a 200 mt/tick -> x=2500)
	sim.set_input("p0", "right", false)
	for _i in range(5):
		sim.step_tick()
	eq(p0.x, 2500, "p0 chegou ao centro de (2,1)")
	check(b.blocks_player("p0"), "após sair completamente de (1,1), a bomba passa a bloquear p0")

	# Tenta voltar para (1,1) -> bloqueado em x=2500
	sim.set_input("p0", "left", false)
	for _i in range(3):
		sim.step_tick()
	eq(p0.x, 2500, "bomba bloqueia retorno para (1,1)")


func _test_cross_explosion_and_block_destruction() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	var p0 := sim.get_player("p0")
	# Limpa (1,1), (2,1), (1,2) e coloca BLOCK em (3,1) e (1,3), com alcance 3
	p0.bomb_range = 3
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(3, 1, Grid.Tile.BLOCK)
	sim.grid.set_tile(4, 1, Grid.Tile.BLOCK) # atrás de (3,1), não deve ser destruído!
	sim.grid.set_tile(1, 2, Grid.Tile.EMPTY)
	sim.grid.set_tile(1, 3, Grid.Tile.BLOCK)

	# Afasta p0 para lugar seguro (1,2) -> (1,3)? Não, tira p0 para (13,11) para não morrer no teste de bloco
	sim.set_input("p0", "none", true)
	sim.step_tick()
	p0.x = 13500
	p0.y = 11500

	var last_events: Array[Dictionary] = []
	for _i in range(50):
		last_events = sim.step_tick()

	eq(sim.bombs.size(), 0, "bomba detonou após 50 ticks")
	eq(sim.grid.get_tile(3, 1), Grid.Tile.EMPTY, "bloco em (3,1) destruído")
	eq(sim.grid.get_tile(4, 1), Grid.Tile.BLOCK, "bloco em (4,1) protegido pelo bloco em (3,1)")
	eq(sim.grid.get_tile(1, 3), Grid.Tile.EMPTY, "bloco em (1,3) destruído")
	eq(p0.blocks_destroyed, 2, "2 blocos contabilizados para p0")
	check(last_events.size() >= 3, "eventos de explosion + 2 block_destroyed")


func _test_chain_reaction_fifo() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	var p0 := sim.get_player("p0")
	var p1 := sim.get_player("p1")
	p0.x = 13500
	p0.y = 11500
	p1.x = 1500
	p1.y = 11500

	for cx in range(1, 7):
		sim.grid.set_tile(cx, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(5, 1, Grid.Tile.BLOCK)

	var b1 := BombState.new(1, "p0", 1, 1, 1, 2)
	var b2 := BombState.new(2, "p1", 3, 1, 30, 2)
	sim.bombs.append(b1)
	sim.bombs.append(b2)

	var evs := sim.step_tick()
	eq(sim.bombs.size(), 0, "ambas as bombas detonaram em cadeia no mesmo tick")
	var exp_ids: Array[int] = []
	for e in evs:
		if str(e["k"]) == "explosion":
			exp_ids.append(int(e["bomb_id"]))
	eq(exp_ids, [1, 2], "ordem FIFO determinística de reação em cadeia")
	eq(sim.grid.get_tile(5, 1), Grid.Tile.EMPTY, "segunda bomba da cadeia destruiu (5,1)")


func _test_elimination_and_victory() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	var p0 := sim.get_player("p0")
	var p1 := sim.get_player("p1")
	sim.grid.set_tile(1, 1, Grid.Tile.EMPTY)
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	p0.x = 13500
	p0.y = 11500
	p1.x = 2500
	p1.y = 1500

	sim.bombs.append(BombState.new(1, "p0", 1, 1, 1, 2))
	sim.step_tick()

	check(not p1.alive, "p1 eliminado pela explosão de p0")
	check(sim.match_over, "partida encerrada com 1 sobrevivente")
	eq(sim.winner_id, "p0", "p0 venceu")
	eq(sim.end_reason, "last_alive", "motivo last_alive")
	eq(p0.kills, 1, "1 kill para p0")
	eq(p0.score, WorldSim.SCORE_KILL + WorldSim.SCORE_WIN, "pontuação kill (100) + vitória (300)")


func _test_conformance_scenarios() -> void:
	var file_path := ProjectSettings.globalize_path("res://../tests/scenarios/03_bombs_and_explosions.json")
	check(FileAccess.file_exists(file_path), "cenário 03_bombs_and_explosions.json existe")
	if not FileAccess.file_exists(file_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	check(data is Dictionary, "JSON válido")
	if not (data is Dictionary):
		return
	for c: Dictionary in data.get("cases", []):
		var sim := WorldSim.new(int(c["seed"]), ["p0", "p1"])
		sim.get_player("p0").x = 13500
		sim.get_player("p0").y = 11500
		sim.get_player("p1").x = 1500
		sim.get_player("p1").y = 11500
		for cell: Array in c.get("clear_cells", []):
			sim.grid.set_tile(int(cell[0]), int(cell[1]), Grid.Tile.EMPTY)
		for cell: Array in c.get("block_cells", []):
			sim.grid.set_tile(int(cell[0]), int(cell[1]), Grid.Tile.BLOCK)

		var ba: Dictionary = c["bomb_a"]
		var bb: Dictionary = c["bomb_b"]
		sim.bombs.append(BombState.new(1, str(ba["owner"]), int(ba["cx"]), int(ba["cy"]), int(ba["fuse"]), int(ba["range"])))
		sim.bombs.append(BombState.new(2, str(bb["owner"]), int(bb["cx"]), int(bb["cy"]), int(bb["fuse"]), int(bb["range"])))

		var order: Array[int] = []
		for _t in range(int(c["ticks_to_run"])):
			var evs := sim.step_tick()
			for e in evs:
				if str(e["k"]) == "explosion":
					order.append(int(e["bomb_id"]))
		eq(order, [1, 2], "ordem de explosão conforme cenário")
		eq(sim.grid.get_tile(5, 1), int(c["expect_cell_5_1_tile"]), "bloco (5,1) destruído conforme cenário")

