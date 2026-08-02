extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SpecialMoves := preload("res://src/sim/special_moves.gd")

const D := SimInput.IN_ABILITY1

func _world(char_id: int, ground: bool = true) -> Array:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[char_id, Chars.CHAR_PANDA, Chars.CHAR_PANDA, Chars.CHAR_PANDA], 0, 0)
	s.phase = SimState.PHASE_RALLY
	s.serve_ball = 0
	s.serve_flight = 0
	var p = s.players[0]
	p.drive_gauge = cfg.drive_gauge_max
	p.on_ground = 1 if ground else 0
	p.y = cfg.floor_y if ground else cfg.floor_y - FP.from_int(140)
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(10) if ground else p.y
	s.ball_vx = FP.from_int(2)
	s.ball_vy = 0
	s.last_touch_team = -1
	return [s, cfg]

func _set_original_height(s, cfg, original_y: int) -> void:
	var rhs: int = (291 - original_y) * (cfg.floor_y - cfg.net_top_y)
	s.ball_y = cfg.floor_y - rhs / 33 - 1
	s.players[0].y = s.ball_y

func test_all_fifteen_hit_activation_routes_select_the_approved_effect() -> void:
	var cases := [
		[Chars.CHAR_TOME, true, D | SimInput.IN_UP, Chars.SUPER_GHOST_BALL, -1, false],
		[Chars.CHAR_TOME, false, D | SimInput.IN_DOWN, Chars.SUPER_FLAME_ATTACK, 152, false],
		[Chars.CHAR_HITO, true, D | SimInput.IN_UP, Chars.SUPER_DISAPPEARING_BALL, -1, false],
		[Chars.CHAR_HITO, true, D, Chars.SUPER_FEINT_ATTACK, -1, false],
		[Chars.CHAR_HITO, false, D | SimInput.IN_DOWN, Chars.SUPER_DISAPPEARING_BALL, 160, false],
		[Chars.CHAR_PIYO, true, D | SimInput.IN_UP, Chars.SUPER_GUST_BALL, -1, false],
		[Chars.CHAR_PIYO, false, D | SimInput.IN_RIGHT, Chars.SUPER_GUST_BALL, -1, true],
		[Chars.CHAR_UME, true, D | SimInput.IN_UP, Chars.SUPER_SNAKE_BALL, -1, false],
		[Chars.CHAR_UME, true, D, Chars.SUPER_BUMBLE_BALL, -1, false],
		[Chars.CHAR_UME, false, D | SimInput.IN_RIGHT, Chars.SUPER_BUMBLE_BALL, -1, true],
		[Chars.CHAR_CARBY, true, D | SimInput.IN_UP, Chars.SUPER_GHOST_BALL, -1, false],
		[Chars.CHAR_CARBY, false, D, Chars.SUPER_THUNDER_BALL, -1, false],
		[Chars.CHAR_DUO, false, D | SimInput.IN_DOWN, Chars.SUPER_BUBBLE_PACK, 160, false],
		[Chars.CHAR_SEC1, false, D | SimInput.IN_DOWN, Chars.SUPER_TRANSFER_BALL, -1, false],
		[Chars.CHAR_SEC2, false, D | SimInput.IN_DOWN, Chars.SUPER_REFRAIN_ATTACK, 192, false],
	]
	for case in cases:
		var w := _world(case[0], case[1]); var s = w[0]; var cfg = w[1]
		if case[4] >= 0:
			_set_original_height(s, cfg, case[4])
		if case[5]:
			s.last_touch_team = 0
		check_eq(SpecialMoves.select_hit_special(s, 0, case[2], cfg), case[3],
			"承認済み発動経路: %s" % Chars.NAMES[case[0]])

func test_team_relative_forward_is_reversed_on_right_team() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_PANDA, Chars.CHAR_PANDA, Chars.CHAR_PIYO, Chars.CHAR_PANDA], 0, 0)
	s.phase = SimState.PHASE_RALLY
	var p = s.players[2]
	p.on_ground = 0
	p.drive_gauge = cfg.drive_gauge_max
	s.last_touch_team = 1
	check_eq(SpecialMoves.select_hit_special(s, 2, D | SimInput.IN_LEFT, cfg),
		Chars.SUPER_GUST_BALL, "右チームの前は画面左")
	check_eq(SpecialMoves.select_hit_special(s, 2, D | SimInput.IN_RIGHT, cfg), 0,
		"右チームの画面右は後ろ")

func test_invalid_conditions_do_not_select_or_spend() -> void:
	var w := _world(Chars.CHAR_TOME, true); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	var before: int = p.drive_gauge
	check_eq(SpecialMoves.select_hit_special(s, 0, SimInput.IN_UP, cfg), 0, "Dなし")
	p.drive_gauge = cfg.special_drive_cost_default - 1
	check_eq(SpecialMoves.select_hit_special(s, 0, D | SimInput.IN_UP, cfg), 0, "34")
	p.drive_gauge = before
	p.burnout_ticks = 1
	check_eq(SpecialMoves.select_hit_special(s, 0, D | SimInput.IN_UP, cfg), 0,
		"バーンアウト")
	p.burnout_ticks = 0
	s.phase = SimState.PHASE_SERVE
	check_eq(SpecialMoves.select_hit_special(s, 0, D | SimInput.IN_UP, cfg), 0,
		"サーブ中")
	s.phase = SimState.PHASE_RALLY
	s.ball_special_id = Chars.SUPER_SNAKE_BALL
	check_eq(SpecialMoves.select_hit_special(s, 0, D | SimInput.IN_UP, cfg), 0,
		"通常球限定技は特殊球を上書きしない")
	check_eq(p.drive_gauge, before, "選択だけでは一切消費しない")

