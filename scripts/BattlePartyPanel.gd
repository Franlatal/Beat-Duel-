class_name BattlePartyPanel
extends Control
## The party panel along the bottom of a level, in the style of
## Deltarune's battle UI: a black strip with one column per "party
## member", here COMBO (with a bar charging up to the next
## multiplier) and SCORE.
##
## Then CLEAR, the active segment's score as a share of its maximum,
## with a white mark at the pass line (segment_pass_ratio), and the
## player's lives as a Deltarune HP bar. A level can put extra bars under the HP bar with
## add_status_widget() (Level 1's MERCY meter).
##
## Optional (show_player_box, off by default): the active member's box
## (YOU) raised above the strip, with an HP bar and a row of buttons for
## the lane keys plus any extra_actions, each lighting up while held.
##
## Everything is read from the level this node belongs to, so no level
## script has to feed it. Give it the whole screen (full rect anchors):
## it only draws along the bottom edge and ignores the mouse.
##
## Level specific look: override the exported names, colors and icons on
## this node in the level's scene (see Level1.tscn).

## The level to read. Left empty, the nearest LevelBase ancestor is used.
@export var level: LevelBase

@export_group("Layout")
## Screen pixels per art pixel. The pixel UI theme uses 3.
@export var px: float = 3.0
## Height of the black strip, in screen pixels (Deltarune's is 37 art px).
@export var strip_height: float = 78.0
## Height of the raised box of the active member.
@export var active_box_height: float = 204.0
## The pixel font looks crispest at multiples of 8.
@export var name_font_size: int = 16
@export var small_font_size: int = 16
@export var score_font_size: int = 24

@export_group("Colors")
@export var strip_color: Color = Color8(0, 0, 0)
@export var strip_line_color: Color = Color8(51, 32, 51)
@export var text_color: Color = Color8(255, 255, 255)
## The part of a bar that's empty (lost HP), dark red like Deltarune's.
@export var empty_bar_color: Color = Color8(128, 0, 0)
@export var low_color: Color = Color8(255, 255, 0)
@export var damage_color: Color = Color8(255, 32, 32)

@export_group("Player")
## Draw the raised YOU box with HP and key buttons.
@export var show_player_box: bool = false
@export var player_name: String = "YOU"
## Border of the raised box and color of the HP bar.
@export var player_color: Color = Color8(64, 255, 64)
## Drawn left of the name. Empty = a pixel heart (the player's SOUL).
@export var player_icon: Texture2D

@export_group("Combo")
@export var combo_name: String = "COMBO"
## Fill of the bar that charges up to the next multiplier.
@export var combo_color: Color = Color8(255, 0, 255)
@export var combo_icon: Texture2D

@export_group("Score")
@export var score_name: String = "SCORE"
@export var score_color: Color = Color8(255, 216, 0)
@export var score_icon: Texture2D

@export_group("Clear")
@export var clear_name: String = "CLEAR"
## Fill of the CLEAR bar below the pass line, and once it's reached.
@export var clear_color: Color = Color8(255, 160, 64)
@export var clear_passed_color: Color = Color8(0, 255, 255)

@export_group("Buttons")
@export var button_color: Color = Color8(255, 128, 48)
@export var button_pressed_color: Color = Color8(255, 255, 0)
## Input actions shown as extra buttons after the lane keys, for level
## mechanics (Level 1 adds "parry"). Missing actions are skipped.
@export var extra_actions: PackedStringArray = []
## Name shown under each extra button (same order as extra_actions).
@export var extra_action_labels: PackedStringArray = []

## Seconds the box shakes and the "-1" floats after losing HP.
const HURT_TIME := 0.6
## The HP bar in the strip, sized to match the MERCY meter's inline bar.
const HP_BAR_W := 180.0
const HP_BAR_H := 15.0
## Room left of the HP bar for its label ("HP", "MERCY").
const HP_LABEL_W := 96.0
## Where a column's name starts, after its icon.
const NAME_X := 84.0
## Widths of the strip's columns, left to right: HP (+ MERCY), COMBO,
## SCORE, CLEAR (the order the user asked for).
const STRIP_COLUMNS: Array[float] = [360.0, 420.0, 330.0, 360.0]
const COLUMN_GAP := 48.0
const BUTTON_SIZE := 72.0
const BUTTON_GAP := 21.0

