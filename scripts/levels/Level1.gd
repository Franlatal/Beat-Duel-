extends LevelBase
## Level 1 (Flower Man).
##
## Exclusive event "jarona": every "E jarona" in the played chart track
## is an attack that lands exactly on the event's tick. The boss winds
## up on his own spot for jarona_windup_beats, then dashes straight from
## there (across the lanes, not down them) into the highway,
## hitting it at the edge of the rightmost lane, the one closest to him.
## Press the parry key (Z by default, rebindable in Options > Controls)
## as he lands to block it. Letting it land, or pressing during the dash
## but too early, costs jarona_damage HP. Presses before the dash starts
## are ignored, so there's no penalty for reacting to the windup.
##
## The chart is trimmed for the attacks when the level loads (see
## _prepare_chart): a jarona (or JaKidding) that would overlap a segment
## being graded is dropped, so he never does two things at once, and the
## notes from clear_notes_before_hit_beats before each jarona lands until
## clear_notes_after_hit_beats after it are removed (holds running
## into that stretch are cut short), so the parry never clashes with
## notes. The first jarona of a run shows a "PRESS <key> TO PARRY" hint,
## and every parry press flashes an orange outline round the highway.
##
## The attacker is the boss himself, using his SpriteFrames (set on
## BossAnchor/BossSprite in Level1.tscn). He flashes white and crouches
## ("crouch") beside the highway for the windup, turns bright blue for the
## dash in a random one of "jarona_punch" / "jarona_fair" and leaves a
## thick blue trail behind him. One of jarona_sounds, picked at random,
## plays as the dash starts and always plays to the end: while he's still
## saying it, the parry / hit sound is played quieter (jarona_voice_duck_db)
## so it doesn't drown out the end of the line.
##
## Parry: a white flash and a thin white slash where he struck, two grey
## rings spreading from it, and he's knocked back in his "deflected" pose,
## back to his own colors, leaving dark afterimages. parry_sound plays.
## A hit shows the HUD banner, shakes the playfield and costs HP.
##
## JaKidding: every "E jakidding" is a fake jarona. Same windup and dash,
## but as the dash starts he says his "jakidding" voice line instead of
## the jarona shout, stops short of the highway at the event's tick,
## stands there ("stand") for kidding_stand_beats and walks back to his
## spot. Nothing to parry, its notes are left in, presses do nothing.
##
## Prism Blow: a failed segment costs no life in this level, because
## Flowery doesn't want to hurt you, he wants to spare you. Instead he
## blows a kiss ("kiss" frames, a speech bubble) and a stream of pink
## spare petals flies across to the highway, bursts there in white with
## sparkles, and the MERCY meter in the top left rises by one step. After
## segment_fails_to_spare failed segments it's full, the player is spared
## and the run ends as a loss ("YOU WERE SPARED"). Hearts are only lost to
## jarona attacks.
##
## When a segment is cleared he recoils ("hit" frame) and shakes.
##
## The background (sunset sky and pink plain, the giant vine behind the
## note highway, petals falling over both) is set up in Level1.tscn
## under BackgroundLayer: Sunset, Vine and Petals.
##
## Notes: flower_notes (resources/note_skins/flowery_notes.tres) gives this
## level its own notes, one flower per lane in the usual lane colours
## (red, yellow, green, cyan), vine hold tails, hollow flower targets on
## the hit line and a petal burst on hits. Clear it to get the default notes.
##
## Sounds: voice clips come from LevelBase.voice_folder (res://sounds/flowery,
## see its README.txt); this level adds the cues "jakidding", "prism_blow"
## (said as he starts the Prism Blow) and "spared" (the full MERCY ending,
## instead of "game_over"). The shared "segment_fail" cue isn't used here,
## "prism_blow" replaces it. Parry and jarona hit use parry_sound and
## hurt_sound. mercy_up (.wav, .ogg or .mp3) in res://sounds/level1 plays
## when the petals burst. Missing files are silent.

const JARONA_EVENT := "jarona"
const PARRY_ACTION := &"parry"
## Voice cues (file names in voice_folder) for a blocked / landed attack.
## Chart event (and voice cue) for the fake attack.
const KIDDING_EVENT := "jakidding"
const VOICE_PRISM_BLOW := "prism_blow"
const VOICE_SPARED := "spared"
const VOICE_SEGMENT_FAIL := "segment_fail"
## This level's own sound effects, found by file name.
const LEVEL_SOUND_FOLDER := "res://sounds/level1"

enum AttackState { WAITING, WINDUP, PARRIED, HIT, DONE }
enum FakeState { WAITING, WINDUP, STAND, RETURN, DONE }

