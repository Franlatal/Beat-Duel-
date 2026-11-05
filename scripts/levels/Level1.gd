extends LevelBase
## Level 1 (Flower Man).
##
## Exclusive event "jarona": every "E jarona" in the played chart track
## is an attack that lands exactly on the event's tick. The boss leaves
## his spot, waits beside the note highway for jarona_windup_beats, then
## dashes sideways (across the lanes, not down them) into the highway,
## hitting it at the edge of the rightmost lane, the one closest to him.
## Press the parry key (Z by default, rebindable in Options > Controls)
## as he lands to block it. Letting it land, or pressing during the dash
## but too early, costs jarona_damage HP. Presses before the dash starts
## are ignored, so there's no penalty for reacting to the windup.
##
## Notes whose hit time falls from shield_before_dash_beats before the
## dash until shield_after_hit_beats after the attack lands are shielded: they're greyed out as soon as
## they appear, and hit automatically (scored as Perfect, holds as Held)
## when they reach the hit line, so the player only has to think about
## the parry and can see in advance which notes they still have to play.
##
## The attacker is the boss himself, using his SpriteFrames (set on
## BossAnchor/BossSprite in Level1.tscn): "idle" while winding up, a
## random one of "jarona_punch" / "jarona_fair" for the dash, and
## "deflected" when parried. He turns dark blue while attacking, leaves
## fading afterimages behind his dash, and goes back to normal when
## parried. parry_sound plays on a parry. One of jarona_sounds, also
## picked at random, plays as the dash starts.
##
## A parry flashes an orange outline around the note highway and pops a
## small "PARRY!" where he struck. A hit shows the HUD banner and costs HP.

const JARONA_EVENT := "jarona"
const PARRY_ACTION := &"parry"

enum AttackState { WAITING, WINDUP, PARRIED, HIT, DONE }

@export_group("Jarona attack")
## How long the windup lasts before the attack lands, in beats.
@export_range(1.0, 8.0, 0.5) var jarona_windup_beats: float = 3.0
## The last part of the windup, in beats, where the boss dashes into the
## highway. Parry presses only count from here on.
@export_range(0.25, 4.0, 0.25) var jarona_dash_beats: float = 1.0
## Seconds either side of the landing that still count as a parry.
@export_range(0.03, 0.4, 0.01) var parry_window: float = 0.15
## Sounds for the dash; one is picked at random each attack.
@export var jarona_sounds: Array[AudioStream] = []
## Plays on a successful parry. Left empty, the level's HitSFX plays.
@export var parry_sound: AudioStream
## Plays when the attack lands. Left empty, the level's SegmentFailSFX plays.
@export var hurt_sound: AudioStream
## Volume of each sound, in decibels (0 = as recorded, -6 = about half as loud).
@export_range(-40.0, 12.0, 0.5) var jarona_sounds_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5) var parry_sound_volume_db: float = 0.0
@export_range(-40.0, 12.0, 0.5) var hurt_sound_volume_db: float = 0.0
## Note shield: starts this many beats before the dash, and lasts this
## many beats after the attack lands.
@export_range(0.0, 4.0, 0.25) var shield_before_dash_beats: float = 0.5
@export_range(0.0, 4.0, 0.25) var shield_after_hit_beats: float = 0.75
## Lives lost when an attack lands.
@export_range(1, 10, 1) var jarona_damage: int = 1

