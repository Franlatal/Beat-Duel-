class_name LevelBase
extends ChartPlayer
## Shared template behavior for every level scene (see scenes/levels/BaseLevel.tscn).
## Extend this for each level's own scene script (see scripts/levels/).
##
## Features provided to every level out of the box:
## - Reads selected level & difficulty from GameSession (supports both a shared
##   .chart with named difficulty tracks and per-difficulty chart_path overrides).
## - Positions 2, 3, or 4 lanes on the left-center of the 1920x1080 canvas and
##   remaps keys accordingly.
## - Runs a 3-2-1-START! countdown before rolling notes and audio.
## - Tracks Score, Combo Streak, and Combo Multiplier (1x -> 4x).
## - Tracks discrete Player HP (hearts/lives). At the end of each chart segment,
##   checks if the player reached segment_pass_ratio (default 70%) of that
##   segment's max possible score; if not, deducts 1 HP (0 HP = Game Over).
## - Drives the Boss AnimatedSprite2D on the right side of the screen (with an
##   automatic visual placeholder until custom sprite frames are assigned).
## - Plays sound effects on the SFX/ players (Hit, Miss, Countdown,
##   CountdownGo, SegmentPass, SegmentFail, Victory, GameOver). A player with
##   no stream set in the scene picks up the file of the same name from
##   sfx_folder (hit, miss, countdown, countdown_go, segment_pass,
##   segment_fail, victory, game_over; .wav, .ogg or .mp3); with no file it
##   stays silent. "hit" clicks on every Perfect / Good, "hold" loops while
##   a hold note is held (one per lane, pitched per lane), optional
##   "hold_end" plays when a hold is finished, and optional countdown_3,
##   countdown_2, countdown_1 replace "countdown" for that one step.
## - Plays the boss's voice clips from voice_folder, by file name: intro,
##   segment_pass, segment_fail, victory, game_over, plus one per chart track
##   event (an "E jakidding" in the played track plays jakidding.wav at that
##   moment). name_1, name_2, ... are picked from at random. See
##   play_boss_voice().
## - Provides virtual hooks for level-specific mechanics:
##     _setup_level()
##     _on_segment_changed(index: int)
##     _on_segment_evaluated(segment_index: int, passed: bool)
##     _on_boss_damaged() / _on_player_damaged()
##     _punish_failed_segment(segment_index: int)
## - damage_player(amount) for level mechanics that cost lives.

const LEVEL_SELECT_SCENE := "res://scenes/LevelSelect.tscn"
const UI_THEME := preload("res://themes/pixel_theme.tres")

## Horizontal spacing between lane columns, in pixels.
const LANE_SPACING := 140.0

## Leftward offset from dead center (960 - 400 = 560) so lanes sit on the
## left-center of the 1920x1080 screen and leave the right side for the boss.
const LANE_LEFT_OFFSET := 400.0

@export_group("Gameplay & HP")
## Starting (and maximum) discrete lives/hearts for this level.
@export_range(1, 10, 1) var max_hp: int = 3
## Fraction of a segment's maximum possible score required to avoid losing 1 HP.
@export_range(0.0, 1.0, 0.05) var segment_pass_ratio: float = 0.70
## How much a "Good" hit counts toward the segment %, as a share of a
## Perfect (a Good still scores points_good for the score).
@export_range(0.0, 1.0, 0.05) var segment_good_credit: float = 0.8
## Whether to run the 3-2-1 countdown before the song starts.
@export var countdown_enabled: bool = true
## Seconds per countdown step (3, 2, 1).
@export_range(0.2, 2.0, 0.05) var countdown_step_duration: float = 0.65

@export_group("Scoring & Combo")
@export var points_perfect: int = 100
@export var points_good: int = 50
@export var points_held: int = 50
## Consecutive hits needed to increase the combo multiplier by +1x.
@export_range(1, 50, 1) var combo_per_multiplier_step: int = 10
@export_range(1, 10, 1) var max_multiplier: int = 4

@export_group("Boss")
## Display name shown beneath/above the boss sprite.
@export var boss_name: String = "BOSS"