## This level's note look (see NoteSkin.gd). Empty = the default notes.
@export var flower_notes: NoteSkin = preload("res://resources/note_skins/flowery_notes.tres")

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
## While his jarona shout is still playing, the parry and hit sounds are
## this many decibels quieter, so the end of the line stays audible.
## 0 = no ducking.
@export_range(-30.0, 0.0, 0.5) var jarona_voice_duck_db: float = -9.0
## Notes are removed from this many beats before the attack lands until this
## many beats after the attack lands.
@export_range(0.0, 4.0, 0.25) var clear_notes_before_hit_beats: float = 0.5
@export_range(0.0, 4.0, 0.25) var clear_notes_after_hit_beats: float = 0.25
## Show "PRESS <parry key> TO PARRY" during the first jarona of a run.
@export var show_parry_hint: bool = true
## Lives lost when an attack lands.
@export_range(1, 10, 1) var jarona_damage: int = 1

@export_group("JaKidding")
## How long he stands there after stopping, in beats.
@export_range(0.5, 8.0, 0.5) var kidding_stand_beats: float = 2.0

@export_group("Prism Blow")
## Failed segments it takes to fill the MERCY meter and end the run.
## 2 means each one adds 50%.
@export_range(1, 20, 1) var segment_fails_to_spare: int = 2
## What he says in the speech bubble. Empty = no bubble.
@export var prism_blow_text: String = ""

@export_group("Hit reactions")
## How far (pixels) and how long (seconds) the playfield shakes when
## the player loses a life.
@export_range(0.0, 40.0, 1.0) var hit_shake_strength: float = 14.0
@export_range(0.0, 1.0, 0.05) var hit_shake_time: float = 0.3

## Seconds the parry / hit reaction lasts after an attack resolves.
const AFTERMATH_TIME := 0.6
const ATTACK_COLOR := Color(1.0, 0.2, 0.3)
## His dash color, and the darker blue of the trail he leaves.
const ATTACK_BLUE := Color8(16, 128, 248)
const TRAIL_BLUE := Color8(0, 56, 176)
## How much of his shading stays visible under the blue (0 = flat color).
const ATTACK_SHADING := 0.65
## Seconds of the white flash that starts the windup.
const WINDUP_FLASH_TIME := 0.3
## Seconds the blue takes to leave him when he's parried or stops.
const TINT_OUT_TIME := 0.08
## Orange outline round the highway on every parry press.
const PARRY_PRESS_COLOR := Color(1.0, 0.55, 0.1)
const PARRY_PRESS_TIME := 0.35
## Where the "PRESS Z TO PARRY" hint sits, from Flower Man's center
## (just under his feet).
## Top-right corner of the parry hint box, from Flower Man's position:
## to his left, about level with his head.
const PARRY_HINT_OFFSET := Vector2(-190, -20)
## Seconds kept clear around a segment being graded when deciding
## whether a jarona would overlap it.
const SEGMENT_GRADE_MARGIN := 0.4
## Dash trail: a blue copy is left behind every AFTERIMAGE_INTERVAL
## seconds, starting at AFTERIMAGE_ALPHA and fading out over AFTERIMAGE_LIFE.
const AFTERIMAGE_INTERVAL := 0.012
const AFTERIMAGE_LIFE := 0.3
const AFTERIMAGE_ALPHA := 0.75
## Knock-back afterimages after a parry: darker copies in his own colors.
const KNOCKBACK_GHOST_INTERVAL := 0.05
const KNOCKBACK_GHOST_LIFE := 0.25
const KNOCKBACK_GHOST_COLOR := Color(0.4, 0.4, 0.32, 0.65)
## Parry effects, in seconds: the white flash, the slash, the two rings.
const PARRY_CIRCLE_TIME := 0.12
const PARRY_SLASH_TIME := 0.18
const PARRY_RING_TIME := 0.45
const PARRY_RING_COLOR := Color8(176, 176, 176)
## JaKidding: how far into the dash he gets before stopping (0..1), and
## the seconds he takes to walk back to his spot afterwards.
const KIDDING_REACH := 0.3
const KIDDING_RETURN_TIME := 0.35
## Recolors a sprite toward tint_color by tint (0 = untouched). flatness
## 1 paints it one flat color (the white flash); lower keeps some shading.
const TINT_SHADER_CODE := """
shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float tint : hint_range(0.0, 1.0) = 0.0;
uniform float flatness : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = COLOR;   // already texture * modulate in Godot 4
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 shaded = tint_color.rgb * (0.45 + 0.75 * lum);
	c.rgb = mix(c.rgb, mix(shaded, tint_color.rgb, flatness), tint);
	COLOR = c;
}
"""
## Sprite offset (texture pixels) for the dash poses, so his fist or
## foot, not his middle, is what reaches the highway.
const DASH_SPRITE_OFFSET := Vector2(26, 0)
## Dash poses; each attack uses one of these that the boss's frames have.
const JARONA_POSES: Array[StringName] = [&"jarona_punch", &"jarona_fair"]
## Animations: windup crouch, JaKidding stand, Prism Blow kiss.
const CROUCH_ANIM := &"crouch"
const STAND_ANIM := &"stand"
const KISS_ANIM := &"kiss"
## Where the petals leave him (his hand), and where the speech bubble's
## tail points (his head), relative to his spot.
const PRISM_HAND_OFFSET := Vector2(-80, -40)
const PRISM_BUBBLE_OFFSET := Vector2(-70, -170)
## Banner and popup color for MERCY (the meter's own yellow).
const MERCY_COLOR := Color8(255, 248, 64)
## Where the MERCY meter sits if the level has no party panel (normally
## it's a row under the HP bar in the bottom strip): just below Flower
## Man, clear of the spot where he crouches for a jarona. Inside
## %LevelUI (screen pixels).
const MERCY_METER_POS := Vector2(1060, 660)
## Sideways steps (in his own art pixels) of the boss's shake when he's
## hurt, and the seconds each step lasts.
const BOSS_HURT_SHAKE: Array[float] = [3.0, -3.0, 2.0, -2.0, 1.0, -1.0, 0.0]
const BOSS_HURT_SHAKE_STEP := 0.05
## How visible the falling petals are behind the note highway (1 = fully).
const PETAL_HIGHWAY_ALPHA := 0.3

