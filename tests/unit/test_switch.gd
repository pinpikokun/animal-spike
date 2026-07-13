extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(420)
	s.ball_y = FP.from_int(50)
	return [s, cfg]

func test_human_input_reaches_controlled_char() -> void:
	var w := _world()
	var s = w[0]
	var x0: int = s.players[0].x
	for i in 30:
		Simulation.tick(s, [Simulation.IN_RIGHT, 0], w[1])
	check(s.players[0].x > x0, "操作キャラ(index0)が動く")
	# 相方はCPUとして自律移動する(構え位置追従)が人間入力そのものには影響されない:
	# 同じ状態から人間入力だけ変えて1tick進め、相方の位置が一致することを確認する
	# (1tickなら全員の判断が同じ事前状態から出るため、純粋に入力遮断だけを見られる)
	var wa := _world()
	var wb := _world()
	Simulation.tick(wa[0], [Simulation.IN_RIGHT | Simulation.IN_JUMP, 0], wa[1])
	Simulation.tick(wb[0], [Simulation.IN_LEFT, 0], wb[1])
	check_eq(wa[0].players[1].x, wb[0].players[1].x, "相方は人間入力では動かない")
	check_eq(wa[0].players[1].vy, wb[0].players[1].vy, "相方は人間のジャンプ入力でも跳ばない")

func test_switch_toggles_on_edge() -> void:
	var w := _world()
	var s = w[0]
	check_eq(s.controlled_l, 0, "初期操作キャラは0")
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	check_eq(s.controlled_l, 1, "SWITCH押下で切替")
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	check_eq(s.controlled_l, 1, "押しっぱなしでは再切替しない(エッジ検出)")
	Simulation.tick(s, [0, 0], w[1])
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	check_eq(s.controlled_l, 0, "離して押し直すと戻る")

func test_after_switch_input_reaches_new_char() -> void:
	var w := _world()
	var s = w[0]
	Simulation.tick(s, [Simulation.IN_SWITCH, 0], w[1])
	var x1: int = s.players[1].x
	for i in 30:
		Simulation.tick(s, [Simulation.IN_RIGHT, 0], w[1])
	check(s.players[1].x > x1, "切替後はindex1が動く")
