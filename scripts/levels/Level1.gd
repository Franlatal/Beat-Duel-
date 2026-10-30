extends LevelBase
## Level 1 (Flower Man).
##
## Exclusive event "jarona": every "E jarona" in the played chart track
## is an attack that lands exactly on the event's tick. An attacker
## comes out of the boss, lines up with the hit line on the right of
## the lanes and winds up for jarona_windup_beats, then dashes sideways
## (across the lanes, not down them) into the target lane's box. Press the parry key (Z by default, rebindable in Options >
## Controls) as it lands to block it. Letting it land, or pressing
## during the dash but too early, costs jarona_damage HP. Presses
## before the dash starts are ignored, so there's no penalty for
## reacting to the warning.
##
## The chart event has no lane, so unless jarona_lane fixes one, each
## attack picks one from a fixed seed: the same lanes every run, never
## the same lane twice in a row.
##
## Visuals are placeholders drawn in code (red block, dash path, lane
## box warning, closing ring, text) until real sprites and animations replace them.

const JARONA_EVENT := "jarona"
const PARRY_ACTION := &"parry"
## Seed for picking each attack's lane. Change it for a different pattern.
const JARONA_LANE_SEED := 20261030

enum AttackState { WAITING, WINDUP, PARRIED, HIT, DONE }

@export_group("Jarona attack")
## How long the warning shows before the attack lands, in beats.
@export_range(1.0, 8.0, 0.5) var jarona_windup_beats: float = 3.0
## The last part of the windup, in beats, where the attacker dashes
## sideways into the lane box. Parry presses only count from here on.
@export_range(0.25, 4.0, 0.25) var jarona_dash_beats: float = 1.0
## Seconds either side of the landing that still count as a parry.
@export_range(0.03, 0.4, 0.01) var parry_window: float = 0.15
## Lives lost when an attack lands.
@export_range(1, 10, 1) var jarona_damage: int = 1
## Lane every attack targets (0 = leftmost). -1 picks a different lane
## for each attack.
@export_range(-1, 3, 1) var jarona_lane: int = -1

# --- placeholder look -----------------------------------------------------
## How far left of the boss's center the attacker waits for its dash,
## level with the hit line.
const LAUNCH_OFFSET_FROM_BOSS := 260.0
## Seconds the attacker takes to come out of the boss to that point.
const EMERGE_TIME := 0.25
const ATTACKER_SIZE := 64.0
## Radius of the closing ring when the windup starts. It shrinks onto
## the lane's hit marker at the moment the attack lands.
const RING_START_RADIUS := 120.0
const RING_END_RADIUS := 22.0
## Seconds the parry / hit effect and text stay after an attack resolves.
const AFTERMATH_TIME := 0.6
const ATTACK_COLOR := Color(1.0, 0.2, 0.3)
const PARRY_COLOR := Color(0.3, 1.0, 0.55)
const OUTLINE_COLOR := Color(0.051, 0.027, 0.129)

## One entry per jarona in the chart:
## {time, start, dash_start, lane, state, resolved_at, resolved_pos, label}
var _attacks: Array = []
var _attack_layer: Node2D

func _setup_level() -> void:
	_attack_layer = Node2D.new()
	_attack_layer.name = "JaronaLayer"
	_attack_layer.z_index = 10   # above notes
	add_child(_attack_layer)
	_attack_layer.draw.connect(_draw_attacks)
	_build_attacks()

func _process(delta: float) -> void:
	super._process(delta)
	if _attack_layer == null:
		return
	_attack_layer.visible = not is_game_over
	if playback_active and not is_game_over and not is_level_complete:
		_update_attacks(_song_time)
	_attack_layer.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PARRY_ACTION):
		if playback_active and not is_game_over and not is_level_complete:
			_try_parry()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

# --- attack timeline ------------------------------------------------------

