class_name AccountStore
extends RefCounted
## Gerenciador de conta do jogador com persistência em ConfigFile (user://account_profile.cfg).
## Gerencia autenticação guest/registered, estatísticas de partidas e rating MMR ranqueado.

const DEFAULT_PATH: String = "user://account_profile.cfg"
const SECTION_ACCOUNT: String = "account"
const SECTION_USERS: String = "users"

var save_path: String = DEFAULT_PATH
var is_logged_in: bool = false
var account_kind: String = "guest" # "guest" | "registered"
var user_id: String = "u_local_1"
var display_name: String = "Convidado"
var email: String = ""
var selected_character: String = "sparky_a"
var rating: int = 1000 # Inicia em 1000 MMR (Bronze I)
var peak_rating: int = 1000
var matches_played: int = 0
var wins: int = 0
var kills_total: int = 0
var blocks_total: int = 0

var _stored_password_hash: String = ""


func _init(custom_path: String = DEFAULT_PATH) -> void:
	save_path = custom_path
	load_account()


func register_account(p_name: String, p_email: String, p_password: String, p_char: String = "sparky_a") -> Dictionary:
	var name_clean := p_name.strip_edges()
	if name_clean.length() < 3 or name_clean.length() > 20:
		return {"ok": false, "error": "O nome deve ter entre 3 e 20 caracteres."}

	var email_clean := p_email.strip_edges().to_lower()
	if not ("@" in email_clean and "." in email_clean) or email_clean.length() < 5:
		return {"ok": false, "error": "E-mail inválido."}

	if p_password.length() < 4:
		return {"ok": false, "error": "A senha deve ter pelo menos 4 caracteres."}

	_stored_password_hash = p_password.sha256_text()
	account_kind = "registered"
	is_logged_in = true
	display_name = name_clean
	email = email_clean
	selected_character = p_char
	if rating <= 0:
		rating = 1000
	peak_rating = maxi(peak_rating, rating)
	user_id = "u_" + email_clean.md5_text().substr(0, 8)

	var cfg := ConfigFile.new()
	var _load_err := cfg.load(save_path)

	# Atualiza perfil ativo
	_write_to_config(cfg)

	# Salva também no registro de usuários para permitir login futuro
	var u_dict: Dictionary = _to_dictionary()
	u_dict["password_hash"] = _stored_password_hash
	cfg.set_value(SECTION_USERS, email_clean, u_dict)
	cfg.set_value(SECTION_USERS, name_clean.to_lower(), u_dict)

	var save_err := cfg.save(save_path)
	if save_err != OK:
		return {"ok": false, "error": "Falha ao gravar arquivo de perfil: %d" % save_err}

	return {"ok": true}


