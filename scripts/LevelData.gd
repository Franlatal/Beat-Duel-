class_name LevelData
extends Resource
## Describes one playable level. Create one .tres per level under
## res://resources/levels/ and register it in LevelSelect.gd's
## LEVEL_PATHS list.
##
## A level that needs exclusive mechanics can set scene_override to its
## own scene; everything else uses the shared gameplay scene.

## Short stable identifier, used later for save data / unlocks.
@export var id: StringName = &""

@export var title: String = "Untitled"
@export var artist: String = ""

## The difficulties this level offers. Put whatever numbers you want
## here -- [1] for a single-difficulty level, [1, 3, 6] for a level the
## player can pick between. The level select shows one chip per entry.
@export var difficulties: Array[String] = ["Normal"]

## Which entry of difficulties starts selected (0 = the first one).
@export var default_difficulty_index: int = 0

@export var bpm: float = 120.0

@export var music: AudioStream

@export_multiline var description: String = ""

## Leave empty to use the shared gameplay scene. Set this only for
## levels that need their own scene because of exclusive features.
@export var scene_override: PackedScene

@export var unlocked: bool = true

## Always returns at least one difficulty, sorted, so the UI never has
## to handle an empty list.
func get_difficulties() -> Array[String]:
	if difficulties.is_empty():
		var fallback: Array[String] = ["Normal"]
		return fallback
	return difficulties.duplicate()   # declared order, no sorting

func get_default_difficulty() -> String:
	var list := get_difficulties()
	return list[clampi(default_difficulty_index, 0, list.size() - 1)]
