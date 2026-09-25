extends Control

@export var bar_count: int = 24
@export var bar_color: Color = Color(0.902, 0.133, 0.475, 0.55)
@export var bar_color_alt: Color = Color(0.2, 0.902, 0.98, 0.45)
@export var max_height: float = 90.0
@export var min_height: float = 8.0

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
		var rect := Rect2(i * w + 2.0, size.y - h, w - 4.0, h)
		var col := bar_color if i % 2 == 0 else bar_color_alt
		draw_rect(rect, col)
