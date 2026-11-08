class_name PlatformInfo
extends RefCounted
## Detecção de plataforma em um só lugar (PLATFORM_COMPATIBILITY.md §2).
## A build Web nunca deve depender de recursos nativos; o código de jogo pergunta aqui.

const FEATURE_STEAM := "steam" # feature tag customizada só nos presets nativos (D-17)


static func is_web() -> bool:
	return OS.has_feature("web")


## Steamworks só pode ser carregado em builds nativas exportadas com a tag "steam".
static func steam_allowed() -> bool:
	return OS.has_feature(FEATURE_STEAM) and not is_web()


static func platform_name() -> String:
	if is_web():
		return "Web"
	return OS.get_name() # "Windows", "Linux", "macOS"...


static func renderer() -> String:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))


static func summary() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	return "v%s · %s · %s · Godot %s" % [version, platform_name(), renderer(), Engine.get_version_info().string]
