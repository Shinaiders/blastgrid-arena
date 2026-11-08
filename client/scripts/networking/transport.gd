class_name Transport
extends RefCounted
## Interface abstrata de transporte de rede no cliente (ARCHITECTURE D-15, NETWORK_PROTOCOL.md §1).
## Permite trocar WebSocket por outro transporte (ex.: WebRTC) ou usar LoopbackTransport em testes headless.

enum State {
	CONNECTING = 0,
	OPEN = 1,
	CLOSING = 2,
	CLOSED = 3,
}


func connect_to_url(_url: String) -> int:
	return ERR_UNAVAILABLE


func send_text(_payload: String) -> int:
	return ERR_UNAVAILABLE


func poll() -> void:
	pass


func receive_text() -> Array[String]:
	return []


func poll_packets() -> Array[String]:
	return receive_text()


func close(_code: int = 1000, _reason: String = "") -> void:
	pass


func disconnect_transport(code: int = 1000, reason: String = "") -> void:
	close(code, reason)


func get_close_code() -> int:
	return 1000


func get_Close_code() -> int:
	return get_close_code()


func get_state() -> int:
	return State.CLOSED


class LoopbackTransport extends Transport:
	## Transporte em memória para testes determinísticos sem abrir socket real.
	var state: int = State.CLOSED
	var last_url: String = ""
	var outbound: Array[String] = []
	var inbound: Array[String] = []
	var close_code: int = 1000
	var close_reason: String = ""
	var peer: LoopbackTransport = null

	static func link(a: LoopbackTransport, b: LoopbackTransport) -> void:
		if a != null:
			a.peer = b
		if b != null:
			b.peer = a

	func link_to(other: LoopbackTransport) -> void:
		link(self, other)

	func connect_to_url(url: String) -> int:
		if url.is_empty():
			return ERR_INVALID_PARAMETER
		last_url = url
		state = State.OPEN
		return OK

	func send_text(payload: String) -> int:
		if state != State.OPEN:
			return ERR_UNAVAILABLE
		if payload.to_utf8_buffer().size() > Protocol.MAX_CLIENT_FRAME_BYTES:
			return ERR_INVALID_DATA
		outbound.append(payload)
		if peer != null and peer.state == State.OPEN:
			peer.inbound.append(payload)
		return OK

	func inject_server_frame(raw: String) -> void:
		inbound.append(raw)

	func receive_text() -> Array[String]:
		var batch: Array[String] = inbound.duplicate()
		inbound.clear()
		return batch

	func poll_packets() -> Array[String]:
		return receive_text()

	func close(code: int = 1000, reason: String = "") -> void:
		state = State.CLOSED
		close_code = code
		close_reason = reason

	func disconnect_transport(code: int = 1000, reason: String = "") -> void:
		close(code, reason)
		if peer != null:
			if peer.peer == self:
				peer.peer = null
			peer = null

	func get_close_code() -> int:
		return close_code

	func get_Close_code() -> int:
		return close_code

	func get_state() -> int:
		return state
