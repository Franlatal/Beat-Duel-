class_name LevelPreviewPlayer
extends Node
## Plays a looping preview clip of a level's song on the level select
## screen. Two players take turns so that switching levels, and the jump
## from the end of the clip back to its start, are crossfades instead of
## hard cuts.
##
## Usage: add it as a child, call play_level(level) whenever the
## highlighted level changes, and await fade_out() before leaving the
## screen. It plays on the Master bus like the in-level song, so the
## Options volume slider controls it.
##
## Every start / missing file is printed to the Output panel with a
## "[LevelPreview]" prefix, so a silent preview says why.

## Seconds the old clip takes to fade out while the new one fades in.
@export var crossfade_time: float = 0.6
## Seconds to wait after a level is highlighted before its clip starts,
## so scrolling quickly through the list doesn't start every song.
@export var start_delay: float = 0.25
## Overall preview volume in decibels, added to each level's own
## preview_volume_db.
@export_range(-40.0, 12.0, 0.5) var volume_db: float = -2.0

const SILENT_DB := -60.0

var _players: Array[AudioStreamPlayer] = []
var _tweens: Array[Tween] = [null, null]
var _active := -1 ## index of the player that is (or is becoming) audible

var _level: LevelData = null ## the level whose clip should be playing
var _playing_level: LevelData = null ## the level the audible player has
var _path := ""
var _clip_start := 0.0
var _clip_end := 0.0
var _clip_db := 0.0
var _pending := false ## waiting for start_delay
var _wait_left := 0.0
var _streams: Dictionary = {} ## path -> AudioStream, so revisits are instant

func _ready() -> void:
	# Keep fading and looping even if the tree was left paused by a level.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Preview%d" % i
		p.volume_db = SILENT_DB
		p.bus = &"Master"
		add_child(p)
		_players.append(p)

## Starts (after start_delay) the preview of level, crossfading from
## whatever is playing. Passing null, or a level without a song, fades
## the current clip out.
func play_level(level: LevelData) -> void:
	if level == _level:
		return
	_level = level
	_pending = false
	if level != null and level == _playing_level and is_playing():
		# Scrolled away and straight back: keep the clip going.
		return
	var path := "" if level == null else level.get_preview_audio_path()
	if level != null and (path == "" or not ResourceLoader.exists(path)):
		print("[LevelPreview] %s: no song file found (%s). Set preview_audio_path in its .tres." % [level.title, path if path != "" else "no audio_path"])
		path = ""
	if path == "":
		_playing_level = null
		_fade_out_active(crossfade_time)
		return
	_path = path
	_wait_left = start_delay
	_pending = true

## Fades everything out over time seconds; await it before changing
## scene so the music doesn't cut off.
func fade_out(time: float = 0.3) -> void:
	_level = null
	_playing_level = null
	_pending = false
	_active = -1
	# Fade both players, so a clip still fading out from a crossfade
	# doesn't outlast this.
	var last: Tween = null
	for i in _players.size():
		var p := _players[i]
		_kill_tween(i)
		if p.playing:
			last = _fade(p, SILENT_DB, time)
			last.tween_callback(p.stop)
			_tweens[i] = last
	if last != null:
		await last.finished

func stop() -> void:
	_level = null
	_playing_level = null
	_pending = false
	for i in _players.size():
		_kill_tween(i)
		_players[i].stop()
	_active = -1

func is_playing() -> bool:
	return _active != -1 and _players[_active].playing

func _process(delta: float) -> void:
	if _pending:
		_wait_left -= delta
		if _wait_left <= 0.0:
			_pending = false
			var stream := _get_stream(_path)
			if stream != null:
				_start_clip(stream)
			else:
				print("[LevelPreview] could not load %s as audio" % _path)
				_fade_out_active(crossfade_time)
		return

	# Loop: shortly before the clip end, crossfade back to its start.
	if _active != -1:
		var p := _players[_active]
		if p.playing and p.get_playback_position() >= _clip_end - crossfade_time:
			_crossfade_to(p.stream, _clip_start)
		elif not p.playing:
			# The song ended before the clip did.
			_crossfade_to(p.stream, _clip_start)

## Loads the song once and keeps it, so going back to a level is instant.
func _get_stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream
	return _streams[path]

func _start_clip(stream: AudioStream) -> void:
	var length := stream.get_length()
	var start := _level.preview_start
	if start < 0.0:
		# Auto: about a third of the way into the song.
		start = length / 3.0
	start = clampf(start, 0.0, maxf(0.0, length - 1.0))
	var end := length
	if _level.preview_length > 0.0:
		end = minf(length, start + _level.preview_length)
	# Keep the clip long enough for a fade in and a fade out.
	if end - start < crossfade_time * 3.0:
		start = maxf(0.0, end - crossfade_time * 3.0)
	_clip_start = start
	_clip_end = end
	_clip_db = volume_db + _level.preview_volume_db
	_playing_level = _level
	print("[LevelPreview] %s: playing %s from %.1fs to %.1fs" % [_level.title, _path, start, end])
	_crossfade_to(stream, start)

## Starts stream at from_time on the quiet player and swaps the two.
func _crossfade_to(stream: AudioStream, from_time: float) -> void:
	var next := 0 if _active != 0 else 1
	_fade_out_active(crossfade_time)
	_kill_tween(next)
	var p := _players[next]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play(from_time)
	_active = next
	_tweens[next] = _fade(p, _clip_db, crossfade_time)

## Fades the audible player out and stops it. Returns the tween, or null
## when nothing was playing.
func _fade_out_active(time: float) -> Tween:
	if _active == -1:
		return null
	var i := _active
	_active = -1
	_kill_tween(i)
	var p := _players[i]
	if not p.playing:
		return null
	var t := _fade(p, SILENT_DB, time)
	t.tween_callback(p.stop)
	_tweens[i] = t
	return t

## Fades in a linear volume ramp (a dB tween sounds like a sudden drop).
func _fade(p: AudioStreamPlayer, to_db: float, time: float) -> Tween:
	var t := create_tween()
	var from_lin := db_to_linear(p.volume_db)
	var to_lin := db_to_linear(to_db)
	t.tween_method(func(v: float) -> void: p.volume_db = linear_to_db(maxf(v, 0.00001)),
			from_lin, to_lin, maxf(time, 0.01))
	return t

func _kill_tween(i: int) -> void:
	if _tweens[i] != null and _tweens[i].is_valid():
		_tweens[i].kill()
	_tweens[i] = null
