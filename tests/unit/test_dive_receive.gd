extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")

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
