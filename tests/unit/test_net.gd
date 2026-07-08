extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _new_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.ball_y = FP.from_int(100)
	s.ball_x = FP.from_int(100)
	return [s, cfg]

func test_left_player_cannot_cross_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = cfg.net_x - FP.from_int(30)
	for i in 120:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.players[0].x < cfg.net_x, "左チームはネットを越えられない")

func test_right_player_cannot_cross_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.players[2].x = cfg.net_x + FP.from_int(30)
	for i in 120:
		Simulation.step(s, [0, 0, Simulation.IN_LEFT, 0], cfg)
	check(s.players[2].x > cfg.net_x, "右チームはネットを越えられない")

func test_ball_bounces_off_net_below_top() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = cfg.net_x - FP.from_int(12)
	s.ball_y = cfg.net_top_y + FP.from_int(40)
	s.ball_vx = FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "ネット下部で反射する")
	check(s.ball_x < cfg.net_x, "左側に留まる")

func test_ball_passes_above_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.touches = 2
	s.last_touch_team = 0
	# 1tick(vx=5px)で確実にnet_xをまたぐ位置から始める
	s.ball_x = cfg.net_x - FP.from_int(3)
	s.ball_y = cfg.net_top_y - FP.from_int(40)
	s.ball_vx = FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_x > cfg.net_x, "ネット上空は通過する")
	check_eq(s.touches, 0, "ネット越えでタッチ数リセット")
