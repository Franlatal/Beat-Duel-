class_name FallingPetals
extends Control
## Pixel petals drifting down the screen, for a battle background.
##
## Draws petal_count petals from a horizontal strip of frames (texture),
## each tinted with one of colors, falling at its own speed, swaying
## side to side and tumbling through the strip's frames. Petals that
## leave the bottom come back in at the top at a new random spot, so it
## never visibly loops.
##
## Put it in the level's BackgroundLayer, above the background rect,
## with a full-rect layout. set_dim_zone() fades the petals that pass
## behind the note highway so they don't get in the way of the notes.

## Strip of petal frames, all the same size, side by side.
@export var texture: Texture2D
## Number of frames in the strip.
@export_range(1, 32, 1) var frame_count: int = 6
@export_range(0, 200, 1) var petal_count: int = 26
## Screen pixels per art pixel.
@export_range(1.0, 12.0, 1.0) var pixel_scale: float = 4.0
## Petal tints. The last one is the rare color (see rare_chance).
@export var colors: Array[Color] = [
	Color8(72, 216, 200),
	Color8(216, 212, 124),
	Color8(168, 112, 208),
	Color8(120, 150, 190),
	Color8(251, 230, 9),
]
## How often a petal takes the last color in the list (0 = never).
@export_range(0.0, 1.0, 0.01) var rare_chance: float = 0.06
@export_range(0.0, 1.0, 0.05) var petal_alpha: float = 0.9

@export_group("Motion")
## Fall speed range, in pixels per second.
@export var fall_speed_min: float = 70.0
@export var fall_speed_max: float = 150.0
## Steady sideways speed, in pixels per second (negative = to the left).
@export var wind: float = 25.0
## Width (pixels) and speed of the side-to-side sway.
@export var sway_amount: float = 28.0
@export var sway_speed: float = 1.6
## Seconds each frame of the tumble lasts.
@export var frame_time: float = 0.14

## Petals between these x positions are drawn at dim_alpha.
var _dim_from := 0.0
var _dim_to := 0.0
var _dim_alpha := 1.0

## One entry per petal: {x, y, speed, phase, color, frame, flip}
var _petals: Array = []
var _time := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_respawn_all)
	_respawn_all()

func _process(delta: float) -> void:
	_time += delta
	var petal := _frame_size() * pixel_scale
	var bottom := size.y + petal.y
	var span := size.x + petal.x * 2.0
	for p in _petals:
		p.y += p.speed * delta
		p.x += wind * delta
		if p.y > bottom:
			_reset_petal(p, false)
		# Carried off one side by the wind: come back in from the other.
		if p.x > size.x + petal.x:
			p.x -= span
		elif p.x < -petal.x:
			p.x += span
	queue_redraw()

## Fades petals whose center is between from_x and to_x (this node's
## own coordinates) to alpha times their usual opacity.
func set_dim_zone(from_x: float, to_x: float, alpha: float) -> void:
	_dim_from = from_x
	_dim_to = to_x
	_dim_alpha = alpha

func _frame_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_width() / float(maxi(frame_count, 1)), texture.get_height())

func _respawn_all() -> void:
	_petals.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for i in range(petal_count):
		var p := {}
		_reset_petal(p, true)
		_petals.append(p)

## Gives a petal a new look and a new start: anywhere on screen when
## anywhere is true (the first frame), otherwise just above the top.
func _reset_petal(p: Dictionary, anywhere: bool) -> void:
	var h := _frame_size().y * pixel_scale
	p.x = randf_range(0.0, size.x)
	p.y = randf_range(-h, size.y) if anywhere else randf_range(-h * 4.0, -h)
	p.speed = randf_range(fall_speed_min, fall_speed_max)
	p.phase = randf() * TAU
	p.frame = randi() % maxi(frame_count, 1)
	p.flip = randf() < 0.5
	p.color = _pick_color()

func _pick_color() -> Color:
	if colors.is_empty():
		return Color.WHITE
	if colors.size() == 1 or randf() < rare_chance:
		return colors[-1]
	return colors[randi() % (colors.size() - 1)]

func _draw() -> void:
	if texture == null or _petals.is_empty():
		return
	var fs := _frame_size()
	var draw_size := fs * pixel_scale
	var frames := maxi(frame_count, 1)
	for p in _petals:
		var x: float = p.x + sin(_time * sway_speed + p.phase) * sway_amount
		var frame := (int(p.frame) + int((_time + p.phase) / maxf(frame_time, 0.01))) % frames
		var col: Color = p.color
		col.a = petal_alpha
		var center_x := x + draw_size.x / 2.0
		if center_x >= _dim_from and center_x <= _dim_to:
			col.a *= _dim_alpha
		# Whole pixels only, so the petals stay crisp.
		var pos := Vector2(roundf(x), roundf(p.y))
		var w := -draw_size.x if p.flip else draw_size.x
		draw_texture_rect_region(texture, Rect2(pos, Vector2(w, draw_size.y)), Rect2(frame * fs.x, 0.0, fs.x, fs.y), col)
