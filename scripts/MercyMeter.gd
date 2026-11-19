class_name MercyMeter
extends Control
## A MERCY meter in the style of Deltarune's: the word MERCY, a
## percentage, and an orange-red bar that fills with yellow from the left.
##
## With inline on, it's one row to sit in the bottom party strip (see
## BattlePartyPanel.add_status_widget): "MERCY", the bar, then "50%".
##
## Call set_value() with 0..1. The fill slides to the new value, the bar
## flashes, and a "+50%" pops up and floats away. The font comes from
## the theme this control inherits, so add it under the level's HUDRoot.

@export var bar_size: Vector2 = Vector2(200, 20)
## The pixel font looks crispest at multiples of 8.
@export var font_size: int = 16
@export var title: String = "MERCY"
@export var back_color: Color = Color8(236, 64, 28)
@export var fill_color: Color = Color8(255, 248, 64)
@export var text_color: Color = Color8(248, 252, 252)
@export var outline_color: Color = Color8(13, 7, 33)
## Seconds the fill takes to slide to a new value.
@export var fill_time: float = 0.6
## Seconds the "+N%" popup and the flash last.
@export var popup_time: float = 1.2

@export_group("Inline")
## One row: title, bar, percentage. For the bottom party strip.
@export var inline: bool = false:
	set(v):
		inline = v
		_update_size()
## Where the bar starts, from the left edge; the title is right-aligned
## before it.
@export var inline_label_width: float = 96.0
@export var inline_bar_size: Vector2 = Vector2(180, 15)

const BORDER := 4.0
const GAP := 8.0

var value: float = 0.0
var _shown: float = 0.0
var _slide_from: float = 0.0
var _slide_t: float = 1.0
## Seconds since the last increase, INF when there's nothing to show.
var _popup_age: float = INF
var _popup_text: String = ""
var _font: Font

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = get_theme_font("font", "Label")
	_update_size()

func _update_size() -> void:
	if inline:
		custom_minimum_size = Vector2(inline_label_width + inline_bar_size.x + 12.0 + font_size * 4.0, inline_bar_size.y)
	else:
		custom_minimum_size = Vector2(bar_size.x + BORDER * 2.0, font_size + GAP + bar_size.y + BORDER * 2.0)
	size = custom_minimum_size

## Sets the meter (0 = empty, 1 = full). With animate, the fill slides
## there and, if it went up, the bar flashes and shows how much was added.
func set_value(new_value: float, animate: bool = true) -> void:
	new_value = clampf(new_value, 0.0, 1.0)
	var gained := new_value - value
	value = new_value
	if not animate:
		_shown = value
		_slide_t = 1.0
	else:
		_slide_from = _shown
		_slide_t = 0.0
		if gained > 0.0:
			_popup_text = "+%d%%" % roundi(gained * 100.0)
			_popup_age = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	var busy := false
	if _slide_t < 1.0:
		_slide_t = minf(1.0, _slide_t + delta / maxf(fill_time, 0.01))
		var eased := 1.0 - (1.0 - _slide_t) * (1.0 - _slide_t)
		_shown = lerpf(_slide_from, value, eased)
		busy = true
	if _popup_age < popup_time:
		_popup_age += delta
		busy = true
	if busy:
		queue_redraw()

func _draw() -> void:
	if _font == null:
		return
	if inline:
		_draw_inline()
		return
	var text_y := float(font_size)   # baseline of the title row
	_draw_text(Vector2(0, text_y), title, text_color)
	var pct := "%d%%" % roundi(_shown * 100.0)
	var pct_w := _font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_draw_text(Vector2(bar_size.x + BORDER * 2.0 - pct_w, text_y), pct, fill_color if value > 0.0 else text_color)

	var top := font_size + GAP
	draw_rect(Rect2(0, top, bar_size.x + BORDER * 2.0, bar_size.y + BORDER * 2.0), outline_color)
	var bar := Rect2(BORDER, top + BORDER, bar_size.x, bar_size.y)
	draw_rect(bar, back_color)
	# Whole pixels of the 4px grid, so the fill edge stays chunky.
	var fill_w := minf(bar.size.x, roundf(bar.size.x * _shown / 4.0) * 4.0)
	if fill_w > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), fill_color)

	if _popup_age < popup_time:
		var k := _popup_age / popup_time
		# flash over the bar, fading in the first third
		var flash := clampf(1.0 - k * 3.0, 0.0, 1.0)
		if flash > 0.0:
			draw_rect(bar, Color(1, 1, 1, flash * 0.8))
		var col := fill_color
		col.a = 1.0 - k * k
		var pos := Vector2(bar.position.x, bar.end.y + BORDER + font_size + 20.0 - roundf(16.0 * k))
		_draw_text(pos, _popup_text, col)

func _draw_inline() -> void:
	var bar := Rect2(Vector2(inline_label_width, 0), inline_bar_size)
	var base_y := bar.end.y
	var title_w := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_draw_text(Vector2(bar.position.x - 12.0 - title_w, base_y), title, text_color)
	draw_rect(bar, back_color)
	var fill_w := minf(bar.size.x, roundf(bar.size.x * _shown / 3.0) * 3.0)
	if fill_w > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), fill_color)
	var pct := "%d%%" % roundi(_shown * 100.0)
	_draw_text(Vector2(bar.end.x + 12.0, base_y), pct, fill_color if value > 0.0 else text_color)
	if _popup_age < popup_time:
		var k := _popup_age / popup_time
		var flash := clampf(1.0 - k * 3.0, 0.0, 1.0)
		if flash > 0.0:
			draw_rect(bar, Color(1, 1, 1, flash * 0.8))
		var col := fill_color
		col.a = 1.0 - k * k
		# floats up out of the strip
		_draw_text(Vector2(bar.position.x + 12.0, bar.position.y - 12.0 - roundf(32.0 * k)), _popup_text, col)

func _draw_text(pos: Vector2, text: String, col: Color) -> void:
	var outline := outline_color
	outline.a = col.a
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, outline)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
