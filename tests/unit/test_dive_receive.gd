extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _first_floor_x_by_production_steps(source, cfg, max_ticks: int = 240) -> int:
	var probe = SimState.new()
	probe.load_int_array(source.to_int_array())
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	for _tick in max_ticks:
		BallPhysics._step_ball(probe, cfg)
		if probe.ball_y >= floor_limit and probe.ball_vy > 0:
			return probe.ball_x
	return -1

func _check_prediction(source, cfg, expected_x: int, label: String, max_ticks: int = 240) -> void:
	var before: Array[int] = source.to_int_array()
	check_eq(_first_floor_x_by_production_steps(source, cfg, max_ticks), expected_x,
		label + "の本番物理fixture")
	check_eq(BallPhysics.predict_first_floor_x(source, cfg, max_ticks), expected_x,
		label + "の予測")
	check_eq(source.to_int_array(), before, label + "の予測は本番状態を変更しない")

func _base_ball(cfg):
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(120)
	s.ball_vx = FP.from_int(120) / cfg.tick_rate
	s.ball_vy = -FP.from_int(60) / cfg.tick_rate
	s.last_touch_team = 1
	return s

func test_predicts_normal_parabola_first_floor_x() -> void:
	var cfg = SimConfig.new()
	var s = _base_ball(cfg)
	_check_prediction(s, cfg, FP.from_int(162), "通常放物線")

func test_predicts_left_and_right_wall_reflections() -> void:
	var cfg = SimConfig.new()
	var left = _base_ball(cfg)
	left.ball_x = cfg.ball_radius + FP.from_int(1)
	left.ball_vx = -FP.from_int(120) / cfg.tick_rate
	_check_prediction(left, cfg, FP.from_int(45), "左壁反射")
	var right = _base_ball(cfg)
	right.ball_x = cfg.court_width - cfg.ball_radius - FP.from_int(1)
	right.ball_vx = FP.from_int(120) / cfg.tick_rate
	_check_prediction(right, cfg, FP.from_int(531), "右壁反射")

func test_predicts_power_ball_wall_vertical_damping() -> void:
	var cfg = SimConfig.new()
	var s = _base_ball(cfg)
	s.ball_x = cfg.ball_radius + FP.from_int(1)
	s.ball_vx = -FP.from_int(120) / cfg.tick_rate
	s.ball_power = 1
	_check_prediction(s, cfg, FP.from_int(44), "パワー球壁減衰")

func test_predicts_net_side_reflection() -> void:
	var cfg = SimConfig.new()
	var s = _base_ball(cfg)
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	s.ball_x = net_left - FP.from_int(2)
	s.ball_y = cfg.net_top_y + FP.from_int(10)
	s.ball_vx = FP.from_int(120) / cfg.tick_rate
	s.ball_vy = 0
	_check_prediction(s, cfg, FP.from_int(271), "ネット側面")

func test_predicts_net_top_bounce() -> void:
	var cfg = SimConfig.new()
	var s = _base_ball(cfg)
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	s.ball_x = net_left + FP.from_int(2)
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vx = 0
	s.ball_vy = FP.from_int(60) / cfg.tick_rate
	_check_prediction(s, cfg, FP.from_int(254), "ネット上端")

func test_prediction_returns_minus_one_after_240_ticks() -> void:
	var cfg = SimConfig.new()
	var s = _base_ball(cfg)
	s.ball_y = -FP.from_int(100000)
	s.ball_vx = 0
	s.ball_vy = 0
	_check_prediction(s, cfg, -1, "240tick無効")

func _dive_start_world(player_index: int, predicted_x: int, last_touch_team: int = -2) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	var team: int = SimState.team_of(player_index)
	var p = s.players[player_index]
	p.char_id = 99
	p.x = predicted_x - cfg.player_reach - 1 if team == 0 \
		else predicted_x + cfg.player_reach + 1
	p.y = cfg.floor_y
	p.on_ground = 1
	s.ball_x = predicted_x
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(120)
	s.ball_vx = 0
	s.ball_vy = 0
	s.last_touch_team = 1 - team if last_touch_team == -2 else last_touch_team
	return [s, cfg]

