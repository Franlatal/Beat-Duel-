extends Control

@export var bar_count: int = 24
@export var bar_color: Color = Color(0.902, 0.133, 0.475, 0.55)
@export var bar_color_alt: Color = Color(0.2, 0.902, 0.98, 0.45)
@export var max_height: float = 90.0
@export var min_height: float = 8.0
## Bars are drawn as stacked blocks this many pixels tall, with a
## 1/3 gap, for an LED-meter look. 0 draws solid bars.
@export var block_size: float = 6.0

var _time: float = 0.0
var _offsets: Array[float] = []

func _ready() -> void:
	_offsets.clear()
	for i in range(bar_count):
		_offsets.append(randf() * TAU)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	if bar_count <= 0 or size.x <= 0.0:
		return
	var w := size.x / float(bar_count)
	for i in range(bar_count):
		var freq := 1.5 + float(i % 5) * 0.35
		var h: float = min_height + (max_height - min_height) * (0.5 + 0.5 * sin(_time * freq + _offsets[i]))
		var col := bar_color if i % 2 == 0 else bar_color_alt
		var x := floorf(i * w) + 3.0
		var bw := floorf(w) - 6.0
		if block_size <= 0.0:
			draw_rect(Rect2(x, size.y - h, bw, h), col)
			continue
		var gap := maxf(1.0, floorf(block_size / 3.0))
		var blocks := int(h / block_size)
		for b in range(blocks):
			var y := size.y - (b + 1) * block_size
			draw_rect(Rect2(x, y, bw, block_size - gap), col)
