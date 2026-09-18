class_name GameSession
extends RefCounted
## Carries state between scenes. Uses static vars rather than an
## autoload, so there's nothing to register in Project Settings.
##
## LevelSelect writes these just before changing scene; the gameplay
## scene reads them in _ready().

static var current_level: LevelData = null
static var current_difficulty: String = ""

## Set later by the gameplay scene if you want a results screen to
## read them back.
static var last_score: int = 0
static var last_accuracy: float = 0.0

static func start(level: LevelData, difficulty: String) -> void:
	current_level = level
	current_difficulty = difficulty
	last_score = 0
	last_accuracy = 0.0

static func clear() -> void:
	current_level = null
	current_difficulty = ""
	last_score = 0
	last_accuracy = 0.0
