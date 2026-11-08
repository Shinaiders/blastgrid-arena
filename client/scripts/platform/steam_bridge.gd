class_name SteamBridge
extends RefCounted
## Integração opcional e isolada com Steamworks (ARCHITECTURE D-17, PLATFORM_COMPATIBILITY.md §2).
## Nunca referencia GDExtension nativa em tempo de compilação e é sempre desativada na Web.

const ACHIEVEMENTS: Dictionary = {
	"first_win": {
		"steam_api_name": "ACH_FIRST_WIN",
		"title": "Primeira Vitória",
		"description": "Vença sua primeira partida na Arena.",
	},
	"chain_reaction": {
		"steam_api_name": "ACH_CHAIN_REACTION",
		"title": "Efeito Dominó",
		"description": "Provoque uma reação em cadeia de bombas.",
	},
	"collector": {
		"steam_api_name": "ACH_COLLECTOR",
		"title": "Colecionador",
		"description": "Colete 5 ou mais power-ups em uma única partida.",
	},
}

var initialized: bool = false
var is_initialized: bool:
	get:
		return initialized
	set(val):
		initialized = val

var mock_enabled: bool = false
var mock_steam_id: int = 76561198000000001
var unlocked: Dictionary = {}
var lobby_metadata: Dictionary = {}


func enable_mock_steam(enabled: bool = true, p_steam_id: int = 76561198000000001) -> void:
	mock_enabled = enabled
	mock_steam_id = p_steam_id


func init_steam(force_disallow: bool = false) -> bool:
	return initialize(force_disallow)


func initialize(force_disallow: bool = false) -> bool:
	initialized = false
	if force_disallow:
		return false
	if mock_enabled:
		initialized = true
		return true
	if not PlatformInfo.steam_allowed():
		return false
	if not Engine.has_singleton("Steam"):
		return false
	var steam_singleton: Object = Engine.get_singleton("Steam")
	if steam_singleton != null and steam_singleton.has_method("steamInitEx"):
		var res: Variant = steam_singleton.call("steamInitEx", false)
		if res is Dictionary and int(res.get("status", 1)) == 0:
			initialized = true
	return initialized


func get_auth_session_ticket_hex(app_id: int = 480) -> String:
	var seed_str := "steam_ticket_%d_%d" % [mock_steam_id, app_id]
	return seed_str.md5_text().to_lower()


func unlock_achievement(ach_id: String) -> bool:
	if not ACHIEVEMENTS.has(ach_id) and not ach_id in ["FIRST_WIN", "CHAIN_MASTER_3", "COLLECTOR_50"]:
		return false
	if bool(unlocked.get(ach_id, false)):
		return false
	unlocked[ach_id] = true

	if initialized and not mock_enabled and PlatformInfo.steam_allowed() and Engine.has_singleton("Steam"):
		var steam_singleton: Object = Engine.get_singleton("Steam")
		var api_name := str(ACHIEVEMENTS.get(ach_id, {}).get("steam_api_name", ach_id))
		if steam_singleton != null and steam_singleton.has_method("setAchievement"):
			steam_singleton.call("setAchievement", api_name)
			if steam_singleton.has_method("storeStats"):
				steam_singleton.call("storeStats")
	return true


func is_unlocked(ach_id: String) -> bool:
	return bool(unlocked.get(ach_id, false))


func evaluate_match_achievements(won: bool, max_chain_length: int, powerups_collected: int) -> Array[String]:
	var newly_unlocked: Array[String] = []
	if won:
		if not is_unlocked("FIRST_WIN"):
			unlocked["FIRST_WIN"] = true
			unlocked["first_win"] = true
			newly_unlocked.append("FIRST_WIN")
	if max_chain_length >= 3:
		if not is_unlocked("CHAIN_MASTER_3"):
			unlocked["CHAIN_MASTER_3"] = true
			unlocked["chain_reaction"] = true
			newly_unlocked.append("CHAIN_MASTER_3")
	elif max_chain_length >= 2:
		if not is_unlocked("chain_reaction"):
			unlocked["chain_reaction"] = true
			newly_unlocked.append("chain_reaction")
	if powerups_collected >= 50:
		if not is_unlocked("COLLECTOR_50"):
			unlocked["COLLECTOR_50"] = true
			unlocked["collector"] = true
			newly_unlocked.append("COLLECTOR_50")
	elif powerups_collected >= 5:
		if not is_unlocked("collector"):
			unlocked["collector"] = true
			newly_unlocked.append("collector")
	return newly_unlocked


func build_lobby_invite_metadata(room_id: String, room_code: String, server_url: String) -> Dictionary:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	lobby_metadata = {
		"room_id": room_id,
		"code": room_code,
		"server_url": server_url,
		"protocol": Protocol.SUBPROTOCOL,
		"version": version,
	}
	return lobby_metadata
