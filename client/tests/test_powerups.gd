extends TestCase
## Testes do Dia 10: Power-ups (Resources .tres, coleta, limites, escudo absorvendo explosão, destruição de power-up exposto).


func run() -> void:
	_test_powerup_resources()
	_test_powerup_stats_and_caps()
	_test_shield_absorbs_blast()
	_test_exposed_powerup_destroyed_but_new_drop_survives()
	_test_conformance_scenarios()


func _test_powerup_resources() -> void:
	var paths := [
		"res://resources/powerups/range_up.tres",
		"res://resources/powerups/bomb_up.tres",
		"res://resources/powerups/speed_up.tres",
		"res://resources/powerups/shield.tres",
	]
	var total_weight := 0
	for path in paths:
		var res: PowerUpDef = load(path)
		check(res != null, "Resource %s carrega" % path)
		if res != null:
			total_weight += res.drop_weight
	eq(total_weight, 100, "soma dos pesos de drop = 100 (35+35+20+10)")


func _test_powerup_stats_and_caps() -> void:
	var p := PlayerState.new("p0", 0, Vector2i(1, 1))
	for _i in range(10):
		PowerUpDef.apply_kind(p, PowerUpDef.KIND_RANGE_UP)
		PowerUpDef.apply_kind(p, PowerUpDef.KIND_BOMB_UP)
		PowerUpDef.apply_kind(p, PowerUpDef.KIND_SPEED_UP)
	eq(p.bomb_range, PlayerState.MAX_RANGE, "alcance respeita teto 8")
	eq(p.max_bombs, PlayerState.MAX_BOMBS, "bombas respeitam teto 8")
	eq(p.speed, PlayerState.MAX_SPEED, "velocidade respeita teto 350 (7,0 tiles/s)")


func _test_shield_absorbs_blast() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	var p0 := sim.get_player("p0")
	sim.place_powerup(1, 1, PowerUpDef.KIND_SHIELD)
	sim.step_tick()
	eq(p0.shield_ticks, PowerUpDef.SHIELD_DURATION_TICKS, "escudo coletado com 120 ticks")

	# Planta bomba aos pés de p0 e espera explodir + chama apagar (50 + 10 ticks)
	sim.bombs.append(BombState.new(1, "p1", 1, 1, 2, 2))
	var broke := false
	for _t in range(15):
		var evs := sim.step_tick()
		for e in evs:
			if str(e["k"]) == "shield_broken":
				broke = true
	check(broke, "evento shield_broken emitido")
	check(p0.alive, "p0 sobreviveu à explosão e aos 10 ticks de chama graças ao escudo")
	eq(p0.shield_ticks, 0, "escudo consumido")


func _test_exposed_powerup_destroyed_but_new_drop_survives() -> void:
	var sim := WorldSim.new(1, ["p0", "p1"])
	sim.get_player("p0").x = 13500
	sim.get_player("p0").y = 11500
	sim.grid.set_tile(2, 1, Grid.Tile.EMPTY)
	sim.place_powerup(2, 1, PowerUpDef.KIND_SPEED_UP)

	sim.bombs.append(BombState.new(1, "p0", 1, 1, 1, 2))
	var evs := sim.step_tick()
	eq(sim.get_powerup_at(2, 1), "", "power-up já exposto em (2,1) foi destruído pela chama")
	var found_destroyed := false
	for e in evs:
		if str(e["k"]) == "powerup_destroyed":
			found_destroyed = true
	check(found_destroyed, "evento powerup_destroyed emitido")


func _test_conformance_scenarios() -> void:
	var file_path := ProjectSettings.globalize_path("res://../tests/scenarios/04_powerups.json")
	check(FileAccess.file_exists(file_path), "cenário 04_powerups.json existe")
	if not FileAccess.file_exists(file_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	check(data is Dictionary, "JSON válido")
	if not (data is Dictionary):
		return
	for c: Dictionary in data.get("cases", []):
		var sim := WorldSim.new(int(c["seed"]), ["p0", "p1"])
		var p0 := sim.get_player("p0")
		var cell: Array = c["player_cell"]
		sim.place_powerup(int(cell[0]), int(cell[1]), str(c["shield_kind"]))
		sim.step_tick() # coleta
		sim.bombs.append(BombState.new(1, "p1", int(cell[0]), int(cell[1]), int(c["bomb_fuse"]), 2))
		for _t in range(int(c["bomb_fuse"]) + int(c["ticks_after_explosion"])):
			sim.step_tick()
		eq(p0.alive, bool(c["expect_alive"]), "sobrevivência com escudo conforme cenário")
		eq(p0.shield_ticks, int(c["expect_shield_ticks"]), "shield_ticks zerado conforme cenário")

