class_name Protocol
extends RefCounted
## Codec do protocolo de rede v1 no cliente GDScript (NETWORK_PROTOCOL.md §2, §6, §9).

const VERSION: int = 1
const SUBPROTOCOL: String = "blastgrid.v1"
const MAX_CLIENT_FRAME_BYTES: int = 4096


static func encode(msg_type: String, seq: int, data: Dictionary = {}, ack: int = 0) -> String:
	var env := {
		"v": VERSION,
		"t": msg_type,
		"type": msg_type,
		"seq": seq,
		"data": data,
	}
	if ack > 0:
		env["ack"] = ack
	return JSON.stringify(env)


static func decode(raw: String) -> Dictionary:
	if raw.is_empty() or raw.to_utf8_buffer().size() > 65536 or not raw.strip_edges().begins_with("{"):
		return {"ok": false, "code": "bad_message"}
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {"ok": false, "code": "bad_message"}
	var d: Dictionary = parsed
	if not d.has("v") or (not (d["v"] is int) and not (d["v"] is float)):
		return {"ok": false, "code": "bad_message"}
	if int(d["v"]) != VERSION:
		return {"ok": false, "code": "unsupported_version"}
	var t := str(d.get("t", d.get("type", "")))
	if t.is_empty() or t.length() > 32:
		return {"ok": false, "code": "bad_message"}
	var seq := int(d.get("seq", 0))
	var ack := int(d.get("ack", 0))
	if seq < 1 or ack < 0:
		return {"ok": false, "code": "bad_message"}
	if not (d.get("data", null) is Dictionary):
		return {"ok": false, "code": "bad_message"}
	return {
		"ok": true,
		"v": VERSION,
		"t": t,
		"type": t,
		"seq": seq,
		"ack": ack,
		"data": d["data"],
	}
