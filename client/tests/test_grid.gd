extends TestCase
## Testes do Dia 06: PRNG xorshift32, Grid 15x13, spawns livres, densidade 55–70% e cenários JSON.


func run() -> void:
	_test_prng_determinism()
	_test_grid_invariants_4p()
	_test_grid_invariants_8p()
	_test_ascii_roundtrip()
	_test_conformance_scenarios()


func _test_prng_determinism() -> void:
	var r1 := PRNG.new(1)
	var r0 := PRNG.new(0) # seed 0 deve virar 1
	eq(r1.next_u32(), 270369, "xorshift32(1) primeiro valor")
	eq(r0.next_u32(), 270369, "xorshift32(0) trata seed zero como 1")
	eq(r1.next_u32(), 67634689, "xorshift32(1) segundo valor")
	eq(r1.next_u32(), 2647435461, "xorshift32(1) terceiro valor")
	eq(r1.next_u32(), 307599695, "xorshift32(1) quarto valor")
	eq(r1.next_u32(), 2398689233, "xorshift32(1) quinto valor")


func _test_grid_invariants_4p() -> void:
	# Em 15x13 = 195 células:
	# Borda = 2*15 + 2*(13-2) = 52 paredes
	# Pilares internos (x par, y par, 2..12 x 2..10) = 6 * 5 = 30 paredes
	# Total WALL = 82. Livres = 113.
	# Zona segura 4 spawns = 4 * 3 = 12 células.
	# Candidatas a BLOCK = 113 - 12 = 101 células.
	for seed_val in [1, 42, 1337, 999999, 3141592653]:
		var g := Grid.generate(seed_val, 4)
		var g2 := Grid.generate(seed_val, 4)
		eq(g.to_compact_string(), g2.to_compact_string(), "mesmo seed deve gerar mesmo grid")
		eq(g.count_tiles(Grid.Tile.WALL), 82, "total de paredes fixas 15x13")

		# Verifica bordas e pilares
		for cy in range(g.rows):
			for cx in range(g.cols):
				if cx == 0 or cx == g.cols - 1 or cy == 0 or cy == g.rows - 1:
					eq(g.get_tile(cx, cy), Grid.Tile.WALL, "borda (%d,%d) deve ser WALL" % [cx, cy])
				elif cx % 2 == 0 and cy % 2 == 0:
					eq(g.get_tile(cx, cy), Grid.Tile.WALL, "pilar (%d,%d) deve ser WALL" % [cx, cy])

		# Verifica 4 cantos em L sempre livres
		for slot in range(4):
			for pt: Vector2i in Grid.SPAWN_SAFE_ZONES[slot]:
				eq(g.get_tile(pt.x, pt.y), Grid.Tile.EMPTY, "zona segura slot %d (%d,%d) livre" % [slot, pt.x, pt.y])

		var blocks := g.count_tiles(Grid.Tile.BLOCK)
		# 55% de 101 = 55; 70% de 101 = 70
		check(blocks >= 55 and blocks <= 70, "blocos (%d) dentro da densidade 55–70%% de 101" % blocks)


func _test_grid_invariants_8p() -> void:
	# Para 8 spawns: 8 * 3 = 24 células seguras; candidatas = 113 - 24 = 89.
	var g := Grid.generate(3141592653, 8)
	for slot in range(8):
		for pt: Vector2i in Grid.SPAWN_SAFE_ZONES[slot]:
			eq(g.get_tile(pt.x, pt.y), Grid.Tile.EMPTY, "zona segura 8p slot %d (%d,%d) livre" % [slot, pt.x, pt.y])
	var blocks := g.count_tiles(Grid.Tile.BLOCK)
	# int(89 * 55 / 100) = 48 .. int(89 * 70 / 100) = 62
	check(blocks >= 48 and blocks <= 62, "blocos 8p (%d) dentro da densidade 55–70%% de 89" % blocks)


func _test_ascii_roundtrip() -> void:
	var g := Grid.generate(42, 4)
	var compact := g.to_compact_string()
	eq(compact.length(), 195, "string compacta tem 195 chars")
	var parsed := Grid.from_ascii(compact)
	eq(parsed.to_compact_string(), compact, "from_ascii roundtrip preserva o grid")


func _test_conformance_scenarios() -> void:
	var file_path := ProjectSettings.globalize_path("res://../tests/scenarios/01_grid_generation.json")
	check(FileAccess.file_exists(file_path), "cenário 01_grid_generation.json deve existir")
	if not FileAccess.file_exists(file_path):
		return
	var raw := FileAccess.get_file_as_string(file_path)
	var data: Variant = JSON.parse_string(raw)
	check(data is Dictionary, "JSON de cenário válido")
	if not (data is Dictionary):
		return

	var prng_cases: Array = data.get("prng_cases", [])
	for c: Dictionary in prng_cases:
		var rng := PRNG.new(int(c["seed"]))
		var expected_seq: Array = c["sequence"]
		for i in range(expected_seq.size()):
			eq(rng.next_u32(), int(expected_seq[i]), "PRNG seed=%d passo %d" % [int(c["seed"]), i])

	var grid_cases: Array = data.get("grid_cases", [])
	for c: Dictionary in grid_cases:
		var g := Grid.generate(int(c["seed"]), int(c["spawn_count"]))
		eq(g.to_compact_string(), str(c["expected_grid"]), "Grid conformance seed=%d spawns=%d" % [int(c["seed"]), int(c["spawn_count"])])
		eq(g.count_tiles(Grid.Tile.BLOCK), int(c["expected_blocks"]), "Grid blocks seed=%d" % int(c["seed"]))

