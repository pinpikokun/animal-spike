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

func test_cpu_team_serves_via_team_input() -> void:
	# 1人プレイの配線(左=人間、右=完全CPU)で右チームにサーブ権が移っても
	# 試合が止まらないことの回帰テスト。表示層はこのパターンでtickを呼ぶ
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	Simulation.reset_match(s, cfg, 1)
	var served := false
	for i in cfg.serve_delay_ticks + 10:
		var cpu_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "右チーム(完全CPU)のサーブで試合が進む")

func test_cpu_serve_crosses_net() -> void:
	# セルフトス方式のサーブでも、CPUは前トス(ネット方向)で確実にネットを越え自滅しない
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左=人間が相方(index1)操作、CPUサーバー(index0)が自動サーブする配線
	s.controlled_l = 1
	var served := false
	for i in cfg.serve_delay_ticks + 5:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUがサーブ(トス)を実行")
	var crossed := false
	for i in 300:
		Simulation.tick(s, [0, 0], cfg)
		if s.ball_x > cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "CPUのサーブがネットを越え相手コートへ渡る(自滅しない)")

func test_cpu_walks_home_during_pause() -> void:
	# 得点後のポーズ中、CPUは棒立ちせず持ち場へ歩いて戻る
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.players[1].x = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "ポーズ中は持ち場(spawn_front=250)へ戻る")

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
