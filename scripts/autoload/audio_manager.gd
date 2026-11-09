extends Node
## Autoload "Sfx": efectos de sonido y música (equivale a src/audio.js).
## Los WAV de assets/audio se generaron a partir de los mismos tonos que el
## juego web sintetizaba en el navegador; puedes reemplazarlos por los tuyos
## con el mismo nombre.

const SOUND_FILES := {
	"hit": "res://assets/audio/hit.wav",
	"heavy_hit": "res://assets/audio/heavy_hit.wav",
	"block": "res://assets/audio/block.wav",
	"jump": "res://assets/audio/jump.wav",
	"special": "res://assets/audio/special.wav",
	"ko": "res://assets/audio/ko.wav",
	"awaken": "res://assets/audio/awaken.wav",
	"win": "res://assets/audio/win.wav",
	"announce": "res://assets/audio/announce.wav",
	"cursor": "res://assets/audio/cursor.wav",
	"confirm": "res://assets/audio/confirm.wav",
}
const MUSIC_FILES := {
	"menu": "res://assets/audio/menu_theme.wav",
	"battle": "res://assets/audio/battle_theme.wav",
}
const POOL_SIZE := 10
const VOICE_DIR := "res://assets/voices/%s/%s_%d.wav"
const VOICE_DB := -1.0

## Voces: [luchador][frase] = Array de AudioStream. Se cargan al primer uso.
var _voice_streams: Dictionary = {}
## Un reproductor de voz por lado (J1 y J2): una frase nueva corta la anterior del mismo lado.
var _voice_players: Array[AudioStreamPlayer] = []
var _last_voice_index: Dictionary = {}

var _streams: Dictionary = {}
var _music_streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music: AudioStreamPlayer
var _current_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Voices")
	for fighter in Catalog.FIGHTERS:
		_ensure_voice_bus(fighter)
	for i in range(2):
		var voice := AudioStreamPlayer.new()
		voice.bus = "Voices"
		voice.volume_db = VOICE_DB
		add_child(voice)
		_voice_players.append(voice)
	for key in SOUND_FILES:
		var path: String = SOUND_FILES[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for key in MUSIC_FILES:
		var path: String = MUSIC_FILES[key]
		if ResourceLoader.exists(path):
			_music_streams[key] = load(path)
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	apply_volumes()


func _exit_tree() -> void:
	_voice_streams.clear()


func _ensure_bus(bus_name: String, send: String = "Master") -> int:
	var existing := AudioServer.get_bus_index(bus_name)
	if existing != -1:
		return existing
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return index


## Cada luchador tiene su bus de voz con efectos propios ("voice_fx" en catalog.gd):
## eco de espejo para Espejo, fase eléctrica para Volt, voz grave de roca para Pedernal…
func _ensure_voice_bus(fighter: Dictionary) -> void:
	var bus_name := "Voice_" + String(fighter["id"])
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var index := _ensure_bus(bus_name, "Voices")
	for fx in fighter.get("voice_fx", []):
		var effect := _voice_effect(fx)
		if effect:
			AudioServer.add_bus_effect(index, effect)


func _voice_effect(fx: Dictionary) -> AudioEffect:
	match String(fx.get("type", "")):
		"reverb":
			var reverb := AudioEffectReverb.new()
			reverb.room_size = float(fx.get("room", 0.4))
			reverb.wet = float(fx.get("wet", 0.2))
			reverb.dry = 1.0
			reverb.damping = 0.4
			return reverb
		"chorus":
			var chorus := AudioEffectChorus.new()
			chorus.voice_count = 2
			chorus.wet = float(fx.get("wet", 0.4))
			chorus.dry = 1.0
			return chorus
		"phaser":
			var phaser := AudioEffectPhaser.new()
			phaser.rate_hz = float(fx.get("rate", 1.0))
			phaser.depth = float(fx.get("depth", 0.5))
			phaser.feedback = 0.6
			return phaser
		"delay":
			var delay := AudioEffectDelay.new()
			delay.dry = 1.0
			delay.tap1_active = true
			delay.tap1_delay_ms = float(fx.get("tap", 100.0))
			delay.tap1_level_db = float(fx.get("level", -8.0))
			delay.tap2_active = fx.has("tap2")
			delay.tap2_delay_ms = float(fx.get("tap2", 200.0))
			delay.tap2_level_db = float(fx.get("level2", -12.0))
			delay.feedback_active = false
			return delay
		"pitch":
			var pitch := AudioEffectPitchShift.new()
			pitch.pitch_scale = float(fx.get("scale", 1.0))
			return pitch
		"distortion":
			var distortion := AudioEffectDistortion.new()
			distortion.mode = AudioEffectDistortion.MODE_OVERDRIVE
			distortion.drive = float(fx.get("drive", 0.2))
			distortion.post_gain = -2.0
			return distortion
	return null


## Frases de voz disponibles de un luchador (vacío si no se generaron).
func voice_streams(fighter_id: String, line: String) -> Array:
	if not _voice_streams.has(fighter_id):
		_voice_streams[fighter_id] = {}
	var lines: Dictionary = _voice_streams[fighter_id]
	if not lines.has(line):
		var streams: Array = []
		for n in range(6):
			var path := VOICE_DIR % [fighter_id, line, n]
			if not ResourceLoader.exists(path):
				break
			streams.append(load(path))
		lines[line] = streams
	return lines[line]


## Reproduce una frase de un luchador en el canal de su lado (0 = J1, 1 = J2).
func play_voice(side: int, fighter_id: String, line: String, delay: float = 0.0) -> void:
	if SaveData.voice_volume <= 0:
		return
	var streams := voice_streams(fighter_id, line)
	if streams.is_empty():
		return
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	# No repite la misma variante dos veces seguidas.
	var key := fighter_id + "/" + line
	var pick := randi() % streams.size()
	if streams.size() > 1 and _last_voice_index.get(key, -1) == pick:
		pick = (pick + 1) % streams.size()
	_last_voice_index[key] = pick
	var player := _voice_players[clampi(side, 0, 1)]
	player.stop()
	player.bus = "Voice_" + fighter_id if AudioServer.get_bus_index("Voice_" + fighter_id) != -1 else "Voices"
	player.stream = streams[pick]
	player.pitch_scale = randf_range(0.97, 1.04)
	player.play()


## Evento de CombatSim: "voice|<lado>|<luchador>|<frase>|<retraso>".
func play_voice_event(event: String) -> void:
	var parts := event.split("|")
	if parts.size() < 4:
		return
	play_voice(int(parts[1]), parts[2], parts[3], float(parts[4]) if parts.size() > 4 else 0.0)


func apply_volumes() -> void:
	_set_bus_volume("Music", SaveData.music_volume / 100.0)
	_set_bus_volume("SFX", SaveData.effects_volume / 100.0)
	_set_bus_volume("Voices", SaveData.voice_volume / 100.0)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


## Reproduce un efecto. Acepta también los nombres del juego web ("heavy-hit").
func play(kind: String, pitch_variation: float = 0.0) -> void:
	var key := kind.replace("-", "_")
	if key == "announce" and not SaveData.announcer:
		return
	if not _streams.has(key):
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[key]
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func play_music(track: String) -> void:
	if track == _current_track and _music.playing:
		return
	_current_track = track
	if not _music_streams.has(track):
		_music.stop()
		return
	_music.stream = _music_streams[track]
	_music.play()


func stop_music() -> void:
	_current_track = ""
	_music.stop()


func _on_music_finished() -> void:
	if _current_track != "":
		_music.play()
