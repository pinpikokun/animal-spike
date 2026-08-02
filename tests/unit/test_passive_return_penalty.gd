extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const PossessionTracker := preload("res://src/sim/possession_tracker.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _start_passive_possession(s, actor: int) -> void:
	s.last_touch_team = 1 - SimState.team_of(actor)
	PossessionTracker.on_team_contact(
		s, actor, PossessionTracker.ACTION_PASSIVE)
	s.last_touch_team = SimState.team_of(actor)

func test_passive_return_charges_last_contact_once() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	_start_passive_possession(s, 0)
	PossessionTracker.on_team_contact(s, 1, PossessionTracker.ACTION_PASSIVE)
	check_eq(s.possession_id, 1, "同じ自陣保持ではIDを維持")
	check_eq(s.last_touch_idx, 1, "同じ保持の最後の接触者を更新")
	PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
	check_eq(s.players[0].drive_gauge, 100, "先に触った選手は支払わない")
	check_eq(s.players[1].drive_gauge, 90, "最後に返した選手だけ10を支払う")
	check_eq(s.passive_return_penalty_applied, 1, "保持IDへ適用済みを記録")
	PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
	check_eq(s.players[1].drive_gauge, 90, "同じ保持へ二重適用しない")

func test_aggressive_block_and_dive_actions_are_exempt() -> void:
	var exempt_actions := [
		PossessionTracker.ACTION_NORMAL_ATTACK,
		PossessionTracker.ACTION_JUST_ATTACK,
		PossessionTracker.ACTION_SPECIAL,
		PossessionTracker.ACTION_BLOCK,
		PossessionTracker.ACTION_DIVE,
	]
	for action_kind in exempt_actions:
		var w := _world(); var s = w[0]; var cfg = w[1]
		s.last_touch_team = 1
		PossessionTracker.on_team_contact(s, 0, action_kind)
		s.last_touch_team = 0
		PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
		check_eq(s.players[0].drive_gauge, 100,
			"攻撃・ブロック・飛びつきは追加10なし kind=%d" % action_kind)
		check_eq(s.passive_return_penalty_applied, 1,
			"免除保持も解決済みにする kind=%d" % action_kind)

func test_low_drive_depletes_but_existing_burnout_timer_is_not_reset() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	s.players[0].drive_gauge = 7
	_start_passive_possession(s, 0)
	PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
	check_eq(s.players[0].drive_gauge, 0, "残量7は0まで強制消費")
	check_eq(s.players[0].burnout_ticks, cfg.burnout_recovery_ticks,
		"0到達でバーンアウト開始")
	PossessionTracker.reset_for_rally(s)
	s.players[0].burnout_ticks = 321
	_start_passive_possession(s, 0)
	PossessionTracker.resolve_opponent_transfer(s, 0, cfg)
	check_eq(s.players[0].burnout_ticks, 321,
		"バーンアウト中の返球でタイマーをリセットしない")

func test_rally_reset_clears_active_possession_but_keeps_monotonic_id() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	_start_passive_possession(s, 0)
	var first_id: int = s.possession_id
	PossessionTracker.reset_for_rally(s)
	check_eq(s.possession_id, 0, "ラリー終了で保持参照を解除")
	check_eq(s.possession_team, -1, "ラリー終了で保持チームを解除")
	check_eq(s.aggressive_action_resolved, 0, "ラリー終了で攻撃成立を解除")
	check_eq(s.passive_return_penalty_applied, 0, "ラリー終了で適用済みを解除")
	s.last_touch_team = 1
	PossessionTracker.on_team_contact(s, 0, PossessionTracker.ACTION_PASSIVE)
	check_eq(s.possession_id, first_id + 1, "次ラリーでも保持IDを再利用しない")
	check_eq(s.next_possession_id, s.possession_id + 1, "次ID列は単調増加")

func test_crossing_opponent_boundary_resolves_but_net_wall_and_own_court_do_not() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	_start_passive_possession(s, 0)
	s.ball_x = cfg.net_x - FP.from_int(1)
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(10)
	s.ball_vx = FP.from_int(3)
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check_eq(s.players[0].drive_gauge, 90, "ボール中心が相手コートへ越えたtickで10消費")

	w = _world(); s = w[0]; cfg = w[1]
	_start_passive_possession(s, 0)
	s.ball_x = cfg.net_x - FP.from_int(1)
	s.ball_y = cfg.net_top_y + FP.from_int(20)
	s.ball_vx = FP.from_int(3)
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check_eq(s.players[0].drive_gauge, 100, "ネット側面で戻っただけでは確定しない")

	w = _world(); s = w[0]; cfg = w[1]
	_start_passive_possession(s, 0)
	s.ball_x = cfg.ball_radius + FP.from_int(1)
	s.ball_y = cfg.net_top_y - FP.from_int(20)
	s.ball_vx = -FP.from_int(3)
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check_eq(s.players[0].drive_gauge, 100, "自陣壁への接触では確定しない")

	w = _world(); s = w[0]; cfg = w[1]
	_start_passive_possession(s, 0)
	s.ball_x = cfg.net_x - FP.from_int(100)
	s.ball_y = cfg.net_top_y - FP.from_int(20)
	s.ball_vx = FP.from_int(1)
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check_eq(s.players[0].drive_gauge, 100, "自陣内のトス移動では確定しない")

func test_crossing_and_score_on_same_tick_charges_once_then_resets_possession() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	_start_passive_possession(s, 0)
	# 1tickの線分がネット上端を越えた後、そのまま相手床へ届く高速軌道。
	# ネット下部へ衝突する軌道では「越境」にならないため、交点の高さも固定する。
	s.ball_x = cfg.net_x - FP.from_int(100)
	s.ball_y = cfg.net_top_y - FP.from_int(75)
	s.ball_vx = FP.from_int(200)
	s.ball_vy = cfg.floor_y - cfg.ball_radius - s.ball_y \
		+ FP.from_int(1) - cfg.gravity
	BallPhysics._step_ball(s, cfg)
	Simulation._check_floor_point(s, cfg)
	check_eq(s.players[0].drive_gauge, 90, "得点終了と同tickでも10を一度払う")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "相手コート着地で得点終了")
	check_eq(s.possession_id, 0, "得点終了で保持を解除")
