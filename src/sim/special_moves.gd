# 原作必殺技の共通合法判定と、接触成立時の球状態設定。
extends RefCounted

const Chars := preload("res://src/sim/chars.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")
const SpecialBall := preload("res://src/sim/special_ball.gd")

static func can_activate(s, actor: int, special_id: int, cfg) -> bool:
	if actor < 0 or actor >= s.players.size():
		return false
	if s.phase != SimStateScript.PHASE_RALLY or s.serve_ball != 0 \
			or s.serve_flight != 0 or s.ball_held_by >= 0:
		return false
	var p = s.players[actor]
	if not Chars.has_super(p.char_id, special_id):
		return false
	if p.burnout_ticks > 0 or p.stun_ticks > 0 or p.burn > 0 \
			or p.shock_ticks > 0 or p.bubble_ticks > 0 or p.quake_stun > 0 \
			or p.dive != 0:
		return false
	return CombatResources.can_pay(p, CombatResources.special_drive_cost(cfg))

static func select_hit_special(s, actor: int, input: int, cfg) -> int:
	if (input & SimInput.IN_ABILITY1) == 0:
		return 0
	if actor < 0 or actor >= s.players.size():
		return 0
	var p = s.players[actor]
	var char_def: Dictionary = Chars.DEFS.get(p.char_id, {})
	var supers: Dictionary = char_def.get("supers", {})
	var required_contact: int = Chars.SPECIAL_CONTACT_GROUND_HIT \
		if p.on_ground == 1 else Chars.SPECIAL_CONTACT_AIR_HIT
	for special_id in supers:
		if not can_activate(s, actor, special_id, cfg):
			continue
		var entry: Dictionary = Chars.super_def(special_id)
		for activation in entry.activations:
			if int(activation.contact) != required_contact:
				continue
			if int(activation.requires_ability) == 0:
				continue
			if not _direction_matches(actor, input, int(activation.direction)):
				continue
			if int(activation.requires_normal_ball) != 0 \
					and s.ball_special_id != 0:
				continue
			if int(activation.friendly_ball) != 0 \
					and s.last_touch_team != SimStateScript.team_of(actor):
				continue
			var original_height_y: int = int(activation.original_height_y)
			if original_height_y >= 0 \
					and not SpecialBall.is_above_original_y(
						s, original_height_y, cfg):
				continue
			if int(activation.requires_apex) != 0 \
					and absi(s.ball_vy) * 5 >= cfg.gravity * 16:
				continue
			return special_id
	return 0

static func commit_cost(p, cfg) -> bool:
	var result: Dictionary = CombatResources.spend_committed(
		p, CombatResources.special_drive_cost(cfg), cfg)
	return bool(result.authorized)

static func apply_ball_contact(s, actor: int, special_id: int) -> void:
	SpecialBall.set_special(s, special_id, actor, s.ball_vx)
	var entry: Dictionary = Chars.super_def(special_id)
	var power: int = int(entry.power)
	s.ball_power = 1 if power > 0 else 0
	if power > 0:
		s.ball_attack_kind = SimStateScript.BALL_ATTACK_NORMAL
	s.ball_health_damage = power
	s.ball_defense_class = int(entry.defense_class)

# 吸引は打球接触ではなく空中の自己行動。Dの新規押下時、原作範囲内に
# 前方の対象球がある場合だけ開始し、この場で一度だけ費用を確定する。
static func try_start_action(s, actor: int, input: int, cfg) -> bool:
	if actor < 0 or actor >= s.players.size():
		return false
	var p = s.players[actor]
	if p.special_action != 0 or p.on_ground != 0 or p.ability_latch != 0 \
			or p.hit_cooldown > 0:
		return false
	if not can_activate(s, actor, Chars.SUPER_SUCTION, cfg):
		return false
	if (input & SimInput.IN_ABILITY1) == 0 \
			or not _direction_matches(actor, input, Chars.SPECIAL_DIR_BACK):
		return false
	if not _suction_target_in_range(s, actor, cfg):
		return false
	if not commit_cost(p, cfg):
		return false
	p.special_action = Chars.SUPER_SUCTION
	p.special_action_ticks = 0
	CombatResources.stop_attack_recovery(p)
	return true

# trueは吸引捕球が成立し、呼び出し側が同tickに通常空中トスを解決すべきことを示す。
static func step_action(s, actor: int, input: int, cfg) -> bool:
	if actor < 0 or actor >= s.players.size():
		return false
	var p = s.players[actor]
	if s.ball_held_by == actor \
			and p.special_action != Chars.SUPER_SUBSPACE_BLOCK:
		SpecialBall.release_hold(s)
		return false
	match p.special_action:
		Chars.SUPER_SUCTION:
			return _step_suction(s, actor, input, cfg)
		Chars.SUPER_SUBSPACE_BLOCK:
			_step_subspace_hold(s, actor, input, cfg)
	return false

# 特殊行動中に通常移動へ通す入力を限定する。吸引はDUO自身を動かさず、
# 亜空間保持は左右移動だけを許す。
static func filter_action_input(p, input: int) -> int:
	match p.special_action:
		Chars.SUPER_SUCTION:
			return 0
		Chars.SUPER_SUBSPACE_BLOCK:
			return input & (SimInput.IN_LEFT | SimInput.IN_RIGHT)
	return input