func _step_player_action(s, cfg, player_index: int, extra_input: int = 0) -> void:
	var inputs: Array[int] = [0, 0, 0, 0]
	inputs[player_index] = Simulation.IN_ACTION | extra_input
	Simulation.step(s, inputs, cfg)

func test_current_normal_reach_hit_wins_over_dive_start() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	s.ball_x = p.x + cfg.player_reach
	s.ball_y = p.y
	s.last_touch_team = 1
	_step_player_action(s, cfg, 0)
	check_eq(p.dive, 0, "通常リーチ内は横っ飛びを開始しない")
	check_eq(s.touches, 1, "通常リーチ内は従来の即時打球を優先")

func test_dive_start_boundaries_are_open_inside_and_closed_outside() -> void:
	var cfg = SimConfig.new()
	var base_x := FP.from_int(150)
	var inner = _dive_start_world(0, base_x)
	inner[0].players[0].x = base_x - cfg.player_reach - 1
	_step_player_action(inner[0], inner[1], 0)
	check_eq(inner[0].players[0].dive, 1, "通常リーチを1単位越えると開始")
	var outer = _dive_start_world(0, base_x)
	outer[0].players[0].x = base_x - cfg.player_reach - cfg.dive_receive_extra_reach
	_step_player_action(outer[0], outer[1], 0)
	check_eq(outer[0].players[0].dive, 1, "追加幅32pxの外端は開始")
	var beyond = _dive_start_world(0, base_x)
	beyond[0].players[0].x = base_x - cfg.player_reach \
		- cfg.dive_receive_extra_reach - 1
	_step_player_action(beyond[0], beyond[1], 0)
	check_eq(beyond[0].players[0].dive, 0, "外端を1単位越えると開始しない")

func test_dive_start_uses_predicted_direction_and_mirrors_teams() -> void:
	var left = _dive_start_world(0, FP.from_int(150))
	var left_x: int = left[0].players[0].x
	_step_player_action(left[0], left[1], 0, Simulation.IN_LEFT)
	var left_p = left[0].players[0]
	check_eq(left_p.dive, 1, "逆入力でも予測着地点の右へ飛ぶ")
	check_eq(left_p.dive_contact_ticks, 14, "開始tickは14のまま")
	check_eq(left_p.dive_age_ticks, 0, "開始tickは移動しない")
	check_eq(left_p.x, left_x - left[1].move_speed,
		"開始tickは先行する通常移動だけで横っ飛び移動はしない")
	check_eq(left_p.vx, left[1].dive_receive_speed, "開始時に右速度を設定")
	check_eq(left_p.vy, -left[1].dive_receive_hop, "開始時に上向き速度を設定")
	check_eq(left_p.on_ground, 0, "開始時に接地を離れる")
	var right = _dive_start_world(2, FP.from_int(426))
	_step_player_action(right[0], right[1], 2, Simulation.IN_RIGHT)
	check_eq(right[0].players[2].dive, -1, "右チームは左へ鏡像で飛ぶ")

func test_dive_does_not_start_for_same_team_or_invalid_prediction() -> void:
	var same = _dive_start_world(0, FP.from_int(150), 0)
	_step_player_action(same[0], same[1], 0)
	check_eq(same[0].players[0].dive, 0, "同チーム球では開始しない")
	var invalid = _dive_start_world(0, FP.from_int(150))
	invalid[0].ball_y = -FP.from_int(100000)
	_step_player_action(invalid[0], invalid[1], 0)
	check_eq(invalid[0].players[0].dive, 0, "予測無効では開始しない")

func test_dive_action_edge_is_consumed_when_conditions_fail() -> void:
	var w = _dive_start_world(0, FP.from_int(150), 0)
	var s = w[0]
	var cfg = w[1]
	_step_player_action(s, cfg, 0)
	s.last_touch_team = 1
	_step_player_action(s, cfg, 0)
	check_eq(s.players[0].dive, 0, "保持入力を条件成立後へ持ち越さない")
	Simulation.step(s, [0, 0, 0, 0], cfg)
	_step_player_action(s, cfg, 0)
	check_eq(s.players[0].dive, 1, "離して押し直すと新しいエッジになる")

