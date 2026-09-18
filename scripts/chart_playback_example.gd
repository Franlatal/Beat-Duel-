extends Node2D

## Minimal example: plays a song and spawns a note (ColorRect) for every
## chart note at the right moment, scrolling toward a hit line.
## This is a starting point to prove the sync works, not a finished
## gameplay system — swap the placeholder note visuals for your own scenes,
## add input/hit-detection, and adjust lane_positions to match "Beat Duel"'s
## actual lane count.
##
## The chart's [Song] "Offset" is already folded into chart_data.notes /
## chart_data.segments by ChartParser, so this script just plays the audio
## normally from the start — no extra delay or seeking needed here.

@export var chart_path: String = "res://charts/song.chart"
@export var audio_path: String = "res://charts/song.ogg"
@export var track_name: String = "ExpertSingle"
@export var lane_positions: Array = [100.0, 200.0, 300.0, 400.0, 500.0]
@export var hit_line_y: float = 700.0
@export var scroll_speed: float = 400.0   # pixels per second
@export var note_lead_time: float = 2.0   # seconds a note is visible before its hit time

var chart_data: Dictionary
var audio_player: AudioStreamPlayer
var upcoming_notes: Array = []
var spawned_notes: Array = []

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

	_setup_segment_label()

	audio_player = AudioStreamPlayer.new()
	audio_player.stream = load(audio_path)
	add_child(audio_player)
	audio_player.play()

func _process(_delta: float) -> void:
	if audio_player == null or not audio_player.playing:
		return

	var song_time := _get_song_time()

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
