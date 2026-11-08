class_name SfxSynth
extends RefCounted
## Sintetizador procedural de efeitos sonoros em memória (PCM 16 bits, sem assets externos).
## Respeita a restrição de autoplay dos navegadores Web (PLATFORM_COMPATIBILITY.md §3):
## o áudio só é marcado como desbloqueado após o primeiro gesto de entrada do usuário.

const MIX_RATE: int = 22050
const SOUND_IDS: Array[String] = ["bomb_place", "explosion", "powerup", "victory", "ui_click"]

var audio_unlocked: bool = false
var muted: bool = false
var _cache: Dictionary = {}


func unlock_on_gesture(event: InputEvent = null) -> bool:
	if event == null:
		audio_unlocked = true
		return audio_unlocked
	if (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventJoypadButton
		or event is InputEventScreenTouch
	) and event.is_pressed():
		audio_unlocked = true
	return audio_unlocked


func can_play() -> bool:
	return audio_unlocked and not muted


func get_stream(sound_id: String) -> AudioStreamWAV:
	if _cache.has(sound_id):
		return _cache[sound_id]

	var stream: AudioStreamWAV
	match sound_id:
		"bomb_place":
			stream = make_bomb_place()
		"explosion":
			stream = make_explosion()
		"powerup":
			stream = make_powerup()
		"victory":
			stream = make_victory()
		"ui_click":
			stream = make_ui_click()
		_:
			stream = make_ui_click()

	_cache[sound_id] = stream
	return stream


static func make_bomb_place() -> AudioStreamWAV:
	return _synth_tone_sweep(260.0, 140.0, 0.09, 0.45)


static func make_explosion() -> AudioStreamWAV:
	return _synth_explosion(0.26, 0.65)


static func make_powerup() -> AudioStreamWAV:
	return _synth_arpeggio([523.25, 659.25, 783.99, 1046.50], 0.04, 0.42)


static func make_victory() -> AudioStreamWAV:
	return _synth_arpeggio([523.25, 659.25, 783.99, 1046.50, 1318.51], 0.07, 0.48)


static func make_ui_click() -> AudioStreamWAV:
	return _synth_tone_sweep(880.0, 440.0, 0.03, 0.35)


static func _synth_tone_sweep(freq_start: float, freq_end: float, duration_s: float, amp: float) -> AudioStreamWAV:
	var total_samples := maxi(int(duration_s * MIX_RATE), 1)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	var phase := 0.0
	for i in range(total_samples):
		var t := float(i) / float(total_samples)
		var freq := lerpf(freq_start, freq_end, t)
		var env := 1.0 - t
		phase += TAU * freq / float(MIX_RATE)
		var sample := sin(phase) * amp * env
		_write_pcm16(bytes, i * 2, sample)
	return _make_wav(bytes)


static func _synth_explosion(duration_s: float, amp: float) -> AudioStreamWAV:
	var total_samples := maxi(int(duration_s * MIX_RATE), 1)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	var rng := PRNG.new(0xB00B1E5)
	var prng := rng
	var phase := 0.0
	for i in range(total_samples):
		var t := float(i) / float(total_samples)
		var env := pow(1.0 - t, 1.8)
		var noise := (float(prng.next_u32() & 0xFFFF) / 32767.5) - 1.0
		phase += TAU * lerpf(110.0, 42.0, t) / float(MIX_RATE)
		var rumble := sin(phase)
		var sample := (noise * 0.65 + rumble * 0.35) * amp * env
		_write_pcm16(bytes, i * 2, sample)
	return _make_wav(bytes)


static func _synth_arpeggio(notes_hz: Array[float], note_duration_s: float, amp: float) -> AudioStreamWAV:
	var samples_per_note := maxi(int(note_duration_s * MIX_RATE), 1)
	var total_samples := samples_per_note * maxi(notes_hz.size(), 1)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	var phase := 0.0
	for i in range(total_samples):
		@warning_ignore("integer_division")
		var note_idx := mini(i / samples_per_note, notes_hz.size() - 1)
		var local_t := float(i % samples_per_note) / float(samples_per_note)
		var env := 1.0 - (local_t * 0.45)
		phase += TAU * notes_hz[note_idx] / float(MIX_RATE)
		var sample := sin(phase) * amp * env
		_write_pcm16(bytes, i * 2, sample)
	return _make_wav(bytes)


static func _write_pcm16(buf: PackedByteArray, offset: int, normalized: float) -> void:
	var pcm := clampi(int(round(normalized * 32767.0)), -32768, 32767)
	var u16 := pcm & 0xFFFF
	buf[offset] = u16 & 0xFF
	buf[offset + 1] = (u16 >> 8) & 0xFF


static func _make_wav(pcm_bytes: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = pcm_bytes
	return wav
