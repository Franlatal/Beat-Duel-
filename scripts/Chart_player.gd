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
## Hold notes: any chart note whose sustain is at least
## min_hold_duration becomes a hold note with a tail. Hit the head as
## usual (Perfect/Good), then keep the key down until the tail ends:
##   - held to the end (or released within HOLD_RELEASE_GRACE of it) → "Held"
##   - released earlier → "Dropped" (tail greys out and scrolls away)
##   - head missed → "Miss" (tail greys out, can't be picked up again)
##
## Every judgement is emitted through note_judged, so scoring / HP can
## hook in without touching this script.
##
## Attach this script to the root of each level's scene, then set
## chart_path / audio_path (and track_name, if a level uses a
## non-Expert difficulty) in the Inspector — each level just points at
## its own chart and song, everything else here is shared.

## Emitted for every judgement: "Perfect", "Good", "Miss" (taps and
## hold heads), plus "Held" / "Dropped" when a hold note's tail ends.
signal note_judged(result: String, lane_index: int)

@export var chart_path: String = "res://music/Chart/FlowerManNew.chart"
@export var audio_path: String = "res://music/Ogg/song.ogg"
@export var track_name: String = "ExpertSingle"
@export var lane_positions: Array = [100.0, 200.0, 300.0, 400.0]
@export var hit_line_y: float = 950.0
@export var scroll_speed: float = 400.0   # pixels per second
@export var note_lead_time: float = 2.0   # seconds a note is visible before its hit time
## Notes with a sustain shorter than this (seconds) are treated as taps.
@export var min_hold_duration: float = 0.15

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

# --- hold notes -----------------------------------------------------------
## Releasing a hold this close (seconds) to its end still counts as "Held".
const HOLD_RELEASE_GRACE: float = 0.1
## Tail width as a fraction of LANE_WIDTH.
const TAIL_WIDTH_RATIO: float = 0.28
const TAIL_DROPPED_COLOR := Color(0.35, 0.35, 0.38)

## Lifecycle of a spawned note (stored in its "state" meta).
## Taps only ever use PENDING; holds go PENDING → HOLDING → (removed)
## or PENDING/HOLDING → DROPPED → (removed once off-screen).
enum NoteState { PENDING, HOLDING, DROPPED }

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
## Latest song time, cached for _draw().
var _song_time: float = 0.0

# --- pre-roll silence (from a negative Offset) ----------------------------
var start_delay: float = 0.0
var wait_elapsed: float = 0.0
var audio_started: bool = false

# --- segment display (debug) ---------------------------------------------
#var segments: Array = []
#var segment_label: Label
#var current_segment_index: int = -1

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
	#segments = chart_data.segments
	start_delay = max(0.0, -chart_data.get("offset", 0.0))

	#_setup_segment_label()

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

	_song_time = song_time
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

	# Move spawned notes, resolve holds and remove missed ones
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	var to_remove: Array[Node] = []
	for note in spawned_notes:
		var hit_time: float = note.get_meta("hit_time")
		var end_time: float = note.get_meta("end_time")
		var lane: int = note.get_meta("lane_index")
		var is_hold: bool = note.get_meta("is_hold")

		match note.get_meta("state"):
			NoteState.PENDING:
				note.position.y = _time_to_y(hit_time, song_time)
				# Auto-miss: note has passed beyond the miss window
				if song_time > hit_time + MISS_WINDOW:
					_on_note_result("Miss", lane)
					if is_hold:
						_drop_hold(note, false, song_time)
					else:
						to_remove.append(note)

			NoteState.HOLDING:
				# Head stays pinned to the hit line while the tail drains into it.
				note.position.y = hit_line_y
				if song_time >= end_time:
					to_remove.append(note)
					_on_note_result("Held", lane)
				elif not Input.is_action_pressed(_action_for_lane(lane)):
					if song_time >= end_time - HOLD_RELEASE_GRACE:
						to_remove.append(note)
						_on_note_result("Held", lane)
					else:
						_drop_hold(note, true, song_time)
						_on_note_result("Dropped", lane)

			NoteState.DROPPED:
				note.position.y = _time_to_y(hit_time, song_time)
				# Remove once the end of the tail has scrolled off-screen.
				if _time_to_y(end_time, song_time) > viewport_h:
					to_remove.append(note)

	for note in to_remove:
		spawned_notes.erase(note)
		note.queue_free()

	#_update_segment_label(song_time)

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

	# Hold-note tails (drawn here so the head sprites, being children,
	# render on top of them)
	_draw_hold_tails()

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

	# Pulsing glow on lanes whose hold note is currently being held
	var pulse: float = 0.75 + 0.25 * sin(_song_time * 20.0)
	for note in spawned_notes:
		if note.get_meta("state") != NoteState.HOLDING:
			continue
		var lane: int = note.get_meta("lane_index")
		var center := Vector2(lane_positions[lane], hit_line_y)
		var glow: Color = LANE_COLORS_SOLID[lane % LANE_COLORS_SOLID.size()]
		glow.a = 0.35 * pulse
		draw_circle(center, 30.0, glow)
		draw_arc(center, 30.0, 0, TAU, 32, Color(1, 1, 1, 0.7 * pulse), 3.0)