## One entry per jarona in the chart:
## {time, start, dash_start, state, resolved_at, resolved_pos, sprite, pose, dashing}
var _attacks: Array = []
## One entry per jakidding in the chart:
## {time, start, dash_start, stand_end, return_end, state, sprite, pose, voiced, stop_pos}
var _fakes: Array = []
var _attack_layer: Node2D
## The boss's frames when they include a jarona pose, else null.
var _jarona_frames: SpriteFrames
## The dash poses _jarona_frames actually has.
var _jarona_poses: Array[StringName] = []
var _tint_shader: Shader
## Shared fully-tinted material for the blue trail.
var _trail_material: ShaderMaterial
## Fading afterimages: [{node, born, life, alpha}]
var _afterimages: Array = []
## Parry effects being drawn: [{at, pos}]
var _parry_fx: Array = []
var _prism: PrismBlow
var _snd_mercy_up: AudioStream
## Player of the jarona shout that's playing (freed when it finishes).
var _jarona_voice: AudioStreamPlayer
## MERCY value waiting for the Prism Blow burst to show it.
var _pending_mercy := 0.0
## True once MERCY is full; the run ends at the burst.
var _spare_pending := false
## A Prism Blow waiting for him to get back from an attack.
var _prism_queued := false
var _queued_prism_text := ""
## Segments failed so far; the MERCY meter shows this out of segment_fails_to_spare.
var _failed_segments := 0
## Song time of the last parry press, for the orange outline.
var _parry_press_at := -INF
## "PRESS Z TO PARRY" over the highway during the first jarona.
var _parry_hint: Label
var _mercy_meter: MercyMeter
var _petals: FallingPetals
## Seconds of playfield shake left.
var _shake_left := 0.0
var _rest_position := Vector2.ZERO
var _boss_sprite_rest := Vector2.ZERO
var _boss_shake_tween: Tween

func _setup_level() -> void:
	if flower_notes != null:
		set_note_skin(flower_notes)
	_attack_layer = Node2D.new()
	_attack_layer.name = "JaronaLayer"
	_attack_layer.z_index = 10   # above notes
	add_child(_attack_layer)
	_attack_layer.draw.connect(_draw_parry_fx)
	_tint_shader = Shader.new()
	_tint_shader.code = TINT_SHADER_CODE
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = _tint_shader
	_trail_material.set_shader_parameter("tint_color", TRAIL_BLUE)
	_trail_material.set_shader_parameter("tint", 1.0)
	_trail_material.set_shader_parameter("flatness", 0.6)
	if boss_sprite != null and boss_sprite.sprite_frames != null:
		var frames := boss_sprite.sprite_frames
		for pose in JARONA_POSES:
			if _has_frames(frames, pose):
				_jarona_poses.append(pose)
		if not _jarona_poses.is_empty():
			_jarona_frames = frames
	# Load these now so the first one doesn't hitch.
	has_boss_voice(KIDDING_EVENT)
	has_boss_voice(VOICE_PRISM_BLOW)
	has_boss_voice(VOICE_SPARED)
	_snd_mercy_up = _find_sound(LEVEL_SOUND_FOLDER, "mercy_up")
	# The JaKidding line is said at the start of his dash (see
	# _update_fakes), not at the event's tick, so LevelBase mustn't play it.
	_voice_events = _voice_events.filter(func(e): return e.name != KIDDING_EVENT)
	# Prism Blow has sounds of its own; the shared fail jingle would clash.
	if segment_fail_sfx != null:
		segment_fail_sfx.stream = null
	_build_attacks()
	_build_fakes()
	_rest_position = position
	if boss_sprite != null:
		_boss_sprite_rest = boss_sprite.position
	_petals = get_node_or_null("BackgroundLayer/Petals") as FallingPetals
	if _petals != null and not lane_positions.is_empty():
		_petals.set_dim_zone(float(lane_positions[0]) - LANE_WIDTH, float(lane_positions[-1]) + LANE_WIDTH, PETAL_HIGHWAY_ALPHA)
	_setup_prism_blow()
	_setup_parry_hint()
	_mercy_meter = MercyMeter.new()
	_mercy_meter.name = "MercyMeter"
	var party := get_node_or_null("%PartyPanel")
	if party != null and party.has_method("add_status_widget"):
		# One row under the HP bar in the bottom strip.
		_mercy_meter.inline = true
		party.add_status_widget(_mercy_meter)
	else:
		var level_ui := get_node_or_null("%LevelUI") as Control
		if level_ui == null:
			level_ui = get_node_or_null("HUDLayer/HUDRoot") as Control
		if level_ui != null:
			_mercy_meter.position = MERCY_METER_POS
			level_ui.add_child(_mercy_meter)

