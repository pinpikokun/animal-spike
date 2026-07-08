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
