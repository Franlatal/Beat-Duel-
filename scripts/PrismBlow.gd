class_name PrismBlow
extends Node2D
## Flowery's Prism Blow, Level 1's answer to a failed segment: a speech
## bubble, a stream of pink spare petals blown from his hand across to the
## note highway, then a white burst with sparkles over the highway and a
## "+N%" MERCY popup.
##
## Call play(). burst is emitted the moment the petals hit, which is when
## the level raises its MERCY meter. Runs on real time, so it finishes even
## if the song is stopped (e.g. the run ends on a full MERCY meter).

signal burst

## Strip of petal frames side by side, all the same size (Flowery's Spare
## petals from the sheet).
@export var petal_texture: Texture2D
@export_range(1, 16, 1) var petal_frames: int = 5
## The sheet's Shockwave frames, drawn white and see-through for the burst.
@export var shockwave_frames: Array[Texture2D] = []
@export var font: Font
## Text in his speech bubble. Empty = no bubble.
@export var bubble_text: String = "PRISM BLOW!"

@export_group("Timing")
## Seconds from play() until the petals leave his hand (his "kiss" frames
## bring his hand to his mouth first).
@export var blow_delay: float = 0.4
## Seconds he keeps blowing petals.
@export var blow_time: float = 0.9
## Seconds from play() until the burst on the highway.
@export var burst_at: float = 1.15
## Seconds the speech bubble stays up.
@export var bubble_time: float = 1.3

const PETAL_SCALE := 4.0
const PETALS_PER_SECOND := 46.0
const PETAL_SPEED := 1150.0
## Seconds a petal takes to fade once it has crossed the highway.
const PETAL_FADE := 0.25
## The Shockwave files are at 2x the art scale, so 2.0 draws them at
## 4 screen px per art px (a bit smaller than his 5, so three fit the highway).
const SHOCKWAVE_SCALE := 2.0
const SHOCKWAVE_FRAME_TIME := 0.07
const SHOCKWAVE_ALPHA := 0.8
const SPARKLE_COUNT := 30
const SPARKLE_LIFE := 0.6
## Size of one art pixel of a sparkle, in screen pixels.
const SPARKLE_PX := 4.0
const SPARKLE_FADED := Color8(176, 176, 176)
const POPUP_COLOR := Color8(255, 248, 64)
const POPUP_TIME := 1.1
const INK := Color8(13, 7, 33)

var _age := INF
var _origin := Vector2.ZERO
var _bubble_anchor := Vector2.ZERO
## Note highway the petals aim at: x range and screen height.
var _left := 0.0
var _right := 0.0
var _height := 1080.0
var _popup_text := ""
var _burst_done := true
var _emitted := 0.0
## {pos, vel, frame, target_x, wobble, phase, faded_at}
var _petals: Array = []
## {pos, born, size}
var _sparkles: Array = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## Starts a Prism Blow from his hand at origin toward the highway between
## highway_left and highway_right. popup_text ("+33%") shows at the burst.
## bubble_anchor is the point the speech bubble's tail points at.
func play(origin: Vector2, bubble_anchor: Vector2, highway_left: float, highway_right: float, height: float, popup_text: String) -> void:
	_origin = origin
	_bubble_anchor = bubble_anchor
	_left = highway_left
	_right = highway_right
	_height = height
	_popup_text = popup_text
	_age = 0.0
	_emitted = 0.0
	_burst_done = false
	_sparkles.clear()

func is_playing() -> bool:
	return _age < burst_at + POPUP_TIME or not _petals.is_empty()

func _process(delta: float) -> void:
	if not is_playing():
		return
	_age += delta
	# Emit petals while he blows.
	if _age >= blow_delay and _age < blow_delay + blow_time:
		_emitted += PETALS_PER_SECOND * delta
		while _emitted >= 1.0:
			_emitted -= 1.0
			_spawn_petal()
	for p in _petals.duplicate():
		p.pos += p.vel * delta
		if p.faded_at < 0.0 and p.pos.x <= p.target_x:
			p.faded_at = _age
		if p.faded_at >= 0.0 and _age - p.faded_at >= PETAL_FADE:
			_petals.erase(p)
	if not _burst_done and _age >= burst_at:
		_burst_done = true
		_spawn_sparkles()
		burst.emit()
	queue_redraw()

func _spawn_petal() -> void:
	var start := _origin + Vector2(randf_range(-10.0, 10.0), randf_range(-24.0, 24.0))
	var target := Vector2(randf_range(_left, _right), randf_range(_height * 0.08, _height * 0.92))
	var vel := (target - start).normalized() * PETAL_SPEED * randf_range(0.85, 1.15)
	_petals.append({
		"pos": start,
		"vel": vel,
		"frame": randi() % maxi(petal_frames, 1),
		# Fade out a little past the point they were aimed at.
		"target_x": target.x - randf_range(40.0, 160.0),
		"wobble": randf_range(6.0, 18.0),
		"phase": randf() * TAU,
		"faded_at": -1.0,
	})

func _spawn_sparkles() -> void:
	for i in range(SPARKLE_COUNT):
		_sparkles.append({
			"pos": Vector2(randf_range(_left - 40.0, _right + 40.0), randf_range(_height * 0.06, _height * 0.94)),
			"born": _age + randf_range(0.0, 0.18),
			"size": randi_range(2, 4),
		})