func _setup_prism_blow() -> void:
	_prism = PrismBlow.new()
	_prism.name = "PrismBlow"
	_prism.z_index = 20   # over the notes and the boss
	_prism.bubble_text = prism_blow_text
	_prism.font = UI_THEME.get_font("font", "Label")
	_prism.petal_texture = load("res://Sprites/flowery/spare_petals.png") as Texture2D
	for i in range(5):
		var tex := load("res://Sprites/flowery/shockwave_%d.png" % i) as Texture2D
		if tex != null:
			_prism.shockwave_frames.append(tex)
	_prism.burst.connect(_on_prism_burst)
	add_child(_prism)

func _process(delta: float) -> void:
	super._process(delta)
	_update_shake(delta)
	if _attack_layer == null:
		return
	_attack_layer.visible = not is_game_over
	if is_game_over and boss_sprite != null:
		boss_sprite.visible = true   # back at his spot if the run ended mid-attack
	if playback_active and not is_game_over and not is_level_complete:
		_update_attacks(_song_time)
		_update_fakes(_song_time)
		_update_attack_sprites(_song_time)
	_update_parry_hint(_song_time)
	_start_queued_prism_blow()
	_attack_layer.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PARRY_ACTION):
		if playback_active and not is_game_over and not is_level_complete:
			_parry_press_at = _current_song_time()
			_try_parry()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

# --- chart trimming -------------------------------------------------------

## Trims the chart for the attacks before any note is queued: drops every
## jarona / JaKidding that would overlap a segment being graded (he'd do
## the attack and his segment reaction at once), then clears the notes
## around each remaining jarona so the parry never clashes with notes.
func _prepare_chart() -> void:
	# Moments when a segment gets graded: each segment start after the
	# first, and the end of the last note.
	var grades: Array[float] = []
	var segs: Array = chart_data.get("segments", [])
	for i in range(1, segs.size()):
		grades.append(segs[i].time)
	var last_end := 0.0
	for n in chart_data.notes:
		last_end = maxf(last_end, n.time + n.get("sustain", 0.0))
	grades.append(last_end)

	var kept: Array = []
	var dropped := 0
	for ev in chart_data.get("track_events", []):
		if ev.name != JARONA_EVENT and ev.name != KIDDING_EVENT:
			kept.append(ev)
			continue
		var beat := _beat_length_at(ev.time)
		var from: float = ev.time - jarona_windup_beats * beat - SEGMENT_GRADE_MARGIN
		var to: float = ev.time + AFTERMATH_TIME + SEGMENT_GRADE_MARGIN
		if ev.name == KIDDING_EVENT:
			to = ev.time + kidding_stand_beats * beat + KIDDING_RETURN_TIME + SEGMENT_GRADE_MARGIN
		var clashes := false
		for g in grades:
			if g >= from and g <= to:
				clashes = true
				break
		if clashes:
			dropped += 1
		else:
			kept.append(ev)
	chart_data["track_events"] = kept

	# Clear the notes around each jarona that's left.
	var windows: Array = []
	for ev in kept:
		if ev.name != JARONA_EVENT:
			continue
		var beat := _beat_length_at(ev.time)
		windows.append([ev.time - maxf(clear_notes_before_hit_beats * beat, parry_window),
			ev.time + maxf(clear_notes_after_hit_beats * beat, parry_window)])
	var notes: Array = []
	var removed := 0
	for n in chart_data.notes:
		var t: float = n.time
		var inside := false
		for w in windows:
			if t >= w[0] and t <= w[1]:
				inside = true
				break
			# A hold that runs into the window ends a quarter beat before it.
			var sustain: float = n.get("sustain", 0.0)
			if t < w[0] and t + sustain > w[0]:
				var cut_to: float = w[0] - _beat_length_at(t) * 0.25 - t
				n.sustain = cut_to if cut_to >= min_hold_duration else 0.0
		if inside:
			removed += 1
		else:
			notes.append(n)
	chart_data.notes = notes
	print_verbose("Level1: dropped %d attacks at segment grades, cleared %d notes" % [dropped, removed])

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
	atk.sprite = _make_attack_sprite()
	atk.pose = _jarona_poses.pick_random()

## A copy of the boss used for an attack, with its own tint material.
func _make_attack_sprite() -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _jarona_frames
	sprite.scale = boss_sprite.scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = _tint_shader
	sprite.material = mat
	_attack_layer.add_child(sprite)
	return sprite