func login_account(p_email_or_name: String, p_password: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(save_path)
	if err != OK:
		return {"ok": false, "error": "Usuário/e-mail ou senha incorretos."}

	var query := p_email_or_name.strip_edges().to_lower()
	var pass_hash := p_password.sha256_text()

	var active_email := str(cfg.get_value(SECTION_ACCOUNT, "email", "")).strip_edges().to_lower()
	var active_name := str(cfg.get_value(SECTION_ACCOUNT, "display_name", "")).strip_edges().to_lower()
	var active_hash := str(cfg.get_value(SECTION_ACCOUNT, "password_hash", ""))

	if (query == active_email or query == active_name) and not active_hash.is_empty() and active_hash == pass_hash:
		load_account()
		is_logged_in = true
		account_kind = "registered"
		_stored_password_hash = active_hash
		save_account()
		return {"ok": true}

	if cfg.has_section(SECTION_USERS):
		if cfg.has_section_key(SECTION_USERS, query):
			var u_data: Dictionary = cfg.get_value(SECTION_USERS, query, {})
			if str(u_data.get("password_hash", "")) == pass_hash:
				_from_dictionary(u_data)
				_stored_password_hash = pass_hash
				is_logged_in = true
				account_kind = "registered"
				save_account()
				return {"ok": true}

		for k in cfg.get_section_keys(SECTION_USERS):
			var u_data: Dictionary = cfg.get_value(SECTION_USERS, k, {})
			var u_email := str(u_data.get("email", "")).strip_edges().to_lower()
			var u_name := str(u_data.get("display_name", "")).strip_edges().to_lower()
			var u_hash := str(u_data.get("password_hash", ""))
			if (query == u_email or query == u_name) and u_hash == pass_hash:
				_from_dictionary(u_data)
				_stored_password_hash = pass_hash
				is_logged_in = true
				account_kind = "registered"
				save_account()
				return {"ok": true}

	return {"ok": false, "error": "Usuário/e-mail ou senha incorretos."}


func login_guest(p_name: String) -> Dictionary:
	account_kind = "guest"
	is_logged_in = true
	var clean := p_name.strip_edges()
	if clean.length() >= 3:
		display_name = clean
	save_account()
	return {"ok": true}


func record_match_result(is_ranked: bool, placement: int, total_players: int, kills: int, blocks: int) -> Dictionary:
	matches_played += 1
	if placement == 1:
		wins += 1
	kills_total += kills
	blocks_total += blocks

	var old_rating: int = rating
	var old_tier: Dictionary = RankedSystem.get_tier_info(old_rating)

	if is_ranked:
		var delta: int = RankedSystem.calculate_mmr_delta(rating, placement, total_players, kills)
		rating = maxi(100, rating + delta)
		peak_rating = maxi(peak_rating, rating)

	save_account()

	var new_tier: Dictionary = RankedSystem.get_tier_info(rating)
	var promoted: bool = str(new_tier["division"]) != str(old_tier["division"]) and rating > old_rating

	return {
		"old_rating": old_rating,
		"new_rating": rating,
		"delta": rating - old_rating,
		"old_tier": old_tier,
		"new_tier": new_tier,
		"promoted": promoted,
	}


func save_account(path: String = "") -> int:
	var target := path if not path.is_empty() else save_path
	var cfg := ConfigFile.new()
	var _err := cfg.load(target)
	_write_to_config(cfg)
	return cfg.save(target)


func load_account(path: String = "") -> int:
	var target := path if not path.is_empty() else save_path
	var cfg := ConfigFile.new()
	var err := cfg.load(target)
	if err != OK:
		return err

	user_id = str(cfg.get_value(SECTION_ACCOUNT, "user_id", user_id))
	account_kind = str(cfg.get_value(SECTION_ACCOUNT, "account_kind", account_kind))
	is_logged_in = bool(cfg.get_value(SECTION_ACCOUNT, "is_logged_in", is_logged_in))
	display_name = str(cfg.get_value(SECTION_ACCOUNT, "display_name", display_name))
	email = str(cfg.get_value(SECTION_ACCOUNT, "email", email))
	selected_character = str(cfg.get_value(SECTION_ACCOUNT, "selected_character", selected_character))
	rating = int(cfg.get_value(SECTION_ACCOUNT, "rating", rating))
	peak_rating = int(cfg.get_value(SECTION_ACCOUNT, "peak_rating", peak_rating))
	matches_played = int(cfg.get_value(SECTION_ACCOUNT, "matches_played", matches_played))
	wins = int(cfg.get_value(SECTION_ACCOUNT, "wins", wins))
	kills_total = int(cfg.get_value(SECTION_ACCOUNT, "kills_total", kills_total))
	blocks_total = int(cfg.get_value(SECTION_ACCOUNT, "blocks_total", blocks_total))
	_stored_password_hash = str(cfg.get_value(SECTION_ACCOUNT, "password_hash", _stored_password_hash))
	return OK


func logout() -> void:
	is_logged_in = false
	save_account()


func _write_to_config(cfg: ConfigFile) -> void:
	cfg.set_value(SECTION_ACCOUNT, "user_id", user_id)
	cfg.set_value(SECTION_ACCOUNT, "account_kind", account_kind)
	cfg.set_value(SECTION_ACCOUNT, "is_logged_in", is_logged_in)
	cfg.set_value(SECTION_ACCOUNT, "display_name", display_name)
	cfg.set_value(SECTION_ACCOUNT, "email", email)
	cfg.set_value(SECTION_ACCOUNT, "selected_character", selected_character)
	cfg.set_value(SECTION_ACCOUNT, "rating", rating)
	cfg.set_value(SECTION_ACCOUNT, "peak_rating", peak_rating)
	cfg.set_value(SECTION_ACCOUNT, "matches_played", matches_played)
	cfg.set_value(SECTION_ACCOUNT, "wins", wins)
	cfg.set_value(SECTION_ACCOUNT, "kills_total", kills_total)
	cfg.set_value(SECTION_ACCOUNT, "blocks_total", blocks_total)
	if not _stored_password_hash.is_empty():
		cfg.set_value(SECTION_ACCOUNT, "password_hash", _stored_password_hash)


func _to_dictionary() -> Dictionary:
	return {
		"user_id": user_id,
		"account_kind": account_kind,
		"display_name": display_name,
		"email": email,
		"selected_character": selected_character,
		"rating": rating,
		"peak_rating": peak_rating,
		"matches_played": matches_played,
		"wins": wins,
		"kills_total": kills_total,
		"blocks_total": blocks_total,
	}


func _from_dictionary(d: Dictionary) -> void:
	user_id = str(d.get("user_id", user_id))
	account_kind = str(d.get("account_kind", account_kind))
	display_name = str(d.get("display_name", display_name))
	email = str(d.get("email", email))
	selected_character = str(d.get("selected_character", selected_character))
	rating = int(d.get("rating", rating))
	peak_rating = int(d.get("peak_rating", peak_rating))
	matches_played = int(d.get("matches_played", matches_played))
	wins = int(d.get("wins", wins))
	kills_total = int(d.get("kills_total", kills_total))
	blocks_total = int(d.get("blocks_total", blocks_total))
