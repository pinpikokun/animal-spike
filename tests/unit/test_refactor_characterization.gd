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
	s.ball_guard_damage = cfg.power_guard_damage_for_rank(
		Chars.Profile.RANK_C) if power == 1 else 0
	s.last_touch_team = 1 if power == 1 else -1
	HitResolver._apply_hit(s, 0, cfg, input | Simulation.IN_ACTION, d2)
	return [p.hit_kind, p.dive, s.ball_vx, s.ball_vy, s.ball_power, p.guard, p.flinch]

func test_intent_classification_table() -> void:
	# 操作原作回帰後の論理ベースライン:
	# 地上は下だけレシーブ、それ以外は横3トス。空中は下=攻撃、なし=トス、上=ブロック。
	var w: Array = _world()
	var cfg = w[1]
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var edge: int = cfg.player_reach * 4 / 5
	var edge_d2: int = edge * edge
	var rows := [
		[1, 0, near_d2, 1, 0],
		[1, Simulation.IN_UP, near_d2, 1, 0],
		[1, Simulation.IN_RIGHT, near_d2, 1, 0],
		[1, Simulation.IN_RIGHT, edge_d2, 1, 1],
		[1, Simulation.IN_UP | Simulation.IN_RIGHT, near_d2, 1, 0],
		[0, Simulation.IN_DOWN, near_d2, 0, 0],
		[0, Simulation.IN_RIGHT, near_d2, 0, 0],
		[0, 0, near_d2, 0, 0],
	]
	for row in rows:
		var out := _hit_snapshot(row[0], row[1], row[2], 0, 0)
		check_eq(out[0], row[3], "意図分類 hit_kind: %s" % [row])
		check_eq(1 if out[1] != 0 else 0, row[4], "意図分類 dive: %s" % [row])

func test_intent_classifier_is_pure_and_complete() -> void:
	# 値はHitResolverの公開意図定数に対応する新体系の確定値。速度スナップショットと
	# 異なり実測不要で、地上ニュートラル=[トス,横なし,上照準なし,diveなし]が正しい。
	var cfg = SimConfig.new()
	var near_d2 := FP.from_int(5) * FP.from_int(5)
	var edge: int = cfg.player_reach * 4 / 5
	var edge_d2: int = edge * edge
	var rows := [
		[1, 0, near_d2, false, [1, 0, 0, 0]],
		[1, Simulation.IN_DOWN, near_d2, false, [0, 0, 0, 0]],
		[1, Simulation.IN_UP, near_d2, false, [1, 0, 0, 0]],
		[1, Simulation.IN_RIGHT, near_d2, false, [1, 1, 0, 0]],
		[1, Simulation.IN_RIGHT, edge_d2, false, [1, 1, 0, 1]],
		[1, Simulation.IN_RIGHT, edge_d2, true, [1, 1, 0, 0]],
		[1, Simulation.IN_LEFT | Simulation.IN_UP, near_d2, false, [1, -1, 0, 0]],
		[0, Simulation.IN_DOWN, near_d2, false, [3, 0, 0, 0]],
		[0, Simulation.IN_DOWN | Simulation.IN_RIGHT, near_d2, false, [3, 1, 0, 0]],
		[0, Simulation.IN_UP, near_d2, false, [5, 0, 1, 0]],
		[0, Simulation.IN_RIGHT, near_d2, false, [4, 1, 0, 0]],
		[0, 0, near_d2, false, [4, 0, 0, 0]],
	]
	for row in rows:
		var actual: Array[int] = HitResolver._classify_intent(
			row[0], row[1], row[2], cfg.player_reach, row[3])
		check_eq(actual, row[4], "純粋意図分類: %s" % [row])

func test_output_velocity_snapshot() -> void:
	# 実測待ち: 地上レシーブを含む行は新しい接触位置式により更新が必要。
	# アタック速度の意図的変更(ジャスト150→110%、通常100→80%)。2026-07-20設計会仕様
	# 固定パワー球はPOWER Cの絶対削り25を持つ。2026-07-20設計会仕様
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
		_hit_snapshot(0, 0, outside_sweet, -FP.from_int(8), FP.from_int(12)),
		_hit_snapshot(1, 0, outside_sweet, -FP.from_int(12), FP.from_int(8), 1),
	]
	check_eq(cases, [
		[1, 0, 64299, -567978, 0, 100, 0],
		[1, 0, 221585, -567978, 0, 100, 0],
		[1, 14, 387280, -567978, 0, 100, 0],
		[0, 0, 1291605, 253406, 1, 100, 0],
		[0, 0, 1332838, 220637, 0, 100, 0],
		[0, 0, 429202, -749294, 0, 100, 0],
		[1, 0, 805721, -170393, 0, 75, 24],
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
	# このテストの目的は「ヒット→移動→ネット→ブロック」の同tick順序の検証であり、
	# ブロックの成立境界を測ることではない。以前は57pxとギリギリに置いていたため
	# アタック速度を80%→50%へ下げただけでブロックが不成立になりテストが壊れた。
	# 実測で成立するのは59px以上なので、余裕を見て範囲の中央に置く。
	blocker.y = cfg.floor_y - FP.from_int(65)
	blocker.x = cfg.net_x + FP.from_int(16)
	s.ball_x = attacker.x + FP.from_int(5)
	s.ball_y = attacker.y - FP.from_int(10)
	s.ball_vx = FP.from_int(2)
	s.ball_vy = 0
	Simulation.step(s, [0, Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		0, Simulation.IN_ACTION | Simulation.IN_UP], cfg)
	# 2026-07-25: アタック速度をジャスト110→80%、通常80→50%へ引き下げたため座標と
	# 速度が変化した。ブロックの成立自体(last_touch_team=1, touches=1, 両者cd=14)は
	# 変わっていないので、検証している同tick順序は保たれている。実測値。
	check_eq([s.ball_x, s.ball_y, s.ball_vx, s.ball_vy, s.last_touch_team,
		s.touches, attacker.hit_cooldown, blocker.hit_cooldown],
		[14999552, 14010686, -555909, 248126, 1, 1, 14, 14],
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
	HitResolver._apply_hit(s, 2, cfg, Simulation.IN_ACTION | Simulation.IN_DOWN, miss_d2)
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
	HitResolver._ball_vs_block(s, cfg, [0, 0, 0, Simulation.IN_ACTION | Simulation.IN_UP])
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
	# 2026-07-25: serve_ball フィールドを SimState へ追加したため全7値が変化した。
	# state_hash は全 int フィールドを畳むので、値が0でもフィールドが増えれば
	# すべてのハッシュがずれる。挙動の異常ではない。実測値。
	#
	# 2026-07-25 (第2回) 気絶時間を 180tick(3秒) から 240tick(4秒) へ変更したため
	# 2番目以降が変化した。この連鎖は2手目でガード破壊→気絶に入るので、
	# 気絶カウンタの初期値がそのまま state_hash に乗る。1番目(ジャストアタック)は
	# 気絶を通らないため変化していない。実測値。
	#
	# 2026-07-25 (第3回) アタック速度の引き下げ(ジャスト110→80%、通常80→50%)で
	# 1番目(ジャストアタック)と2番目が変化した。3番目以降はブロックと帽子で、
	# アタック速度を通らないため不変。実測値。
	check_eq(_chain_hashes(), [
		923267379770092831,
		-7035687006816462201,
		-6676369414171217957,
		6003829651502486851,
		2945686973259461767,
		9081282535588430626,
		5525061651035603349,
	], "ジャスト→芯外し→気絶→ブロック→帽子の第2ゴールデン")
