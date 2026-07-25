extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")

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

func test_fast_ball_cannot_tunnel_through_net_from_multiple_starts() -> void:
	for start_x in [193, 196, 200, 205, 210]:
		var w := _new_world()
		var s = w[0]
		var cfg = w[1]
		s.serve_flight = 1
		s.touches = 2
		s.ball_x = FP.from_int(start_x)
		s.ball_y = FP.from_int(290)
		s.ball_vx = FP.from_int(2940) / cfg.tick_rate
		s.ball_vy = 0
		BallPhysics._step_ball(s, cfg)
		check(s.ball_x < cfg.net_x,
			"49px/tickの高速球を開始x=%dでも左側へ跳ね返す" % start_x)
		check(s.ball_vx < 0,
			"49px/tickの高速球を開始x=%dでも反射する" % start_x)
		check_eq(s.serve_flight, 1,
			"ネットに当たった開始x=%dのサーブ飛行状態を維持する" % start_x)
		check_eq(s.touches, 2,
			"ネットに当たった開始x=%dのタッチ数を維持する" % start_x)

func test_observed_85px_per_tick_ball_cannot_tunnel_through_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(200)
	s.ball_y = FP.from_int(290)
	s.ball_vx = FP.from_int(5100) / cfg.tick_rate
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check(s.ball_x < cfg.net_x, "実測最大85px/tickの球を左側へ跳ね返す")
	check(s.ball_vx < 0, "実測最大85px/tickの球を反射する")

func test_fast_serve_cross_above_net_top_clears_flight() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.serve_flight = 1
	s.ball_x = FP.from_int(200)
	s.ball_y = FP.from_int(250)
	s.ball_vx = FP.from_int(2940) / cfg.tick_rate
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check(s.ball_x > cfg.net_x, "高速サーブがネット上側を横切る")
	check_eq(s.serve_flight, 0, "上側横断でもサーブ飛行状態を解除する")

func test_descending_fast_ball_hits_net_during_tick() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(200)
	s.ball_y = FP.from_int(270)
	s.ball_vx = FP.from_int(2940) / cfg.tick_rate
	s.ball_vy = FP.from_int(600) / cfg.tick_rate
	BallPhysics._step_ball(s, cfg)
	check(s.ball_x < cfg.net_x, "上端より上から降下して帯へ入る球を左側へ戻す")
	check(s.ball_vx < 0, "上端より上から降下して帯へ入る球を反射する")

func test_zero_horizontal_speed_does_not_divide_by_zero_at_net() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = cfg.net_x
	s.ball_y = FP.from_int(290)
	s.ball_vx = 0
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check(s.ball_x > cfg.net_x, "水平速度0の帯内球も既存の右押し出しを行う")
	check(s.ball_vx > 0, "水平速度0の帯内球へ最低反発を与える")

func test_serve_bounced_by_net_keeps_flight() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.serve_flight = 1
	s.touches = 2
	s.ball_x = cfg.net_x - FP.from_int(12)
	s.ball_y = FP.from_int(290)
	s.ball_vx = FP.from_int(5)
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check(s.ball_x < cfg.net_x, "ネット帯に当たったサーブは来た側へ跳ね返る")
	check_eq(s.serve_flight, 1, "跳ね返されたサーブは横断扱いにしない")
	check_eq(s.touches, 2, "跳ね返されたサーブはタッチ数を維持する")
