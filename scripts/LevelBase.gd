class_name LevelBase
extends ChartPlayer
## Shared behavior for every level scene. Extend this for each level's
## own scene script (see scripts/levels/).
##
## - Reads which level/difficulty was picked in level select from
##   GameSession and configures ChartPlayer's track_name and
##   lane_positions to match, before the chart is parsed.
## - Adds a themed back button.
## - Calls _setup_level() once ChartPlayer has finished setting up
##   audio/notes -- override it per level for anything that needs to
##   run at the start. Empty by default.
## - _on_segment_changed(index), inherited from ChartPlayer, is the hook
##   for level-exclusive events tied to a specific chart segment --
##   override it per level. Empty by default.

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelect.tscn"
const UI_THEME := preload("res://themes/pixel_theme.tres")

## Horizontal spacing between lane columns, in pixels.
const LANE_SPACING := 140.0

## Leftward offset from dead center so lanes sit slightly left.
const LANE_LEFT_OFFSET := 75.0

## Maps lane count to which input actions to use.
## 2 lanes → Left + Right (spatially outermost keys).
## 3 lanes → Left + Up + Right (spread across 3 keys).
## 4 lanes → Left + Up + Down + Right (all 4 keys).
## For > 4, they just get lane_0 … lane_N sequentially.
const LANE_KEY_MAP := {
	2: [0, 3],       # lane_0 (Left), lane_3 (Right)
	3: [0, 1, 3],    # lane_0 (Left), lane_1 (Up), lane_3 (Right)
	4: [0, 1, 2, 3], # lane_0 (Left), lane_1 (Up), lane_2 (Down), lane_3 (Right)
}

var level: LevelData
var difficulty: DifficultyOption

func _ready() -> void:
	level = GameSession.current_level
	difficulty = GameSession.current_difficulty

	if difficulty != null:
		track_name = difficulty.track_name
		lane_positions = _lane_positions_for(difficulty.lane_count)
	else:
		# Direct-run (F6) fallback -- no GameSession data yet, so this
		# scene's own Inspector values for track_name/lane_positions are
		# used as-is.
		push_warning("LevelBase: no GameSession data -- using this scene's Inspector defaults.")

	_setup_back_button()
	super._ready()   # ChartPlayer._ready(): parses the chart, starts audio/notes
	_setup_level()

func _lane_positions_for(count: int) -> Array:
	var width := get_viewport().get_visible_rect().size.x
	var center := width / 2.0 - LANE_LEFT_OFFSET
	var start := center - LANE_SPACING * (count - 1) / 2.0
	var positions: Array = []
	for i in range(count):
		positions.append(start + LANE_SPACING * i)
	return positions

## Override ChartPlayer's lane -> input action mapping to spread keys for
## 2/3 lanes. ChartPlayer uses this both for presses and for checking
## whether a hold note's key is still held down.
func _action_for_lane(lane_index: int) -> String:
	# key_map[chart_lane] = action_index
	var key_map: Array = LANE_KEY_MAP.get(lane_positions.size(), [])
	if lane_index < key_map.size():
		return "lane_%d" % key_map[lane_index]
	# Fallback: sequential mapping for unexpected lane counts
	return "lane_%d" % lane_index

func _setup_back_button() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.theme = UI_THEME
	back_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	back_button.position = Vector2(24, 24)
	back_button.pressed.connect(_on_back_pressed)
	layer.add_child(back_button)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

## Override per level for one-time setup once the chart/audio pipeline is
## running (e.g. spawning level-specific scenery). Empty by default.
func _setup_level() -> void:
	pass
