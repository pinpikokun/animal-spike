extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(175)
	s.players[2].x = FP.from_int(380)
	s.players[3].x = FP.from_int(270)
	return [s, cfg]

func test_wall_half_damps_reflection() -> void:
	# 壁反射トグル: 50%なら跳ね返り速度が半分になる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	cfg.wall_bounce_num = 50
	s.ball_x = FP.from_int(2)
	s.ball_y = FP.from_int(100)
	var vin: int = -FP.from_int(200) / cfg.tick_rate
	s.ball_vx = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vx, -vin * 50 / 100, "壁反射50%で勢い半減")

func test_wall_default_unchanged() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(2)
	s.ball_y = FP.from_int(100)
	var vin: int = -FP.from_int(200) / cfg.tick_rate
	s.ball_vx = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vx, -vin * 78 / 100, "既定は従来の78%")

func test_net_top_original_bounces_and_pushes_out() -> void:
	# ネット上端トグル: 落下中に白帯へ当たると縦半減で跳ね、ネットから離れる横へ
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	cfg.net_top_original = 1
	s.ball_x = cfg.net_x - FP.from_int(1)  # 左側からネット直上へ
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vx = 0
	var vin: int = FP.from_int(300) / cfg.tick_rate
	s.ball_vy = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "上端に当たって跳ね上がる")
	check(s.ball_vx < 0, "左側の球は左(ネットから離れる向き)へ押し出される")

func test_net_top_default_passes_through() -> void:
	# 既定: ネット上空は素通し(当たり判定なし)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = cfg.net_x - FP.from_int(1)
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vx = FP.from_int(60) / cfg.tick_rate
	s.ball_vy = 0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "既定では上端に阻まれず横速度を保つ")

func test_toss_aim_lands_at_home_position() -> void:
	# いいとこ取りトス: レシーブが「味方の定位置」へ落ちる横速度に逆算される
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	cfg.toss_aim = 1
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0  # 入射ゼロ=慣性外乱なしの理想値を検証
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	var target: int = FP.from_int(cfg.spawn_front_px)
	var air: int = 2 * cfg.bump_up_speed / cfg.gravity
	# step内で1tick進んでいる分の誤差を許容して「定位置へ向かう速度」を確認
	var expect: int = (target - (s.ball_x - s.ball_vx)) / air
	check(absi(s.ball_vx - expect) <= absi(expect) / 10 + 1, "定位置への逆算速度")
	# 実際に飛ばして着地点を見る(統合検証)
	s.players[0].x = FP.from_int(30)  # 打った本人はどかす
	for i in 600:
		if s.ball_y >= cfg.floor_y - cfg.ball_radius:
			break
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check(absi(s.ball_x - target) < FP.from_int(40), "定位置の近くに落ちる")

func test_toss_aim_off_keeps_legacy() -> void:
	# 既定(OFF)では従来の打ち出し方式のまま
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.ball_vx, cfg.bump_fwd_speed, "OFFなら従来の素レシーブ横速度")

func test_loose_floor_bounce_is_half() -> void:
	# ポーズ中の床バウンドは勢い半分(設定なしの固定仕様)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = 1000  # ポーズが明けないよう長めに
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	var vin: int = FP.from_int(300) / cfg.tick_rate
	s.ball_vy = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "床で跳ね返る")
	var bounced: int = -(vin + cfg.gravity) * 50 / 100 + cfg.ball_rest_speed / 4
	check(absi(s.ball_vy - bounced) <= absi(bounced) / 5 + 1, "反発はおよそ勢い半分")
