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
## - Triggers optional SFX players (Hit, Miss, Countdown, SegmentPass, SegmentFail).
## - Provides virtual hooks for level-specific mechanics:
##     _setup_level()
##     _on_segment_changed(index: int)
##     _on_segment_evaluated(segment_index: int, passed: bool)
##     _on_boss_damaged() / _on_player_damaged()

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
	_refresh_hud()
	_setup_level()

	if countdown_enabled:
		_run_countdown()
	else:
		if countdown_label != null:
			countdown_label.visible = false

func _process(delta: float) -> void:
	super._process(delta)
	if playback_active and not is_game_over and not is_level_complete:
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

	# Pre-calculate the maximum achievable score in each segment (simulating
	# a Perfect full-combo run starting at combo = 0 for each segment).
	var lane_count := lane_positions.size()
	for rec in _segment_records:
		var sim_combo := 0
		var max_pts := 0
		for note in chart_data.notes:
			if note.lane < 0 or note.lane >= lane_count:
				continue
			if note.time >= rec.start_time and note.time < rec.end_time:
				sim_combo += 1
				var mult := _multiplier_for_combo(sim_combo)
				max_pts += points_perfect * mult
				if note.get("sustain", 0.0) >= min_hold_duration:
					sim_combo += 1
					mult = _multiplier_for_combo(sim_combo)
					max_pts += points_held * mult
		rec.max_score = max_pts

	if not _segment_records.is_empty():
		_active_segment_record_idx = 0

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
		if _active_segment_record_idx >= 0 and _active_segment_record_idx < _segment_records.size():
			_segment_records[_active_segment_record_idx].earned_score += gained
		_play_sfx(hit_sfx)
	else:
		combo = 0
		multiplier = 1
		_play_sfx(miss_sfx)

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
		play_boss_animation(&"hit")
		_show_status_banner("SEGMENT %d CLEARED!" % rec.index, Color(0.3, 1.0, 0.55))
		_on_boss_damaged()
	else:
		hp = maxi(0, hp - 1)
		_play_sfx(segment_fail_sfx)
		play_boss_animation(&"attack")
		_show_status_banner("SEGMENT %d FAILED! -1 HP" % rec.index, Color(1.0, 0.3, 0.35))
		_on_player_damaged()
		_refresh_hud()
		if hp <= 0:
			_trigger_game_over()
			return

	_on_segment_evaluated(rec.index, passed)
	_refresh_hud()

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

func _trigger_game_over() -> void:
	is_game_over = true
	stop_playback()
	_save_session_results()
	_show_result_panel("GAME OVER", Color(1.0, 0.3, 0.35))

func _trigger_level_complete() -> void:
	is_level_complete = true
	stop_playback()
	_save_session_results()
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
				pct = roundi(float(rec.earned_score) / float(rec.max_score) * 100.0)
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

func _play_sfx(player: AudioStreamPlayer) -> void:
	if player != null and player.stream != null:
		player.play()

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

## Called when the player fails a segment and loses 1 HP.
func _on_player_damaged() -> void:
	pass