func _draw() -> void:
	if not is_playing():
		return
	_draw_bubble()
	_draw_shockwaves()
	_draw_petals()
	_draw_sparkles()
	_draw_popup()

func _draw_petals() -> void:
	if petal_texture == null:
		return
	var fw := petal_texture.get_width() / float(maxi(petal_frames, 1))
	var fh := float(petal_texture.get_height())
	var size := Vector2(fw, fh) * PETAL_SCALE
	for p in _petals:
		var alpha := 1.0
		if p.faded_at >= 0.0:
			alpha = 1.0 - clampf((_age - p.faded_at) / PETAL_FADE, 0.0, 1.0)
		# A little sway across the direction of travel.
		var side: Vector2 = Vector2(-p.vel.y, p.vel.x).normalized() * sin(_age * 14.0 + p.phase) * p.wobble
		var pos: Vector2 = (p.pos + side - size / 2.0).round()
		draw_texture_rect_region(petal_texture, Rect2(pos, size), Rect2(p.frame * fw, 0.0, fw, fh), Color(1, 1, 1, alpha))

## Three white blasts over the highway (top, middle, bottom), opening
## toward the left like the petals came from the right.
func _draw_shockwaves() -> void:
	if shockwave_frames.is_empty() or _age < burst_at:
		return
	var i := int((_age - burst_at) / SHOCKWAVE_FRAME_TIME)
	if i >= shockwave_frames.size():
		return
	var tex := shockwave_frames[i]
	var size := tex.get_size() * SHOCKWAVE_SCALE
	var alpha := SHOCKWAVE_ALPHA * (1.0 - float(i) / float(shockwave_frames.size()))
	var cx := (_left + _right) / 2.0
	for k in range(3):
		var cy := _height * (0.22 + 0.28 * k)
		# Negative width flips it so it opens to the left (Godot keeps the
		# position and draws the flipped texture to its right).
		var rect := Rect2(Vector2(cx - size.x / 2.0, cy - size.y / 2.0).round(), Vector2(-size.x, size.y))
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, alpha))

## Four-pointed white sparkles that twinkle, then turn into small grey
## crosses and fade.
func _draw_sparkles() -> void:
	for s in _sparkles:
		var age: float = _age - s.born
		if age < 0.0 or age >= SPARKLE_LIFE:
			continue
		var k := age / SPARKLE_LIFE
		var c: Vector2 = s.pos.round()
		var px := SPARKLE_PX
		if k < 0.6:
			var arm: int = s.size if k < 0.3 else maxi(1, s.size - 1)
			var col := Color(1, 1, 1, 1.0)
			draw_rect(Rect2(c - Vector2(px, px) * 1.5, Vector2(px, px) * 3.0), col)
			for d in range(1, arm + 2):
				var step := float(d) * px
				var w := px if d <= arm else 0.0
				if w <= 0.0:
					break
				draw_rect(Rect2(c + Vector2(-px / 2.0, -1.5 * px - step), Vector2(px, px)), col)
				draw_rect(Rect2(c + Vector2(-px / 2.0, 0.5 * px + step), Vector2(px, px)), col)
				draw_rect(Rect2(c + Vector2(-1.5 * px - step, -px / 2.0), Vector2(px, px)), col)
				draw_rect(Rect2(c + Vector2(0.5 * px + step, -px / 2.0), Vector2(px, px)), col)
		else:
			var col := SPARKLE_FADED
			col.a = 1.0 - (k - 0.6) / 0.4
			var q := px * 0.75
			for d in [-1, 0, 1]:
				draw_rect(Rect2(c + Vector2(d * q, d * q) - Vector2(q, q) / 2.0, Vector2(q, q)), col)
				if d != 0:
					draw_rect(Rect2(c + Vector2(d * q, -d * q) - Vector2(q, q) / 2.0, Vector2(q, q)), col)

func _draw_popup() -> void:
	if font == null or _popup_text == "" or _age < burst_at:
		return
	var k := (_age - burst_at) / POPUP_TIME
	if k >= 1.0:
		return
	var size := 32
	var w := font.get_string_size(_popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2((_left + _right) / 2.0 - w / 2.0, _height * 0.5 - roundf(40.0 * k)).round()
	var col := POPUP_COLOR
	col.a = 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
	var ink := INK
	ink.a = col.a
	draw_string_outline(font, pos, _popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, ink)
	draw_string(font, pos, _popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## White speech bubble left of his head, with its tail pointing at him.
func _draw_bubble() -> void:
	if font == null or bubble_text == "" or _age >= bubble_time:
		return
	var size := 16
	var text_w := font.get_string_size(bubble_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := Vector2(16, 14)
	var box := Vector2(text_w, size) + pad * 2.0
	var tail_tip := _bubble_anchor
	var rect := Rect2((tail_tip - Vector2(box.x + 24.0, box.y * 0.5)).round(), box)
	draw_rect(rect.grow(4.0), INK)
	draw_rect(rect, Color.WHITE)
	var tail := PackedVector2Array([
		Vector2(rect.end.x - 1.0, rect.position.y + box.y * 0.35),
		tail_tip,
		Vector2(rect.end.x - 1.0, rect.position.y + box.y * 0.65),
	])
	draw_colored_polygon(tail, Color.WHITE)
	draw_polyline(PackedVector2Array([tail[0], tail[1], tail[2]]), INK, 4.0)
	draw_string(font, rect.position + Vector2(pad.x, pad.y + size), bubble_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)
