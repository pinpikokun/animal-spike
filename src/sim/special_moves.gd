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
	s.ball_health_damage = power
	s.ball_defense_class = int(entry.defense_class)

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
