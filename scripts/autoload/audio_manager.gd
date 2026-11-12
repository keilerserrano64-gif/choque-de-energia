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


func _ensure_bus(bus_name: String, send: String = "Master") -> int:
	var existing := AudioServer.get_bus_index(bus_name)
	if existing != -1:
		return existing
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return index


func apply_volumes() -> void:
	_set_bus_volume("Music", SaveData.music_volume / 100.0)
	_set_bus_volume("SFX", SaveData.effects_volume / 100.0)


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