func _play_jarona_sound() -> void:
	if jarona_sounds.is_empty():
		return
	_jarona_voice = _play_one_shot(jarona_sounds.pick_random(), jarona_sounds_volume_db)

## Extra volume for a sound that lands on top of the jarona shout: quieter
## while the shout is still playing, so the line is heard to the end.
func _duck_under_jarona_voice() -> float:
	if _jarona_voice != null and is_instance_valid(_jarona_voice) and _jarona_voice.playing:
		return jarona_voice_duck_db
	return 0.0

## Plays a sound on its own one-shot player, so no other attack sound
## (or the next attack's) ever cuts it off. Does nothing for null.
func _play_one_shot(stream: AudioStream, volume_db: float = 0.0) -> AudioStreamPlayer:
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
	return player

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
	if parried:
		if parry_sound != null:
			_play_one_shot(parry_sound, parry_sound_volume_db + _duck_under_jarona_voice())
		else:
			_play_sfx(hit_sfx)
		_parry_fx.append({"at": t, "pos": atk.resolved_pos})
	else:
		if hurt_sound != null:
			_play_one_shot(hurt_sound, hurt_sound_volume_db + _duck_under_jarona_voice())
		else:
			_play_sfx(segment_fail_sfx)
		_show_status_banner("JARONA HIT! -%d HP" % jarona_damage, ATTACK_COLOR)
		damage_player(jarona_damage)

# --- jakidding (fake attack) ----------------------------------------------

func _build_fakes() -> void:
	_fakes.clear()
	for ev in chart_data.get("track_events", []):
		if ev.name != KIDDING_EVENT:
			continue
		var stop_time: float = ev.time
		var beat := _beat_length_at(stop_time)
		var stand_end := stop_time + kidding_stand_beats * beat
		_fakes.append({
			"time": stop_time,
			"start": stop_time - jarona_windup_beats * beat,
			"dash_start": stop_time - minf(jarona_dash_beats, jarona_windup_beats) * beat,
			"stand_end": stand_end,
			"return_end": stand_end + KIDDING_RETURN_TIME,
			"state": FakeState.WAITING,
			"sprite": null,
			"pose": &"",
			"voiced": false,
			"stop_pos": Vector2.ZERO,
			"last_afterimage": -INF,
		})

func _update_fakes(t: float) -> void:
	for fake in _fakes:
		match fake.state:
			FakeState.WAITING:
				if t < fake.start:
					break
				fake.state = FakeState.WINDUP
				if _jarona_frames != null:
					fake.sprite = _make_attack_sprite()
					fake.pose = _jarona_poses.pick_random()
			FakeState.WINDUP:
				if t >= fake.dash_start and not fake.voiced:
					fake.voiced = true
					play_boss_voice(KIDDING_EVENT)
				if t >= fake.time:
					fake.state = FakeState.STAND
					fake.stop_pos = _fake_dash_pos(fake, fake.time)
			FakeState.STAND:
				if t >= fake.stand_end:
					fake.state = FakeState.RETURN
			FakeState.RETURN:
				if t >= fake.return_end:
					fake.state = FakeState.DONE
					if fake.sprite != null:
						fake.sprite.queue_free()
						fake.sprite = null

## Where a fake attack is during its dash: it starts like the real one
## but only gets KIDDING_REACH of the way before he stops.
func _fake_dash_pos(fake: Dictionary, t: float) -> Vector2:
	var q := clampf(inverse_lerp(fake.dash_start, fake.time, t), 0.0, 1.0)
	return _launch_pos().lerp(_strike_pos(), KIDDING_REACH * q * q)

# --- parry feedback -------------------------------------------------------

## Orange outline round the whole note highway, fading after any parry
## press, so the player can see the press registered.
func _draw_parry_press() -> void:
	var k := (_song_time - _parry_press_at) / PARRY_PRESS_TIME
	if k < 0.0 or k >= 1.0 or lane_positions.is_empty():
		return
	var viewport_h: float = get_viewport().get_visible_rect().size.y
	var grow := 6.0 * k
	var left: float = float(lane_positions[0]) - LANE_WIDTH / 2.0 - 8.0 - grow
	var right: float = float(lane_positions[-1]) + LANE_WIDTH / 2.0 + 8.0 + grow
	var rect := Rect2(left, 4.0 - grow, right - left, viewport_h - 8.0 + grow * 2.0)
	_attack_layer.draw_rect(rect, Color(PARRY_PRESS_COLOR, 1.0 - k), false, 6.0)

