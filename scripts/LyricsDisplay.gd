class_name LyricsDisplay
extends Control
## Karaoke-style lyrics for levels whose chart has lyric events (see
## ChartParser's "lyrics"). One sung line at a time is centered in this
## control: syllables start white and turn yellow the moment they're
## sung, with a small hop. Lines in chorus sections also pulse on every
## beat, like the lyrics in Deltarune's Flowery battle.
##
## Song time and chart data are read from the ChartPlayer this node
## belongs to (the level root), so no level script has to feed it.
## A chart with no lyric events simply draws nothing.

## The level to follow. Left empty, the nearest ChartPlayer ancestor is used.
@export var chart_player: ChartPlayer

@export_group("Look")
## The pixel font looks crispest at multiples of 8.
@export var font_size: int = 32
@export var unsung_color: Color = Color(0.961, 0.941, 1.0)
@export var sung_color: Color = Color(1.0, 0.86, 0.0)
@export var outline_color: Color = Color(0.051, 0.027, 0.129)
@export var outline_size: int = 8
## Also show the upcoming line, smaller and dimmer, under the current one.
@export var show_next_line: bool = false
@export var next_line_font_size: int = 24
@export var next_line_color: Color = Color(0.961, 0.941, 1.0, 0.45)

@export_group("Timing")
## Seconds a line appears before its first syllable is sung.
@export var lead_in: float = 0.75
## Seconds a line stays up after its last syllable ends.
@export var linger: float = 0.6
@export var fade_time: float = 0.15
## Duration (seconds) and height (pixels) of the hop a syllable does when sung.
@export var hop_time: float = 0.14
@export var hop_height: float = 6.0

@export_group("Chorus pulse")
## Lines in a chart section whose name contains this (any case) pulse
## on every beat. Leave empty to turn the pulse off.
@export var pulse_section_keyword: String = "chorus"
## Extra scale at the start of each beat while pulsing.
@export var pulse_amount: float = 0.08

## ChartParser lyric lines, plus "show_at" / "hide_at" / "pulse".
var _lines: Array = []
var _tempo_events: Array = []
var _resolution: int = 192
var _built := false
## First line that hasn't been hidden yet (song time only moves forward).
var _line_index := 0
var _font: Font

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if chart_player == null:
		chart_player = _find_chart_player()
	_font = get_theme_font("font", "Label")

func _process(_delta: float) -> void:
	if chart_player == null:
		return
	if not _built:
		# The player parses its chart in its own _ready(), which runs after ours.
		if chart_player.chart_data.is_empty():
			return
		_build(chart_player.chart_data)
	if not _lines.is_empty():
		queue_redraw()

func _build(chart_data: Dictionary) -> void:
	_built = true
	_tempo_events = chart_data.get("tempo_events", [])
	_resolution = chart_data.get("resolution", 192)
	var keyword := pulse_section_keyword.to_lower()
	var raw: Array = chart_data.get("lyrics", [])
	for i in range(raw.size()):
		var line: Dictionary = raw[i].duplicate()
		var show_at: float = line.start - lead_in
		if i > 0:
			# Don't replace the previous line until its last syllable has
			# had a moment in yellow, even when the next line follows fast.
			var prev_last: float = raw[i - 1].syllables.back().time
			show_at = maxf(show_at, prev_last + minf(0.25, (line.start - prev_last) * 0.5))
		line["show_at"] = show_at
		line["pulse"] = keyword != "" and String(line.get("section", "")).to_lower().contains(keyword)
		_lines.append(line)
	for i in range(_lines.size()):
		var hide_at: float = _lines[i].end + linger
		if i + 1 < _lines.size():
			hide_at = minf(hide_at, _lines[i + 1].show_at)
		_lines[i]["hide_at"] = hide_at

func _draw() -> void:
	if _lines.is_empty() or _font == null or not chart_player.playback_active:
		return
	# Same clock the notes scroll with, so lyrics stay in sync with them.
	var t: float = chart_player._song_time
	while _line_index < _lines.size() and _lines[_line_index].hide_at <= t:
		_line_index += 1
	if _line_index >= _lines.size():
		return
	var line: Dictionary = _lines[_line_index]
	if t < line.show_at:
		return

	var fade_in := clampf((t - line.show_at) / maxf(fade_time, 0.001), 0.0, 1.0)
	var fade_out := clampf((line.hide_at - t) / maxf(fade_time, 0.001), 0.0, 1.0)
	var alpha := fade_in * fade_out
	var pulse := _beat_pulse(t) if line.pulse else 0.0

	# Lines rise a few pixels into place as they fade in.
	var baseline := roundf(font_size + outline_size + (1.0 - fade_in) * 6.0)
	var line_scale := 1.0 + pulse_amount * pulse
	draw_set_transform(Vector2(roundf(size.x / 2.0), baseline), 0.0, Vector2(line_scale, line_scale))
	_draw_line(line, t, font_size, alpha, pulse, true)

	if show_next_line and _line_index + 1 < _lines.size():
		var next_baseline := baseline + roundf(font_size * 0.6 + next_line_font_size + outline_size)
		draw_set_transform(Vector2(roundf(size.x / 2.0), next_baseline), 0.0, Vector2.ONE)
		_draw_line(_lines[_line_index + 1], t, next_line_font_size, alpha, 0.0, false)

	draw_set_transform_matrix(Transform2D.IDENTITY)

## Draws one line centered on x = 0 with its baseline at y = 0 (the
## caller positions it with draw_set_transform).
func _draw_line(line: Dictionary, t: float, fs: int, alpha: float, pulse: float, is_current: bool) -> void:
	var syllables: Array = line.syllables
	var widths: Array[float] = []
	var total := 0.0
	for syl in syllables:
		var w := _font.get_string_size(syl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w

	var outline := outline_color
	outline.a *= alpha
	var x := roundf(-total / 2.0)
	for i in range(syllables.size()):
		var syl: Dictionary = syllables[i]
		var col := next_line_color
		var hop := 0.0
		if is_current:
			var sung: bool = t >= syl.time
			col = sung_color if sung else unsung_color
			if sung and hop_time > 0.0:
				var k: float = (t - syl.time) / hop_time
				if k < 1.0:
					hop = roundf(hop_height * sin(PI * k))
			# Chorus beats flash the text a little brighter.
			col = col.lerp(Color.WHITE, 0.35 * pulse)
		col.a *= alpha
		var pos := Vector2(x, -hop)
		if outline_size > 0:
			draw_string_outline(_font, pos, syl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_size, outline)
		draw_string(_font, pos, syl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += widths[i]

## 1 right on each beat, easing down to 0 before the next one.
func _beat_pulse(t: float) -> float:
	if _tempo_events.is_empty():
		return 0.0
	var te: Dictionary = _tempo_events[0]
	for e in _tempo_events:
		if e.get("time", 0.0) <= t:
			te = e
		else:
			break
	var beats: float = float(te.tick) / float(_resolution) + (t - te.get("time", 0.0)) * te.bpm / 60.0
	var phase := beats - floorf(beats)
	return pow(1.0 - phase, 3.0)

func _find_chart_player() -> ChartPlayer:
	var node := get_parent()
	while node != null and not (node is ChartPlayer):
		node = node.get_parent()
	return node as ChartPlayer
