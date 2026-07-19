extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

const STANDARD_CHAR := 99

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.char_id = STANDARD_CHAR
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(175)
	s.players[2].x = FP.from_int(380)
	s.players[3].x = FP.from_int(270)
	return [s, cfg]

func _hit_snapshot(on_ground: int, input: int, d2: int, vx: int, vy: int, power: int = 0) -> Array[int]:
	var w: Array = _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = on_ground
	if on_ground == 0:
		p.y = cfg.floor_y - FP.from_int(80)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(10)
	s.ball_vx = vx
	s.ball_vy = vy
	s.ball_power = power
	s.last_touch_team = 1 if power == 1 else -1
	HitResolver._apply_hit(s, 0, cfg, input | Simulation.IN_ACTION, d2)
	return [p.hit_kind, p.dive, s.ball_vx, s.ball_vy, s.ball_power, p.guard, p.flinch]

func test_intent_classification_table() -> void:
	var w: Array = _world()
	var cfg = w[1]
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var edge: int = cfg.player_reach * 4 / 5
	var edge_d2: int = edge * edge
	var rows := [
		[1, 0, near_d2, 0, 0],
		[1, Simulation.IN_UP, near_d2, 1, 0],
		[1, Simulation.IN_RIGHT, near_d2, 2, 0],
		[1, Simulation.IN_RIGHT, edge_d2, 2, 1],
		[1, Simulation.IN_UP | Simulation.IN_RIGHT, near_d2, 1, 0],
		[0, Simulation.IN_DOWN, near_d2, 0, 0],
		[0, Simulation.IN_RIGHT, near_d2, 0, 0],
		[0, Simulation.IN_UP, near_d2, 0, 0],
		[0, 0, near_d2, 0, 0],
	]
	for row in rows:
		var out := _hit_snapshot(row[0], row[1], row[2], 0, 0)
		check_eq(out[0], row[3], "意図分類 hit_kind: %s" % [row])
		check_eq(1 if out[1] != 0 else 0, row[4], "意図分類 dive: %s" % [row])

func test_intent_classifier_is_pure_and_complete() -> void:
	var cfg = SimConfig.new()
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var edge: int = cfg.player_reach * 4 / 5
	var edge_d2: int = edge * edge
	var rows := [
		[1, 0, near_d2, false, [0, 0, 0, 0]],
		[1, Simulation.IN_UP, near_d2, false, [1, 0, 1, 0]],
		[1, Simulation.IN_RIGHT, near_d2, false, [2, 1, 0, 0]],
		[1, Simulation.IN_RIGHT, edge_d2, false, [2, 1, 0, 1]],
		[1, Simulation.IN_RIGHT, edge_d2, true, [2, 1, 0, 0]],
		[1, Simulation.IN_LEFT | Simulation.IN_UP, near_d2, false, [1, -1, 1, 0]],
		[0, Simulation.IN_DOWN, near_d2, false, [3, 0, 0, 0]],
		[0, Simulation.IN_DOWN | Simulation.IN_RIGHT, near_d2, false, [3, 1, 0, 0]],
		[0, Simulation.IN_UP, near_d2, false, [4, 0, 1, 0]],
		[0, Simulation.IN_RIGHT, near_d2, false, [5, 1, 0, 0]],
		[0, 0, near_d2, false, [6, 0, 0, 0]],
	]
	for row in rows:
		var actual: Array[int] = HitResolver._classify_intent(
			row[0], row[1], row[2], cfg.player_reach, row[3])
		check_eq(actual, row[4], "純粋意図分類: %s" % [row])

