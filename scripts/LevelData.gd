class_name LevelData
extends Resource
## Describes one playable level. Create one .tres per level under
## res://resources/levels/ and register it in LevelSelect.gd's
## LEVEL_PATHS list.

## Short stable identifier, used later for save data / unlocks.
@export var id: StringName = &""

@export var title: String = "Untitled"
@export var artist: String = ""

## The difficulties this level offers, in the order they should be
## shown as chips. Each carries its own chart track name and lane
## count -- see DifficultyOption.gd.
@export var difficulties: Array[DifficultyOption] = []

## Which entry of difficulties starts selected (0 = the first one).
@export var default_difficulty_index: int = 0

## Shown on the level-select card. Purely informational -- actual note
## timing comes from the chart's own tempo track, not this value.
@export var bpm: float = 120.0

@export_multiline var description: String = ""

## Every level is its own scene, built on LevelBase.
@export var level_scene: PackedScene

@export var unlocked: bool = true

@export_group("Level select preview")
## Song clip played while this level is highlighted on the level select
## screen. Leave empty to use the audio_path of level_scene's song.
@export_file("*.ogg", "*.mp3", "*.wav") var preview_audio_path: String = ""
## Where the preview starts, in seconds into the song. -1 = automatic
## (about a third of the way in).
@export var preview_start: float = -1.0
## How long the preview plays before looping back to preview_start, in
## seconds. 0 = until the end of the song.
@export var preview_length: float = 20.0
## Volume adjustment for this level's preview, in decibels.
@export_range(-24.0, 12.0, 0.5) var preview_volume_db: float = 0.0
@export_group("")

## Always returns at least one difficulty, in declared order, so the UI
## never has to handle an empty list.
func get_difficulties() -> Array[DifficultyOption]:
	if difficulties.is_empty():
		var fallback: Array[DifficultyOption] = [DifficultyOption.new()]
		return fallback
	return difficulties.duplicate()

func get_default_difficulty() -> DifficultyOption:
	var list := get_difficulties()
	return list[clampi(default_difficulty_index, 0, list.size() - 1)]

## The song file the level select preview plays: preview_audio_path if
## set, otherwise the audio_path the level scene gives its ChartPlayer.
func get_preview_audio_path() -> String:
	if preview_audio_path != "":
		return preview_audio_path
	if level_scene == null:
		return ""
	# Read the property straight out of the scene file instead of
	# instancing the whole level. Inherited scenes (Level1.tscn builds on
	# BaseLevel.tscn) store their override on the root node, node 0.
	var state := level_scene.get_state()
	while state != null:
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"audio_path":
				return str(state.get_node_property_value(0, i))
		var base := state.get_node_instance(0)
		state = null if base == null else base.get_state()
	return ""
