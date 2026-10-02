class_name ChartPlayer
extends Node2D

## Plays a chart + audio pair and drives a note-lane display, synced
## to the audio server's real playback position.
##
## Draws visible lane columns and a hit line via _draw(). Notes are
## Sprite2D nodes using the note*.png textures from res://Sprites/.
## Input is handled per-lane via the lane_0 – lane_3 input actions
## (arrow keys by default), with Perfect / Good / Miss timing windows.
##
## Attach this script to the root of each level's scene, then set
## chart_path / audio_path (and track_name, if a level uses a
## non-Expert difficulty) in the Inspector — each level just points at
## its own chart and song, everything else here is shared.

@export var chart_path: String = "res://music/Chart/Flower Man.chart"
@export var audio_path: String = "res://music/Ogg/FlowerMan.ogg"
@export var track_name: String = "ExpertSingle"
@export var lane_positions: Array = [100.0, 200.0, 300.0, 400.0, 500.0]
@export var hit_line_y: float = 950.0
@export var scroll_speed: float = 400.0   # pixels per second
@export var note_lead_time: float = 2.0   # seconds a note is visible before its hit time

# --- lane visuals ---------------------------------------------------------
const LANE_WIDTH: float = 80.0            # width of each lane stripe
const NOTE_TEXTURES: Array[String] = [
	"res://Sprites/note1.png",
	"res://Sprites/note2.png",
	"res://Sprites/note3.png",
	"res://Sprites/note4.png",
]
## Colors matching each note sprite, used for lane tinting and feedback.
const LANE_COLORS: Array[Color] = [
	Color(0.9, 0.15, 0.15, 0.12),   # red    (note1)
	Color(0.9, 0.8,  0.1,  0.12),   # yellow (note2)
	Color(0.1, 0.85, 0.2,  0.12),   # green  (note3)
	Color(0.1, 0.75, 0.9,  0.12),   # cyan   (note4)
]
const LANE_COLORS_SOLID: Array[Color] = [
	Color(0.9, 0.15, 0.15),
	Color(0.9, 0.8,  0.1),
	Color(0.1, 0.85, 0.2),
	Color(0.1, 0.75, 0.9),
]

var _note_textures_loaded: Array[Texture2D] = []

# --- timing windows (seconds, one-sided from hit_time) --------------------
const PERFECT_WINDOW: float = 0.045
const GOOD_WINDOW: float = 0.09
const MISS_WINDOW: float = 0.135

# --- hit feedback flash ---------------------------------------------------
## Per-lane flash alpha (0 = off, fades down each frame).
var _lane_flash: Array[float] = []
## Per-lane flash color.
var _lane_flash_color: Array[Color] = []
const FLASH_DURATION: float = 0.15

# --- chart state ----------------------------------------------------------
var chart_data: Dictionary
var audio_player: AudioStreamPlayer
var upcoming_notes: Array = []
var spawned_notes: Array = []

# --- pre-roll silence (from a negative Offset) ----------------------------
var start_delay: float = 0.0
var wait_elapsed: float = 0.0
var audio_started: bool = false

# --- segment display (debug) ---------------------------------------------
var segments: Array = []
var segment_label: Label
var current_segment_index: int = -1

# --- floating feedback labels ---------------------------------------------
var _feedback_nodes: Array[Node] = []

func _ready() -> void:
	# Load note textures
	for path in NOTE_TEXTURES:
		_note_textures_loaded.append(load(path) as Texture2D)

	# Initialize per-lane flash arrays
	for i in range(lane_positions.size()):
		_lane_flash.append(0.0)
		_lane_flash_color.append(Color.WHITE)

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

func _process(delta: float) -> void:
	if chart_data.is_empty():
		return

	var song_time: float

	if not audio_started:
		wait_elapsed += delta
		song_time = wait_elapsed - start_delay
		if wait_elapsed >= start_delay:
			audio_player.play()
			audio_started = true
	else:
		if not audio_player.playing:
			return
		song_time = _get_song_time()

	_update_gameplay(song_time, delta)

	# Fade lane flashes
	for i in range(_lane_flash.size()):
		if _lane_flash[i] > 0.0:
			_lane_flash[i] = max(0.0, _lane_flash[i] - delta / FLASH_DURATION)

	# Update floating feedback labels
	_update_feedback_labels(delta)

	queue_redraw()

func _update_gameplay(song_time: float, delta: float) -> void:
	# Spawn notes that are about to enter the visible area
	while not upcoming_notes.is_empty() and upcoming_notes[0].time - note_lead_time <= song_time:
		_spawn_note(upcoming_notes.pop_front())

	# Move spawned notes and remove missed ones
	var to_remove: Array[Node] = []
	for note in spawned_notes:
		var hit_time: float = note.get_meta("hit_time")
		note.position.y = hit_line_y - (hit_time - song_time) * scroll_speed

		# Auto-miss: note has passed beyond the miss window
		if song_time > hit_time + MISS_WINDOW:
			to_remove.append(note)
			_on_note_result("Miss", note.get_meta("lane_index"))

	for note in to_remove:
		spawned_notes.erase(note)
		note.queue_free()

	_update_segment_label(song_time)

# --- drawing --------------------------------------------------------------