@export_group("Sound")
## Folder with the shared sound effects. A file named hit, miss, countdown,
## countdown_go, segment_pass, segment_fail, victory or game_over (.wav,
## .ogg or .mp3) is used for the SFX/ player of the same name, unless that
## player already has a stream set in the scene. Missing files stay silent.
@export_dir var sfx_folder: String = "res://sounds/sfx"
## Volume of the sound effects, in decibels (0 = as recorded).
@export_range(-40.0, 12.0, 0.5) var sfx_volume_db: float = 0.0
## Shortest gap between two miss sounds, in seconds, so a run of missed
## notes doesn't turn into a machine gun.
@export_range(0.0, 1.0, 0.01) var miss_sound_cooldown: float = 0.12
## Click (the "hit" file in sfx_folder) on every note you hit.
@export var hit_sounds_enabled: bool = true
## Extra volume for the note click, in decibels. It plays on every note,
## so it sits under the music by default.
@export_range(-40.0, 12.0, 0.5) var hit_sound_volume_db: float = -4.0
## Loop the "hold" file in sfx_folder while a hold note is held.
@export var hold_sounds_enabled: bool = true
## Extra volume for the hold loop, in decibels.
@export_range(-40.0, 12.0, 0.5) var hold_sound_volume_db: float = -6.0
## Pitch of the hold loop in each lane (1.0 = as recorded), left to right,
## so two holds at once sound like a chord instead of one louder tone.
@export var hold_lane_pitches: Array[float] = [1.0, 1.125, 1.25, 1.333]
## Folder with this level's boss voice clips, found by file name: intro,
## segment_pass, segment_fail, victory, game_over, and the name of any
## chart track event (jakidding.wav plays on "E jakidding"). Add _1, _2,
## ... to a name for variants picked at random. Empty = no voice.
@export_dir var voice_folder: String = ""
## Volume of the voice clips, in decibels (0 = as recorded).
@export_range(-40.0, 12.0, 0.5) var voice_volume_db: float = 0.0

# --- runtime state --------------------------------------------------------
var level: LevelData
var difficulty: DifficultyOption

var hp: int = 3
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var multiplier: int = 1
var total_notes_judged: int = 0
var total_notes_hit: int = 0
var is_game_over: bool = false
var is_level_complete: bool = false

# --- segment scoring state ------------------------------------------------
## Ordered list of segment definitions: [{index, start_time, end_time, max_score, earned_score, evaluated}]
var _segment_records: Array[Dictionary] = []
var _active_segment_record_idx: int = -1

# --- scene node references (from BaseLevel.tscn) --------------------------
@onready var boss_anchor: Node2D = get_node_or_null("BossAnchor")
@onready var boss_sprite: AnimatedSprite2D = get_node_or_null("BossAnchor/BossSprite")
@onready var boss_placeholder: Control = get_node_or_null("BossAnchor/BossPlaceholder")
@onready var boss_name_label: Label = get_node_or_null("BossAnchor/BossNameLabel")

@onready var hit_sfx: AudioStreamPlayer = get_node_or_null("SFX/HitSFX")
@onready var miss_sfx: AudioStreamPlayer = get_node_or_null("SFX/MissSFX")
@onready var countdown_sfx: AudioStreamPlayer = get_node_or_null("SFX/CountdownSFX")
@onready var segment_pass_sfx: AudioStreamPlayer = get_node_or_null("SFX/SegmentPassSFX")
@onready var segment_fail_sfx: AudioStreamPlayer = get_node_or_null("SFX/SegmentFailSFX")
@onready var countdown_go_sfx: AudioStreamPlayer = get_node_or_null("SFX/CountdownGoSFX")
@onready var victory_sfx: AudioStreamPlayer = get_node_or_null("SFX/VictorySFX")
@onready var game_over_sfx: AudioStreamPlayer = get_node_or_null("SFX/GameOverSFX")

@onready var back_button: Button = get_node_or_null("%BackButton")
@onready var hearts_container: HBoxContainer = get_node_or_null("%HeartsContainer")
@onready var score_value_label: Label = get_node_or_null("%ScoreValueLabel")
@onready var combo_value_label: Label = get_node_or_null("%ComboValueLabel")
@onready var segment_title_label: Label = get_node_or_null("%SegmentTitleLabel")
@onready var segment_score_label: Label = get_node_or_null("%SegmentScoreLabel")
@onready var status_banner: Label = get_node_or_null("%StatusBanner")
@onready var countdown_label: Label = get_node_or_null("%CountdownLabel")
@onready var result_panel: PanelContainer = get_node_or_null("%ResultPanel")
@onready var result_title_label: Label = get_node_or_null("%ResultTitleLabel")
@onready var result_stats_label: Label = get_node_or_null("%ResultStatsLabel")
@onready var retry_button: Button = get_node_or_null("%RetryButton")
@onready var menu_button: Button = get_node_or_null("%MenuButton")

var _boss_idle_tween: Tween
var _banner_tween: Tween

# --- sound state ----------------------------------------------------------
const SOUND_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]
## Highest variant number looked for (name_1 ... name_9).
const MAX_SOUND_VARIANTS := 9
## Voice cues every level has. Chart track events add their own.
const VOICE_CUES: Array[String] = ["intro", "segment_pass", "segment_fail", "victory", "game_over"]