func _build_attacks() -> void:
	_attacks.clear()
	var lane_count := lane_positions.size()
	if lane_count == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = JARONA_LANE_SEED
	var last_lane := -1
	for ev in chart_data.get("track_events", []):
		if ev.name != JARONA_EVENT:
			continue
		var lane := rng.randi_range(0, lane_count - 1)
		if lane == last_lane and lane_count > 1:
			lane = (lane + rng.randi_range(1, lane_count - 1)) % lane_count
		if jarona_lane >= 0:
			lane = mini(jarona_lane, lane_count - 1)
		last_lane = lane
		var hit_time: float = ev.time
		var beat := _beat_length_at(hit_time)
		_attacks.append({
			"time": hit_time,
			"start": hit_time - jarona_windup_beats * beat,
			"dash_start": hit_time - minf(jarona_dash_beats, jarona_windup_beats) * beat,
			"lane": lane,
			"state": AttackState.WAITING,
			"resolved_at": 0.0,
			"resolved_pos": Vector2.ZERO,
			"label": null,
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
				_resolve_attack(atk, false, t, "HIT! -%d HP" % jarona_damage)
			else:
				_update_windup_label(atk, t)
		elif state == AttackState.PARRIED or state == AttackState.HIT:
			var age: float = t - atk.resolved_at
			var label: Label = atk.label
			if age >= AFTERMATH_TIME:
				atk.state = AttackState.DONE
				label.queue_free()
				atk.label = null
			else:
				label.position.y = _label_y() - 60.0 * age
				label.modulate.a = 1.0 - age / AFTERMATH_TIME

func _start_windup(atk: Dictionary) -> void:
	atk.state = AttackState.WINDUP
	var label := Label.new()
	label.theme = UI_THEME
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", ATTACK_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", 8)
	label.size = Vector2(360, 64)
	label.position = Vector2(float(lane_positions[atk.lane]) - 180.0, _label_y())
	_attack_layer.add_child(label)
	atk.label = label
	_update_windup_label(atk, _song_time)
	play_boss_animation(&"attack")

func _update_windup_label(atk: Dictionary, t: float) -> void:
	var beats_left := ceili(maxf(0.0, (atk.time - t) / _beat_length_at(atk.time)))
	var count := str(beats_left) if beats_left > 0 else "NOW"
	var label: Label = atk.label
	label.text = "JARONA! %s\nPRESS %s" % [count, Settings.get_action_key_text(PARRY_ACTION)]

func _try_parry() -> void:
	var t := _current_song_time()
	for atk in _attacks:
		if atk.state != AttackState.WINDUP:
			continue
		var diff: float = t - atk.time
		if absf(diff) <= parry_window:
			_resolve_attack(atk, true, t, "PARRIED!")
		elif t >= atk.dash_start:
			_resolve_attack(atk, false, t, "TOO EARLY! -%d HP" % jarona_damage)
		return   # only the next attack to land can be parried

func _resolve_attack(atk: Dictionary, parried: bool, t: float, text: String) -> void:
	atk.resolved_pos = _attacker_pos(atk, t)
	atk.state = AttackState.PARRIED if parried else AttackState.HIT
	atk.resolved_at = t
	var col := PARRY_COLOR if parried else ATTACK_COLOR

	var label: Label = atk.label
	label.text = text
	label.add_theme_color_override("font_color", col)

	var lane: int = atk.lane
	if lane < _lane_flash.size():
		_lane_flash[lane] = 1.0
		_lane_flash_color[lane] = col

	if parried:
		_play_sfx(hit_sfx)
		play_boss_animation(&"hit")
		_show_status_banner("JARONA PARRIED!", PARRY_COLOR)
	else:
		_play_sfx(segment_fail_sfx)
		_show_status_banner("JARONA HIT! -%d HP" % jarona_damage, ATTACK_COLOR)
		damage_player(jarona_damage)

# --- placeholder drawing --------------------------------------------------

func _draw_attacks() -> void:
	var t := _song_time
	for atk in _attacks:
		var state: int = atk.state
		if state == AttackState.WINDUP:
			_draw_windup(atk, t)
		elif state == AttackState.PARRIED or state == AttackState.HIT:
			_draw_aftermath(atk, t)

func _draw_windup(atk: Dictionary, t: float) -> void:
	var c := _attack_layer
	var lane_pos := _lane_box_pos(atk.lane)
	var launch := _launch_pos()
	var beats_left: float = maxf(0.0, (atk.time - t) / _beat_length_at(atk.time))
	# Brightest right on each beat of the windup, fading until the next.
	var pulse := 1.0 - fposmod(-beats_left, 1.0)

	# Dash path along the hit line, from the launch point to the lane box
	var path := Rect2(lane_pos.x, hit_line_y - 6.0, launch.x - lane_pos.x, 12.0)
	c.draw_rect(path, Color(ATTACK_COLOR, 0.15 + 0.25 * pulse))

	# Target lane box
	var box := Rect2(lane_pos - Vector2(LANE_WIDTH, LANE_WIDTH) / 2.0, Vector2(LANE_WIDTH, LANE_WIDTH))
	c.draw_rect(box, Color(ATTACK_COLOR, 0.15 + 0.35 * pulse))
	c.draw_rect(box, Color(ATTACK_COLOR, 0.9), false, 4.0)

	# Closing ring: lands on the hit marker exactly when the attack does
	var p := clampf(inverse_lerp(atk.start, atk.time, t), 0.0, 1.0)
	var ring_r := lerpf(RING_START_RADIUS, RING_END_RADIUS, p)
	c.draw_arc(lane_pos, ring_r, 0.0, TAU, 48, Color(1, 1, 1, 0.5 + 0.5 * p), 4.0)

	# The attacker: shakes at the launch point, then dashes sideways
	var pos := _attacker_pos(atk, t)
	if t >= atk.dash_start:
		c.draw_rect(Rect2(pos.x, hit_line_y - 20.0, launch.x - pos.x, 40.0), Color(ATTACK_COLOR, 0.3))
	elif t >= atk.start + EMERGE_TIME:
		pos.y += sin(t * 45.0) * 4.0 * pulse
	_draw_attacker(pos, ATTACK_COLOR, 1.0)

func _draw_aftermath(atk: Dictionary, t: float) -> void:
	var c := _attack_layer
	var lane_pos := _lane_box_pos(atk.lane)
	var k := clampf((t - atk.resolved_at) / AFTERMATH_TIME, 0.0, 1.0)
	var fade := 1.0 - k
	var from: Vector2 = atk.resolved_pos
	if atk.state == AttackState.PARRIED:
		# Knocked back toward the boss, with a burst on the lane box
		var pos := from + Vector2(500.0 * (1.0 - fade * fade), -120.0 * k)
		_draw_attacker(pos, Color.WHITE, fade)
		c.draw_arc(lane_pos, RING_END_RADIUS + 140.0 * k, 0.0, TAU, 48, Color(PARRY_COLOR, fade), 6.0)
	else:
		# Slams into the lane box
		c.draw_rect(Rect2(lane_pos - Vector2(LANE_WIDTH, 120.0) / 2.0, Vector2(LANE_WIDTH, 120.0)), Color(ATTACK_COLOR, 0.6 * fade))
		_draw_attacker(from.lerp(lane_pos, minf(1.0, k * 4.0)), ATTACK_COLOR, fade)

func _draw_attacker(center: Vector2, col: Color, alpha: float) -> void:
	var c := _attack_layer
	var half := ATTACKER_SIZE / 2.0
	var rect := Rect2(center - Vector2(half, half), Vector2(ATTACKER_SIZE, ATTACKER_SIZE))
	c.draw_rect(rect, Color(col, alpha))
	c.draw_rect(rect, Color(OUTLINE_COLOR, alpha), false, 4.0)
	# "!" mark
	c.draw_rect(Rect2(center.x - 4.0, center.y - 20.0, 8.0, 24.0), Color(1, 1, 1, alpha))
	c.draw_rect(Rect2(center.x - 4.0, center.y + 10.0, 8.0, 8.0), Color(1, 1, 1, alpha))

# --- helpers --------------------------------------------------------------

## Attacker's position: coming out of the boss to the launch point,
## waiting there, then accelerating sideways along the hit line into
## the lane box, arriving exactly at the attack's time.
func _attacker_pos(atk: Dictionary, t: float) -> Vector2:
	var launch := _launch_pos()
	if t < atk.start + EMERGE_TIME:
		var e := clampf(inverse_lerp(atk.start, atk.start + EMERGE_TIME, t), 0.0, 1.0)
		return _boss_pos().lerp(launch, 1.0 - (1.0 - e) * (1.0 - e))
	if t < atk.dash_start:
		return launch
	var q := clampf(inverse_lerp(atk.dash_start, atk.time, t), 0.0, 1.0)
	return launch.lerp(_lane_box_pos(atk.lane), q * q)

## Center of a lane's box on the hit line.
func _lane_box_pos(lane: int) -> Vector2:
	return Vector2(float(lane_positions[lane]), hit_line_y)

func _boss_pos() -> Vector2:
	if boss_anchor != null:
		return boss_anchor.position
	return Vector2(float(lane_positions[-1]) + 600.0, hit_line_y)

## Where the attacker waits before dashing: left of the boss, level
## with the hit line.
func _launch_pos() -> Vector2:
	return Vector2(_boss_pos().x - LAUNCH_OFFSET_FROM_BOSS, hit_line_y)

func _label_y() -> float:
	return hit_line_y - 220.0

## Seconds per beat at a song time, from the chart's tempo map.
func _beat_length_at(time: float) -> float:
	var bpm := 120.0
	for te in chart_data.get("tempo_events", []):
		if te.get("time", 0.0) <= time:
			bpm = te.bpm
		else:
			break
	return 60.0 / maxf(bpm, 1.0)