const HEART_BITMAP := [
	[0, 1, 1, 0, 1, 1, 0],
	[1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 0],
	[0, 0, 1, 1, 1, 0, 0],
	[0, 0, 0, 1, 0, 0, 0],
]
const NOTE_BITMAP := [
	[0, 0, 0, 1, 1, 0, 0],
	[0, 0, 0, 1, 0, 1, 1],
	[0, 0, 0, 1, 0, 0, 0],
	[0, 0, 0, 1, 0, 0, 0],
	[0, 1, 1, 1, 0, 0, 0],
	[1, 1, 1, 1, 0, 0, 0],
	[0, 1, 1, 0, 0, 0, 0],
]
const STAR_BITMAP := [
	[0, 0, 0, 1, 0, 0, 0],
	[0, 0, 1, 1, 1, 0, 0],
	[1, 1, 1, 1, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 0],
	[0, 0, 1, 1, 1, 0, 0],
	[0, 1, 1, 0, 1, 1, 0],
	[0, 1, 0, 0, 0, 1, 0],
]

var _font: Font
var _last_hp: int = -1
## Seconds since HP last dropped, INF when there's nothing to show.
var _hurt_age: float = INF
var _hurt_amount: int = 0
var _status_widgets: Array[Control] = []

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = get_theme_font("font", "Label")
	if level == null:
		var node := get_parent()
		while node != null and not (node is LevelBase):
			node = node.get_parent()
		level = node as LevelBase

func _process(delta: float) -> void:
	if level != null:
		if _last_hp >= 0 and level.hp < _last_hp:
			_hurt_amount = _last_hp - level.hp
			_hurt_age = 0.0
		_last_hp = level.hp
	if _hurt_age < HURT_TIME:
		_hurt_age += delta
	# Key presses and the level's numbers change every frame anyway.
	queue_redraw()

## Shows `widget` under the HP bar in the player's column, its bar lined
## up with the HP bar. The widget may define inline_label_width: how far
## its own bar starts from its left edge.
func add_status_widget(widget: Control) -> void:
	_status_widgets.append(widget)
	add_child(widget)
	_layout_status_widgets()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_status_widgets()

func _layout_status_widgets() -> void:
	var rows := _hp_rows()
	for i in range(_status_widgets.size()):
		var widget := _status_widgets[i]
		if not is_instance_valid(widget):
			continue
		var bar := rows[mini(i + 1, rows.size() - 1)]
		var label_w: float = widget.get("inline_label_width") if widget.get("inline_label_width") != null else 0.0
		widget.position = Vector2(bar.position.x - label_w, bar.position.y)

func _column_width() -> float:
	return roundf(minf(size.x / 3.0, 480.0))

## Left edge of strip column i (0 HP, 1 COMBO, 2 SCORE, 3 CLEAR); the
## columns are centered as a group.
func _strip_col_x(i: int) -> float:
	var total := COLUMN_GAP * (STRIP_COLUMNS.size() - 1)
	for wd in STRIP_COLUMNS:
		total += wd
	var x := roundf((size.x - total) / 2.0)
	for j in range(i):
		x += STRIP_COLUMNS[j] + COLUMN_GAP
	return x

## The bar rects of the player's column: the HP bar first, then one row
## for each status widget, splitting the strip's height between them.
func _hp_rows() -> Array[Rect2]:
	var x := _strip_col_x(0) + HP_LABEL_W
	var strip_top := size.y - strip_height
	var rows: Array[Rect2] = []
	var count := 1 + _status_widgets.size()
	var row_h := strip_height / float(count)
	for i in range(count):
		var y := strip_top + roundf(row_h * i + (row_h - HP_BAR_H) / 2.0)
		rows.append(Rect2(x, y, HP_BAR_W, HP_BAR_H))
	return rows

func _draw() -> void:
	if _font == null:
		return
	var w := size.x
	var h := size.y
	var col_w := _column_width()
	var strip_top := h - strip_height

	# The strip, with a thin line along its top edge.
	draw_rect(Rect2(0, strip_top, w, strip_height), strip_color)
	draw_rect(Rect2(0, strip_top, w, px), strip_line_color)

	# Text sits a little above the strip's middle.
	var cy := strip_top + roundf(strip_height * 0.45)
	if show_player_box:
		_draw_combo_column(Vector2(0, cy), col_w)
		_draw_score_column(Vector2(col_w, cy), col_w)
		_draw_player_box(Rect2(col_w * 2.0, h - active_box_height, w - col_w * 2.0, active_box_height))
	else:
		_draw_hp_column(Vector2(_strip_col_x(0), strip_top + strip_height / 2.0))
		_draw_combo_column(Vector2(_strip_col_x(1), cy), STRIP_COLUMNS[1])
		_draw_score_column(Vector2(_strip_col_x(2), cy), STRIP_COLUMNS[2])
		_draw_clear_column(Vector2(_strip_col_x(3), cy))