var _voice_player: AudioStreamPlayer
## cue name -> Array[AudioStream] (empty when the folder has no such clip)
var _voice_clips: Dictionary = {}
## The last clip played for each cue, so variants don't repeat back to back.
var _last_voice_clip: Dictionary = {}
## Chart track events that have a voice clip: [{time, name}], sorted by time.
var _voice_events: Array = []
var _next_voice_event: int = 0
var _last_miss_sound_msec: int = -1000000
## Optional "hold_end" sound (finished hold), made in _setup_sound().
var hold_end_sfx: AudioStreamPlayer
## countdown_3 / countdown_2 / countdown_1 by step text ("3", "2", "1").
var _countdown_step_sounds: Dictionary = {}
var _countdown_default_stream: AudioStream
## The "hold" loop, and one player + fade gain (0..1) per lane.
var _hold_stream: AudioStream
var _hold_players: Array[AudioStreamPlayer] = []
var _hold_gains: Array[float] = []
var _hold_base_db: float = 0.0
## Fade times of the hold loop, so it never clicks on or off.
const HOLD_FADE_IN := 0.04
const HOLD_FADE_OUT := 0.1

func _ready() -> void:
	level = GameSession.current_level
	difficulty = GameSession.current_difficulty

	if difficulty != null:
		track_name = difficulty.track_name
		if difficulty.chart_path != "":
			chart_path = difficulty.chart_path
		lane_positions = _lane_positions_for(difficulty.lane_count)
	else:
		# Direct-run (F6) fallback -- no GameSession data yet, so this
		# scene's own Inspector values for track_name/lane_positions are
		# used as-is.
		lane_positions = _lane_positions_for(lane_positions.size() if not lane_positions.is_empty() else 4)

	hp = max_hp
	if countdown_enabled:
		autostart = false

	_setup_ui_connections()
	super._ready()   # ChartPlayer._ready(): parses the chart, sets up audio/notes

	note_judged.connect(_on_level_note_judged)
	segment_changed.connect(_on_chart_segment_changed)
	song_finished.connect(_on_chart_song_finished)

	_build_segment_records()
	_setup_boss_visuals()
	_setup_sound()
	_refresh_hud()
	_setup_level()

	play_boss_voice("intro")
	if countdown_enabled:
		_run_countdown()
	else:
		if countdown_label != null:
			countdown_label.visible = false

func _process(delta: float) -> void:
	super._process(delta)
	_update_hold_sounds(delta)
	if playback_active and not is_game_over and not is_level_complete:
		_update_voice_events(_song_time)
		_check_pending_segment_evaluations()

# --- lane & input mapping -------------------------------------------------

func _lane_positions_for(count: int) -> Array:
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	var center := width / 2.0 - LANE_LEFT_OFFSET
	var start := center - LANE_SPACING * (count - 1) / 2.0
	var positions: Array = []
	for i in range(count):
		positions.append(start + LANE_SPACING * i)
	return positions

# --- countdown ------------------------------------------------------------