func test_dive_action_edge_is_consumed_during_freeze_and_incapacitation() -> void:
	var frozen = _dive_start_world(0, FP.from_int(150))
	frozen[0].hit_freeze = 1
	_step_player_action(frozen[0], frozen[1], 0)
	_step_player_action(frozen[0], frozen[1], 0)
	check_eq(frozen[0].players[0].dive, 0,
		"ヒットストップ中の押下を再開後へ持ち越さない")
	var slowed = _dive_start_world(0, FP.from_int(150))
	slowed[0].slow_ticks = 2
	_step_player_action(slowed[0], slowed[1], 0)
	_step_player_action(slowed[0], slowed[1], 0)
	check_eq(slowed[0].players[0].dive, 0,
		"スロー停止中の押下を再開後へ持ち越さない")
	var stunned = _dive_start_world(0, FP.from_int(150))
	stunned[0].players[0].stun = 1
	_step_player_action(stunned[0], stunned[1], 0)
	_step_player_action(stunned[0], stunned[1], 0)
	check_eq(stunned[0].players[0].dive, 0,
		"行動不能中の押下を回復後へ持ち越さない")

func test_multiple_players_can_start_dive_on_same_tick() -> void:
	var w = _dive_start_world(0, FP.from_int(150))
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(90)
	s.players[1].y = cfg.floor_y
	s.players[1].on_ground = 1
	s.players[1].char_id = 99
	Simulation.step(s, [Simulation.IN_ACTION, Simulation.IN_ACTION, 0, 0], cfg)
	check_eq(s.players[0].dive, 1, "低index選手が開始")
	check_eq(s.players[1].dive, 1, "同tickの相方も開始")

func test_dive_moves_for_14_physics_ticks_then_stops_horizontally() -> void:
	var w = _dive_start_world(0, FP.from_int(150))
	var s = w[0]
	var cfg = w[1]
	_step_player_action(s, cfg, 0)
	var p = s.players[0]
	var start_x: int = p.x
	Simulation.step(s, [Simulation.IN_LEFT | Simulation.IN_JUMP, 0, 0, 0], cfg)
	check_eq(p.x, start_x + cfg.dive_receive_speed, "逆入力とジャンプを無視して球側へ移動")
	check_eq(p.dive_contact_ticks, 13, "最初の物理tick後に1減る")
	check_eq(p.dive_age_ticks, 1, "最初の物理tickで経過1")
	for _tick in 13:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(p.dive_contact_ticks, 0, "14回目の失敗後に受付終了")
	check_eq(p.dive_age_ticks, 14, "受付終了時の経過は14")
	check_eq(p.vx, 0, "受付終了時に水平速度を止める")
	check(p.dive != 0, "受付終了後も着地まで飛び込み状態を維持")

func test_dive_timers_do_not_advance_when_physics_is_stopped() -> void:
	var w = _dive_start_world(0, FP.from_int(150))
	var s = w[0]
	var cfg = w[1]
	_step_player_action(s, cfg, 0)
	var p = s.players[0]
	s.hit_freeze = 1
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(p.dive_contact_ticks, 14, "ヒットストップ中は受付残りを進めない")
	check_eq(p.dive_age_ticks, 0, "ヒットストップ中は経過を進めない")
	s.slow_ticks = 2
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(p.dive_contact_ticks, 14, "スロー停止中は受付残りを進めない")
	check_eq(p.dive_age_ticks, 0, "スロー停止中は経過を進めない")

func test_dive_landing_clears_state_and_restores_control_next_tick() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_GAME_OVER
	var p = s.players[0]
	p.x = FP.from_int(100)
	p.y = cfg.floor_y - FP.from_int(1)
	p.vy = FP.from_int(2)
	p.on_ground = 0
	p.dive = 1
	p.dive_contact_ticks = 0
	p.dive_age_ticks = 9
	Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], cfg)
	check_eq(p.y, cfg.floor_y, "着地位置を床へ固定")
	check_eq(p.dive, 0, "着地で横っ飛び方向を消す")
	check_eq(p.dive_contact_ticks, 0, "着地で受付残りを消す")
	check_eq(p.dive_age_ticks, 0, "着地で経過を消す")
	Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], cfg)
	check_eq(p.vx, -cfg.move_speed, "着地の次tickから通常操作へ戻る")
