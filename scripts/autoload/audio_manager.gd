extends Node
## Sound and music hooks.
##
## Gameplay code only ever calls AudioManager.play(&"jump") style hooks with a
## sound id. The id maps to res://assets/audio/<id>.wav when that file exists,
## so sounds can be replaced or added without touching gameplay code. Missing
## files are skipped silently: the game is fully playable with no audio.
##
## Players are pooled and reused instead of being created per sound.

const AUDIO_DIR := "res://assets/audio/"
const POOL_SIZE := 14
const MUSIC_TRACKS := {
	&"menu": "music_menu",
	&"match": "music_match",
}

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}   # id -> AudioStream (or null when missing)
var _music: AudioStreamPlayer
var _music_id: StringName = &""
var _sfx_bus := 0
var _music_bus := 0
## Last sounds requested — tests and the debug panel read this.
var recent: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sfx_bus = _ensure_bus("SFX")
	_music_bus = _ensure_bus("Music")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_settings()


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func apply_settings() -> void:
	if not is_inside_tree() or _pool.is_empty():
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var muted: bool = gs.get_setting("muted", false)
	AudioServer.set_bus_mute(_sfx_bus, muted)
	AudioServer.set_bus_mute(_music_bus, muted)
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(maxf(0.0001, float(gs.get_setting("sfx_volume", 0.8)))))
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(0.0001, float(gs.get_setting("music_volume", 0.55)))))


## Plays a one-shot sound hook. Returns false when no sound file exists for it.
func play(id: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> bool:
	recent.append(id)
	if recent.size() > 32:
		recent.remove_at(0)
	var stream := _get_stream(id)
	if stream == null:
		return false
	var player := _take_player()
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.25, 4.0)
	player.volume_db = volume_db
	player.play()
	return true


## Same as [method play] with a little random pitch so repeats sound alive.
func play_varied(id: StringName, base_pitch: float = 1.0, spread: float = 0.08, volume_db: float = 0.0) -> bool:
	return play(id, base_pitch * randf_range(1.0 - spread, 1.0 + spread), volume_db)


func play_music(track: StringName) -> void:
	if track == _music_id and _music.playing:
		return
	_music_id = track
	var stream := _get_stream(StringName(MUSIC_TRACKS.get(track, String(track))))
	if stream == null:
		_music.stop()
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = _wav_frame_count(wav)
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music_id = &""
	_music.stop()


func is_music_playing() -> bool:
	return _music.playing


func _wav_frame_count(wav: AudioStreamWAV) -> int:
	var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels := 2 if wav.stereo else 1
	return wav.data.size() / (bytes_per_sample * channels)


func _take_player() -> AudioStreamPlayer:
	for i in _pool.size():
		var p := _pool[(_next + i) % _pool.size()]
		if not p.playing:
			_next = (_next + i + 1) % _pool.size()
			return p
	# Everything busy: steal the oldest round-robin slot.
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	return p


func _get_stream(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var stream: AudioStream = null
	for ext: String in [".ogg", ".wav"]:
		var path := AUDIO_DIR + String(id) + ext
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	_streams[id] = stream
	return stream
