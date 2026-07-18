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

func test_just_attack_recoils_attacker() -> void:
	# ジャストアタックの反作用: 打った本人がネットと逆(自陣側)へ小さく後退する
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)  # スイート内=ジャスト成立
	s.ball_y = p.y - FP.from_int(5)
	var x0: int = p.x
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 1, "ジャスト成立の前提確認")
	check(p.push < 0, "左チームの反動は左向き(ネットと逆)")
	# ジャスト後は瞬止+スローモーションで実時間が延びるため長めに待つ
	for i in 60:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check(p.x < x0, "反動で後退している")
	check(x0 - p.x < FP.from_int(25), "後退は控えめ(吹っ飛びすぎない)")
	check_eq(p.push, 0, "反動は減衰して消える")

func test_normal_attack_no_recoil() -> void:
	# 芯を外した通常アタックは無反動
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(30)  # スイート外
	s.ball_y = p.y
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 0, "通常アタックの前提確認")
	check_eq(p.push, 0, "通常アタックは無反動")

func test_power_ball_block_pushes_blocker() -> void:
	# パワーボールをブロックすると小さく押し込まれる。通常球は無反動
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[2]  # 右チームのブロッカー
	p.x = cfg.net_x + FP.from_int(20)
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 0
	s.ball_power = 1
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate  # 右へ=右チームへ向かう
	s.ball_vy = 0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.last_touch_team, 1, "ブロック成立の前提確認")
	check(p.push > 0, "右チームのブロッカーは右(後ろ)へ押し込まれる")

func test_normal_ball_block_no_push() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[2]
	p.x = cfg.net_x + FP.from_int(20)
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 0
	s.ball_power = 0
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate
	s.ball_vy = 0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.last_touch_team, 1, "ブロック成立の前提確認")
	check_eq(p.push, 0, "通常球のブロックは無反動")
