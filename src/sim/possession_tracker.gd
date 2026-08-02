# 自陣保持と防御返球ペナルティの決定論状態を扱う。
extends RefCounted

const SimStateScript := preload("res://src/sim/sim_state.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")

const ACTION_PASSIVE := 0
const ACTION_NORMAL_ATTACK := 1
const ACTION_JUST_ATTACK := 2
const ACTION_SPECIAL := 3
const ACTION_BLOCK := 4
const ACTION_DIVE := 5

static func on_team_contact(s, actor: int, action_kind: int) -> void:
	if actor < 0 or actor >= s.players.size():
		return
	var team: int = SimStateScript.team_of(actor)
	if s.possession_id == 0 or s.possession_team != team:
		s.possession_id = s.alloc_possession_id()
		s.possession_team = team
		s.aggressive_action_resolved = 0
		s.passive_return_penalty_applied = 0
	s.last_touch_idx = actor
	if action_kind == ACTION_DIVE:
		mark_dive_exempt(s)
	elif action_kind != ACTION_PASSIVE:
		mark_aggressive(s)

static func mark_aggressive(s) -> void:
	if s.possession_id != 0:
		s.aggressive_action_resolved = 1

static func mark_dive_exempt(s) -> void:
	if s.possession_id != 0:
		s.aggressive_action_resolved = 1

static func resolve_opponent_transfer(s, owner: int, cfg) -> void:
	if s.possession_id == 0 or s.possession_team != owner \
			or s.passive_return_penalty_applied != 0:
		return
	s.passive_return_penalty_applied = 1
	if s.aggressive_action_resolved != 0:
		return
	var actor: int = s.last_touch_idx
	if actor < 0 or actor >= s.players.size() \
			or SimStateScript.team_of(actor) != owner:
		return
	CombatResources.spend_mandatory(
		s.players[actor], cfg.passive_return_drive_cost, cfg)

static func reset_for_rally(s) -> void:
	s.possession_id = 0
	s.possession_team = -1
	s.aggressive_action_resolved = 0
	s.passive_return_penalty_applied = 0
