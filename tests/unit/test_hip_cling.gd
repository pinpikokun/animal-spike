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
	# 帽子持ち(ヒップアタック可)はマリオ(slot1)のみ。人間入力をslot1へ向ける
	s.controlled_l = 1
	return [s, cfg]

func test_hip_attack_hover_then_drop() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	# ジャンプして空中に
	Sim.tick(s, [SimInput.IN_JUMP, 0], cfg)
	for t in 3:
		Sim.tick(s, [0, 0], cfg)
	check_eq(s.players[1].on_ground, 0, "空中にいる")
	# 空中+下(スペース無し)でヒップアタック発動→空中静止
	Sim.tick(s, [SimInput.IN_DOWN, 0], cfg)
	check(s.players[1].hip > 0, "ヒップアタックで空中静止 hip=%d" % s.players[1].hip)
	check_eq(s.players[1].vy, 0, "静止中は落下しない")
	# 静止が終わると急降下して着地
	var landed := false
	for t in 120:
		Sim.tick(s, [SimInput.IN_DOWN, 0], cfg)
		if s.players[1].on_ground == 1:
			landed = true
			break
	check(landed, "急降下して着地しhipが解ける")
	check_eq(s.players[1].hip, 0, "着地でhip解除")

func test_hip_needs_hat() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[1].has_hat = 0
	Sim.tick(s, [SimInput.IN_JUMP, 0], cfg)
	for t in 3:
		Sim.tick(s, [0, 0], cfg)
	Sim.tick(s, [SimInput.IN_DOWN, 0], cfg)
	check_eq(s.players[1].hip, 0, "帽子が無ければヒップアタック不可")

func test_wall_cling_slides() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	# 左壁際・空中に置いて左を押す
	var p = s.players[1]
	p.x = 0
	p.y = cfg.floor_y - (20 << 16)
	p.on_ground = 0
	p.vy = 0
	Sim.tick(s, [SimInput.IN_LEFT, 0], cfg)
	check(s.players[1].cling == 1, "左壁に張り付く cling=%d" % s.players[1].cling)
	check(s.players[1].vy > 0, "ずるずる降下 vy=%d" % s.players[1].vy)
