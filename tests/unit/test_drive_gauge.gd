extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
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
		check_eq(p.drive_gauge, cfg.drive_gauge_max, "試合開始は6本満タン")
	s.players[0].drive_gauge = cfg.drive_gauge_max - cfg.drive_gauge_stock
	s.players[0].drive_recovery_progress = 73
	Simulation.reset_rally(s, cfg, 1)
	check_eq(s.players[0].drive_gauge,
		cfg.drive_gauge_max - cfg.drive_gauge_stock, "得点を跨いでも残量を維持")
	check_eq(s.players[0].drive_recovery_progress, 73, "得点を跨いでも回復端数を維持")

func test_drive_gauge_recovers_only_during_rally() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = cfg.drive_gauge_max - cfg.drive_gauge_stock
	s.phase = SimState.PHASE_SERVE
	for i in cfg.drive_recovery_ticks_per_stock:
		Simulation._update_drive_recovery(s, cfg)
	check_eq(p.drive_gauge, cfg.drive_gauge_max - cfg.drive_gauge_stock,
		"サーブ保持中は回復停止")
	check_eq(p.drive_recovery_progress, 0, "サーブ保持中は回復端数も停止")
	s.phase = SimState.PHASE_POINT_PAUSE
	for i in cfg.drive_recovery_ticks_per_stock:
		Simulation._update_drive_recovery(s, cfg)
	check_eq(p.drive_gauge, cfg.drive_gauge_max - cfg.drive_gauge_stock,
		"得点間インターバル中は回復停止")
	s.phase = SimState.PHASE_RALLY
	for i in cfg.drive_recovery_ticks_per_stock - 1:
		Simulation._update_drive_recovery(s, cfg)
	check(p.drive_gauge > cfg.drive_gauge_max - cfg.drive_gauge_stock,
		"ラリー中は整数端数を使って毎tick段階的に回復")
	check(p.drive_gauge < cfg.drive_gauge_max, "180tick未満では1本分に届かない")
	Simulation._update_drive_recovery(s, cfg)
	check_eq(p.drive_gauge, cfg.drive_gauge_max, "ラリー180tickで1本回復")
	check_eq(p.drive_recovery_progress, 0, "満タン時は回復端数を残さない")

func test_normal_attack_shaves_receiver_one_stock() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	_air_attack(s, cfg, 0, false)
	check_eq(s.players[0].drive_gauge, cfg.drive_gauge_max,
		"通常アタックは打ち手の消費なし")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL, "通常アタック属性を保持")
	s.players[2].on_ground = 1
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[2].drive_gauge,
		cfg.drive_gauge_max - cfg.drive_gauge_stock, "通常アタックのレシーブで1本削り")

func test_just_attack_costs_half_and_shaves_receiver_two_stocks() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	_air_attack(s, cfg, 0, true)
	check_eq(s.players[0].drive_gauge,
		cfg.drive_gauge_max - cfg.drive_gauge_stock / 2, "ジャスト打撃は0.5本消費")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_JUST, "ジャストアタック属性を保持")
	s.players[2].on_ground = 1
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[2].drive_gauge,
		cfg.drive_gauge_max - cfg.drive_gauge_stock * 2, "ジャストのレシーブで2本削り")

func test_toss_and_attack_return_do_not_take_incoming_drive_damage() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.last_touch_team = 1
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION,
		cfg.player_reach * cfg.player_reach)
	check_eq(s.players[0].drive_gauge, cfg.drive_gauge_max, "トスでは削られない")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE, "トス後は攻撃属性を消す")
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.last_touch_team = 1
	s.players[0].on_ground = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[0].drive_gauge, cfg.drive_gauge_max,
		"アタック返しは被削りも自己消費もなし")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"アタック返しは削り属性を持たない")

func test_blocker_takes_incoming_damage_but_reflection_loses_attack_kind() -> void:
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
		[0, 0, Simulation.IN_ACTION | Simulation.IN_UP, 0])
	check_eq(p.drive_gauge, cfg.drive_gauge_max - cfg.drive_gauge_stock,
		"通常アタックを受けたブロッカー本人は1本削られる")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"ブロック反射球は攻撃属性を持たない")
	p.hit_cooldown = 0
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(8)
	HitResolver._ball_vs_block(s, cfg,
		[0, 0, Simulation.IN_ACTION | Simulation.IN_UP, 0])
	check_eq(p.drive_gauge, cfg.drive_gauge_max - cfg.drive_gauge_stock * 3,
		"続けてジャストを受けたブロッカー本人は2本削られる")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NONE,
		"ジャストのブロック反射球も攻撃属性を持たない")
	s.players[0].on_ground = 1
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(s.players[0].drive_gauge, cfg.drive_gauge_max,
		"ブロック反射球を受けても元アタッカーは削られない")

func test_just_cost_clamps_at_zero_when_gauge_is_insufficient() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].drive_gauge = cfg.drive_gauge_stock / 4
	_air_attack(s, cfg, 0, true)
	check_eq(s.players[0].drive_gauge, 0, "0.5本未満でもジャスト成立し下限0で止まる")
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_JUST, "不足時もジャスト属性は成立")

func test_drive_gauge_serialization_roundtrip() -> void:
	var w := _world()
	var a = w[0]
	a.players[1].drive_gauge = 2345
	a.players[1].drive_recovery_progress = 67
	a.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	var b = SimState.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.players[1].drive_gauge, 2345, "ゲージ残量を復元")
	check_eq(b.players[1].drive_recovery_progress, 67, "回復端数を復元")
	check_eq(b.ball_attack_kind, SimState.BALL_ATTACK_NORMAL, "飛来アタック属性を復元")
	check_eq(b.state_hash(), a.state_hash(), "ドライブ状態を含めた直列化往復")