func _setup_parry_hint() -> void:
	if not show_parry_hint or _attacks.is_empty() or lane_positions.is_empty():
		return
	var hud_root := get_node_or_null("HUDLayer/HUDRoot") as Control
	if hud_root == null:
		return
	_parry_hint = Label.new()
	_parry_hint.name = "ParryHint"
	_parry_hint.theme = UI_THEME
	_parry_hint.text = "PRESS %s\nTO PARRY" % _parry_key_name()
	_parry_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parry_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_parry_hint.add_theme_font_size_override("font_size", 32)
	_parry_hint.add_theme_color_override("font_color", PARRY_PRESS_COLOR)
	_parry_hint.add_theme_color_override("font_outline_color", Color8(13, 7, 33))
	_parry_hint.add_theme_constant_override("outline_size", 8)
	_parry_hint.add_theme_constant_override("line_spacing", 6)
	# Dark box behind it so it reads on the bright sunset.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.82)
	box.border_color = PARRY_PRESS_COLOR
	box.set_border_width_all(4)
	box.set_content_margin_all(10)
	_parry_hint.add_theme_stylebox_override("normal", box)
	_parry_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Left of Flower Man at head height, between him and the lanes.
	var hint_size := Vector2(330.0, 104.0)
	_parry_hint.size = hint_size
	_parry_hint.position = (_boss_pos() + PARRY_HINT_OFFSET - Vector2(hint_size.x, 0.0)).round()
	_parry_hint.visible = false
	hud_root.add_child(_parry_hint)

## Shows the hint while the first jarona is winding up, blinking once
## the dash starts.
func _update_parry_hint(t: float) -> void:
	if _parry_hint == null:
		return
	var atk: Dictionary = _attacks[0]
	var visible_now: bool = atk.state == AttackState.WINDUP and not is_game_over
	if visible_now and t >= atk.dash_start:
		visible_now = fmod(t - atk.dash_start, 0.2) < 0.13
	_parry_hint.visible = visible_now
	if atk.state == AttackState.PARRIED or atk.state == AttackState.HIT or atk.state == AttackState.DONE:
		_parry_hint.queue_free()
		_parry_hint = null

## The key bound to parry, as the player would read it (Z by default).
func _parry_key_name() -> String:
	for ev in InputMap.action_get_events(PARRY_ACTION):
		if ev is InputEventKey:
			var key := ev as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if key.physical_keycode != KEY_NONE:
				code = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			var key_name := OS.get_keycode_string(code)
			if key_name != "":
				return key_name.to_upper()
	return "Z"

# --- prism blow & hit reactions ------------------------------------------

## A failed segment: no life lost. He does his Prism Blow and MERCY rises
## when the petals burst on the highway; once the meter is full the
## player is spared and the run is over.
func _punish_failed_segment(segment_index: int) -> void:
	var before := _mercy()
	_failed_segments += 1
	_pending_mercy = _mercy()
	var gained := roundi((_pending_mercy - before) * 100.0)
	_show_status_banner("SEGMENT %d FAILED! MERCY +%d%%" % [segment_index, gained], MERCY_COLOR)
	if _failed_segments >= segment_fails_to_spare:
		_spare_pending = true
	_queued_prism_text = "+%d%%" % gained
	_prism_queued = true
	_start_queued_prism_blow()

## Starts a queued Prism Blow once he's back at his spot (a segment can
## fail while he's still out on a jarona).
func _start_queued_prism_blow() -> void:
	if not _prism_queued or _boss_is_away():
		return
	_prism_queued = false
	if boss_sprite != null and boss_sprite.sprite_frames != null and _has_frames(boss_sprite.sprite_frames, KISS_ANIM):
		boss_sprite.play(KISS_ANIM)   # LevelBase puts him back in "idle" after
	play_boss_voice(VOICE_PRISM_BLOW)
	if _prism != null and not lane_positions.is_empty():
		var view_h: float = get_viewport().get_visible_rect().size.y
		_prism.play(_boss_pos() + PRISM_HAND_OFFSET, _boss_pos() + PRISM_BUBBLE_OFFSET,
			float(lane_positions[0]) - LANE_WIDTH / 2.0, float(lane_positions[-1]) + LANE_WIDTH / 2.0,
			view_h, _queued_prism_text)
	else:
		_on_prism_burst()

## True while a jarona or JaKidding has him away from his spot.
func _boss_is_away() -> bool:
	for atk in _attacks:
		if atk.sprite != null:
			return true
	for fake in _fakes:
		if fake.sprite != null:
			return true
	return false

## Level 1 says "prism_blow" when the Prism Blow actually starts (it can
## wait for him to get back from a jarona), so the shared fail line is off.
func play_boss_voice(cue: String, interrupt: bool = true) -> bool:
	if cue == VOICE_SEGMENT_FAIL:
		return false
	return super.play_boss_voice(cue, interrupt)

## The petals hit the highway: MERCY goes up, and a full meter spares you.
func _on_prism_burst() -> void:
	_play_one_shot(_snd_mercy_up)
	if _mercy_meter != null:
		_mercy_meter.set_value(_pending_mercy)
	if _spare_pending and not is_game_over and not is_level_complete:
		_trigger_game_over("YOU WERE SPARED")
		if has_boss_voice(VOICE_SPARED):
			play_boss_voice(VOICE_SPARED)   # over the "game_over" line