func test_output_velocity_snapshot() -> void:
	var w: Array = _world()
	var cfg = w[1]
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var outside_sweet: int = cfg.player_reach * cfg.player_reach
	var cases := [
		_hit_snapshot(1, 0, near_d2, 0, 0),
		_hit_snapshot(1, Simulation.IN_UP, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(1, Simulation.IN_RIGHT, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(0, Simulation.IN_DOWN, near_d2, 0, FP.from_int(8)),
		_hit_snapshot(0, Simulation.IN_DOWN | Simulation.IN_RIGHT, outside_sweet, -FP.from_int(8), -FP.from_int(4)),
		_hit_snapshot(0, Simulation.IN_UP, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(1, 0, outside_sweet, -FP.from_int(12), FP.from_int(8), 1),
	]
	check_eq(cases, [
		[0, 0, 43690, -567978, 0, 100, 0],
		[1, 0, 157286, -567978, 0, 100, 0],
		[2, 14, 321126, -567978, 0, 100, 0],
		[0, 0, 753663, 668467, 1, 100, 0],
		[0, 0, 900027, 362632, 0, 100, 0],
		[0, 0, 157286, -803907, 0, 100, 0],
		[0, 0, 799539, -694681, 0, 50, 24],
	], "固定フィクスチャの整数出力速度")

func test_collision_order_hit_move_net_block() -> void:
	var w: Array = _world()
	var s = w[0]
	var cfg = w[1]
	var attacker = s.players[1]
	var blocker = s.players[3]
	attacker.on_ground = 0
	attacker.y = cfg.floor_y - FP.from_int(100)
	attacker.x = cfg.net_x - cfg.net_half_w - FP.from_int(8)
	blocker.on_ground = 0
	blocker.y = cfg.floor_y - FP.from_int(56)
	blocker.x = cfg.net_x + FP.from_int(16)
	s.ball_x = attacker.x + FP.from_int(5)
	s.ball_y = attacker.y - FP.from_int(10)
	s.ball_vx = FP.from_int(2)
	s.ball_vy = 0
	Simulation.step(s, [0, Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		0, Simulation.IN_ACTION | Simulation.IN_LEFT], cfg)
	check_eq([s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, s.last_touch_team,
		s.touches, attacker.hit_cooldown, blocker.hit_cooldown],
		[15400959, 14209478, -869006, 446918, 1, 1, 14, 14],
		"同tickのヒット→移動→ネット→ブロック順")

func test_scatter_stream_snapshot() -> void:
	var w: Array = _world()
	var s = w[0]
	var actual: Array[int] = []
	for tick in [0, 1, 17, 999, 123456]:
		s.tick = tick
		for actor in [0, 1, 3]:
			for salt in [11, 13, 17, 19]:
				actual.append(HitResolver._scatter(s, actor, salt))
	check_eq(actual, [
		-52, 89, -94, 83, -59, -28, -35, -60, -27, -2, 49, -3,
		-42, -97, -85, 94, -73, -16, -93, 42, -61, -41, -87, 55,
		-89, -25, 9, 20, 25, 94, 18, 61, -92, -54, 25, 38,
		-64, 58, -50, -74, 71, -5, 35, -7, 3, 84, 31, -91,
		32, 6, -65, 42, 47, -73, 7, 24, -90, -58, -44, -80,
	], "固定tick/actor/saltの乱数列")

func _chain_hashes() -> Array[int]:
	var w: Array = _world()
	var s = w[0]
	var cfg = w[1]
	var out: Array[int] = []
	var near_d2 := FP.from_int(2) * FP.from_int(2)
	var miss_d2: int = cfg.player_reach * cfg.player_reach

	# ジャストアタック。
	s.players[0].on_ground = 0
	s.players[0].y = cfg.floor_y - FP.from_int(80)
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, near_d2)
	out.append(s.state_hash())

	# パワーボールを芯外しレシーブし、ガード破壊まで踏む。
	s.players[2].guard = 1
	s.ball_power = 1
	s.last_touch_team = 0
	HitResolver._apply_hit(s, 2, cfg, Simulation.IN_ACTION, miss_d2)
	out.append(s.state_hash())

	# 別のパワーボールをネット際でブロックする。
	s.phase = SimState.PHASE_RALLY
	s.players[3].x = cfg.net_x + FP.from_int(30)
	s.players[3].y = cfg.floor_y - FP.from_int(80)
	s.players[3].on_ground = 0
	s.players[3].hit_cooldown = 0
	s.ball_x = s.players[3].x
	s.ball_y = s.players[3].y - cfg.player_reach_up
	s.ball_vx = FP.from_int(12)
	s.ball_vy = FP.from_int(5)
	s.ball_power = 1
	s.last_touch_team = 0
	HitResolver._ball_vs_block(s, cfg, [0, 0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT])
	out.append(s.state_hash())

	# 帽子投げの溜めから発射まで進める。
	s.players[0].char_id = Chars.CHAR_MARIO
	s.players[0].has_hat = 1
	s.players[0].guard = s.players[0].guard_max
	s.players[0].throw = 0
	s.ball_x = cfg.net_x
	s.ball_y = FP.from_int(20)
	for t in 24:
		Simulation.step(s, [Simulation.IN_ABILITY1, 0, 0, 0], cfg)
		if t in [0, 8, 16, 23]:
			out.append(s.state_hash())
	return out

func test_hit_chain_second_golden() -> void:
	# 2026-07-20: 全選択キャラのA-E基礎能力を全C、重量を標準へ統一したため、
	# マリオを使う帽子工程の2値だけを意図的な物理変更として更新。
	check_eq(_chain_hashes(), [
		2607265428710046085,
		4199287578241784369,
		6492904640078887931,
		-1786523298607686049,
		8539928622375474511,
		870852631837508964,
		-8729129261578934675,
	], "ジャスト→芯外し→気絶→ブロック→帽子の第2ゴールデン")