func test_height_boundary_friendly_ball_and_apex_are_strict() -> void:
	var hito := _world(Chars.CHAR_HITO, false)
	var hs = hito[0]; var hc = hito[1]
	var rhs: int = (291 - 160) * (hc.floor_y - hc.net_top_y)
	hs.ball_y = hc.floor_y - rhs / 33
	check_eq(SpecialMoves.select_hit_special(hs, 0, D | SimInput.IN_DOWN, hc), 0,
		"高さ境界同値は不成立")
	hs.ball_y -= 1
	check_eq(SpecialMoves.select_hit_special(hs, 0, D | SimInput.IN_DOWN, hc),
		Chars.SUPER_DISAPPEARING_BALL, "境界より1だけ高ければ成立")
	var piyo := _world(Chars.CHAR_PIYO, false)
	check_eq(SpecialMoves.select_hit_special(piyo[0], 0, D | SimInput.IN_RIGHT, piyo[1]),
		0, "味方の直前接触なしでは空中連携不成立")
	var carby := _world(Chars.CHAR_CARBY, false)
	carby[0].ball_vy = carby[1].gravity * 16 / 5
	check_eq(SpecialMoves.select_hit_special(carby[0], 0, D, carby[1]), 0,
		"頂点窓の同値は不成立")
	carby[0].ball_vy -= 1
	check_eq(SpecialMoves.select_hit_special(carby[0], 0, D, carby[1]),
		Chars.SUPER_THUNDER_BALL, "頂点窓内は成立")

func test_each_hit_effect_commits_once_on_actual_contact() -> void:
	var cases := [
		[Chars.CHAR_TOME, true, D | SimInput.IN_UP, Chars.SUPER_GHOST_BALL, -1, false],
		[Chars.CHAR_HITO, true, D, Chars.SUPER_FEINT_ATTACK, -1, false],
		[Chars.CHAR_PIYO, false, D | SimInput.IN_RIGHT, Chars.SUPER_GUST_BALL, -1, true],
		[Chars.CHAR_UME, false, D | SimInput.IN_RIGHT, Chars.SUPER_BUMBLE_BALL, -1, true],
		[Chars.CHAR_CARBY, false, D, Chars.SUPER_THUNDER_BALL, -1, false],
		[Chars.CHAR_DUO, false, D | SimInput.IN_DOWN, Chars.SUPER_BUBBLE_PACK, 160, false],
		[Chars.CHAR_SEC1, false, D | SimInput.IN_DOWN, Chars.SUPER_TRANSFER_BALL, -1, false],
		[Chars.CHAR_SEC2, false, D | SimInput.IN_DOWN, Chars.SUPER_REFRAIN_ATTACK, 192, false],
	]
	for case in cases:
		var w := _world(case[0], case[1]); var s = w[0]; var cfg = w[1]
		if case[4] >= 0:
			_set_original_height(s, cfg, case[4])
		if case[5]:
			s.last_touch_team = 0
		HitResolver._apply_hit(s, 0, cfg, case[2], 0)
		check_eq(s.ball_special_id, case[3], "接触時に特殊球IDを確定")
		check_eq(s.players[0].drive_gauge,
			cfg.drive_gauge_max - cfg.special_drive_cost_default, "接触時に35を一度消費")
		check_eq(s.ball_health_damage, Chars.super_def(case[3]).power,
			"カタログ威力を球へ記録")
		var expected_power: int = 1 if int(Chars.super_def(case[3]).power) > 0 else 0
		check_eq(s.ball_power, expected_power,
			"攻撃型だけを体力ダメージ対象のパワー球にする")

func test_exact_thirty_five_pays_before_effect_and_still_completes() -> void:
	var w := _world(Chars.CHAR_TOME, true); var s = w[0]; var cfg = w[1]
	s.players[0].drive_gauge = cfg.special_drive_cost_default
	HitResolver._apply_hit(s, 0, cfg, D | SimInput.IN_UP, 0)
	check_eq(s.players[0].drive_gauge, 0, "35を全額先払い")
	check(s.players[0].burnout_ticks > 0, "0到達でバーンアウト")
	check_eq(s.ball_special_id, Chars.SUPER_GHOST_BALL,
		"同tickのバーンアウト開始で成立済み効果を失わない")

func test_out_of_range_d_only_does_not_become_a_normal_hit() -> void:
	var w := _world(Chars.CHAR_HITO, true); var s = w[0]; var cfg = w[1]
	s.ball_x = s.players[0].x + cfg.player_reach * 2
	check_eq(HitResolver._resolve_hit(s, [D, 0, 0, 0], cfg), HitResolver.NO_HIT,
		"圏外Dは通常打球へ化けない")
	check_eq(s.touches, 0, "圏外Dはタッチを増やさない")
