extends SceneTree
## Runner headless de testes do cliente Godot:
##   godot --headless --path client -s res://tests/run_tests.gd

const SUITES: Array[String] = [
	"res://tests/test_foundation.gd",
	"res://tests/test_grid.gd",
	"res://tests/test_movement.gd",
	"res://tests/test_bombs_explosions.gd",
	"res://tests/test_powerups.gd",
	"res://tests/test_visual_and_bots.gd",
	"res://tests/test_hud_and_menus.gd",
	"res://tests/test_networking.gd",
	"res://tests/test_phases_5_6.gd",
]


func _init() -> void:
	var total_assertions := 0
	var total_failures := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			printerr("FALHA ao carregar suíte: %s" % path)
			quit(1)
			return
		var suite: TestCase = script.new()
		suite.run()
		total_assertions += suite.assertions
		if suite.failures.is_empty():
			print("OK   %s (%d asserções)" % [path, suite.assertions])
		else:
			print("FAIL %s (%d falhas de %d asserções)" % [path, suite.failures.size(), suite.assertions])
			for f in suite.failures:
				printerr("  - %s" % f)
			total_failures += suite.failures.size()

	print("Total: %d suítes, %d asserções, %d falhas" % [SUITES.size(), total_assertions, total_failures])
	quit(1 if total_failures > 0 else 0)
