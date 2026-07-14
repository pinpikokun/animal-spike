extends "res://tests/test_case.gd"
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")

func _rally_world():
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0)
	s.phase = St.PHASE_RALLY
	s.serve_tossed = 1
	# ボールを遠ざけてヒット判定に絡まないように
	s.ball_x = cfg.net_x
	s.ball_y = cfg.net_top_y
	return [s, cfg]

func test_skid_triggers_after_sustained_run() -> void:
	var w = _rally_world()
	var s = w[0]
	var cfg = w[1]
	for t in 30:
		Sim.tick(s, [Sim.IN_RIGHT, 0], cfg)
	check(s.players[0].run >= 12, "30tick右走行でrunが溜まる run=%d" % s.players[0].run)
	Sim.tick(s, [Sim.IN_LEFT, 0], cfg)
	check(s.players[0].brake != 0, "逆入力でスキッド発動 brake=%d" % s.players[0].brake)

func test_no_skid_on_oscillation() -> void:
	var w = _rally_world()
	var s = w[0]
	var cfg = w[1]
	for t in 20:
		Sim.tick(s, [Sim.IN_RIGHT if t % 2 == 0 else Sim.IN_LEFT, 0], cfg)
	check_eq(s.players[0].brake, 0, "細かい左右振りではスキッドしない")

func test_skid_survives_short_neutral_gap() -> void:
	# 右を離して(数フレームneutral)から左を押す反転でもスキッドする(人間の操作)
	var w = _rally_world()
	var s = w[0]
	var cfg = w[1]
	for t in 30:
		Sim.tick(s, [Sim.IN_RIGHT, 0], cfg)
	for t in 3:
		Sim.tick(s, [0, 0], cfg)  # 一瞬離す
	Sim.tick(s, [Sim.IN_LEFT, 0], cfg)
	check(s.players[0].brake != 0, "短いニュートラルを挟んだ反転でもスキッド brake=%d" % s.players[0].brake)
