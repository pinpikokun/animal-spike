extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	return [s, cfg]

# 「敵が敵陣で攻撃を組み立て中」の局面を組む共通セットアップ。
# players[1](左チームのマリオ)がネット際に立ち、敵陣ではトスが上がっている
# =帽子をネット面へ先置きして敵の攻めの通り道を塞ぐ、AB_HATの発動想定シーン
func _hat_scene() -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 1  # 敵がタッチ済み(組み立て中)
	s.tick = 1000
	s.last_hit_tick = 900  # 反応遅延はとっくに明けている
	var p = s.players[1]
	p.x = cfg.net_x - FP.from_int(40)
	p.on_ground = 1
	# ボール: 敵陣の上空で自由落下(そのまま敵陣に落ちる=敵のもう1タッチが来る)
	s.ball_x = cfg.net_x + FP.from_int(60)
	s.ball_y = FP.from_int(60)
	s.ball_vx = 0
	s.ball_vy = 0
	return [s, cfg]

func test_hat_constants_match_simulation() -> void:
	# sim_cpuは循環preload禁止のため帽子定数を鏡写しで持つ。ずれの番人
	check_eq(SimCpu.HAT_WINDUP, Simulation.THROW_TICKS, "溜め時間")
	check_eq(SimCpu.HAT_FLY_PX, Simulation.CAP_THROW_PX, "飛行速度")
	check_eq(SimCpu.HAT_OUT_TICKS, Simulation.CAP_OUT_TICKS, "飛行時間")
	check_eq(SimCpu.HAT_HOVER_TICKS, Simulation.CAP_HOVER_TICKS, "滞在時間")
	check_eq(SimCpu.HAT_RADIUS_PX, Simulation.CAP_RADIUS_PX, "当たり半径")
	check_eq(SimCpu.HAT_HAND_UP_PX, Simulation.CAP_HAND_UP_PX, "手の高さ")
	check_eq(SimCpu.HAT_GUARD_COST, Simulation.HAT_GUARD_COST, "スタミナ消費")

func test_hat_roster_is_mario_only() -> void:
	# 帽子(とヒップアタック)はマリオ専用。slot0=パンダ/敵チームは持たない
	var w := _world()
	var s = w[0]
	check_eq(s.players[0].has_hat, 0, "パンダは帽子なし")
	check_eq(s.players[1].has_hat, 1, "マリオは帽子あり")
	check_eq(s.players[2].has_hat, 0, "キツネは帽子なし")
	check_eq(s.players[3].has_hat, 0, "カエルは帽子なし")

func test_throws_hat_while_enemy_builds_attack() -> void:
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ABILITY1, "敵の組み立て中にネットへ帽子を先置きする")

func test_no_throw_without_ability_flag() -> void:
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.players[1].cpu = SimCpu.PRESET_NORMAL  # AB_HATなし
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ABILITY1), "能力なしは投げない")

func test_no_throw_on_low_guard() -> void:
	# 投げた後にもう1回ぶんの余力が残らないなら投げない(自滅スタンの構造的回避)
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.players[1].guard = SimCpu.HAT_GUARD_COST * 2 - 1
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ABILITY1), "スタミナ余力なしは投げない")

func test_no_throw_at_own_team_ball() -> void:
	# 味方が触った球の間に投げても敵の妨害にならない(自陣の組み立て時間を潰すだけ)
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.last_touch_team = 0
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ABILITY1), "自チームの球では投げない")

func test_no_throw_at_incoming_ball() -> void:
	# 自陣へ向かう球へ投げると溜め30tickの硬直で受けが崩れる=投げない
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.ball_vx = -FP.from_int(4)  # 自陣へ飛んで来る
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ABILITY1), "自陣へ来る球には投げない")

func test_no_throw_when_far_from_net() -> void:
	# 帽子は72pxしか飛ばない。ネット面に届かない位置からは投げない(無駄撃ち温存)
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.players[1].x = FP.from_int(30)  # 自陣の奥深く
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ABILITY1), "ネットに届かない位置からは投げない")

func test_no_throw_while_cap_in_flight() -> void:
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.cap_phase = 2
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ABILITY1), "帽子が出ている間は投げない")

func test_thrown_cap_reaches_net_face() -> void:
	# 統合検証: decideの判断どおりtickを回すと、帽子がネット面に到達して滞在する
	var w := _hat_scene()
	var s = w[0]
	var cfg = w[1]
	s.controlled_l = 0  # index1はCPU相方(tick内でdecideが呼ばれる)
	var posted := false
	for t in 200:
		Simulation.tick(s, [0, 0], cfg)
		# ボールが敵陣床に落ちてポーズに入っても帽子は飛び続けるので回し切る
		if s.cap_phase == 2 and s.cap_x == cfg.net_x - cfg.net_half_w:
			posted = true
			break
	check(posted, "投げた帽子がネット面に置かれて滞在する")
