class_name WSTransport
extends Transport
## Implementação concreta de Transport sobre WebSocketPeer (NETWORK_PROTOCOL.md §1).
## Compatível com builds nativas (Windows/Linux/macOS) e Web (WASM).

const STATE_CONNECTING: int = WebSocketPeer.STATE_CONNECTING
const STATE_OPEN: int = WebSocketPeer.STATE_OPEN
const STATE_CLOSING: int = WebSocketPeer.STATE_CLOSING
const STATE_CLOSED: int = WebSocketPeer.STATE_CLOSED

const SUBPROTOCOL: String = Protocol.SUBPROTOCOL
const INBOUND_BUFFER_BYTES: int = 65536 # 64 KiB (NETWORK_PROTOCOL §1)
const OUTBOUND_BUFFER_BYTES: int = 16384

var socket: WebSocketPeer = WebSocketPeer.new()


func _init() -> void:
	_configure_socket()


func _configure_socket() -> void:
	socket.supported_protocols = PackedStringArray([SUBPROTOCOL])
	socket.inbound_buffer_size = INBOUND_BUFFER_BYTES
	socket.outbound_buffer_size = OUTBOUND_BUFFER_BYTES


func connect_to_url(url: String) -> int:
	_configure_socket()
	return socket.connect_to_url(url)


func poll() -> void:
	socket.poll()


func send_text(payload: String) -> int:
	if payload.to_utf8_buffer().size() > Protocol.MAX_CLIENT_FRAME_BYTES:
		return ERR_INVALID_DATA
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return socket.send_text(payload)


func receive_text() -> Array[String]:
	var frames: Array[String] = []
	while socket.get_available_packet_count() > 0:
		var pkt := socket.get_packet()
		if socket.was_string_packet():
			frames.append(pkt.get_string_from_utf8())
	return frames


func poll_packets() -> Array[String]:
	return receive_text()


func close(code: int = 1000, reason: String = "") -> void:
	socket.close(code, reason)


func disconnect_transport(code: int = 1000, reason: String = "") -> void:
	close(code, reason)


func get_state() -> int:
	return int(socket.get_ready_state())
