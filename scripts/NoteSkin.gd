class_name NoteSkin
extends Resource
## A custom look for a level's notes, set on a ChartPlayer with
## set_note_skin(). Without one, ChartPlayer draws its default notes
## (note1-4.png circles, plain hold bars, circles on the hit line).
##
## Every texture list is per lane and wraps (lane 4 uses entry 0, ...).
## The art is pixel art: it's drawn with nearest filtering at pixel_scale
## screen pixels per art pixel, so keep pixel_scale a whole number.
##
## - note_textures: tap notes and hold heads.
## - receptor_textures: the targets drawn on the hit line, under the notes.
##   receptor_pressed_textures replace them while that lane's key is held.
## - tail_textures: hold tails. Tiled vertically and scrolled with the note,
##   centred on the lane. tail_end_textures caps the far (top) end.
##   dead_tail_texture / dead_tail_end_texture replace them on a dropped
##   hold (or one a level greyed out).
## - burst_textures: hit effect played on Perfect, Good and Held, a strip of
##   burst_frames frames side by side.
##
## Level 1 uses resources/note_skins/flowery_notes.tres (Sprites/notes_flowery).

## Screen pixels per art pixel.
@export var pixel_scale: int = 3

@export var note_textures: Array[Texture2D] = []
@export var receptor_textures: Array[Texture2D] = []
## Receptors shown while that lane's key is held. Empty = receptor_textures
## drawn at receptor_pressed_brightness.
@export var receptor_pressed_textures: Array[Texture2D] = []
## Brightness of a receptor while its lane key is held (1 = normal).
@export var receptor_pressed_brightness: float = 1.7
## Receptor brightness when its key isn't held.
@export var receptor_idle_brightness: float = 1.0

@export_group("Hold tails")
@export var tail_textures: Array[Texture2D] = []
@export var tail_end_textures: Array[Texture2D] = []
@export var dead_tail_texture: Texture2D
@export var dead_tail_end_texture: Texture2D
## Tail brightness while the hold is being held (1 = normal).
@export var holding_brightness: float = 1.35

@export_group("Hit burst")
@export var burst_textures: Array[Texture2D] = []
@export var burst_frames: int = 6
## Seconds each burst frame is shown.
@export var burst_frame_time: float = 0.045


static func pick(list: Array[Texture2D], lane: int) -> Texture2D:
	if list.is_empty():
		return null
	return list[posmod(lane, list.size())]