func _draw() -> void:
	var viewport_h: float = get_viewport().get_visible_rect().size.y

	# Draw lane columns
	for i in range(lane_positions.size()):
		var x: float = lane_positions[i]
		var col: Color = LANE_COLORS[i % LANE_COLORS.size()]

		# Lane stripe background
		var rect := Rect2(x - LANE_WIDTH / 2.0, 0, LANE_WIDTH, viewport_h)
		draw_rect(rect, col)

		# Lane border lines (subtle)
		var border_col := Color(1, 1, 1, 0.08)
		draw_line(Vector2(x - LANE_WIDTH / 2.0, 0), Vector2(x - LANE_WIDTH / 2.0, viewport_h), border_col, 1.0)
		draw_line(Vector2(x + LANE_WIDTH / 2.0, 0), Vector2(x + LANE_WIDTH / 2.0, viewport_h), border_col, 1.0)

		# Flash overlay when a note is hit
		if _lane_flash.size() > i and _lane_flash[i] > 0.0:
			var flash_col: Color = _lane_flash_color[i]
			flash_col.a = _lane_flash[i] * 0.35
			draw_rect(rect, flash_col)

	# Draw hit line
	if not lane_positions.is_empty():
		var left_x: float = lane_positions[0] - LANE_WIDTH / 2.0 - 10.0
		var right_x: float = lane_positions[lane_positions.size() - 1] + LANE_WIDTH / 2.0 + 10.0
		draw_line(Vector2(left_x, hit_line_y), Vector2(right_x, hit_line_y), Color(1, 1, 1, 0.7), 3.0)

		# Small marker circles on the hit line at each lane position
		for i in range(lane_positions.size()):
			var solid_col: Color = LANE_COLORS_SOLID[i % LANE_COLORS_SOLID.size()]
			solid_col.a = 0.5
			draw_circle(Vector2(lane_positions[i], hit_line_y), 18.0, solid_col)
			draw_arc(Vector2(lane_positions[i], hit_line_y), 18.0, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)

# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if chart_data.is_empty():
		return
	for i in range(lane_positions.size()):
		var action_name := "lane_%d" % i
		if event.is_action_pressed(action_name):
			_try_hit_lane(i)
			get_viewport().set_input_as_handled()
			return

func _try_hit_lane(lane_index: int) -> void:
	var song_time := _current_song_time()

	# Find the closest note in this lane within the miss window
	var best_note: Node = null
	var best_diff: float = INF

	for note in spawned_notes:
		if note.get_meta("lane_index") != lane_index:
			continue
		var hit_time: float = note.get_meta("hit_time")
		var diff := absf(song_time - hit_time)
		if diff <= MISS_WINDOW and diff < best_diff:
			best_diff = diff
			best_note = note

	if best_note == null:
		# Pressed but no note nearby — could add a "wrong press" penalty here
		return

	# Classify the hit
	var result: String
	if best_diff <= PERFECT_WINDOW:
		result = "Perfect"
	elif best_diff <= GOOD_WINDOW:
		result = "Good"
	else:
		result = "Miss"

	# Remove the note
	spawned_notes.erase(best_note)
	best_note.queue_free()

	_on_note_result(result, lane_index)

func _on_note_result(result: String, lane_index: int) -> void:
	# Lane flash
	if lane_index < _lane_flash.size():
		_lane_flash[lane_index] = 1.0
		match result:
			"Perfect":
				_lane_flash_color[lane_index] = Color(0.3, 1.0, 0.5)
			"Good":
				_lane_flash_color[lane_index] = Color(1.0, 0.9, 0.3)
			"Miss":
				_lane_flash_color[lane_index] = Color(1.0, 0.2, 0.2)

	# Floating label
	_spawn_feedback_label(result, lane_index)

# --- feedback labels ------------------------------------------------------

func _spawn_feedback_label(text: String, lane_index: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(lane_positions[lane_index] - 40, hit_line_y - 50)
	label.set_meta("lifetime", 0.6)
	label.set_meta("age", 0.0)
	match text:
		"Perfect":
			label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		"Good":
			label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		"Miss":
			label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	add_child(label)
	_feedback_nodes.append(label)

func _update_feedback_labels(delta: float) -> void:
	var to_remove: Array[Node] = []
	for label: Label in _feedback_nodes:
		var age: float = label.get_meta("age") + delta
		label.set_meta("age", age)
		var lifetime: float = label.get_meta("lifetime")
		# Float upward and fade out
		label.position.y -= 60.0 * delta
		label.modulate.a = clamp(1.0 - age / lifetime, 0.0, 1.0)
		if age >= lifetime:
			to_remove.append(label)
	for label in to_remove:
		_feedback_nodes.erase(label)
		label.queue_free()

# --- segment display (debug) ---------------------------------------------

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

# --- helpers --------------------------------------------------------------

func _get_song_time() -> float:
	var pos := audio_player.get_playback_position()
	pos += AudioServer.get_time_since_last_mix()
	pos -= AudioServer.get_output_latency()
	return pos

## Returns the current song time, accounting for pre-roll silence.
func _current_song_time() -> float:
	if not audio_started:
		return wait_elapsed - start_delay
	return _get_song_time()

func _spawn_note(note_data: Dictionary) -> void:
	if note_data.lane < 0 or note_data.lane >= lane_positions.size():
		return  # skip notes for lanes that don't exist at this difficulty

	var tex_index: int = note_data.lane % _note_textures_loaded.size()
	var note := Sprite2D.new()
	note.texture = _note_textures_loaded[tex_index]
	# Scale sprite to fit nicely within the lane
	if note.texture != null:
		var tex_size: Vector2 = note.texture.get_size()
		var desired_width: float = LANE_WIDTH * 0.7
		var scale_factor: float = desired_width / max(tex_size.x, 1.0)
		note.scale = Vector2(scale_factor, scale_factor)
	note.position.x = lane_positions[note_data.lane]
	note.set_meta("hit_time", note_data.time)
	note.set_meta("lane_index", note_data.lane)
	add_child(note)
	spawned_notes.append(note)
