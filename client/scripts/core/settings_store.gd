class_name SettingsStore
extends RefCounted
## Persistência de preferências e remapeamento de controles em `user://input.cfg` (PLATFORM_COMPATIBILITY.md §5).
## Usa physical_keycode para compatibilidade com teclados AZERTY/Dvorak/QWERTY em todas as plataformas.

const DEFAULT_PATH: String = "user://input.cfg"
const SECTION_PREFS: String = "preferences"
const SECTION_INPUT: String = "input"

const REMAP_ACTIONS: Array[String] = [
	"move_up",
	"move_down",
	"move_left",
	"move_right",
	"place_bomb",
	"pause",
]

const ACTION_ALIASES: Dictionary = {
	"bomb": "place_bomb",
	"up": "move_up",
	"down": "move_down",
	"left": "move_left",
	"right": "move_right",
}

var config_path: String = DEFAULT_PATH
var bot_difficulty: String = "medium"
var audio_muted: bool = false
var mute: bool:
	get:
		return audio_muted
	set(val):
		audio_muted = val

var master_volume: float = 0.85
var server_url: String = "ws://localhost:8080/ws"
var fullscreen: bool = false

var volumes: Dictionary = {
	"master": 0.85,
	"sfx": 1.0,
	"music": 1.0,
}

var key_bindings: Dictionary = {
	"move_up": int(KEY_W),
	"move_down": int(KEY_S),
	"move_left": int(KEY_A),
	"move_right": int(KEY_D),
	"place_bomb": int(KEY_SPACE),
	"bomb": int(KEY_SPACE),
	"pause": int(KEY_P),
}


func _init(path: String = DEFAULT_PATH) -> void:
	config_path = path


func set_volume(channel: String, vol: float) -> void:
	var clamped := clampf(vol, 0.0, 1.0)
	volumes[channel] = clamped
	if channel == "master":
		master_volume = clamped


func get_volume(channel: String) -> float:
	return float(volumes.get(channel, 1.0))


func rebind_key(action: String, physical_keycode: int, apply_to_input_map: bool = true) -> bool:
	var canonical: String = ACTION_ALIASES.get(action, action)
	key_bindings[action] = physical_keycode
	key_bindings[canonical] = physical_keycode
	return set_key_binding(canonical, physical_keycode, apply_to_input_map)


func set_key_binding(action: String, physical_keycode: int, apply_to_input_map: bool = true) -> bool:
	var canonical: String = ACTION_ALIASES.get(action, action)
	if not REMAP_ACTIONS.has(canonical) or physical_keycode <= 0:
		return false
	key_bindings[canonical] = physical_keycode
	key_bindings[action] = physical_keycode
	if apply_to_input_map:
		_apply_action_to_input_map(canonical, physical_keycode)
	return true


func get_key_binding(action: String) -> int:
	var canonical: String = ACTION_ALIASES.get(action, action)
	if key_bindings.has(canonical):
		return int(key_bindings[canonical])
	return int(key_bindings.get(action, 0))


func save_settings(path: String = "") -> int:
	var target_path := path if not path.is_empty() else config_path
	return save_to_disk(target_path)


func load_settings(path: String = "", apply_to_input_map: bool = true) -> int:
	var target_path := path if not path.is_empty() else config_path
	return load_from_disk(target_path, apply_to_input_map)


func save_to_disk(path: String = DEFAULT_PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_PREFS, "bot_difficulty", bot_difficulty)
	cfg.set_value(SECTION_PREFS, "audio_muted", audio_muted)
	cfg.set_value(SECTION_PREFS, "master_volume", clampf(master_volume, 0.0, 1.0))
	cfg.set_value(SECTION_PREFS, "sfx_volume", get_volume("sfx"))
	cfg.set_value(SECTION_PREFS, "music_volume", get_volume("music"))
	cfg.set_value(SECTION_PREFS, "fullscreen", fullscreen)
	cfg.set_value(SECTION_PREFS, "server_url", server_url)

	for action in REMAP_ACTIONS:
		cfg.set_value(SECTION_INPUT, action, int(key_bindings.get(action, 0)))

	for alias in ACTION_ALIASES:
		cfg.set_value(SECTION_INPUT, alias, int(key_bindings.get(alias, 0)))

	return cfg.save(path)


func load_from_disk(path: String = DEFAULT_PATH, apply_to_input_map: bool = true) -> int:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err

	var diff := str(cfg.get_value(SECTION_PREFS, "bot_difficulty", bot_difficulty))
	if diff in ["easy", "medium", "hard"]:
		bot_difficulty = diff
	audio_muted = bool(cfg.get_value(SECTION_PREFS, "audio_muted", audio_muted))
	master_volume = clampf(float(cfg.get_value(SECTION_PREFS, "master_volume", master_volume)), 0.0, 1.0)
	volumes["master"] = master_volume
	volumes["sfx"] = clampf(float(cfg.get_value(SECTION_PREFS, "sfx_volume", volumes["sfx"])), 0.0, 1.0)
	volumes["music"] = clampf(float(cfg.get_value(SECTION_PREFS, "music_volume", volumes["music"])), 0.0, 1.0)
	fullscreen = bool(cfg.get_value(SECTION_PREFS, "fullscreen", fullscreen))

	var loaded_url := str(cfg.get_value(SECTION_PREFS, "server_url", server_url)).strip_edges()
	if not loaded_url.is_empty():
		server_url = loaded_url

	for action in REMAP_ACTIONS:
		var code := int(cfg.get_value(SECTION_INPUT, action, int(key_bindings.get(action, 0))))
		if code > 0:
			set_key_binding(action, code, apply_to_input_map)

	for alias in ACTION_ALIASES:
		var code := int(cfg.get_value(SECTION_INPUT, alias, int(key_bindings.get(alias, 0))))
		if code > 0:
			rebind_key(alias, code, apply_to_input_map)

	return OK


static func _apply_action_to_input_map(action: String, physical_keycode: int) -> void:
	var sn := StringName(action)
	if not InputMap.has_action(sn):
		return
	var preserved: Array[InputEvent] = []
	for ev in InputMap.action_get_events(sn):
		if not (ev is InputEventKey):
			preserved.append(ev)
	InputMap.action_erase_events(sn)
	var key_ev := InputEventKey.new()
	key_ev.physical_keycode = physical_keycode as Key
	InputMap.action_add_event(sn, key_ev)
	for ev in preserved:
		InputMap.action_add_event(sn, ev)