# 通常ブロックの全結果が確定した後だけ呼ぶ強化予約の成立点。
static func try_enhance_block(s, actor: int, input: int, cfg) -> bool:
	if actor < 0 or actor >= s.players.size() or s.ball_held_by >= 0:
		return false
	var p = s.players[actor]
	if s.phase != SimStateScript.PHASE_RALLY \
			or not Chars.has_super(p.char_id, Chars.SUPER_SUBSPACE_BLOCK) \
			or p.special_action != 0 or p.burnout_ticks > 0:
		return false
	if (input & (SimInput.IN_ACTION | SimInput.IN_ABILITY1)) \
			!= (SimInput.IN_ACTION | SimInput.IN_ABILITY1) \
			or not _direction_matches(actor, input, Chars.SPECIAL_DIR_FORWARD):
		return false
	if not commit_cost(p, cfg):
		return false
	p.special_action = Chars.SUPER_SUBSPACE_BLOCK
	p.special_action_ticks = 0
	# 強化予約に使ったDを押しっぱなし解放へ誤認しない。
	p.ability_latch = 1
	SpecialBall.hold(s, actor)
	CombatResources.stop_attack_recovery(p)
	return true

static func _suction_target_in_range(s, actor: int, cfg) -> bool:
	if s.serve_ball != 0 or s.serve_flight != 0 or s.ball_held_by >= 0 \
			or not SpecialBall.is_contactable(s):
		return false
	var p = s.players[actor]
	var dx: int = s.ball_x - p.x
	var forward: int = SimStateScript._dir_of_team(SimStateScript.team_of(actor))
	return signi(dx) == forward \
		and absi(dx) < SpecialBall.original_x_distance(32, cfg) \
		and absi(s.ball_y - p.y) < SpecialBall.original_y_distance(64, cfg)

static func _step_suction(s, actor: int, input: int, cfg) -> bool:
	var p = s.players[actor]
	var interrupted: bool = s.phase != SimStateScript.PHASE_RALLY \
		or p.on_ground != 0 or p.stun_ticks > 0 or p.burn > 0 \
		or p.shock_ticks > 0 or p.bubble_ticks > 0 or p.quake_stun > 0 \
		or p.flinch > 0 or not _direction_matches(
			actor, input, Chars.SPECIAL_DIR_BACK)
	if interrupted:
		_end_player_action(p)
		return false
	p.special_action_ticks += 1
	if not _suction_target_in_range(s, actor, cfg):
		return false
	var toward_duo: int = signi(p.x - s.ball_x)
	var pull_step: int = SpecialBall.original_vx(1, cfg)
	var pull_limit: int = SpecialBall.original_vx(6, cfg)
	s.ball_vx = clampi(s.ball_vx + toward_duo * pull_step,
		-pull_limit, pull_limit)
	s.ball_vy = 0
	s.ball_y = p.y + SpecialBall.original_y_distance(4, cfg)
	if absi(s.ball_x - p.x) >= SpecialBall.original_x_distance(8, cfg):
		return false
	s.ball_x = p.x
	_end_player_action(p)
	return true

static func _step_subspace_hold(s, actor: int, input: int, cfg) -> void:
	var p = s.players[actor]
	var interrupted: bool = s.phase != SimStateScript.PHASE_RALLY \
		or s.ball_held_by != actor or p.stun_ticks > 0 or p.burn > 0 \
		or p.shock_ticks > 0 or p.bubble_ticks > 0 or p.quake_stun > 0 \
		or p.flinch > 0
	if interrupted:
		SpecialBall.release_hold(s)
		_end_player_action(p)
		return
	SpecialBall.pin_held(s, cfg)
	p.special_action_ticks += 1
	var release_edge: bool = (input & SimInput.IN_ABILITY1) != 0 \
		and p.ability_latch == 0
	if release_edge \
			or p.special_action_ticks >= SpecialBall.original_ticks(20, cfg):
		SpecialBall.release_hold(s)
		_end_player_action(p)

static func _end_player_action(p) -> void:
	p.special_action = 0
	p.special_action_ticks = 0

static func _direction_matches(actor: int, input: int, direction: int) -> bool:
	var vertical: int = input & (SimInput.IN_UP | SimInput.IN_DOWN)
	var horizontal: int = input & (SimInput.IN_LEFT | SimInput.IN_RIGHT)
	match direction:
		Chars.SPECIAL_DIR_NEUTRAL:
			return vertical == 0 and horizontal == 0
		Chars.SPECIAL_DIR_UP:
			return (input & SimInput.IN_UP) != 0 \
				and (input & SimInput.IN_DOWN) == 0 and horizontal == 0
		Chars.SPECIAL_DIR_DOWN:
			return (input & SimInput.IN_DOWN) != 0 \
				and (input & SimInput.IN_UP) == 0 and horizontal == 0
		Chars.SPECIAL_DIR_FORWARD, Chars.SPECIAL_DIR_BACK:
			if vertical != 0:
				return false
			var team: int = SimStateScript.team_of(actor)
			var forward: int = SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
			var back: int = SimInput.IN_LEFT if team == 0 else SimInput.IN_RIGHT
			var wanted: int = forward if direction == Chars.SPECIAL_DIR_FORWARD else back
			var rejected: int = back if direction == Chars.SPECIAL_DIR_FORWARD else forward
			return (input & wanted) != 0 and (input & rejected) == 0
	return false
