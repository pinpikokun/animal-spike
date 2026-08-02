extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const PossessionTracker := preload("res://src/sim/possession_tracker.gd")

func _prefix(s, cfg) -> void:
	var p = s.players[0]
	s.phase = SimState.PHASE_RALLY
	p.drive_gauge = 25
	var attack_id: int = s.alloc_attack_id()
	s.ball_attack_id = attack_id
	s.ball_attacker_id = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	HitResolver._grant_valid_normal_attack(s, attack_id, 0, cfg)
	HitResolver._grant_valid_normal_attack(s, attack_id, 0, cfg)
	check_eq(p.drive_gauge, 40, "通常アタック15は攻撃IDにつき一度")
	var stance_action_id: int = s.alloc_action_id()
	check(CombatResources.reserve_stance(p, stance_action_id, s.tick, cfg),
		"反応構え5を予約")
	CombatResources.resolve_stance_contact(p, attack_id + 1, s.tick - 1, cfg)
	check_eq(p.drive_gauge, 35, "反応構えは5を一度消費")
	PossessionTracker.on_team_contact(s, 0, PossessionTracker.ACTION_PASSIVE)
	PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
	PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
	check_eq(p.drive_gauge, 25, "防御返球10は保持IDにつき一度")
	check_eq(CombatResources.start_dive(p, cfg), SimState.DIVE_NORMAL,
		"残量25では通常飛びつき")
	check_eq(p.drive_gauge, 10, "飛びつき15を一度消費")
	p.dive = 0
	p.dive_resource_mode = SimState.DIVE_NONE
	p.on_ground = 0
	p.x = cfg.net_x - FP.from_int(20)
	p.y = cfg.net_top_y - FP.from_int(40)
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_health_damage = 25
	s.ball_power = 1
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(400) / cfg.tick_rate
	s.ball_vy = 0
	var block_input: int = Simulation.IN_ACTION | Simulation.IN_RIGHT
	HitResolver._ball_vs_block(s, cfg, [block_input, 0, 0, 0])
	HitResolver._ball_vs_block(s, cfg, [block_input, 0, 0, 0])
	check_eq(p.drive_gauge, 0, "ブロック開始5と接触5を一度ずつ消費")
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"0到達行動の成立後にバーンアウト")

func _suffix(s, cfg) -> void:
	var p = s.players[0]
	# 直前のブロック演出2tickは既に成立確認済み。ここから有効プレイ300tickを測る。
	s.hit_freeze = 0
	p.on_ground = 1
	p.y = cfg.floor_y
	p.health = 100
	CombatResources.apply_health_damage(p, 100, cfg)
	check_eq(p.stun_ticks, cfg.stun_ticks, "体力100損害でスタン")
	s.ball_x = cfg.net_x
	s.ball_y = -FP.from_int(1000000)
	s.ball_vx = 0
	s.ball_vy = 0
	for _tick in cfg.stun_ticks:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(p.health, 100, "300tickで体力100復帰")
	check_eq(p.burnout_ticks,
		cfg.burnout_recovery_ticks - cfg.stun_ticks,
		"スタン中もバーンアウト時間が進む")
	for _tick in cfg.burnout_recovery_ticks - cfg.stun_ticks:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(p.burnout_ticks, 0, "600tickでバーンアウト終了")
	check_eq(p.drive_gauge, cfg.burnout_exit_drive, "バーンアウトは30復帰")

func test_one_rally_resource_trace_is_once_only_and_rollback_deterministic() -> void:
	var cfg = SimConfig.new()
	var original = SimState.new()
	_prefix(original, cfg)
	var snapshot: Array[int] = original.to_int_array()
	var restored = SimState.new()
	restored.load_int_array(snapshot)
	_suffix(original, cfg)
	_suffix(restored, cfg)
	check_eq(restored.to_int_array(), original.to_int_array(),
		"同じ固定イベント列をsnapshot後に再生して全状態一致")
	check_eq(restored.state_hash(), original.state_hash(), "最終同期hash一致")
	check(original.next_attack_id > 1, "攻撃IDは単調増加")
	check(original.next_action_id > 1, "構えアクションIDは単調増加")
	check(original.next_possession_id > 1, "保持IDは単調増加")
