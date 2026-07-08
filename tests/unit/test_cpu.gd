extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_rally(s, cfg, 0)
	return [s, cfg]

func test_cpu_chases_ball_on_own_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(200)
	s.ball_y = FP.from_int(100)
	# players[1](左チーム相方、spawn_front=250)から見てボールは左
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_LEFT, "ボールへ向かって左移動")

func test_cpu_hits_in_reach() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = s.players[1].x + FP.from_int(3)
	s.ball_y = s.players[1].y - FP.from_int(10)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION, "リーチ内でACTION")

func test_cpu_ignores_ball_on_other_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(500)
	s.ball_y = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ACTION), "敵陣のボールは打たない")

func test_cpu_auto_serves() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左チームのサーバーはplayers[0]。人間が相方(index1)を操作している想定で
	# tick経由でCPUサーバーの自動サーブを検証する
	s.controlled_l = 1
	var served := false
	for i in cfg.serve_delay_ticks + 10:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUサーバーが自動サーブする")

func test_cpu_returns_to_spawn() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(500)
	s.ball_y = FP.from_int(100)
	s.players[1].x = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "持ち場(spawn_front=250)へ戻る")