## While a full MERCY meter is waiting for its burst, the song ending
## doesn't count as a win.
func _trigger_level_complete() -> void:
	if _spare_pending:
		return
	super._trigger_level_complete()

## How full the MERCY meter is, 0..1.
func _mercy() -> float:
	return minf(1.0, float(_failed_segments) / float(maxi(segment_fails_to_spare, 1)))

## A life was lost (a jarona landed): shake the playfield and flash every
## lane red. The sounds are played by whoever took the life.
func _on_player_damaged() -> void:
	_shake_left = hit_shake_time
	for lane in range(_lane_flash.size()):
		_lane_flash[lane] = 1.0
		_lane_flash_color[lane] = ATTACK_COLOR

## The player cleared a segment: the boss (already in his "hit" pose
## from LevelBase) shakes from side to side.
func _on_boss_damaged() -> void:
	if boss_sprite == null:
		return
	if _boss_shake_tween != null and _boss_shake_tween.is_valid():
		_boss_shake_tween.kill()
	_boss_shake_tween = create_tween()
	for art_px in BOSS_HURT_SHAKE:
		var pos := _boss_sprite_rest + Vector2(art_px * boss_sprite.scale.x, 0.0)
		_boss_shake_tween.tween_callback(boss_sprite.set_position.bind(pos))
		_boss_shake_tween.tween_interval(BOSS_HURT_SHAKE_STEP)

## Jolts the whole playfield (lanes, notes, boss) for hit_shake_time,
## easing out. The HUD and background stay still.
func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left -= delta
	if _shake_left <= 0.0 or hit_shake_time <= 0.0:
		_shake_left = 0.0
		position = _rest_position
		return
	var reach := hit_shake_strength * _shake_left / hit_shake_time
	position = _rest_position + Vector2(roundf(randf_range(-reach, reach)), roundf(randf_range(-reach, reach) * 0.5))

# --- boss sprite ----------------------------------------------------------

## Moves and animates the boss sprite of every active attack (real and
## fake), and hides the boss at his spot while he's out attacking.
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
		if state == AttackState.WINDUP:
			if t >= atk.dash_start:
				_show_dashing(sprite, atk, _attacker_pos(atk, t), t)
			else:
				_show_windup(sprite, atk, _attacker_pos(atk, t), t)
			continue
		var since: float = t - atk.resolved_at
		var pos := _aftermath_pos(atk, t)
		sprite.modulate.a = 1.0 - clampf(since / AFTERMATH_TIME, 0.0, 1.0)
		if state == AttackState.HIT:
			# still sliding into the highway for the first quarter
			_set_look(sprite, pose, pos, ATTACK_BLUE, 1.0, 1.0 - ATTACK_SHADING)
			if since < AFTERMATH_TIME / 4.0:
				_leave_trail(sprite, atk, t)
		else:
			var anim := &"deflected" if _has_frames(_jarona_frames, &"deflected") else pose
			var blue := 1.0 - clampf(since / TINT_OUT_TIME, 0.0, 1.0)
			_set_look(sprite, anim, pos, ATTACK_BLUE, blue, 1.0 - ATTACK_SHADING)
			if t - atk.last_afterimage >= KNOCKBACK_GHOST_INTERVAL and since < AFTERMATH_TIME * 0.7:
				atk.last_afterimage = t
				_spawn_afterimage(sprite, t, null, KNOCKBACK_GHOST_COLOR, KNOCKBACK_GHOST_LIFE)
	for fake in _fakes:
		var sprite: AnimatedSprite2D = fake.sprite
		if sprite == null:
			continue
		boss_away = true
		match fake.state:
			FakeState.WINDUP:
				if t >= fake.dash_start:
					_show_dashing(sprite, fake, _fake_dash_pos(fake, t), t)
				else:
					_show_windup(sprite, fake, _attacker_pos(fake, t), t)
			FakeState.STAND:
				var anim := STAND_ANIM if _has_frames(_jarona_frames, STAND_ANIM) else &"idle"
				var blue := 1.0 - clampf((t - fake.time) / TINT_OUT_TIME, 0.0, 1.0)
				_set_look(sprite, anim, fake.stop_pos, ATTACK_BLUE, blue, 1.0 - ATTACK_SHADING)
			FakeState.RETURN:
				var k := clampf(inverse_lerp(fake.stand_end, fake.return_end, t), 0.0, 1.0)
				_set_look(sprite, &"idle", fake.stop_pos.lerp(_boss_pos(), k * (2.0 - k)), Color.WHITE, 0.0, 0.0)
	if boss_sprite != null:
		boss_sprite.visible = not boss_away
	_update_afterimages(t)

## Windup: crouched beside the highway, starting with a white flash.
func _show_windup(sprite: AnimatedSprite2D, atk: Dictionary, pos: Vector2, t: float) -> void:
	var anim := CROUCH_ANIM if _has_frames(_jarona_frames, CROUCH_ANIM) else &"idle"
	var flash := 1.0 - clampf((t - atk.start) / WINDUP_FLASH_TIME, 0.0, 1.0)
	_set_look(sprite, anim, pos, Color.WHITE, flash, 1.0)

