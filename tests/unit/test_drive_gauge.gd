extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _air_attack(s, cfg, actor: int, sweet: bool) -> void:
	var p = s.players[actor]
	p.on_ground = 0
	var d2: int = 0 if sweet else cfg.player_reach * cfg.player_reach
	HitResolver._apply_hit(s, actor, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, d2)

func test_drive_gauge_starts_full_and_survives_rally_reset() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	for p in s.players:
		check_eq(p.drive_gauge, 100, "試合開始は100満タン")
	s.players[0].drive_gauge = 65
	Simulation.reset_rally(s, cfg, 1)
	check_eq(s.players[0].drive_gauge, 65, "得点を跨いでも残量を維持")

func test_drive_has_no_passive_recovery() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 65
	for phase in [SimState.PHASE_SERVE, SimState.PHASE_POINT_PAUSE,
			SimState.PHASE_RALLY]:
		s.phase = phase
		for i in 300:
			Simulation._update_drive_recovery(s, cfg)
		check_eq(p.drive_gauge, 65, "自然回復はフェーズを問わず発生しない")

func test_normal_attack_and_receive_cost_no_drive() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	_air_attack(s, cfg, 0, false)
	check_eq(s.players[0].drive_gauge, 100, "通常アタックは消費なし")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL, "通常属性を保持")
	s.players[2].on_ground = 1
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[2].drive_gauge, 100, "通常レシーブも消費なし")

func test_just_attack_costs_25_and_receive_costs_no_drive() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	_air_attack(s, cfg, 0, true)
	check_eq(s.players[0].drive_gauge, 75, "ジャストアタックは25消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_JUST, "ジャスト属性を保持")
	s.players[2].on_ground = 1
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[2].drive_gauge, 100, "強い球を受けてもドライブは減らない")

func test_up_attack_stays_normal_without_drive_cost() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_UP, 0)
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
		"上アタックは芯でも通常属性")
	check_eq(s.ball_power, 0, "上アタックはパワーボールにならない")
	check_eq(p.drive_gauge, 100, "上アタックはドライブを消費しない")

func test_toss_and_attack_return_cost_no_drive() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.last_touch_team = 1
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION,
		cfg.player_reach * cfg.player_reach)
	check_eq(s.players[0].drive_gauge, 100, "トスは消費なし")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE, "トス後は攻撃属性を消す")
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.last_touch_team = 1
	s.players[0].on_ground = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[0].drive_gauge, 100, "アタック返しも消費なし")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"アタック返しは攻撃属性を持たない")

func test_block_spends_start_and_contact_costs_and_clears_attack_kind() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[2]
	p.x = cfg.net_x + FP.from_int(20)
	p.y = cfg.floor_y - FP.from_int(60)
	p.on_ground = 0
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(8)
	HitResolver._ball_vs_block(s, cfg,
		[0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0])
	check_eq(p.drive_gauge, 90, "ブロックは開始5と接触5を消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"ブロック反射球は攻撃属性を持たない")

func test_insufficient_just_falls_back_to_normal_without_partial_spend() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].drive_gauge = 24
	_air_attack(s, cfg, 0, true)
	check_eq(s.players[0].drive_gauge, 24, "不足時は一部消費しない")
	check_eq(s.players[0].burnout_ticks, 0, "不成立ではバーンアウトしない")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
		"不足時は通常アタックへフォールバック")

func test_drive_gauge_serialization_roundtrip() -> void:
	var w := _world()
	var a = w[0]
	a.players[1].drive_gauge = 65
	a.players[1].drive_reserved = 5
	a.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	var b = SimState.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.players[1].drive_gauge, 65, "ゲージ残量を復元")
	check_eq(b.players[1].drive_reserved, 5, "予約量を復元")
	check_eq(b.ball_attack_kind, SimState.BALL_ATTACK_NORMAL, "攻撃属性を復元")
	check_eq(b.state_hash(), a.state_hash(), "ドライブ状態を含めた直列化往復")
