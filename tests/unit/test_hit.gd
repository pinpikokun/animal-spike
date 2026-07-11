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
	s.players[1].x = FP.from_int(250)
	s.players[2].x = FP.from_int(540)
	s.players[3].x = FP.from_int(390)
	return [s, cfg]

func test_bump_on_ground() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vy = FP.from_int(3)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "バンプでボールが上昇する")
	check(s.ball_vx > 0, "左チームのバンプは右向き成分")
	check_eq(s.touches, 1, "タッチ数1")
	check_eq(s.last_touch_team, 0, "最終タッチは左チーム")
	check(s.players[0].hit_cooldown > 0, "クールダウン開始")

func test_toss_up_is_vertical() -> void:
	# 上入力+アクション: 真上トス(横成分ゼロ、高く上がる)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(s.ball_vx, 0, "真上トスは横成分ゼロ")
	# step内で重力が1回乗るため厳密等値は避け、前トスより高い初速であることを見る
	check(s.ball_vy < -cfg.toss_fwd_vy, "真上トスは前トスより高く上がる")

func test_toss_forward_goes_far() -> void:
	# 横入力+アクション: 前トス(横速度が素レシーブより大きく、入力方向へ)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check_eq(s.ball_vx, cfg.toss_fwd_vx, "前トスは入力方向(右)へ遠く")
	check(s.ball_vx > cfg.bump_fwd_speed, "前トスは素レシーブより横に速い")

func test_toss_backward_follows_input() -> void:
	# 左入力で左チームでも後ろ(相方側)へ返せる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_LEFT, 0, 0, 0], cfg)
	check(s.ball_vx < 0, "左入力なら左チームでも後ろ向きに返せる")

func test_toss_mid_is_between() -> void:
	# 上+横: 中間トス(高さは真上トス級、横は前トスより小さい)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP | Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.ball_vy < -cfg.toss_fwd_vy, "中間トスの高さは前トスより高い(真上トス級)")
	check_eq(s.ball_vx, cfg.toss_mid_vx, "中間トスの横は中程度")
	check(s.ball_vx < cfg.toss_fwd_vx, "中間トスは前トスより横が小さい")

func test_no_hit_out_of_reach() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + cfg.player_reach * 3
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "届かなければヒットしない")

func test_spike_in_air() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - FP.from_int(5)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vy > 0, "スパイクは下向き")
	check(s.ball_vx > 0, "左チームのスパイクは右向き")
	check(s.ball_vx >= cfg.spike_vx, "スパイクは速い")

func test_cooldown_blocks_double_hit() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "1回目でタッチ1")
	# ボールを引き戻して連打
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "クールダウン中は再ヒットしない")

func test_same_tick_closest_teammate_wins() -> void:
	# 同tickに複数人がリーチ内なら最も近い1人だけがヒットする(1tick1ヒット)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(110)
	s.ball_x = FP.from_int(103)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, Simulation.IN_ACTION, 0, 0], cfg)
	check_eq(s.touches, 1, "同チーム同時タッチでも1タッチ")
	check(s.players[0].hit_cooldown > 0, "近い方がヒットする")
	check_eq(s.players[1].hit_cooldown, 0, "負けた側は硬直しない")

func test_same_tick_tie_ball_side_team_wins() -> void:
	# 距離が同点なら、ボールがある側のチームが優先(ネット際ジョストの公平化)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.players[1].x = cfg.net_x - cfg.net_half_w - FP.from_int(4)
	s.players[2].x = cfg.net_x + cfg.net_half_w + FP.from_int(4)
	s.ball_x = cfg.net_x
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [0, Simulation.IN_ACTION, Simulation.IN_ACTION, 0], cfg)
	check_eq(s.last_touch_team, 1, "ボール側(右)のチームが同距離タイを制す")
	check(s.players[2].hit_cooldown > 0, "右前衛がヒットする")
	check_eq(s.players[1].hit_cooldown, 0, "左前衛は硬直しない")

func test_touch_count_resets_on_team_change() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.touches = 2
	s.last_touch_team = 1
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 1, "チームが替わればタッチ数は1から")
