class_name ChartPlayer
extends Node2D

## Plays a chart + audio pair and drives a simple note-lane display, synced
## to the audio server's real playback position. Attach this script to the
## root of each level's scene, then set chart_path / audio_path (and
## track_name, if a level uses a non-Expert difficulty) in the Inspector —
## each level just points at its own chart and song, everything else here
## is shared. The note visuals (plain ColorRects) and hit_line_y/scroll_speed
## are placeholders — swap in your own note scenes and add input/hit
## detection when you're ready to move past prototyping.
##
## How "Offset" is used here, two parts working together:
## 1. ChartParser already shifts note/segment times by Offset (time = tick
##    time + offset), so they're correctly positioned on the audio's own
##    internal timeline (song_time == 0 is the start of the audio file).
## 2. This script additionally waits -Offset seconds, playing nothing, before
##    starting the audio at all — so a chart with Offset = -3 gets 3 real
##    seconds of silence first. Notes are still free to scroll in during
##    that silence, so the first one arrives at the hit line right as the
##    audio starts, rather than there being a gap of dead air on screen.

@export var chart_path: String = "res://music/Chart/Flower Man.chart"
@export var audio_path: String = "res://music/Ogg/FlowerMan.ogg"
@export var track_name: String = "ExpertSingle"
@export var lane_positions: Array = [100.0, 200.0, 300.0, 400.0, 500.0]
@export var hit_line_y: float = 700.0
@export var scroll_speed: float = 400.0   # pixels per second
@export var note_lead_time: float = 2.0   # seconds a note is visible before its hit time

var chart_data: Dictionary
var audio_player: AudioStreamPlayer
var upcoming_notes: Array = []
var spawned_notes: Array = []

# --- pre-roll silence (from a negative Offset) --------------------------
var start_delay: float = 0.0   # seconds of silence before audio starts (Offset < 0)
var wait_elapsed: float = 0.0
var audio_started: bool = false

# --- temporary segment display ----------------------------------------
var segments: Array = []          # [{tick, index, time}, ...] from ChartParser
var segment_label: Label
var current_segment_index: int = -1

func _ready() -> void:
	var parser := ChartParser.new()
	chart_data = parser.parse_file(chart_path, track_name)
	if chart_data.is_empty():
		push_error("Chart failed to parse — check chart_path/track_name.")
		return
	upcoming_notes = chart_data.notes.duplicate()
	segments = chart_data.segments
	start_delay = max(0.0, -chart_data.get("offset", 0.0))

	_setup_segment_label()

	audio_player = AudioStreamPlayer.new()
	audio_player.stream = load(audio_path)
	add_child(audio_player)

	if start_delay <= 0.0:
		audio_player.play()
		audio_started = true
	# else: _process() below starts playback once start_delay has elapsed

func _process(delta: float) -> void:
	if chart_data.is_empty():
		return

	var song_time: float

	if not audio_started:
		wait_elapsed += delta
		song_time = wait_elapsed - start_delay   # negative during the silence, 0 right as audio begins
		if wait_elapsed >= start_delay:
			audio_player.play()
			audio_started = true
	else:
		if not audio_player.playing:
			return
		song_time = _get_song_time()

	_update_gameplay(song_time)

func _update_gameplay(song_time: float) -> void:
	while not upcoming_notes.is_empty() and upcoming_notes[0].time - note_lead_time <= song_time:
		_spawn_note(upcoming_notes.pop_front())

	for note in spawned_notes:
		var hit_time: float = note.get_meta("hit_time")
		note.position.y = hit_line_y - (hit_time - song_time) * scroll_speed

	_update_segment_label(song_time)

# Creates a plain on-screen label — no scene editing required. This is a
# temporary debug display; swap for a real HUD scene once you don't need it.
func _setup_segment_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	segment_label = Label.new()
	segment_label.add_theme_font_size_override("font_size", 32)
	segment_label.position = Vector2(20, 20)
	segment_label.text = ""
	layer.add_child(segment_label)

func _update_segment_label(song_time: float) -> void:
	var active := -1
	for seg in segments:
		if seg.time <= song_time:
			active = seg.index
		else:
			break
	if active != current_segment_index:
		current_segment_index = active
		segment_label.text = "Segment %d" % active if active != -1 else ""
		_on_segment_changed(active)

## Override in a subclass (see LevelBase.gd) for level-specific behavior
## when the active chart segment changes. index is -1 before the first
## segment starts.
func _on_segment_changed(index: int) -> void:
	pass

# Accounts for the audio server's internal mix buffer so the visual timing
# lines up with what's actually audible, not just the reported stream position.
func _get_song_time() -> float:
	var pos := audio_player.get_playback_position()
	pos += AudioServer.get_time_since_last_mix()
	pos -= AudioServer.get_output_latency()
	return pos

func _spawn_note(note_data: Dictionary) -> void:
	if note_data.lane < 0 or note_data.lane >= lane_positions.size():
		return  # skip force/tap/open flags if your lane list doesn't cover them
	var note := ColorRect.new()
	note.size = Vector2(40, 20)
	note.color = Color.CYAN
	note.position.x = lane_positions[note_data.lane]
	note.set_meta("hit_time", note_data.time)
	add_child(note)
	spawned_notes.append(note)
