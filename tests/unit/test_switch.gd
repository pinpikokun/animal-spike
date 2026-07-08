extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_rally(s, cfg, 0)
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(600)
	s.ball_y = FP.from_int(50)
	return [s, cfg]

func test_human_input_reaches_controlled_char() -> void:
	var w := _world()
	var s = w[0]
	var x0: int = s.players[0].x
	var x1: int = s.players[1].x
	for i in 30:
		Simulation.tick(s, [Simulation.IN_RIGHT, 0], w[1])
	check(s.players[0].x > x0, "操作キャラ(index0)が動く")
	check_eq(s.players[1].x, x1, "相方は人間入力では動かない")

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