## Dash: bright blue, leaving a thick blue trail.
func _show_dashing(sprite: AnimatedSprite2D, atk: Dictionary, pos: Vector2, t: float) -> void:
	_set_look(sprite, atk.pose, pos, ATTACK_BLUE, 1.0, 1.0 - ATTACK_SHADING)
	_leave_trail(sprite, atk, t)

func _set_look(sprite: AnimatedSprite2D, anim: StringName, pos: Vector2, tint_color: Color, tint: float, flatness: float) -> void:
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("tint_color", tint_color)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("flatness", flatness)
	sprite.offset = DASH_SPRITE_OFFSET if anim in JARONA_POSES else Vector2.ZERO
	sprite.position = pos
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)

func _leave_trail(sprite: AnimatedSprite2D, atk: Dictionary, t: float) -> void:
	if t - atk.last_afterimage >= AFTERIMAGE_INTERVAL:
		atk.last_afterimage = t
		_spawn_afterimage(sprite, t, _trail_material, Color(1, 1, 1, AFTERIMAGE_ALPHA), AFTERIMAGE_LIFE)

## Leaves a copy of the sprite's current frame where it is now, behind
## him, fading out over life seconds.
func _spawn_afterimage(sprite: AnimatedSprite2D, t: float, material: Material, color: Color, life: float) -> void:
	var ghost := Sprite2D.new()
	ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.position = sprite.position
	ghost.offset = sprite.offset
	ghost.scale = sprite.scale
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.material = material
	ghost.modulate = color
	_attack_layer.add_child(ghost)
	_attack_layer.move_child(ghost, 0)   # behind him
	_afterimages.append({"node": ghost, "born": t, "life": life, "alpha": color.a})

func _update_afterimages(t: float) -> void:
	for ai in _afterimages.duplicate():
		var age: float = t - ai.born
		var ghost: Sprite2D = ai.node
		if age >= ai.life:
			ghost.queue_free()
			_afterimages.erase(ai)
		else:
			ghost.modulate.a = ai.alpha * (1.0 - age / ai.life)

# --- parry feedback -------------------------------------------------------

## Where he was parried: a white flash, a thin white slash through it,
## and two grey rings spreading out to the left.
func _draw_parry_fx() -> void:
	_draw_parry_press()
	for fx in _parry_fx.duplicate():
		var age: float = _song_time - fx.at
		if age > PARRY_RING_TIME + 0.1:
			_parry_fx.erase(fx)
			continue
		var p: Vector2 = fx.pos
		if age < PARRY_CIRCLE_TIME:
			var k := age / PARRY_CIRCLE_TIME
			_attack_layer.draw_circle(p, 30.0 + 10.0 * k, Color(1, 1, 1, 1.0 - k * k))
		if age < PARRY_SLASH_TIME:
			var k := age / PARRY_SLASH_TIME
			var dir := Vector2(0.22, 1.0).normalized()
			var half := 200.0 + 60.0 * k
			_attack_layer.draw_line(p - dir * half, p + dir * half, Color(1, 1, 1, 1.0 - k), 4.0)
		for i in range(2):
			var ring_age := age - 0.05 * i
			if ring_age < 0.0 or ring_age >= PARRY_RING_TIME:
				continue
			var k := ring_age / PARRY_RING_TIME
			var ry := 50.0 + 80.0 * k + 18.0 * i
			var center := p + Vector2(-20.0 - 60.0 * k - 26.0 * i, 0.0)
			var col := PARRY_RING_COLOR
			col.a = 1.0 - k
			_attack_layer.draw_polyline(_ellipse(center, ry * 0.32, ry), col, 5.0 - 2.0 * k)

func _ellipse(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(41):
		var a := TAU * i / 40.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

# --- helpers --------------------------------------------------------------

## Boss position during an attack: moving from his spot to the launch
## point, waiting there, then accelerating sideways into the highway,
## arriving exactly at the attack's time.
func _attacker_pos(atk: Dictionary, t: float) -> Vector2:
	var launch := _launch_pos()
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

## Where the boss winds up and dashes from: his own spot (no step
## toward the highway first; he's close enough to strike from there).
func _launch_pos() -> Vector2:
	return _boss_pos()

## Boss position after the attack resolves: knocked back toward his spot
## when parried, or carried a little further into the highway when it hit.
func _aftermath_pos(atk: Dictionary, t: float) -> Vector2:
	var k := clampf((t - atk.resolved_at) / AFTERMATH_TIME, 0.0, 1.0)
	var from: Vector2 = atk.resolved_pos
	if atk.state == AttackState.PARRIED:
		var fade := 1.0 - k
		return from + Vector2(500.0 * (1.0 - fade * fade), -120.0 * k)
	return from.lerp(_strike_pos() - Vector2(LANE_WIDTH, 0.0), minf(1.0, k * 4.0))

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
