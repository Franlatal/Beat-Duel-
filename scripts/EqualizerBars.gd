extends Control

## Number of bars across the base (design) width. On wider aspect ratios
## more bars are added so each bar keeps the same width.
@export var bar_count: int = 24
@export var bar_color: Color = Color(0.902, 0.133, 0.475, 0.55)
@export var bar_color_alt: Color = Color(0.2, 0.902, 0.98, 0.45)
@export var max_height: float = 90.0
@export var min_height: float = 8.0
## Bars are drawn as stacked blocks this many pixels tall, with a
## 1/3 gap, for an LED-meter look. 0 draws solid bars.
@export var block_size: float = 6.0
## Empty space on each side of a bar, in design pixels.
@export var bar_margin: float = 3.0

var _time: float = 0.0
var _offsets: Array[float] = []

func _ready() -> void:
	_ensure_offsets(bar_count)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _ensure_offsets(count: int) -> void:
	while _offsets.size() < count:
		_offsets.append(randf() * TAU)

func _bars_for_width() -> int:
	var base_w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	if base_w <= 0.0:
		return bar_count
	return maxi(1, roundi(bar_count * size.x / base_w))

func _draw() -> void:
	if bar_count <= 0 or size.x <= 0.0:
		return
	var count := _bars_for_width()
	_ensure_offsets(count)

	# Work in real screen pixels so every block and gap is a whole number
	# of pixels at any window size, instead of being scaled by a
	# fractional factor (which made blocks uneven and shimmer).
	var xf := get_viewport().get_stretch_transform() * get_global_transform_with_canvas()
	var s := xf.get_scale()
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var frac := xf.origin - xf.origin.floor()
	draw_set_transform(-frac / s, 0.0, Vector2.ONE / s)

	var w_px := size.x * s.x
	var h_px := size.y * s.y
	var bar_px := floorf(w_px / float(count))
	var left := floorf((w_px - bar_px * count) / 2.0)
	var margin_px := maxf(1.0, roundf(bar_margin * s.x))
	var bw := maxf(1.0, bar_px - margin_px * 2.0)
	var bottom := floorf(h_px)

	var block_px := 0.0
	var gap_px := 0.0
	if block_size > 0.0:
		block_px = maxf(2.0, roundf(block_size * s.y))
		gap_px = maxf(1.0, roundf(block_px / 3.0))

	for i in range(count):
		var freq := 1.5 + float(i % 5) * 0.35
		var h: float = min_height + (max_height - min_height) * (0.5 + 0.5 * sin(_time * freq + _offsets[i]))
		var h_scr := h * s.y
		var col := bar_color if i % 2 == 0 else bar_color_alt
		var x := left + bar_px * i + margin_px
		if block_px <= 0.0:
			var hh := roundf(h_scr)
			draw_rect(Rect2(x, bottom - hh, bw, hh), col)
			continue
		var blocks := int(h_scr / block_px)
		for b in range(blocks):
			var y := bottom - (b + 1) * block_px
			draw_rect(Rect2(x, y, bw, block_px - gap_px), col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