func _run_countdown() -> void:
	if countdown_label == null:
		start_playback()
		return

	countdown_label.visible = true
	var steps := ["3", "2", "1", "DUEL!"]
	for i in range(steps.size()):
		if not is_inside_tree():
			return
		countdown_label.text = steps[i]
		countdown_label.scale = Vector2(1.35, 1.35)
		countdown_label.modulate = Color(1, 1, 1, 1)
		countdown_label.pivot_offset = countdown_label.size / 2.0
		if i == steps.size() - 1 and countdown_go_sfx != null and countdown_go_sfx.stream != null:
			_play_sfx(countdown_go_sfx)
		elif countdown_sfx != null:
			countdown_sfx.stream = _countdown_step_sounds.get(steps[i], _countdown_default_stream)
			_play_sfx(countdown_sfx)

		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(countdown_label, "scale", Vector2.ONE, countdown_step_duration * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i == steps.size() - 1:
			tw.tween_property(countdown_label, "modulate:a", 0.0, countdown_step_duration * 0.5).set_delay(countdown_step_duration * 0.35)
		await get_tree().create_timer(countdown_step_duration).timeout

	if is_inside_tree():
		countdown_label.visible = false
		start_playback()

# --- scoring, combo & segment HP logic ------------------------------------

func _build_segment_records() -> void:
	_segment_records.clear()
	if chart_data.is_empty():
		return

	var raw_segments: Array = chart_data.get("segments", [])
	if raw_segments.is_empty():
		_segment_records.append({
			"index": 1,
			"start_time": -INF,
			"end_time": INF,
			"max_score": 0,
			"earned_score": 0,
			"evaluated": false,
		})
	else:
		for i in range(raw_segments.size()):
			var seg: Dictionary = raw_segments[i]
			var s_time: float = seg.time if i > 0 else -INF
			var e_time: float = raw_segments[i + 1].time if i + 1 < raw_segments.size() else INF
			_segment_records.append({
				"index": seg.index,
				"start_time": s_time,
				"end_time": e_time,
				"max_score": 0,
				"earned_score": 0,
				"evaluated": false,
			})

	# The most a segment can earn: every note in it Perfect (and every hold
	# held). Segment credit ignores the combo multiplier (that's only for
	# the score), and each judgement counts toward the segment its note
	# belongs to, so a segment always ends between 0% and 100%.
	var lane_count := lane_positions.size()
	for rec in _segment_records:
		var max_pts := 0
		for note in chart_data.notes:
			if note.lane < 0 or note.lane >= lane_count:
				continue
			if note.time >= rec.start_time and note.time < rec.end_time:
				max_pts += points_perfect
				if note.get("sustain", 0.0) >= min_hold_duration:
					max_pts += points_held
		rec.max_score = max_pts

	if not _segment_records.is_empty():
		_active_segment_record_idx = 0

## How far the current segment is toward its maximum, 0..1 (Perfect on
## every note = 1). The HUD's segment meter reads this.
func get_segment_progress() -> float:
	if _active_segment_record_idx < 0 or _active_segment_record_idx >= _segment_records.size():
		return 0.0
	var rec: Dictionary = _segment_records[_active_segment_record_idx]
	if rec.max_score <= 0:
		return 1.0
	return clampf(float(rec.earned_score) / float(rec.max_score), 0.0, 1.0)

func _multiplier_for_combo(c: int) -> int:
	return clampi(1 + c / combo_per_multiplier_step, 1, max_multiplier)

func _record_index_for_time(t: float) -> int:
	for i in range(_segment_records.size() - 1, -1, -1):
		if t >= _segment_records[i].start_time:
			return i
	return 0 if not _segment_records.is_empty() else -1

func _on_level_note_judged(result: String, _lane_index: int) -> void:
	if is_game_over or is_level_complete:
		return

	total_notes_judged += 1
	var base_pts := 0
	var is_hit := false

	match result:
		"Perfect":
			base_pts = points_perfect
			is_hit = true
		"Good":
			base_pts = points_good
			is_hit = true
		"Held":
			base_pts = points_held
			is_hit = true
		"Miss", "Dropped":
			base_pts = 0
			is_hit = false

	if is_hit:
		total_notes_hit += 1
		combo += 1
		max_combo = maxi(max_combo, combo)
		multiplier = _multiplier_for_combo(combo)
		var gained := base_pts * multiplier
		score += gained
		var credit := base_pts
		if result == "Good":
			credit = roundi(points_perfect * segment_good_credit)
		var rec_idx := _active_segment_record_idx
		if not is_nan(judged_note_time):
			rec_idx = _record_index_for_time(judged_note_time)
		if rec_idx >= 0 and rec_idx < _segment_records.size():
			_segment_records[rec_idx].earned_score += credit
		if result == "Held":
			_play_sfx(hold_end_sfx)   # the head already clicked
		elif hit_sounds_enabled:
			_play_hit_sound()
	else:
		combo = 0
		multiplier = 1
		_play_miss_sound()

	_refresh_hud()

func _on_chart_segment_changed(seg_index: int) -> void:
	for i in range(_segment_records.size()):
		if _segment_records[i].index == seg_index:
			_active_segment_record_idx = i
			break
	_refresh_hud()

## Checks if any earlier segment has finished all its notes and can now be graded.
func _check_pending_segment_evaluations() -> void:
	for i in range(_active_segment_record_idx):
		var rec: Dictionary = _segment_records[i]
		if rec.evaluated:
			continue
		if _has_active_notes_before(rec.end_time):
			continue
		_evaluate_segment(i)

func _has_active_notes_before(end_time: float) -> bool:
	for note in spawned_notes:
		var state: int = note.get_meta("state")
		if state == NoteState.DROPPED:
			continue
		var hit_time: float = note.get_meta("hit_time")
		if hit_time < end_time:
			return true
	return false

func _evaluate_segment(record_idx: int) -> void:
	if record_idx < 0 or record_idx >= _segment_records.size():
		return
	var rec: Dictionary = _segment_records[record_idx]
	if rec.evaluated:
		return
	rec.evaluated = true

	if rec.max_score <= 0:
		return

	var required := ceili(float(rec.max_score) * segment_pass_ratio)
	var passed: bool = rec.earned_score >= required

	if passed:
		_play_sfx(segment_pass_sfx)
		play_boss_voice("segment_pass")
		play_boss_animation(&"hit")
		_show_status_banner("SEGMENT %d CLEARED!" % rec.index, Color(0.3, 1.0, 0.55))
		_on_boss_damaged()
	else:
		_play_sfx(segment_fail_sfx)
		play_boss_voice("segment_fail")
		_punish_failed_segment(rec.index)
		if is_game_over:
			return

	_on_segment_evaluated(rec.index, passed)
	_refresh_hud()

## Takes lives from the player (a failed segment, or a level's own attack
## such as Level 1's jarona) and ends the run at 0 HP.
func damage_player(amount: int = 1) -> void:
	if is_game_over or is_level_complete:
		return
	hp = maxi(0, hp - amount)
	_on_player_damaged()
	_refresh_hud()
	if hp <= 0:
		_trigger_game_over()

func _on_chart_song_finished() -> void:
	if is_game_over or is_level_complete:
		return
	# Evaluate any remaining un-evaluated segments (including the final one).
	for i in range(_segment_records.size()):
		if not _segment_records[i].evaluated:
			_evaluate_segment(i)
			if is_game_over:
				return
	_trigger_level_complete()

## Ends the run as a loss. title is the heading of the result panel, for
## levels that lose in their own way (e.g. Level 1's "YOU WERE SPARED").
func _trigger_game_over(title: String = "GAME OVER") -> void:
	is_game_over = true
	stop_playback()
	_save_session_results()
	_play_sfx(game_over_sfx)
	play_boss_voice("game_over")
	_show_result_panel(title, Color(1.0, 0.3, 0.35))

func _trigger_level_complete() -> void:
	is_level_complete = true
	stop_playback()
	_save_session_results()
	_play_sfx(victory_sfx)
	play_boss_voice("victory")
	_show_result_panel("VICTORY!", Color(0.3, 1.0, 0.55))

func _save_session_results() -> void:
	GameSession.last_score = score
	GameSession.last_accuracy = (float(total_notes_hit) / float(total_notes_judged) * 100.0) if total_notes_judged > 0 else 0.0

# --- boss visuals & animations --------------------------------------------

func _setup_boss_visuals() -> void:
	if boss_name_label != null:
		if level != null and level.title != "":
			boss_name_label.text = boss_name if boss_name != "BOSS" else level.title.to_upper()
		else:
			boss_name_label.text = boss_name

	var has_custom_frames := false
	if boss_sprite != null and boss_sprite.sprite_frames != null:
		if boss_sprite.sprite_frames.has_animation(&"idle") and boss_sprite.sprite_frames.get_frame_count(&"idle") > 0:
			has_custom_frames = true
			boss_sprite.play(&"idle")
		if not boss_sprite.animation_finished.is_connected(_on_boss_anim_finished):
			boss_sprite.animation_finished.connect(_on_boss_anim_finished)

	if boss_placeholder != null:
		boss_placeholder.visible = not has_custom_frames

	if boss_anchor != null:
		var base_y := boss_anchor.position.y
		_boss_idle_tween = create_tween().set_loops()
		_boss_idle_tween.tween_property(boss_anchor, "position:y", base_y - 12.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_boss_idle_tween.tween_property(boss_anchor, "position:y", base_y + 12.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Plays an animation on the boss sprite (e.g. "idle", "hit", "attack") and
## flashes/nudges the boss anchor so even placeholder bosses react visibly.
func play_boss_animation(anim_name: StringName) -> void:
	if boss_sprite != null and boss_sprite.sprite_frames != null:
		if boss_sprite.sprite_frames.has_animation(anim_name) and boss_sprite.sprite_frames.get_frame_count(anim_name) > 0:
			boss_sprite.play(anim_name)

	if boss_anchor != null:
		var tw := create_tween()
		if anim_name == &"hit":
			boss_anchor.modulate = Color(1.8, 0.5, 0.5)
			tw.tween_property(boss_anchor, "modulate", Color.WHITE, 0.35)
		elif anim_name == &"attack":
			var orig_x := boss_anchor.position.x
			boss_anchor.modulate = Color(1.5, 1.3, 0.4)
			tw.tween_property(boss_anchor, "position:x", orig_x - 45.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(boss_anchor, "position:x", orig_x, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(boss_anchor, "modulate", Color.WHITE, 0.35)

func _on_boss_anim_finished() -> void:
	if boss_sprite != null and boss_sprite.sprite_frames != null:
		if boss_sprite.animation != &"idle" and boss_sprite.sprite_frames.has_animation(&"idle"):
			boss_sprite.play(&"idle")

# --- HUD & UI -------------------------------------------------------------

func _setup_ui_connections() -> void:
	if back_button != null:
		back_button.pressed.connect(_on_back_pressed)
	else:
		# Fallback if a scene doesn't instance BaseLevel.tscn
		_setup_fallback_back_button()

	if retry_button != null:
		retry_button.pressed.connect(_on_retry_pressed)
	if menu_button != null:
		menu_button.pressed.connect(_on_back_pressed)
	if result_panel != null:
		result_panel.visible = false
	if status_banner != null:
		status_banner.modulate.a = 0.0

func _refresh_hud() -> void:
	# HP Hearts (crisp pixel-art hearts)
	if hearts_container != null:
		for child in hearts_container.get_children():
			child.queue_free()
		for i in range(max_hp):
			hearts_container.add_child(_create_heart_icon(i < hp))

	# Score & Combo
	if score_value_label != null:
		score_value_label.text = "%06d" % score
	if combo_value_label != null:
		combo_value_label.text = "%dx  [%dx]" % [combo, multiplier]

	# Segment Progress
	if segment_title_label != null and segment_score_label != null:
		if _active_segment_record_idx >= 0 and _active_segment_record_idx < _segment_records.size():
			var rec: Dictionary = _segment_records[_active_segment_record_idx]
			segment_title_label.text = "SEGMENT %d" % rec.index
			var pct := 100
			if rec.max_score > 0:
				pct = mini(100, roundi(float(rec.earned_score) / float(rec.max_score) * 100.0))
			var req_pct := roundi(segment_pass_ratio * 100.0)
			segment_score_label.text = "%d%% / %d%%" % [pct, req_pct]
			if pct >= req_pct:
				segment_score_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.55))
			else:
				segment_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		else:
			segment_title_label.text = "SEGMENT -"
			segment_score_label.text = "--%"

const HEART_BITMAP := [
	[0, 1, 1, 0, 1, 1, 0],
	[1, 2, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 0],
	[0, 0, 1, 1, 1, 0, 0],
	[0, 0, 0, 1, 0, 0, 0],
]

func _create_heart_icon(filled: bool) -> Control:
	var icon := Control.new()
	var px := 4.0
	icon.custom_minimum_size = Vector2(7.0 * px, 6.0 * px)
	var main_col := Color(0.95, 0.18, 0.38) if filled else Color(0.28, 0.2, 0.35, 0.65)
	var shine_col := Color(1.0, 0.78, 0.86) if filled else Color(0.38, 0.3, 0.45, 0.45)
	icon.draw.connect(func():
		for r in range(HEART_BITMAP.size()):
			var row: Array = HEART_BITMAP[r]
			for c in range(row.size()):
				var cell: int = row[c]
				if cell == 0:
					continue
				var col := shine_col if cell == 2 else main_col
				icon.draw_rect(Rect2(c * px, r * px, px, px), col)
	)
	return icon

func _show_status_banner(text: String, col: Color) -> void:
	if status_banner == null:
		return
	status_banner.text = text
	status_banner.add_theme_color_override("font_color", col)
	status_banner.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.2)
	_banner_tween.tween_property(status_banner, "modulate:a", 0.0, 0.4)

func _show_result_panel(title_text: String, title_col: Color) -> void:
	# The Deltarune style end screen (scripts/BattleResultScreen.gd).
	var screen := get_node_or_null("%ResultScreen")
	if screen != null and screen.has_method("show_result"):
		var kind := "victory" if is_level_complete else ("game_over" if title_text == "GAME OVER" else "loss")
		screen.call("show_result", kind, title_text, {
			"score": score, "max_combo": max_combo, "accuracy": GameSession.last_accuracy,
			"hp": hp, "max_hp": max_hp,
		})
		return
	if result_panel == null:
		return
	result_panel.visible = true
	if result_title_label != null:
		result_title_label.text = title_text
		result_title_label.add_theme_color_override("font_color", title_col)
	if result_stats_label != null:
		var acc := GameSession.last_accuracy
		result_stats_label.text = "SCORE: %d\nMAX COMBO: %dx\nACCURACY: %.1f%%\nHP REMAINING: %d / %d" % [
			score, max_combo, acc, hp, max_hp
		]
	if retry_button != null:
		retry_button.grab_focus()

func _setup_fallback_back_button() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var btn := Button.new()
	btn.text = "BACK"
	btn.theme = UI_THEME
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.position = Vector2(24, 24)
	btn.pressed.connect(_on_back_pressed)
	layer.add_child(btn)

func _on_retry_pressed() -> void:
	get_tree().reload_current_scene()

func _on_back_pressed() -> void:
	stop_playback()
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)

# --- sound effects & boss voice -------------------------------------------

func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()

## Miss sound, with a short cooldown and a slight random pitch so a run
## of misses doesn't sound like one sample on repeat.
func _play_miss_sound() -> void:
	if miss_sfx == null or miss_sfx.stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_miss_sound_msec < int(miss_sound_cooldown * 1000.0):
		return
	_last_miss_sound_msec = now
	miss_sfx.pitch_scale = randf_range(0.94, 1.06)
	miss_sfx.play()

## Note click, with a tiny random pitch so fast runs don't sound robotic.
## The player has room for several at once, so chords and fast notes
## never cut each other off.
func _play_hit_sound() -> void:
	if hit_sfx == null or hit_sfx.stream == null:
		return
	hit_sfx.pitch_scale = randf_range(0.97, 1.03)
	hit_sfx.play()

## Fades the hold loop in on every lane that is holding a note right now
## and out on the rest. Polled each frame, so drops, releases, game over
## and leaving the level all stop it without extra hooks.
func _update_hold_sounds(delta: float) -> void:
	if _hold_stream == null:
		return
	var held := {}
	if hold_sounds_enabled and playback_active and not is_game_over and not is_level_complete:
		for note in spawned_notes:
			if note.get_meta("state", -1) == NoteState.HOLDING:
				held[int(note.get_meta("lane_index", 0))] = true
	for lane in held:
		_hold_player(lane)
	for lane in range(_hold_players.size()):
		var player := _hold_players[lane]
		var target := 1.0 if held.has(lane) else 0.0
		var fade := HOLD_FADE_IN if target > _hold_gains[lane] else HOLD_FADE_OUT
		_hold_gains[lane] = move_toward(_hold_gains[lane], target, delta / fade)
		if _hold_gains[lane] > 0.0:
			player.volume_db = _hold_base_db + linear_to_db(_hold_gains[lane])
			if not player.playing:
				player.play()
		elif player.playing:
			player.stop()

## The hold loop player for a lane, made the first time it's needed.
func _hold_player(lane: int) -> AudioStreamPlayer:
	while _hold_players.size() <= lane:
		var idx := _hold_players.size()
		var player := AudioStreamPlayer.new()
		player.name = "HoldSFX%d" % idx
		player.stream = _hold_stream
		player.pitch_scale = hold_lane_pitches[idx] if idx < hold_lane_pitches.size() else 1.0
		player.volume_db = -80.0
		_route_to_bus(player, &"SFX")
		# Fallback for a file that won't loop: start it again.
		player.finished.connect(func():
			if _hold_gains[idx] > 0.0:
				player.play())
		var parent := get_node_or_null("SFX")
		(parent if parent != null else self).add_child(player)
		_hold_players.append(player)
		_hold_gains.append(0.0)
	return _hold_players[lane]

## Turns on looping for a sound file loaded at runtime, so the hold sound
## can be any .wav / .ogg / .mp3 without touching its import settings.
func _make_looping(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.set("loop", true)

## Plays one of the boss's voice clips for a cue (a file name in
## voice_folder without its extension or variant number, e.g. "intro" or
## "jakidding"). Does nothing when the folder has no clip for it, so
## levels can call this for cues whose audio doesn't exist yet. A new
## line cuts off the one still playing unless interrupt is false, in
## which case it's skipped instead. Returns true if a clip started.
func play_boss_voice(cue: String, interrupt: bool = true) -> bool:
	if _voice_player == null:
		return false
	var clips: Array = _load_voice_cue(cue)
	if clips.is_empty():
		return false
	if _voice_player.playing and not interrupt:
		return false
	var clip: AudioStream = clips.pick_random()
	if clips.size() > 1:
		while clip == _last_voice_clip.get(cue):
			clip = clips.pick_random()
	_last_voice_clip[cue] = clip
	_voice_player.stream = clip
	_voice_player.play()
	return true

## True if voice_folder has at least one clip for this cue.
func has_boss_voice(cue: String) -> bool:
	return not _load_voice_cue(cue).is_empty()

func _setup_sound() -> void:
	hit_sfx = _prepare_sfx(hit_sfx, "hit")
	miss_sfx = _prepare_sfx(miss_sfx, "miss")
	countdown_sfx = _prepare_sfx(countdown_sfx, "countdown")
	countdown_go_sfx = _prepare_sfx(countdown_go_sfx, "countdown_go")
	segment_pass_sfx = _prepare_sfx(segment_pass_sfx, "segment_pass")
	segment_fail_sfx = _prepare_sfx(segment_fail_sfx, "segment_fail")
	victory_sfx = _prepare_sfx(victory_sfx, "victory")
	game_over_sfx = _prepare_sfx(game_over_sfx, "game_over")
	hold_end_sfx = _prepare_sfx(get_node_or_null("SFX/HoldEndSFX"), "hold_end")
	hit_sfx.volume_db += hit_sound_volume_db
	hit_sfx.max_polyphony = 6

	_countdown_default_stream = countdown_sfx.stream
	for step in ["3", "2", "1"]:
		var step_sound: AudioStream = _find_sfx("countdown_" + step)
		if step_sound != null:
			_countdown_step_sounds[step] = step_sound

	_hold_stream = _find_sfx("hold")
	if _hold_stream != null:
		_make_looping(_hold_stream)
	_hold_base_db = sfx_volume_db + hold_sound_volume_db

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "BossVoice"
	_voice_player.volume_db = voice_volume_db
	_route_to_bus(_voice_player, &"Voice")
	add_child(_voice_player)

	# Load every clip up front so nothing hitches mid-song.
	for cue in VOICE_CUES:
		_load_voice_cue(cue)
	_voice_events.clear()
	_next_voice_event = 0
	for ev in chart_data.get("track_events", []):
		if has_boss_voice(ev.name):
			_voice_events.append({"time": ev.time, "name": ev.name})

## Makes sure an SFX player exists (scenes that don't have the node get
## one), gives it the file from sfx_folder if its stream is empty, and
## applies the volume.
func _prepare_sfx(player: AudioStreamPlayer, sound_name: String) -> AudioStreamPlayer:
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = sound_name.to_pascal_case() + "SFX"
		var parent := get_node_or_null("SFX")
		(parent if parent != null else self).add_child(player)
	if player.stream == null and sfx_folder != "":
		player.stream = _find_sound(sfx_folder, sound_name)
	player.volume_db += sfx_volume_db
	_route_to_bus(player, &"SFX")
	return player

## Sends a player to an audio bus if the project has one by that name
## (so separate SFX / Voice volume sliders work once the buses exist),
## else leaves it on Master.
func _route_to_bus(player: AudioStreamPlayer, bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		player.bus = bus

## Plays the voice clip of each chart track event as the song reaches it.
func _update_voice_events(song_time: float) -> void:
	while _next_voice_event < _voice_events.size() and song_time >= _voice_events[_next_voice_event].time:
		play_boss_voice(_voice_events[_next_voice_event].name)
		_next_voice_event += 1

## The clips for a cue: name.ext plus name_1.ext ... name_9.ext.
func _load_voice_cue(cue: String) -> Array:
	if _voice_clips.has(cue):
		return _voice_clips[cue]
	var clips: Array = []
	if voice_folder != "" and cue != "":
		var single := _find_sound(voice_folder, cue)
		if single != null:
			clips.append(single)
		for i in range(1, MAX_SOUND_VARIANTS + 1):
			var variant := _find_sound(voice_folder, "%s_%d" % [cue, i])
			if variant != null:
				clips.append(variant)
	_voice_clips[cue] = clips
	return clips

## A file from sfx_folder by name, or null.
func _find_sfx(sound_name: String) -> AudioStream:
	return _find_sound(sfx_folder, sound_name) if sfx_folder != "" else null

## The sound file called sound_name in a folder, whatever its format.
func _find_sound(folder: String, sound_name: String) -> AudioStream:
	for ext in SOUND_EXTENSIONS:
		var path := "%s/%s.%s" % [folder.trim_suffix("/"), sound_name, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null

# --- virtual hooks for subclasses -----------------------------------------

## Override per level for one-time setup once the chart/audio pipeline is
## running (e.g. spawning level-specific scenery). Empty by default.
func _setup_level() -> void:
	pass

## Called when a segment finishes and has been graded.
func _on_segment_evaluated(_segment_index: int, _passed: bool) -> void:
	pass

## Called when the player clears a segment and damages the boss.
func _on_boss_damaged() -> void:
	pass

## Called whenever the player loses HP (see damage_player()).
func _on_player_damaged() -> void:
	pass

## What a failed segment costs, called right after its sound and voice
## cue. By default the boss attacks and the player loses 1 HP. Override
## it for a level with a penalty of its own (Level 1 fills a MERCY meter
## instead); such a level ends the run with _trigger_game_over().
func _punish_failed_segment(segment_index: int) -> void:
	play_boss_animation(&"attack")
	_show_status_banner("SEGMENT %d FAILED! -1 HP" % segment_index, Color(1.0, 0.3, 0.35))
	damage_player(1)