# --- columns --------------------------------------------------------------

## Icon + name on the left, the way every Deltarune column starts.
func _draw_member_head(origin: Vector2, icon: Texture2D, bitmap: Array, icon_col: Color, member_name: String) -> void:
	var icon_size := Vector2(7, 7) * px
	var icon_pos := Vector2(origin.x + 48, origin.y - icon_size.y / 2.0)
	if icon != null:
		var tex_size := Vector2(icon.get_size()) * px
		draw_texture_rect(icon, Rect2(Vector2(icon_pos.x, origin.y - tex_size.y / 2.0), tex_size), false)
	else:
		_draw_bitmap(bitmap, icon_pos, px, icon_col)
	_draw_text(Vector2(origin.x + NAME_X, origin.y + name_font_size / 2.0), member_name, name_font_size, text_color)

## The "HP" style label, the numbers above the bar, and the bar.
func _draw_member_bar(origin: Vector2, col_w: float, tag: String, tag_col: Color, numbers: String, numbers_col: Color, fill: float, fill_col: Color, bar_override := Rect2()) -> void:
	var bar := bar_override if bar_override.size != Vector2.ZERO else _bar_rect(origin, col_w)
	_draw_text(Vector2(bar.position.x - 12 - _text_width(tag, small_font_size), bar.end.y), tag, small_font_size, tag_col)
	_draw_text(Vector2(bar.end.x - _text_width(numbers, small_font_size), bar.position.y - px * 2.0), numbers, small_font_size, numbers_col)
	draw_rect(bar, empty_bar_color)
	var fill_w := roundf(bar.size.x * clampf(fill, 0.0, 1.0) / px) * px
	if fill_w > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), fill_col)

func _bar_rect(origin: Vector2, col_w: float) -> Rect2:
	var bar_w := 180.0
	var bar_h := px * 6.0
	return Rect2(origin.x + col_w - 48.0 - bar_w, origin.y, bar_w, bar_h)

## A bar placed right after a column's name (and its "x4" style tag),
## instead of at the column's right end.
func _bar_after_name(origin: Vector2, member_name: String, tag: String) -> Rect2:
	var x := origin.x + NAME_X + _text_width(member_name, name_font_size) + 24.0 + _text_width(tag, small_font_size) + 12.0
	return Rect2(x, origin.y, 180.0, px * 6.0)

func _draw_combo_column(origin: Vector2, col_w: float) -> void:
	_draw_member_head(origin, combo_icon, NOTE_BITMAP, combo_color, combo_name)
	var combo := 0
	var mult := 1
	var max_mult := 1
	var step := 1
	if level != null:
		combo = level.combo
		mult = level.multiplier
		max_mult = level.max_multiplier
		step = maxi(1, level.combo_per_multiplier_step)
	# The bar charges up to the next multiplier, and stays full at the top one.
	var fill := 1.0 if mult >= max_mult else float(combo % step) / float(step)
	var tag_col := low_color if mult > 1 else text_color
	var tag := "x%d" % mult
	_draw_member_bar(origin, col_w, tag, tag_col, str(combo), text_color, fill, low_color if mult >= max_mult else combo_color, _bar_after_name(origin, combo_name, "x%d" % max_mult))

func _draw_score_column(origin: Vector2, col_w: float) -> void:
	_draw_member_head(origin, score_icon, STAR_BITMAP, score_color, score_name)
	var score := level.score if level != null else 0
	var digits := "%06d" % score
	var x := origin.x + NAME_X + _text_width(score_name, name_font_size) + 24.0
	# vertically centered on the name
	_draw_text(Vector2(x, origin.y + name_font_size / 2.0 + (score_font_size - name_font_size) / 2.0), digits, score_font_size, score_color)

