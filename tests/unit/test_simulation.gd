extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _new_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	for p in s.players:
		p.y = cfg.floor_y
	return [s, cfg]

func test_tick_advances() -> void:
	var w := _new_world()
	Simulation.step(w[0], [0, 0, 0, 0], w[1])
	check_eq(w[0].tick, 1, "tickが進む")

func test_move_right_speed() -> void:
	var w := _new_world()
	var s = w[0]
	for i in 60:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], w[1])
	var moved := FP.to_int(s.players[0].x)
	check(moved >= 175 and moved <= 185, "1秒で約180px移動 actual=" + str(moved))

func test_move_left_speed() -> void:
	var w := _new_world()
	var s = w[0]
	s.players[0].x = FP.from_int(300)
	for i in 60:
		Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], w[1])
	var moved := 300 - FP.to_int(s.players[0].x)
	check(moved >= 175 and moved <= 185, "1秒で約180px左移動 actual=" + str(moved))

func test_jump_and_land() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], cfg)
	check_eq(s.players[0].on_ground, 0, "ジャンプで空中へ")
	check(s.players[0].y < cfg.floor_y, "上昇している")
	var landed := false
	for i in 300:
		Simulation.step(s, [0, 0, 0, 0], cfg)
		if s.players[0].on_ground == 1:
			landed = true
			break
	check(landed, "300tick以内に着地する")
	check_eq(s.players[0].y, cfg.floor_y, "床にスナップ")

func test_no_double_jump() -> void:
	var w := _new_world()
	var s = w[0]
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], w[1])
	var vy_air: int = s.players[0].vy
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], w[1])
	check(s.players[0].vy > vy_air, "空中で再ジャンプできない(重力で減速のみ)")

func test_player_stays_in_court() -> void:
	# 境界の内側から出発して両端のクランプを検証する(境界から始めると空振りする)
	# 右端は右チームのプレイヤー2で検証する(左チームはネットで止まるため)
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(50)
	for i in 600:
		Simulation.step(s, [Simulation.IN_LEFT, 0, 0, 0], cfg)
	check_eq(s.players[0].x, 0, "左端で止まる")
	s.players[2].x = cfg.court_width - FP.from_int(50)
	for i in 600:
		Simulation.step(s, [0, 0, Simulation.IN_RIGHT, 0], cfg)
	check_eq(s.players[2].x, cfg.court_width, "右端で止まる")

func test_ball_wall_bounce() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.ball_radius + FP.from_int(2)
	s.ball_y = FP.from_int(100)
	s.ball_vx = -FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "左壁で反射して右向きになる")
	check(s.ball_x >= cfg.ball_radius, "壁にめり込まない")

func test_ball_right_wall_bounce() -> void:
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.court_width - cfg.ball_radius - FP.from_int(2)
	s.ball_y = FP.from_int(100)
	s.ball_vx = FP.from_int(5)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "右壁で反射して左向きになる")
	check(s.ball_x <= cfg.court_width - cfg.ball_radius, "右壁にめり込まない")

func test_ball_passes_through_ceiling() -> void:
	# 原作準拠: 上端で跳ね返らずボールは画面上へ突き抜ける(左右の壁だけ反射)
	var w := _new_world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.ball_radius + FP.from_int(1)
	s.ball_vy = -FP.from_int(6)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "上向き速度が反転せず上昇を続ける")
	check(s.ball_y < cfg.ball_radius, "天井ラインを越えて画面上へ抜ける")

# 床バウンドのテストは削除(仕様変更: RALLY中の床接触は得点。test_rally.gdが検証する)
