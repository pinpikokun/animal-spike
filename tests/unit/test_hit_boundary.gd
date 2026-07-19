extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func test_hit_boundary_declares_three_state_results() -> void:
	check_eq(Simulation.NO_HIT, -2, "不成立定数")
	check_eq(Simulation.HIT_NO_POINT, -1, "成立・得点なし定数")

func _clone_state(s):
	var clone = SimState.new()
	clone.load_int_array(s.to_int_array())
	return clone

func _place_ball_on_player(s, player_index: int, cfg) -> int:
	var p = s.players[player_index]
	p.y = cfg.floor_y
	p.on_ground = 1
	p.hit_cooldown = 0
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(10)
	return FP.from_int(10) * FP.from_int(10)

func _resolve_result(s, inputs: Array[int], cfg):
	return Simulation._resolve_hit(s, inputs, cfg)

func _legacy_expected_hit(s, player_index: int, input: int, d2: int, cfg,
		was_serve_strike: bool) -> void:
	Simulation._apply_hit(s, player_index, cfg, input, d2)
	if s.touches > cfg.max_touches \
			and s.phase != SimState.PHASE_POINT_PAUSE \
			and s.phase != SimState.PHASE_GAME_OVER:
		Simulation._award_point(s, 1 - player_index / 2, cfg)
	if was_serve_strike:
		s.phase = SimState.PHASE_RALLY
		s.serve_tossed = 0
		s.serve_flight = 1

func test_normal_serve_strike_returns_hit_no_point_and_preserves_state() -> void:
	var cfg = SimConfig.new()
	var actual = SimState.new()
	Simulation.reset_match(actual, cfg, 0)
	actual.serve_tossed = 1
	var d2 := _place_ball_on_player(actual, 0, cfg)
	var expected = _clone_state(actual)
	var input := Simulation.IN_ACTION | Simulation.IN_RIGHT
	_legacy_expected_hit(expected, 0, input, d2, cfg, true)

	var result = _resolve_result(actual, [input, 0, 0, 0], cfg)
	if result == 0 or result == 1:
		Simulation._award_point(actual, result, cfg)
	if result != Simulation.NO_HIT:
		actual.phase = SimState.PHASE_RALLY
		actual.serve_tossed = 0
		actual.serve_flight = 1

	check_eq(result, Simulation.HIT_NO_POINT, "通常サーブ打撃は得点なしの成立")
	check_eq(actual.to_int_array(), expected.to_int_array(), "通常サーブ打撃の全state")

func test_zero_max_touches_serve_preserves_award_then_transition_order() -> void:
	var cfg = SimConfig.new()
	cfg.max_touches = 0
	var actual = SimState.new()
	Simulation.reset_match(actual, cfg, 0)
	actual.serve_tossed = 1
	var d2 := _place_ball_on_player(actual, 0, cfg)
	var expected = _clone_state(actual)
	var through_step = _clone_state(actual)
	var input := Simulation.IN_ACTION | Simulation.IN_RIGHT
	_legacy_expected_hit(expected, 0, input, d2, cfg, true)

	var result = _resolve_result(actual, [input, 0, 0, 0], cfg)
	if result == 0 or result == 1:
		Simulation._award_point(actual, result, cfg)
	if result != Simulation.NO_HIT:
		actual.phase = SimState.PHASE_RALLY
		actual.serve_tossed = 0
		actual.serve_flight = 1
	Simulation._step_players_and_hits(through_step, [input, 0, 0, 0], cfg)

	check_eq(result, 1, "タッチ上限0のサーブは相手得点を返す")
	check_eq(actual.to_int_array(), expected.to_int_array(), "授与後にサーブ遷移する全state")
	check_eq([through_step.score_r, through_step.phase, through_step.serve_tossed,
		through_step.serve_flight], [1, SimState.PHASE_RALLY, 0, 1],
		"実呼び出し元も得点後にサーブ遷移")

func test_missed_serve_strike_returns_no_hit_without_state_change() -> void:
	var cfg = SimConfig.new()
	var actual = SimState.new()
	Simulation.reset_match(actual, cfg, 0)
	actual.serve_tossed = 1
	actual.ball_x = cfg.net_x
	actual.ball_y = 0
	var before: Array[int] = actual.to_int_array()

	var result = _resolve_result(actual,
		[Simulation.IN_ACTION | Simulation.IN_RIGHT, 0, 0, 0], cfg)

	check_eq(result, Simulation.NO_HIT, "届かないサーブ打撃は不成立")
	check_eq(actual.to_int_array(), before, "不成立時は全state不変")

func test_rally_touch_over_returns_point_and_awards_same_tick() -> void:
	var cfg = SimConfig.new()
	var actual = SimState.new()
	Simulation.reset_match(actual, cfg, 0)
	actual.phase = SimState.PHASE_RALLY
	actual.last_touch_team = 0
	actual.touches = cfg.max_touches
	var d2 := _place_ball_on_player(actual, 0, cfg)
	var expected = _clone_state(actual)
	var input := Simulation.IN_ACTION | Simulation.IN_RIGHT
	_legacy_expected_hit(expected, 0, input, d2, cfg, false)

	var result = _resolve_result(actual, [input, 0, 0, 0], cfg)
	if result == 0 or result == 1:
		Simulation._award_point(actual, result, cfg)

	check_eq(result, 1, "ラリー中のタッチ超過は相手得点を返す")
	check_eq(actual.to_int_array(), expected.to_int_array(), "得点授与まで含む全state")