func _draw_hold_tails() -> void:
	var tail_w: float = LANE_WIDTH * TAIL_WIDTH_RATIO
	for note in spawned_notes:
		if not note.get_meta("is_hold"):
			continue
		var lane: int = note.get_meta("lane_index")
		var x: float = lane_positions[lane]
		var state: int = note.get_meta("state")

		var bottom_y: float
		match state:
			NoteState.PENDING:
				bottom_y = _time_to_y(note.get_meta("hit_time"), _song_time)
			NoteState.HOLDING:
				bottom_y = hit_line_y
			_:
				bottom_y = _time_to_y(note.get_meta("tail_start"), _song_time)
		var top_y: float = _time_to_y(note.get_meta("end_time"), _song_time)
		if bottom_y <= top_y:
			continue

		var col: Color = LANE_COLORS_SOLID[lane % LANE_COLORS_SOLID.size()]
		var shine_alpha := 0.25
		if state == NoteState.HOLDING:
			col = col.lerp(Color.WHITE, 0.25)
			shine_alpha = 0.5
		elif state == NoteState.DROPPED:
			col = TAIL_DROPPED_COLOR
			shine_alpha = 0.08

		draw_rect(Rect2(x - tail_w / 2.0, top_y, tail_w, bottom_y - top_y), col)
		draw_circle(Vector2(x, top_y), tail_w / 2.0, col)   # rounded end cap
		# Thin highlight stripe down the middle
		draw_rect(Rect2(x - tail_w * 0.15, top_y, tail_w * 0.3, bottom_y - top_y), Color(1, 1, 1, shine_alpha))

# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if chart_data.is_empty():
		return
	for i in range(lane_positions.size()):
		if event.is_action_pressed(_action_for_lane(i)):
			_try_hit_lane(i)
			get_viewport().set_input_as_handled()
			return

## Input action that drives a given chart lane. Used both for presses
## (_unhandled_input) and for checking whether a hold is still held.
## LevelBase overrides this to spread keys out for 2/3-lane difficulties.
func _action_for_lane(lane_index: int) -> String:
	return "lane_%d" % lane_index

func _try_hit_lane(lane_index: int) -> void:
	var song_time := _current_song_time()

	# Find the closest note in this lane within the miss window
	var best_note: Node = null
	var best_diff: float = INF

	for note in spawned_notes:
		if note.get_meta("lane_index") != lane_index:
			continue
		if note.get_meta("state") != NoteState.PENDING:
			continue   # already being held, or a dead tail
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

	if best_note.get_meta("is_hold"):
		if result == "Miss":
			_drop_hold(best_note, false, song_time)
		else:
			# Head hit -- start holding; the tail is judged when it ends.
			best_note.set_meta("state", NoteState.HOLDING)
			best_note.position.y = hit_line_y
	else:
		# Remove the note
		spawned_notes.erase(best_note)
		best_note.queue_free()

	_on_note_result(result, lane_index)

## Turns a hold note into a dead, greyed-out tail that just scrolls away.
## released_mid_hold: the head was already hit (so it's hidden and the
## tail's bottom starts at the hit line); otherwise the head was missed.
func _drop_hold(note: Node, released_mid_hold: bool, song_time: float) -> void:
	note.set_meta("state", NoteState.DROPPED)
	if released_mid_hold:
		note.set_meta("tail_start", song_time)
		note.visible = false
	else:
		note.set_meta("tail_start", note.get_meta("hit_time"))
		note.modulate = Color(0.45, 0.45, 0.45, 0.8)

func _on_note_result(result: String, lane_index: int) -> void:
	# Lane flash
	if lane_index < _lane_flash.size():
		_lane_flash[lane_index] = 1.0
		_lane_flash_color[lane_index] = _result_color(result)

	# Floating label
	_spawn_feedback_label(result, lane_index)

	note_judged.emit(result, lane_index)

func _result_color(result: String) -> Color:
	match result:
		"Perfect":
			return Color(0.3, 1.0, 0.5)
		"Good":
			return Color(1.0, 0.9, 0.3)
		"Held":
			return Color(0.4, 0.85, 1.0)
		"Dropped":
			return Color(1.0, 0.55, 0.2)
		_:
			return Color(1.0, 0.2, 0.2)   # Miss

# --- feedback labels ------------------------------------------------------

func _spawn_feedback_label(text: String, lane_index: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(lane_positions[lane_index] - 40, hit_line_y - 50)
	label.set_meta("lifetime", 0.6)
	label.set_meta("age", 0.0)
	label.add_theme_color_override("font_color", _result_color(text))
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

#func _setup_segment_label() -> void:
	#var layer := CanvasLayer.new()
	#add_child(layer)
	#segment_label = Label.new()
	#segment_label.add_theme_font_size_override("font_size", 32)
	#segment_label.position = Vector2(20, 20)
	#segment_label.text = ""
	#layer.add_child(segment_label)

#func _update_segment_label(song_time: float) -> void:
	#var active := -1
	#for seg in segments:
		#if seg.time <= song_time:
			#active = seg.index
		#else:
			#break
	#if active != current_segment_index:
		#current_segment_index = active
		#segment_label.text = "Segment %d" % active if active != -1 else ""
		#_on_segment_changed(active)

## Override in a subclass (see LevelBase.gd) for level-specific behavior
## when the active chart segment changes. index is -1 before the first
## segment starts.
#func _on_segment_changed(index: int) -> void:
	#pass

# --- helpers --------------------------------------------------------------

## Screen y of a note scheduled at time t, given the current song time.
func _time_to_y(t: float, song_time: float) -> float:
	return hit_line_y - (t - song_time) * scroll_speed

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
	var sustain: float = note_data.get("sustain", 0.0)
	var is_hold: bool = sustain >= min_hold_duration
	note.set_meta("is_hold", is_hold)
	note.set_meta("end_time", note_data.time + (sustain if is_hold else 0.0))
	note.set_meta("tail_start", note_data.time)
	note.set_meta("state", NoteState.PENDING)
	add_child(note)
	spawned_notes.append(note)
