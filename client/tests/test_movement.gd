extends TestCase
## Testes do Dia 07: movimentação em 4 direções, colisões precisas e corner sliding (≤ 400 mt).


func run() -> void:
	_test_basic_four_directions()
	_test_wall_and_block_collisions()
	_test_corner_sliding_all_axes()
	_test_conformance_scenarios()


func _test_basic_four_directions() -> void:
	var g := Grid.new(15, 13) # tudo EMPTY exceto o que marcarmos
	for x in range(15):
		g.set_tile(x, 0, Grid.Tile.WALL)
		g.set_tile(x, 12, Grid.Tile.WALL)
	for y in range(13):
		g.set_tile(0, y, Grid.Tile.WALL)
		g.set_tile(14, y, Grid.Tile.WALL)

	var p := PlayerState.new("p1", 0, Vector2i(1, 1))
	eq(p.x, 1500, "spawn x")
	eq(p.y, 1500, "spawn y")

	p.dir = "right"
	for _i in range(5):
		MovementRules.step_player(p, g)
	eq(p.x, 2500, "5 ticks a 200 mt/tick anda 1 tile para a direita")
	eq(p.y, 1500, "y inalterado")

	p.dir = "down"
	for _i in range(5):
		MovementRules.step_player(p, g)
	eq(p.x, 2500, "x inalterado")
	eq(p.y, 2500, "5 ticks anda 1 tile para baixo")

	p.dir = "left"
	for _i in range(5):
		MovementRules.step_player(p, g)
	eq(p.x, 1500, "5 ticks anda 1 tile para a esquerda")

	p.dir = "up"
	for _i in range(5):
		MovementRules.step_player(p, g)
	eq(p.y, 1500, "5 ticks anda 1 tile para cima")


func _test_wall_and_block_collisions() -> void:
	var g := Grid.generate(1, 4)
	g.set_tile(2, 1, Grid.Tile.BLOCK)
	var p := PlayerState.new("p1", 0, Vector2i(1, 1))

	# Contra parede superior (1,0)
	p.dir = "up"
	MovementRules.step_player(p, g)
	eq(p.y, 1500, "bloqueado pela parede superior")

	# Contra bloco em (2,1)
	p.dir = "right"
	for _i in range(3):
		MovementRules.step_player(p, g)
	eq(p.x, 1500, "bloqueado pelo bloco em (2,1)")

	# Destrói bloco em (2,1) -> passa a andar
	g.set_tile(2, 1, Grid.Tile.EMPTY)
	MovementRules.step_player(p, g)
	eq(p.x, 1700, "avança após bloco ser removido")


func _test_corner_sliding_all_axes() -> void:
	var g := Grid.generate(1, 4)
	g.set_tile(1, 1, Grid.Tile.EMPTY)
	g.set_tile(2, 1, Grid.Tile.EMPTY)
	g.set_tile(3, 1, Grid.Tile.EMPTY)
	g.set_tile(3, 2, Grid.Tile.EMPTY)
	g.set_tile(3, 3, Grid.Tile.EMPTY)

	# Deslize vertical -> horizontal (dentro de 400 mt)
	var p := PlayerState.new("p1", 0, Vector2i(1, 1))
	p.x = 2650 # em (2,1), 350 mt à esquerda do centro de (3,1) = 3500 -> mas (2,2) é pilar!
	# Distância até a borda direita de (2,1) (x=3000) é 3000 - 2650 = 350 <= 400!
	p.y = 1500
	p.dir = "down"
	for _i in range(6):
		MovementRules.step_player(p, g)
	eq(p.x, 3500, "deslizou para o corredor x=3500 ao redor do pilar (2,2)")
	eq(p.y, 1850, "entrou no corredor vertical (3,2)")


func _test_conformance_scenarios() -> void:
	var file_path := ProjectSettings.globalize_path("res://../tests/scenarios/02_movement.json")
	check(FileAccess.file_exists(file_path), "cenário 02_movement.json deve existir")
	if not FileAccess.file_exists(file_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	check(data is Dictionary, "JSON válido em 02_movement.json")
	if not (data is Dictionary):
		return

	var cases: Array = data.get("cases", [])
	for c: Dictionary in cases:
		var g := Grid.generate(int(c["seed"]), 4)
		for cell: Array in c.get("clear_cells", []):
			g.set_tile(int(cell[0]), int(cell[1]), Grid.Tile.EMPTY)
		for cell: Array in c.get("block_cells", []):
			g.set_tile(int(cell[0]), int(cell[1]), Grid.Tile.BLOCK)

		var p := PlayerState.new("p1", 0, Vector2i(1, 1))
		p.x = int(c["start_x"])
		p.y = int(c["start_y"])
		p.speed = int(c["speed"])

		for st: Dictionary in c.get("steps", []):
			p.dir = str(st["dir"])
			var ticks := int(st["ticks"])
			for _t in range(ticks):
				MovementRules.step_player(p, g)
			eq(p.x, int(st["expect_x"]), "%s expect_x" % str(c["name"]))
			eq(p.y, int(st["expect_y"]), "%s expect_y" % str(c["name"]))

