extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")
const STANDARD_CHAR := 99

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	return [s, cfg]

func _select_successful_roll(s, actor: int, salt: int, threshold: int) -> void:
	for key in 900:
		if SimCpu._noise(salt, key, actor) % 256 < threshold:
			s.last_hit_tick = key
			return

func _air_attack_world(char_id: int, profile: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	s.tick = 1000
	var p = s.players[1]
	p.char_id = char_id
	p.cpu = profile
	p.on_ground = 0
	p.x = cfg.net_x - FP.from_int(24)
	# 下向きアタックがネット到達までに落ちても、球半径込みで上端を越える高さ。
	p.y = cfg.net_top_y - cfg.ball_radius - FP.from_int(48)
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	return [s, cfg]

func test_max_cpu_prefers_attack_over_air_toss() -> void:
	var w := _air_attack_world(STANDARD_CHAR, SimCpu.PRESET_MAX)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check(input & Simulation.IN_ACTION, "最強CPUは攻撃機会で打球する")
	check(input & Simulation.IN_DOWN, "成立するアタックを空中トスより優先する")

func test_max_tome_uses_flame_with_three_stocks_at_high_contact() -> void:
	var w := _air_attack_world(Chars.CHAR_TOME, SimCpu.PRESET_MAX)
	var s = w[0]
	var cfg = w[1]
	s.players[1].drive_gauge = cfg.drive_gauge_stock * 3
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ABILITY1, "最強TOMEは3本以上の攻撃機会で炎を選ぶ")
	check(input & Simulation.IN_DOWN, "炎は空中の下+Dで明示入力する")

func test_weak_cpu_does_not_use_flame_at_same_opportunity() -> void:
	var w := _air_attack_world(Chars.CHAR_TOME, SimCpu.PRESET_WEAK)
	var s = w[0]
	var cfg = w[1]
	s.players[1].drive_gauge = cfg.drive_gauge_stock * 6
	var input: int = SimCpu.decide(s, 1, cfg)
	check_eq(input & Simulation.IN_ABILITY1, 0, "弱CPUは必殺技を選ばない")

func _incoming_attack_world(profile: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	var p = s.players[1]
	p.cpu = profile
	p.vx = 0
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(100)
	s.ball_vx = 0
	s.ball_vy = 0
	_select_successful_roll(s, 1, SimCpu.SALT_RECEIVE,
		SimCpu.prof_byte(profile, SimCpu.P_SWEET))
	return [s, cfg]

func test_max_cpu_stops_and_builds_receive_stance_after_early_arrival() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_MAX)
	var s = w[0]
	var input: int = SimCpu.decide(s, 1, w[1])
	check(input & Simulation.IN_ACTION, "最強CPUは攻撃球へ事前到達すると構える")
	check(input & Simulation.IN_DOWN, "構えは下+ボタン")
	check_eq(input & (Simulation.IN_LEFT | Simulation.IN_RIGHT), 0,
		"構え中は横入力を止める")
	Simulation._update_receive_stances(s, [0, input, 0, 0])
	check_eq(s.players[1].receive_stance, 1, "CPU入力でreceive_stanceが立つ")

func test_max_cpu_just_receive_actually_fires() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_MAX)
	var s = w[0]
	var cfg = w[1]
	var input: int = SimCpu.decide(s, 1, cfg)
	Simulation._update_receive_stances(s, [0, input, 0, 0])
	s.ball_y = s.players[1].y
	input = SimCpu.decide(s, 1, cfg)
	HitResolver._apply_hit(s, 1, cfg, input, 0)
	check_eq(s.players[1].just_receive_event, 1,
		"事前構えからCPUのジャストレシーブが実際に成立する")

func test_weak_cpu_does_not_prepare_just_receive() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_WEAK)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check_eq(input & (Simulation.IN_ACTION | Simulation.IN_DOWN), 0,
		"弱CPUは攻撃球に対するジャストレシーブ構えを使わない")
