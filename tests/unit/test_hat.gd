extends "res://tests/test_case.gd"
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")

func _rally():
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0)
	s.phase = St.PHASE_RALLY
	s.serve_tossed = 1
	return [s, cfg]

func test_throw_and_return_cycle() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[0].face = 1
	Sim.tick(s, [SimInput.IN_HAT_THROW, 0], cfg)
	check(s.players[0].throw > 0, "投げ溜め開始 throw=%d" % s.players[0].throw)
	check_eq(s.players[0].has_hat, 1, "溜め中はまだ帽子あり")
	# 溜めが終わると発射される
	for t in 40:
		Sim.tick(s, [0, 0], cfg)
		if s.cap_phase != 0:
			break
	check_eq(s.players[0].has_hat, 0, "発射で帽子を外す")
	check(s.cap_phase != 0, "帽子が飛行中 phase=%d" % s.cap_phase)
	# 十分な時間まわすと戻ってキャッチ(has_hat=1)する
	var caught := false
	for t in 400:
		Sim.tick(s, [0, 0], cfg)
		if s.players[0].has_hat == 1 and s.cap_phase == 0:
			caught = true
			break
	check(caught, "最終的に帽子が戻ってキャッチされる")

func test_no_throw_without_hat() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[0].has_hat = 0
	Sim.tick(s, [SimInput.IN_HAT_THROW, 0], cfg)
	check_eq(s.cap_phase, 0, "帽子が無ければ投げられない")

func test_cap_deflects_ball() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	# 帽子を飛行状態にしてボールを右から左へ突っ込ませる
	s.cap_phase = 2
	s.cap_x = cfg.net_x
	s.cap_y = cfg.net_top_y
	s.cap_owner = 0
	s.ball_x = cfg.net_x + FP_from(6)
	s.ball_y = cfg.net_top_y
	s.ball_vx = -FP_from(5)  # 左へ向かう
	s.ball_vy = 0
	Sim.tick(s, [0, 0], cfg)
	check(s.ball_vx > 0, "帽子の右側の球は右へ弾かれる vx=%d" % s.ball_vx)

func FP_from(v: int) -> int:
	return v << 16

func test_hat_costs_guard() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var g0 = s.players[0].guard
	Sim.tick(s, [SimInput.IN_HAT_THROW, 0], cfg)
	check(s.players[0].guard < g0, "帽子投げで耐久を消費 guard=%d" % s.players[0].guard)

func test_hat_without_stamina_stuns() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[0].guard = 5  # スタミナ不足
	Sim.tick(s, [SimInput.IN_HAT_THROW, 0], cfg)
	check(s.players[0].stun > 0, "スタミナ切れで投げるとスタン stun=%d" % s.players[0].stun)
	check_eq(s.cap_phase, 0, "帽子は出ない")
	check_eq(s.players[0].guard, s.players[0].guard_max, "スタン時に全快")