## CLEAR: the active segment's progress (level.get_segment_progress(),
## 0..1) as a bar, a white mark at the pass line, and "55%" after it.
## Orange until the pass line, cyan from there.
func _draw_clear_column(origin: Vector2) -> void:
	var value := 0.0
	var active := false
	var pass_ratio := 0.7
	if level != null:
		pass_ratio = level.segment_pass_ratio
		if level.has_method("get_segment_progress"):
			value = clampf(float(level.call("get_segment_progress")), 0.0, 1.0)
		var idx = level.get("_active_segment_record_idx")
		active = idx != null and int(idx) >= 0
	var passed := active and value >= pass_ratio - 0.0001
	var fill_col := clear_passed_color if passed else clear_color
	_draw_text(Vector2(origin.x, origin.y + name_font_size / 2.0), clear_name, name_font_size, text_color)
	var bar := Rect2(origin.x + _text_width(clear_name, name_font_size) + 24.0, origin.y - px * 3.0, 180.0, px * 6.0)
	draw_rect(bar, empty_bar_color)
	var fill_w := roundf(bar.size.x * (value if active else 0.0) / px) * px
	if fill_w > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), fill_col)
	# the pass line: a white notch sticking out above and below the bar
	var mark_x := bar.position.x + roundf(bar.size.x * pass_ratio / px) * px
	draw_rect(Rect2(mark_x - px * 0.5, bar.position.y - px * 2.0, px, bar.size.y + px * 4.0), text_color)
	var pct := "%d%%" % roundi(value * 100.0) if active else "--%"
	_draw_text(Vector2(bar.end.x + 12.0, origin.y + name_font_size / 2.0), pct, small_font_size, fill_col if passed else text_color)

## The player's lives as a Deltarune HP bar: "HP", the bar, and "2/ 3"
## after it (no icon or name, the user asked for just the bar). Shakes and shows "-1" when a life is lost.
func _draw_hp_column(origin: Vector2) -> void:
	var shake := 0.0
	if _hurt_age < HURT_TIME * 0.5:
		shake = roundf(sin(_hurt_age * 90.0) * 2.0) * px
	var hp := 3
	var max_hp := 3
	if level != null:
		hp = maxi(level.hp, 0)
		max_hp = maxi(level.max_hp, 1)
	var bar: Rect2 = _hp_rows()[0]
	bar.position.x += shake
	var numbers_col := text_color
	if hp <= 0:
		numbers_col = damage_color
	elif hp == 1 and max_hp > 1:
		numbers_col = low_color
	var text_y := bar.end.y
	_draw_text(Vector2(bar.position.x - 12 - _text_width("HP", small_font_size), text_y), "HP", small_font_size, text_color)
	draw_rect(bar, empty_bar_color)
	var fill_w := roundf(bar.size.x * float(hp) / float(max_hp) / px) * px
	if fill_w > 0.0:
		draw_rect(Rect2(bar.position, Vector2(fill_w, bar.size.y)), player_color)
	_draw_text(Vector2(bar.end.x + 12, text_y), "%d/ %d" % [hp, max_hp], small_font_size, numbers_col)
	if _hurt_age < HURT_TIME:
		var k := _hurt_age / HURT_TIME
		var col := damage_color
		col.a = 1.0 - k * k
		_draw_text(Vector2(bar.position.x + 12, bar.position.y - px - roundf(24.0 * k)), "-%d" % _hurt_amount, name_font_size, col)

func _draw_player_box(box: Rect2) -> void:
	# Losing HP shakes the box sideways for a moment.
	if _hurt_age < HURT_TIME * 0.5:
		box.position.x += roundf(sin(_hurt_age * 90.0) * 2.0) * px
	var border := px * 2.0
	draw_rect(box, strip_color)
	draw_rect(Rect2(box.position, Vector2(box.size.x, border)), player_color)
	draw_rect(Rect2(box.position, Vector2(border, box.size.y)), player_color)
	draw_rect(Rect2(Vector2(box.end.x - border, box.position.y), Vector2(border, box.size.y)), player_color)

	var hp := 3
	var max_hp := 3
	if level != null:
		hp = maxi(level.hp, 0)
		max_hp = maxi(level.max_hp, 1)
	var head := Vector2(box.position.x, box.position.y + 54.0)
	_draw_member_head(head, player_icon, HEART_BITMAP, Color8(255, 0, 0), player_name)
	var numbers_col := text_color
	if hp <= 0:
		numbers_col = damage_color
	elif hp == 1 and max_hp > 1:
		numbers_col = low_color
	_draw_member_bar(head, box.size.x, "HP", text_color, "%d/ %d" % [hp, max_hp], numbers_col, float(hp) / float(max_hp), player_color)

	if _hurt_age < HURT_TIME:
		var k := _hurt_age / HURT_TIME
		var bar := _bar_rect(head, box.size.x)
		var col := damage_color
		col.a = 1.0 - k * k
		_draw_text(Vector2(bar.position.x + 12, bar.position.y - px * 2.0 - roundf(24.0 * k)), "-%d" % _hurt_amount, name_font_size, col)

	_draw_buttons(Rect2(box.position.x + border, box.position.y + 84.0, box.size.x - border * 2.0, box.size.y - 84.0))

