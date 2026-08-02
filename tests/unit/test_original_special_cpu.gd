extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SpecialBall := preload("res://src/sim/special_ball.gd")
const SpecialMoves := preload("res://src/sim/special_moves.gd")

const D := SimInput.IN_ABILITY1

const SPECIAL_CASES: Array[Array] = [
	[Chars.CHAR_TOME, Chars.SUPER_GHOST_BALL, true],
	[Chars.CHAR_HITO, Chars.SUPER_DISAPPEARING_BALL, true],
	[Chars.CHAR_PIYO, Chars.SUPER_GUST_BALL, true],
	[Chars.CHAR_UME, Chars.SUPER_SNAKE_BALL, true],
	[Chars.CHAR_CARBY, Chars.SUPER_GHOST_BALL, true],
	[Chars.CHAR_DUO, Chars.SUPER_BUBBLE_PACK, false],
	[Chars.CHAR_SEC1, Chars.SUPER_TRANSFER_BALL, false],
	[Chars.CHAR_SEC2, Chars.SUPER_REFRAIN_ATTACK, false],
]

func _world(char_id: int, ground: bool, drive: int = 100) -> Array:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[char_id, Chars.CHAR_PANDA, Chars.CHAR_PANDA, Chars.CHAR_PANDA], 0, 0)
	s.phase = SimState.PHASE_RALLY
	s.serve_ball = 0
	s.serve_flight = 0
	s.last_touch_team = 0
	s.last_touch_idx = 1
	s.touches = 1
	s.aitick = 37
	var p = s.players[0]
	p.cpu = SimCpu.PRESET_MAX
	p.drive_gauge = drive
	p.x = cfg.court_width / 4
	p.y = cfg.floor_y if ground else cfg.ball_radius
	p.on_ground = 1 if ground else 0
	p.vx = 0
	p.vy = 0
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = FP.from_int(2)
	s.ball_vy = 0
	s.ball_special_id = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NONE
	return [s, cfg, p]

func test_each_original_cpu_returns_a_legal_shared_special_input_deterministically() -> void:
	for row: Array in SPECIAL_CASES:
		var first := _world(int(row[0]), bool(row[2]))
		var second := _world(int(row[0]), bool(row[2]))
		var before_drive: int = first[2].drive_gauge
		var before_state: Array[int] = first[0].to_int_array()
		var input_a: int = SimCpu.decide(first[0], 0, first[1])
		var input_b: int = SimCpu.decide(second[0], 0, second[1])
		check_eq(input_a, input_b, "同じseedと状態なら入力一致: %d" % row[0])
		check((input_a & D) != 0, "原作キャラが合法なD複合入力を選ぶ: %d" % row[0])
		check_eq(SpecialMoves.select_hit_special(first[0], 0, input_a, first[1]),
			int(row[1]), "CPU入力も人間と同じ必殺判定で成立: %d" % row[0])
		check_eq(first[2].drive_gauge, before_drive, "CPU判断だけでは消費しない: %d" % row[0])
		check_eq(first[0].ball_special_id, 0, "CPU判断だけでは球状態を変えない: %d" % row[0])
		check_eq(first[0].to_int_array(), before_state,
			"CPU判断は同期状態を一切変更しない: %d" % row[0])

func test_tome_air_flame_also_returns_through_the_shared_hit_selector() -> void:
	var w := _world(Chars.CHAR_TOME, false)
	var input: int = SimCpu.decide(w[0], 0, w[1])
	check_eq(SpecialMoves.select_hit_special(w[0], 0, input, w[1]),
		Chars.SUPER_FLAME_ATTACK, "既存CPU炎球も共通必殺判定で成立")

func test_tome_cpu_uses_original_y_152_not_the_old_net_top_approximation() -> void:
	var w := _world(Chars.CHAR_TOME, false)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	# 旧CPU試作では合法だった「ネットより少し上」。承認済み原作条件y<152には
	# 足りないため、Task7以後はDを返さないことを明示する。
	p.y = cfg.net_top_y - cfg.ball_radius - FP.from_int(48)
	s.ball_y = p.y
	var input: int = SimCpu.decide(s, 0, cfg)
	check_eq(input & D, 0, "旧ネット上近似では炎球を要求しない")
	check_eq(SpecialMoves.select_hit_special(s, 0, D | SimInput.IN_DOWN, cfg),
		0, "人間と共通の原作y<152判定でも不成立")

