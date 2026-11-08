extends TestCase
## Testes da Fase 1 / Dia 05: configurações de projeto, input map, presets de exportação e cena inicial.

const MainScript = preload("res://scripts/core/main.gd")
const MainScene = preload("res://scenes/main/main.tscn")


func run() -> void:
	_test_project_settings()
	_test_input_map()
	_test_platform_info()
	_test_export_presets()
	_test_main_scene()


func _test_project_settings() -> void:
	eq(PlatformInfo.renderer(), "gl_compatibility", "renderer principal deve ser gl_compatibility (D-01)")
	eq(
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "")),
		"gl_compatibility",
		"renderer mobile deve ser gl_compatibility"
	)
	eq(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)), 1280, "largura base 1280")
	eq(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)), 720, "altura base 720")
	eq(str(ProjectSettings.get_setting("display/window/stretch/mode", "")), "canvas_items", "stretch mode canvas_items")
	eq(str(ProjectSettings.get_setting("display/window/stretch/aspect", "")), "expand", "stretch aspect expand")
	check(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)), "pixel snap transforms ativo")


func _test_input_map() -> void:
	var required: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right", &"place_bomb", &"pause"]
	for action in required:
		check(InputMap.has_action(action), "InputMap deve conter ação %s" % action)
		var events := InputMap.action_get_events(action)
		var has_key := false
		var has_joy := false
		for ev in events:
			if ev is InputEventKey:
				has_key = true
			elif ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_joy = true
		check(has_key, "ação %s deve ter tecla mapeada" % action)
		check(has_joy, "ação %s deve ter gamepad mapeado" % action)


func _test_platform_info() -> void:
	check(not PlatformInfo.is_web(), "execução headless local não é Web")
	check(not PlatformInfo.steam_allowed(), "sem feature tag steam, steam_allowed() deve ser false")
	check(PlatformInfo.summary().contains("gl_compatibility"), "summary inclui renderer")


func _test_export_presets() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://export_presets.cfg")
	eq(err, OK, "export_presets.cfg deve carregar sem erro")

	var by_name := {}
	for i in range(4):
		var section := "preset.%d" % i
		var opts := "preset.%d.options" % i
		check(cfg.has_section(section), "seção %s existe" % section)
		var preset_name := str(cfg.get_value(section, "name", ""))
		by_name[preset_name] = {"section": section, "opts": opts}

	check(by_name.has("Web"), "preset Web existe")
	check(by_name.has("Windows Desktop"), "preset Windows Desktop existe")
	check(by_name.has("Linux"), "preset Linux existe")
	check(by_name.has("macOS"), "preset macOS existe")

	if by_name.has("Web"):
		var web: Dictionary = by_name["Web"]
		eq(bool(cfg.get_value(web["opts"], "variant/thread_support", true)), false, "Web deve ser single-thread (D-02)")
		check(not str(cfg.get_value(web["section"], "custom_features", "")).contains("steam"), "Web não pode ter feature steam (D-17)")

	if by_name.has("macOS"):
		var mac: Dictionary = by_name["macOS"]
		eq(str(cfg.get_value(mac["opts"], "binary_format/architecture", "")), "universal", "macOS deve ser Universal 2 (D-18)")
		eq(int(cfg.get_value(mac["opts"], "codesign/codesign", -1)), 0, "macOS sem assinatura paga (D-18)")
		eq(int(cfg.get_value(mac["opts"], "notarization/notarization", -1)), 0, "macOS sem notarização paga (D-18)")


func _test_main_scene() -> void:
	var idle_txt := MainScript.describe_input([], false)
	check(idle_txt.contains("WASD"), "describe_input ocioso mostra instruções")
	var move_txt := MainScript.describe_input([&"move_up", &"place_bomb"], false)
	check(move_txt.contains("move_up") and move_txt.contains("place_bomb"), "describe_input lista ações ativas")
	var pause_txt := MainScript.describe_input([&"move_up"], true)
	check(pause_txt.begins_with("PAUSADO"), "describe_input prioriza estado pausado")

	var node: Control = MainScene.instantiate()
	check(node != null, "main.tscn instancia com sucesso")
	node.free()

