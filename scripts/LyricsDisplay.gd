class_name LyricsDisplay
extends Control
## Karaoke-style lyrics for levels whose chart has lyric events (see
## ChartParser's "lyrics"), styled like Deltarune's Flowery battle.
## One sung line at a time is centered in this control. Its letters start
## yellow and turn green, left to right, as each syllable is sung.
## Lines in chorus sections use brighter colors and a jittering
## horizontal smear (echo copies of the line on both sides).
##
## Song time and chart data are read from the ChartPlayer this node
## belongs to (the level root), so no level script has to feed it.
## A chart with no lyric events simply draws nothing.

## The level to follow. Left empty, the nearest ChartPlayer ancestor is used.
@export var chart_player: ChartPlayer

@export_group("Look")
## The pixel font looks crispest at multiples of 8.
@export var font_size: int = 32
## Verse (non-chorus) lines: dim olive yellow, turning pale green when sung.
@export var unsung_color: Color = Color8(204, 200, 48)
@export var sung_color: Color = Color8(144, 196, 120)
@export var outline_color: Color = Color(0.0, 0.0, 0.0)
@export var outline_size: int = 6
## Seconds the green takes to sweep across one syllable's letters
## (shorter if the next syllable comes sooner).
@export var fill_time: float = 0.25
## Also show the upcoming line, smaller and dimmer, under the current one.
@export var show_next_line: bool = false
@export var next_line_font_size: int = 24
@export var next_line_color: Color = Color(0.72, 0.71, 0.16, 0.45)

@export_group("Timing")
## Seconds a line appears before its first syllable is sung.
@export var lead_in: float = 0.75
## Seconds a line stays up after its last syllable ends.
@export var linger: float = 0.6
@export var fade_time: float = 0.15
## Duration (seconds) and height (pixels) of a hop a syllable does when
## sung. 0 = no hop (Deltarune's lyrics don't hop).
@export var hop_time: float = 0.0
@export var hop_height: float = 6.0

@export_group("Chorus")
## Lines in a chart section whose name contains this (any case) use the
## chorus look. Leave empty to draw every line in the verse look.
@export var chorus_section_keyword: String = "chorus"
@export var chorus_unsung_color: Color = Color8(244, 240, 40)
@export var chorus_sung_color: Color = Color8(104, 236, 104)
## Soft pale glow around the chorus text.
@export var chorus_glow_color: Color = Color(0.8, 1.0, 0.8, 0.28)
@export var chorus_glow_size: int = 10
## Echo copies drawn on each side of a chorus line.
@export var smear_count: int = 10
## Pixels between echoes, and how far each one jitters.
@export var smear_spacing: float = 14.0
@export var smear_jitter: float = 6.0
## Alpha of the nearest echo (further ones fade out).
@export var smear_alpha: float = 0.5
## How much darker than the text the echoes are.
@export var smear_darken: float = 0.45
## Times per second the smear jitters.
@export var smear_rate: float = 12.0
## Extra scale on each beat for chorus lines (0 = off).
@export var pulse_amount: float = 0.0

## ChartParser lyric lines, plus "show_at" / "hide_at" / "chorus".
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
	var keyword := chorus_section_keyword.to_lower()
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
		line["chorus"] = keyword != "" and String(line.get("section", "")).to_lower().contains(keyword)
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
	var chorus: bool = line.chorus
	var pulse := _beat_pulse(t) if chorus and pulse_amount > 0.0 else 0.0

	# Lines rise a few pixels into place as they fade in.
	var baseline := roundf(font_size + outline_size + (1.0 - fade_in) * 4.0)
	var line_scale := 1.0 + pulse_amount * pulse
	draw_set_transform(Vector2(roundf(size.x / 2.0), baseline), 0.0, Vector2(line_scale, line_scale))
	var cols := _line_colors(chorus)
	if chorus and smear_count > 0:
		_draw_smear(line, t, font_size, alpha, cols)
	if chorus and chorus_glow_size > 0:
		var glow := chorus_glow_color
		glow.a *= alpha
		_draw_line(line, t, font_size, Vector2.ZERO, [glow, glow], chorus_glow_size + outline_size, glow)
	var outline := outline_color
	outline.a *= alpha
	_draw_line(line, t, font_size, Vector2.ZERO, _faded(cols, alpha), outline_size, outline)

	if show_next_line and _line_index + 1 < _lines.size():
		var next_baseline := baseline + roundf(font_size * 0.6 + next_line_font_size + outline_size)
		draw_set_transform(Vector2(roundf(size.x / 2.0), next_baseline), 0.0, Vector2.ONE)
		var nc := next_line_color
		nc.a *= alpha
		_draw_line(_lines[_line_index + 1], -INF, next_line_font_size, Vector2.ZERO, [nc, nc], outline_size, outline)

	draw_set_transform_matrix(Transform2D.IDENTITY)