## How far left of the boss's center he waits for his dash.
const LAUNCH_OFFSET_FROM_BOSS := 260.0
## Seconds the boss takes to move from his spot to that point.
const EMERGE_TIME := 0.25
## Seconds the parry / hit reaction lasts after an attack resolves.
const AFTERMATH_TIME := 0.6
const ATTACK_COLOR := Color(1.0, 0.2, 0.3)
const PARRY_COLOR := Color(1.0, 0.55, 0.1)
## Seconds the orange parry outline and "PARRY!" pop take to fade.
const PARRY_FLASH_TIME := 0.5
## Color he turns while attacking, and how long the fade into it takes.
const ATTACK_TINT := Color(0.1, 0.2, 0.8)
const TINT_IN_TIME := 0.2
## How shielded notes look (same as a missed note's greyed-out head).
const SHIELDED_NOTE_MODULATE := Color(0.45, 0.45, 0.45, 0.8)
## Dash afterimages: one is left behind every AFTERIMAGE_INTERVAL seconds,
## starting at AFTERIMAGE_ALPHA and fading out over AFTERIMAGE_LIFE.
const AFTERIMAGE_INTERVAL := 0.03
const AFTERIMAGE_LIFE := 0.25
const AFTERIMAGE_ALPHA := 0.6
## Recolors a sprite toward tint_color by tint (0 = untouched), keeping
## its shading so the pose still reads.
const TINT_SHADER_CODE := """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform float tint : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = COLOR;   // already texture * modulate in Godot 4
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, tint_color.rgb * (0.2 + 0.9 * lum), tint);
	COLOR = c;
}
"""
## Sprite offset (texture pixels) for the dash poses, so his fist or
## foot, not his middle, is what reaches the highway.
const DASH_SPRITE_OFFSET := Vector2(26, 0)
## Dash poses; each attack uses one of these that the boss's frames have.
const JARONA_POSES: Array[StringName] = [&"jarona_punch", &"jarona_fair"]

## One entry per jarona in the chart:
## {time, start, dash_start, state, resolved_at, resolved_pos, sprite, pose, dashing}
var _attacks: Array = []
var _attack_layer: Node2D
## The boss's frames when they include a jarona pose, else null.
var _jarona_frames: SpriteFrames
## The dash poses _jarona_frames actually has.
var _jarona_poses: Array[StringName] = []
var _tint_shader: Shader
## Shared fully-tinted material for the afterimages.
var _afterimage_material: ShaderMaterial
## Fading afterimages: [{node, born}]
var _afterimages: Array = []
## Song time of the last parry (for the outline flash), -INF if none yet.
var _parry_flash_at := -INF
var _parry_popup: Label

func _setup_level() -> void:
	_attack_layer = Node2D.new()
	_attack_layer.name = "JaronaLayer"
	_attack_layer.z_index = 10   # above notes
	add_child(_attack_layer)
	_attack_layer.draw.connect(_draw_parry_flash)
	_tint_shader = Shader.new()
	_tint_shader.code = TINT_SHADER_CODE
	_afterimage_material = ShaderMaterial.new()
	_afterimage_material.shader = _tint_shader
	_afterimage_material.set_shader_parameter("tint_color", ATTACK_TINT)
	_afterimage_material.set_shader_parameter("tint", 1.0)
	_parry_popup = Label.new()
	_parry_popup.theme = UI_THEME
	_parry_popup.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_parry_popup.text = "PARRY!"
	_parry_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parry_popup.add_theme_font_size_override("font_size", 16)
	_parry_popup.add_theme_color_override("font_color", PARRY_COLOR)
	_parry_popup.add_theme_color_override("font_outline_color", Color(0.051, 0.027, 0.129))
	_parry_popup.add_theme_constant_override("outline_size", 6)
	_parry_popup.size = Vector2(160, 24)
	_parry_popup.visible = false
	_attack_layer.add_child(_parry_popup)
	if boss_sprite != null and boss_sprite.sprite_frames != null:
		var frames := boss_sprite.sprite_frames
		for pose in JARONA_POSES:
			if _has_frames(frames, pose):
				_jarona_poses.append(pose)
		if not _jarona_poses.is_empty():
			_jarona_frames = frames
	_build_attacks()

func _process(delta: float) -> void:
	super._process(delta)
	if _attack_layer == null:
		return
	_attack_layer.visible = not is_game_over
	if playback_active and not is_game_over and not is_level_complete:
		_update_attacks(_song_time)
		_update_attack_sprites(_song_time)
		_update_parry_popup(_song_time)
	_attack_layer.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PARRY_ACTION):
		if playback_active and not is_game_over and not is_level_complete:
			_try_parry()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _update_gameplay(song_time: float, delta: float) -> void:
	_auto_hit_notes(song_time)
	super._update_gameplay(song_time, delta)
	_grey_out_shielded_notes()

# --- note shield ----------------------------------------------------------

