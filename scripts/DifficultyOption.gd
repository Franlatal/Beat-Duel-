class_name DifficultyOption
extends Resource
## One difficulty a level offers. A single .chart file holds every
## difficulty as its own named track (Moonscraper convention), so this
## just says which track to read and how many lanes to lay out for it --
## no separate chart file needed per difficulty.

## Shown on the difficulty chip, e.g. "Easy", "Normal", "Hard".
@export var label: String = "Normal"

## The track section ChartParser should read, e.g. "EasySingle",
## "MediumSingle", "HardSingle", "ExpertSingle" -- the standard four
## Moonscraper tiers, though a chart can use any track name as long as
## this matches it exactly.
@export var track_name: String = "MediumSingle"

## How many lane columns this difficulty uses. Lower difficulties can
## use fewer lanes than higher ones -- each is its own track section in
## the same chart file, so there's no filtering to do here, just layout.
@export_range(1, 8, 1) var lane_count: int = 3