## [unsung, sung] colors for a line.
func _line_colors(chorus: bool) -> Array:
	if chorus:
		return [chorus_unsung_color, chorus_sung_color]
	return [unsung_color, sung_color]

func _faded(cols: Array, alpha: float) -> Array:
	var out := []
	for c in cols:
		var faded: Color = c
		faded.a *= alpha
		out.append(faded)
	return out

## Darker echo copies of the line trailing out on both sides. Their
## offsets jump a few times a second, like a glitchy video smear.
func _draw_smear(line: Dictionary, t: float, fs: int, alpha: float, cols: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(floorf(t * smear_rate)))
	for i in range(smear_count, 0, -1):
		var fade := smear_alpha * (1.0 - float(i - 1) / float(smear_count)) * alpha
		var echo_cols := []
		for c in cols:
			var e: Color = (c as Color).darkened(smear_darken)
			e.a = fade
			echo_cols.append(e)
		for side in [-1.0, 1.0]:
			var dx: float = side * (i * smear_spacing + rng.randf_range(-smear_jitter, smear_jitter))
			_draw_line(line, t, fs, Vector2(roundf(dx), 0.0), echo_cols, 0, Color.TRANSPARENT)

## Draws one line centered on x = 0 with its baseline at y = 0 (the
## caller positions it with draw_set_transform), shifted by offset.
## cols = [unsung, sung]; letters turn sung left to right while each
## syllable is sung. outline_px 0 draws no outline.
func _draw_line(line: Dictionary, t: float, fs: int, offset: Vector2, cols: Array, outline_px: int, outline: Color) -> void:
	var syllables: Array = line.syllables
	var widths: Array[float] = []
	var total := 0.0
	for syl in syllables:
		var w := _font.get_string_size(syl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w

	var x := roundf(-total / 2.0) + offset.x
	for i in range(syllables.size()):
		var syl: Dictionary = syllables[i]
		var text: String = syl.text
		var hop := 0.0
		if hop_time > 0.0 and t >= syl.time:
			var k: float = (t - syl.time) / hop_time
			if k < 1.0:
				hop = roundf(hop_height * sin(PI * k))
		var pos := Vector2(x, offset.y - hop)
		if outline_px > 0:
			draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_px, outline)
		var sung_chars := _sung_chars(syllables, i, t)
		if sung_chars >= text.length():
			draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[1])
		elif sung_chars <= 0:
			draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[0])
		else:
			var head := text.substr(0, sung_chars)
			draw_string(_font, pos, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[1])
			var head_w := _font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, pos + Vector2(head_w, 0.0), text.substr(sung_chars), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[0])
		x += widths[i]

## How many letters of syllable i are green at time t: the sweep starts
## when it's sung and takes fill_time (or until the next syllable).
func _sung_chars(syllables: Array, i: int, t: float) -> int:
	var syl: Dictionary = syllables[i]
	var text: String = syl.text
	if t < syl.time:
		return 0
	var dur := fill_time
	if i + 1 < syllables.size():
		dur = minf(dur, syllables[i + 1].time - syl.time)
	if dur <= 0.0:
		return text.length()
	# Spaces don't count as letters to sweep through.
	var letters := text.strip_edges().length()
	var lead := text.length() - text.strip_edges(true, false).length()
	var n := ceili(clampf((t - syl.time) / dur, 0.0, 1.0) * letters)
	return text.length() if n >= letters else lead + n

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
