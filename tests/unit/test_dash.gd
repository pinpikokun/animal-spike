extends "res://tests/test_case.gd"

const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const Chars := preload("res://src/sim/chars.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")

func _rally(char_id: int):
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = St.PHASE_RALLY
	s.serve_tossed = 1
	s.players[0].char_id = char_id
	# ボールを遠くへ置き、ヒット判定が動きに混ざらないようにする
	s.ball_x = cfg.court_width - 10
	s.ball_y = 60
	return [s, cfg]

func _tap_twice(s, cfg, dir_input: int, gap: int) -> void:
	# 押す→離す(gap tick)→もう一度押す
	Sim.tick(s, [dir_input, 0], cfg)
	for i in gap:
		Sim.tick(s, [0, 0], cfg)
	Sim.tick(s, [dir_input, 0], cfg)

func test_double_tap_dashes() -> void:
	var w = _rally(Chars.CHAR_DEBUG); var s = w[0]; var cfg = w[1]
	_tap_twice(s, cfg, SimInput.IN_RIGHT, 2)
	check(s.players[0].dash > 0, "窓内の2回タップでダッシュ発動")
	var spd: int = cfg.move_speed * Chars.stat(Chars.CHAR_DEBUG, "speed") / 100
	check_eq(s.players[0].vx, spd * PlayerMovement.DASH_SPD_PCT / 100, "ダッシュ速度=speed%x175%")

func test_no_dash_outside_window() -> void:
	var w = _rally(Chars.CHAR_DEBUG); var s = w[0]; var cfg = w[1]
	_tap_twice(s, cfg, SimInput.IN_RIGHT, PlayerMovement.DASH_TAP_WINDOW + 1)
	check_eq(s.players[0].dash, 0, "窓を過ぎた2回目では発動しない")

func test_no_dash_on_reverse_tap() -> void:
	var w = _rally(Chars.CHAR_DEBUG); var s = w[0]; var cfg = w[1]
	Sim.tick(s, [SimInput.IN_RIGHT, 0], cfg)
	Sim.tick(s, [0, 0], cfg)
	Sim.tick(s, [SimInput.IN_LEFT, 0], cfg)
	check_eq(s.players[0].dash, 0, "逆方向タップでは発動しない")

func test_no_dash_without_ability() -> void:
	var w = _rally(Chars.CHAR_PANDA); var s = w[0]; var cfg = w[1]
	_tap_twice(s, cfg, SimInput.IN_RIGHT, 2)
	check_eq(s.players[0].dash, 0, "CA_DASH無しキャラは発動しない")

func test_rally_reset_turns_same_direction_tap_into_a_new_first_tap() -> void:
	var control = _rally(Chars.CHAR_DEBUG)
	var control_state = control[0]
	var cfg = control[1]
	Sim.tick(control_state, [SimInput.IN_RIGHT, 0], cfg)
	Sim.tick(control_state, [0, 0], cfg)
	check(control_state.players[0].tap_tick > 0,
		"対照: 1回目の右タップ受付が残っている")
	Sim.tick(control_state, [SimInput.IN_RIGHT, 0], cfg)
	check(control_state.players[0].dash > 0,
		"対照: resetなしの同方向2回目はダッシュになる")

	var reset_case = _rally(Chars.CHAR_DEBUG)
	var reset_state = reset_case[0]
	Sim.tick(reset_state, [SimInput.IN_RIGHT, 0], cfg)
	Sim.tick(reset_state, [0, 0], cfg)
	check(reset_state.players[0].tap_tick > 0,
		"前提: reset前に右タップ受付が残っている")
	Sim.reset_rally(reset_state, cfg, 1)
	Sim.tick(reset_state, [SimInput.IN_RIGHT, 0], cfg)
	check_eq(reset_state.players[0].dash, 0,
		"reset後の同方向1回目ではダッシュしない")
	check_eq(reset_state.players[0].tap_tick, PlayerMovement.DASH_TAP_WINDOW,
		"reset後の入力を新しい1回目として記録する")

func test_dash_jump_carries_speed() -> void:
	# ダッシュ中にジャンプ→空中でもダッシュ速度で横移動(ダッシュジャンプ)
	var w = _rally(Chars.CHAR_DEBUG); var s = w[0]; var cfg = w[1]
	_tap_twice(s, cfg, SimInput.IN_RIGHT, 2)
	Sim.tick(s, [SimInput.IN_RIGHT | SimInput.IN_JUMP, 0], cfg)
	check_eq(s.players[0].on_ground, 0, "ジャンプで離陸")
	var spd: int = cfg.move_speed * Chars.stat(Chars.CHAR_DEBUG, "speed") / 100
	check_eq(s.players[0].vx, spd * PlayerMovement.DASH_SPD_PCT / 100, "空中もダッシュ速度")

func test_dash_expires() -> void:
	var w = _rally(Chars.CHAR_DEBUG); var s = w[0]; var cfg = w[1]
	_tap_twice(s, cfg, SimInput.IN_RIGHT, 2)
	for i in PlayerMovement.DASH_TICKS:
		Sim.tick(s, [SimInput.IN_RIGHT, 0], cfg)
	check_eq(s.players[0].dash, 0, "持続tick経過で終了")
	var spd: int = cfg.move_speed * Chars.stat(Chars.CHAR_DEBUG, "speed") / 100
	check_eq(s.players[0].vx, spd, "終了後は通常速度に戻る")