func test_original_cpu_does_not_add_special_input_during_serve() -> void:
	for row: Array in SPECIAL_CASES:
		var w := _world(int(row[0]), true)
		w[0].phase = SimState.PHASE_SERVE
		w[0].serving_team = 0
		check_eq(SimCpu.decide(w[0], 0, w[1]) & D, 0,
			"サーブ中は必殺Dを混ぜない: %d" % row[0])

func test_original_cpu_never_requests_special_at_34_or_during_burnout() -> void:
	for row: Array in SPECIAL_CASES:
		var low := _world(int(row[0]), bool(row[2]), 34)
		check_eq(SimCpu.decide(low[0], 0, low[1]) & D, 0,
			"34ではDを要求しない: %d" % row[0])
		var burnout := _world(int(row[0]), bool(row[2]))
		burnout[2].burnout_ticks = 1
		check_eq(SimCpu.decide(burnout[0], 0, burnout[1]) & D, 0,
			"バーンアウト中はDを要求しない: %d" % row[0])

func test_duo_cpu_can_choose_suction_outside_normal_hit_reach_without_mutation() -> void:
	var w := _world(Chars.CHAR_DUO, false)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	s.ball_x = p.x + SpecialBall.original_x_distance(32, cfg) - 1
	s.ball_y = p.y
	var before_drive: int = p.drive_gauge
	var input: int = SimCpu.decide(s, 0, cfg)
	check((input & D) != 0 and (input & SimInput.IN_LEFT) != 0,
		"DUOは通常打球圏外の前方球へ後+D吸引を選ぶ")
	check(SpecialMoves.can_start_action(s, 0, input, cfg),
		"吸引入力も人間と同じ共通合法判定を通る")
	check_eq(p.drive_gauge, before_drive, "吸引判断だけでは消費しない")

func test_sec1_cpu_adds_subspace_d_only_when_projected_total_cost_is_payable() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_SEC1, Chars.CHAR_PANDA, Chars.CHAR_PANDA, Chars.CHAR_PANDA], 0, 0)
	s.phase = SimState.PHASE_RALLY
	s.serve_ball = 0
	s.serve_flight = 0
	s.last_touch_team = 1
	s.rally_role_roll_team0 = 0
	var p = s.players[0]
	p.cpu = SimCpu.PRESET_MAX
	p.on_ground = 0
	p.x = cfg.net_x - FP.from_int(20)
	var attacker = s.players[2]
	attacker.on_ground = 0
	attacker.x = cfg.net_x + FP.from_int(40)
	attacker.y = cfg.floor_y - FP.from_int(20)
	s.ball_x = cfg.net_x + FP.from_int(1)
	s.ball_y = attacker.y
	var total: int = cfg.block_start_drive_cost + cfg.block_contact_drive_cost \
		+ cfg.special_drive_cost_default
	p.drive_gauge = total
	var input: int = SimCpu._decide_block(
		s, 0, p, cfg, 0, SimCpu.AB_BLOCK, 0)
	check((input & (SimInput.IN_ACTION | SimInput.IN_RIGHT | D)) \
		== (SimInput.IN_ACTION | SimInput.IN_RIGHT | D),
		"45あれば通常ブロック入力へDを添える")
	check(SpecialMoves.can_request_block_enhancement(s, 0, input, cfg),
		"亜空間ブロック候補は共通の事前合法判定を通る")
	check_eq(p.drive_gauge, total, "ブロック判断だけでは消費しない")
	p.drive_gauge = total - 1
	check_eq(SimCpu._decide_block(s, 0, p, cfg, 0, SimCpu.AB_BLOCK, 0) & D, 0,
		"通常費用込みで1不足ならDを添えない")