## True if a note at this song time falls under an attack's shield.
func _is_shielded_time(time: float) -> bool:
	for atk in _attacks:
		if time < atk.shield_start:
			return false   # sorted by time
		if time <= atk.shield_end:
			return true
	return false

## Greys out newly spawned notes that will be hit automatically.
func _grey_out_shielded_notes() -> void:
	for note in spawned_notes:
		if note.get_meta("greyed", false) or note.get_meta("state") != NoteState.PENDING:
			continue
		if _is_shielded_time(note.get_meta("hit_time")):
			note.set_meta("greyed", true)
			note.modulate = SHIELDED_NOTE_MODULATE

## Hits every shielded note that has reached the hit line, as if played
## perfectly. Hold notes are completed on the spot.
func _auto_hit_notes(song_time: float) -> void:
	var shielded_now := _is_shielded_time(song_time)
	for note in spawned_notes.duplicate():
		var lane: int = note.get_meta("lane_index")
		var state: int = note.get_meta("state")
		var hit_time: float = note.get_meta("hit_time")
		var done := false
		if state == NoteState.PENDING and song_time >= hit_time and _is_shielded_time(hit_time):
			_on_note_result("Perfect", lane)
			if note.get_meta("is_hold"):
				_on_note_result("Held", lane)
			done = true
		elif state == NoteState.HOLDING and shielded_now:
			_on_note_result("Held", lane)
			done = true
		if done:
			spawned_notes.erase(note)
			note.queue_free()

# --- attack timeline ------------------------------------------------------

func _build_attacks() -> void:
	_attacks.clear()
	for ev in chart_data.get("track_events", []):
		if ev.name != JARONA_EVENT:
			continue
		var hit_time: float = ev.time
		var beat := _beat_length_at(hit_time)
		_attacks.append({
			"time": hit_time,
			"start": hit_time - jarona_windup_beats * beat,
			"dash_start": hit_time - minf(jarona_dash_beats, jarona_windup_beats) * beat,
			"shield_start": hit_time - (minf(jarona_dash_beats, jarona_windup_beats) + shield_before_dash_beats) * beat,
			"shield_end": hit_time + maxf(shield_after_hit_beats * beat, parry_window),
			"state": AttackState.WAITING,
			"resolved_at": 0.0,
			"resolved_pos": Vector2.ZERO,
			"sprite": null,
			"pose": &"",
			"dashing": false,
			"last_afterimage": -INF,
		})

func _update_attacks(t: float) -> void:
	for atk in _attacks:
		var state: int = atk.state
		if state == AttackState.WAITING:
			if t < atk.start:
				break   # sorted by time, so later ones haven't started either
			_start_windup(atk)
		elif state == AttackState.WINDUP:
			if t > atk.time + parry_window:
				_resolve_attack(atk, false, t)
			elif t >= atk.dash_start and not atk.dashing:
				atk.dashing = true
				_play_jarona_sound()
		elif state == AttackState.PARRIED or state == AttackState.HIT:
			if t - atk.resolved_at >= AFTERMATH_TIME:
				atk.state = AttackState.DONE
				if atk.sprite != null:
					atk.sprite.queue_free()
					atk.sprite = null

func _start_windup(atk: Dictionary) -> void:
	atk.state = AttackState.WINDUP
	if _jarona_frames == null:
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _jarona_frames
	sprite.scale = boss_sprite.scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = _tint_shader
	sprite.material = mat
	_attack_layer.add_child(sprite)
	atk.sprite = sprite
	atk.pose = _jarona_poses.pick_random()

func _play_jarona_sound() -> void:
	if jarona_sounds.is_empty():
		return
	_play_jarona_sfx(jarona_sounds.pick_random(), jarona_sounds_volume_db)

