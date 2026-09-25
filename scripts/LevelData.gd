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