# --- buttons --------------------------------------------------------------

func _draw_buttons(area: Rect2) -> void:
	var actions: Array[StringName] = []
	var labels: Array[String] = []
	var lanes := 4
	if level != null and not level.lane_positions.is_empty():
		lanes = level.lane_positions.size()
	for i in range(lanes):
		actions.append(StringName("lane_%d" % i))
		labels.append("")
	for i in range(extra_actions.size()):
		if InputMap.has_action(extra_actions[i]):
			actions.append(StringName(extra_actions[i]))
			labels.append(extra_action_labels[i] if i < extra_action_labels.size() else extra_actions[i].to_upper())

	# Thin inner lines down both sides, like Deltarune's box.
	var line_top := area.position.y + px
	draw_rect(Rect2(area.position.x + px * 4.0, line_top, px, area.end.y - line_top), player_color)
	draw_rect(Rect2(area.end.x - px * 5.0, line_top, px, area.end.y - line_top), player_color)

	var total := actions.size() * BUTTON_SIZE + maxi(actions.size() - 1, 0) * BUTTON_GAP
	var x := area.position.x + roundf((area.size.x - total) / 2.0)
	var y := area.position.y + px
	for i in range(actions.size()):
		var pressed := Input.is_action_pressed(actions[i])
		var col := button_pressed_color if pressed else button_color
		var r := Rect2(x, y, BUTTON_SIZE, BUTTON_SIZE)
		if pressed:
			var glow := col
			glow.a = 0.25
			draw_rect(r, glow)
		_draw_frame(r, px, col)
		_draw_key_glyph(r, actions[i], col)
		if labels[i] != "":
			var label_col := col if pressed else Color(col, 0.75)
			var lw := _text_width(labels[i], small_font_size)
			_draw_text(Vector2(r.get_center().x - lw / 2.0, r.end.y + px + small_font_size), labels[i], small_font_size, label_col)
		x += BUTTON_SIZE + BUTTON_GAP

## The first key bound to the action: an arrow for arrow keys, otherwise
## the key's name (shortened to fit).
func _draw_key_glyph(r: Rect2, action: StringName, col: Color) -> void:
	var keycode := _first_keycode(action)
	var c := r.get_center()
	var s := px * 5.0
	match keycode:
		KEY_LEFT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(s, -s), c + Vector2(s, s)]), col)
			return
		KEY_RIGHT:
			draw_colored_polygon(PackedVector2Array([c + Vector2(s, 0), c + Vector2(-s, -s), c + Vector2(-s, s)]), col)
			return
		KEY_UP:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(-s, s), c + Vector2(s, s)]), col)
			return
		KEY_DOWN:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, s), c + Vector2(-s, -s), c + Vector2(s, -s)]), col)
			return
	var text := "?" if keycode == KEY_NONE else OS.get_keycode_string(keycode).to_upper()
	if text.length() > 3:
		text = text.substr(0, 3)
	var size_px := name_font_size if text.length() == 1 else small_font_size
	var tw := _text_width(text, size_px)
	_draw_text(Vector2(c.x - tw / 2.0, c.y + size_px / 2.0), text, size_px, col)

func _first_keycode(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for ev in InputMap.action_get_events(action):
		var key := ev as InputEventKey
		if key == null:
			continue
		if key.keycode != KEY_NONE:
			return key.keycode
		if key.physical_keycode != KEY_NONE:
			return DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
	return KEY_NONE

# --- drawing helpers ------------------------------------------------------

func _draw_frame(r: Rect2, t: float, col: Color) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, t)), col)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - t), Vector2(r.size.x, t)), col)
	draw_rect(Rect2(r.position, Vector2(t, r.size.y)), col)
	draw_rect(Rect2(Vector2(r.end.x - t, r.position.y), Vector2(t, r.size.y)), col)

func _draw_bitmap(bitmap: Array, pos: Vector2, cell: float, col: Color) -> void:
	for row_i in range(bitmap.size()):
		var row: Array = bitmap[row_i]
		for col_i in range(row.size()):
			if row[col_i] != 0:
				draw_rect(Rect2(pos + Vector2(col_i, row_i) * cell, Vector2(cell, cell)), col)

func _text_width(text: String, font_size: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func _draw_text(pos: Vector2, text: String, font_size: int, col: Color) -> void:
	draw_string(_font, pos.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