## Plays a sound on its own one-shot player, so no other jarona sound
## (or the next attack's) ever cuts it off.
func _play_jarona_sfx(stream: AudioStream, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func _try_parry() -> void:
	var t := _current_song_time()
	for atk in _attacks:
		if atk.state != AttackState.WINDUP:
			continue
		var diff: float = t - atk.time
		if absf(diff) <= parry_window:
			_resolve_attack(atk, true, t)
		elif t >= atk.dash_start:
			_resolve_attack(atk, false, t)
		return   # only the next attack to land can be parried

func _resolve_attack(atk: Dictionary, parried: bool, t: float) -> void:
	atk.resolved_pos = _attacker_pos(atk, t)
	atk.state = AttackState.PARRIED if parried else AttackState.HIT
	atk.resolved_at = t
	var col := PARRY_COLOR if parried else ATTACK_COLOR

	# He hits the whole highway, so every lane flashes.
	for lane in range(_lane_flash.size()):
		_lane_flash[lane] = 1.0
		_lane_flash_color[lane] = col

	if parried:
		if parry_sound != null:
			_play_jarona_sfx(parry_sound, parry_sound_volume_db)
		else:
			_play_sfx(hit_sfx)
		_parry_flash_at = t
		_parry_popup.position = _strike_pos() - Vector2(_parry_popup.size.x / 2.0, 40.0)
	else:
		if hurt_sound != null:
			_play_jarona_sfx(hurt_sound, hurt_sound_volume_db)
		else:
			_play_sfx(segment_fail_sfx)
		_show_status_banner("JARONA HIT! -%d HP" % jarona_damage, ATTACK_COLOR)
		damage_player(jarona_damage)

# --- boss sprite ----------------------------------------------------------

## Moves and animates the boss sprite of every active attack, and hides
## the boss at his spot while he's out attacking.
func _update_attack_sprites(t: float) -> void:
	if _jarona_frames == null:
		return
	var boss_away := false
	for atk in _attacks:
		var sprite: AnimatedSprite2D = atk.sprite
		if sprite == null:
			continue
		boss_away = true
		var state: int = atk.state
		var pose: StringName = atk.pose
		var anim := &"idle"
		var pos: Vector2
		var tint := 0.0
		var trailing := false
		if state == AttackState.WINDUP:
			pos = _attacker_pos(atk, t)
			if t >= atk.dash_start:
				anim = pose
				tint = 1.0
				trailing = true
			else:
				tint = clampf((t - atk.start) / TINT_IN_TIME, 0.0, 1.0)
				pos.y += _windup_shake(atk, t)
		else:
			pos = _aftermath_pos(atk, t)
			anim = pose
			if state == AttackState.HIT:
				tint = 1.0
				# still sliding into the highway for the first quarter
				trailing = t - atk.resolved_at < AFTERMATH_TIME / 4.0
			elif _has_frames(_jarona_frames, &"deflected"):
				anim = &"deflected"
			sprite.modulate.a = 1.0 - clampf((t - atk.resolved_at) / AFTERMATH_TIME, 0.0, 1.0)
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("tint_color", ATTACK_TINT)
		mat.set_shader_parameter("tint", tint)
		sprite.offset = DASH_SPRITE_OFFSET if anim == pose else Vector2.ZERO
		sprite.position = pos
		if sprite.animation != anim or not sprite.is_playing():
			sprite.play(anim)
		if trailing and t - atk.last_afterimage >= AFTERIMAGE_INTERVAL:
			atk.last_afterimage = t
			_spawn_afterimage(sprite, t)
	if boss_sprite != null:
		boss_sprite.visible = not boss_away
	_update_afterimages(t)

## Leaves a tinted copy of the sprite's current frame where it is now.
func _spawn_afterimage(sprite: AnimatedSprite2D, t: float) -> void:
	var ghost := Sprite2D.new()
	ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.position = sprite.position
	ghost.offset = sprite.offset
	ghost.scale = sprite.scale
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.material = _afterimage_material
	ghost.modulate.a = AFTERIMAGE_ALPHA
	_attack_layer.add_child(ghost)
	_attack_layer.move_child(ghost, 0)   # behind him
	_afterimages.append({"node": ghost, "born": t})

func _update_afterimages(t: float) -> void:
	for ai in _afterimages.duplicate():
		var age: float = t - ai.born
		var ghost: Sprite2D = ai.node
		if age >= AFTERIMAGE_LIFE:
			ghost.queue_free()
			_afterimages.erase(ai)
		else:
			ghost.modulate.a = AFTERIMAGE_ALPHA * (1.0 - age / AFTERIMAGE_LIFE)

# --- parry feedback -------------------------------------------------------

## Orange outline around the whole note highway, fading after a parry.
func _draw_parry_flash() -> void:
	var k := (_song_time - _parry_flash_at) / PARRY_FLASH_TIME
	if k < 0.0 or k >= 1.0 or lane_positions.is_empty():
		return
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	var grow := 6.0 * k
	var left: float = float(lane_positions[0]) - LANE_WIDTH / 2.0 - 8.0 - grow
	var right: float = float(lane_positions[-1]) + LANE_WIDTH / 2.0 + 8.0 + grow
	var rect := Rect2(left, 4.0 - grow, right - left, viewport_h - 8.0 + grow * 2.0)
	_attack_layer.draw_rect(rect, Color(PARRY_COLOR, 1.0 - k), false, 6.0)

## Small "PARRY!" that pops up where he struck, rises a little and fades.
func _update_parry_popup(t: float) -> void:
	var k := (t - _parry_flash_at) / PARRY_FLASH_TIME
	_parry_popup.visible = k >= 0.0 and k < 1.0
	if not _parry_popup.visible:
		return
	_parry_popup.position.y = _strike_pos().y - 40.0 - 30.0 * k
	_parry_popup.modulate.a = 1.0 - k * k

# --- helpers --------------------------------------------------------------

## Boss position during an attack: moving from his spot to the launch
## point, waiting there, then accelerating sideways into the highway,
## arriving exactly at the attack's time.
func _attacker_pos(atk: Dictionary, t: float) -> Vector2:
	var launch := _launch_pos()
	if t < atk.start + EMERGE_TIME:
		var e := clampf(inverse_lerp(atk.start, atk.start + EMERGE_TIME, t), 0.0, 1.0)
		return _boss_pos().lerp(launch, 1.0 - (1.0 - e) * (1.0 - e))
	if t < atk.dash_start:
		return launch
	var q := clampf(inverse_lerp(atk.dash_start, atk.time, t), 0.0, 1.0)
	return launch.lerp(_strike_pos(), q * q)

## Where the dash lands: the outer edge of the rightmost lane, halfway
## down the highway.
func _strike_pos() -> Vector2:
	return Vector2(float(lane_positions[-1]) + LANE_WIDTH / 2.0, hit_line_y / 2.0)

func _boss_pos() -> Vector2:
	if boss_anchor != null:
		return boss_anchor.position
	return Vector2(float(lane_positions[-1]) + 600.0, hit_line_y / 2.0)

## Where the boss waits before dashing: left of his spot, level with
## the point he'll strike.
func _launch_pos() -> Vector2:
	return Vector2(_boss_pos().x - LAUNCH_OFFSET_FROM_BOSS, _strike_pos().y)

## Boss position after the attack resolves: knocked back toward his spot
## when parried, or carried a little further into the highway when it hit.
func _aftermath_pos(atk: Dictionary, t: float) -> Vector2:
	var k := clampf((t - atk.resolved_at) / AFTERMATH_TIME, 0.0, 1.0)
	var from: Vector2 = atk.resolved_pos
	if atk.state == AttackState.PARRIED:
		var fade := 1.0 - k
		return from + Vector2(500.0 * (1.0 - fade * fade), -120.0 * k)
	return from.lerp(_strike_pos() - Vector2(LANE_WIDTH, 0.0), minf(1.0, k * 4.0))

## Small up-and-down shake on each beat while waiting to dash.
func _windup_shake(atk: Dictionary, t: float) -> float:
	if t < atk.start + EMERGE_TIME or t >= atk.dash_start:
		return 0.0
	var beats_left: float = maxf(0.0, (atk.time - t) / _beat_length_at(atk.time))
	return sin(t * 45.0) * 4.0 * (1.0 - fposmod(-beats_left, 1.0))

func _has_frames(frames: SpriteFrames, anim: StringName) -> bool:
	return frames.has_animation(anim) and frames.get_frame_count(anim) > 0

## Seconds per beat at a song time, from the chart's tempo map.
func _beat_length_at(time: float) -> float:
	var bpm := 120.0
	for te in chart_data.get("tempo_events", []):
		if te.get("time", 0.0) <= time:
			bpm = te.bpm
		else:
			break
	return 60.0 / maxf(bpm, 1.0)
