extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Chars := preload("res://src/sim/chars.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _has_recovery_api() -> bool:
	var methods := ["start_attack_recovery", "stop_attack_recovery",
		"tick_attack_recovery"]
	for method in methods:
		if not CombatResources.new().has_method(method):
			check(false, "攻撃後回復APIが必要: " + method)
			return false
	return true

func test_recovery_grants_on_ticks_30_179_and_180() -> void:
	if not _has_recovery_api():
		return
	var w := _world(); var p = w[0].players[0]; var cfg = w[1]
	p.drive_gauge = 0
	CombatResources.start_attack_recovery(p, 0, cfg)
	for i in 29:
		CombatResources.tick_attack_recovery(p, true, cfg)
	check_eq(p.drive_gauge, 0, "29tickではまだ回復しない")
	CombatResources.tick_attack_recovery(p, true, cfg)
	check_eq(p.drive_gauge, 1, "30tick目に1回復")
	for i in 149:
		CombatResources.tick_attack_recovery(p, true, cfg)
	check_eq(p.drive_gauge, 5, "179tick終了時は合計5回復")
	CombatResources.tick_attack_recovery(p, true, cfg)
	check_eq(p.drive_gauge, 6, "180tick目に6点目を回復")
	check_eq(p.attack_recovery_window_ticks, 0, "6点付与後に窓を閉じる")

func test_recovery_delay_pause_stop_and_burnout_cancel() -> void:
	if not _has_recovery_api():
		return
	var w := _world(); var p = w[0].players[0]; var cfg = w[1]
	p.drive_gauge = 40
	CombatResources.start_attack_recovery(p, cfg.just_attack_recovery_delay_ticks, cfg)
	for i in cfg.just_attack_recovery_delay_ticks:
		CombatResources.tick_attack_recovery(p, true, cfg)
	check_eq(p.drive_gauge, 40, "60tickの遅延中は回復しない")
	check_eq(p.attack_recovery_fraction_ticks, 0, "遅延中は端数を進めない")
	for i in 30:
		CombatResources.tick_attack_recovery(p, false, cfg)
	check_eq(p.attack_recovery_fraction_ticks, 0, "非アクティブtickでは窓を進めない")
	CombatResources.stop_attack_recovery(p)
	check_eq(p.attack_recovery_delay_ticks, 0, "停止で遅延を破棄")
	check_eq(p.attack_recovery_window_ticks, 0, "停止で窓を破棄")
	check_eq(p.attack_recovery_fraction_ticks, 0, "停止で端数を破棄")
	check_eq(p.attack_recovery_granted, 0, "停止で付与数を破棄")
	CombatResources.start_attack_recovery(p, 0, cfg)
	p.burnout_ticks = 1
	CombatResources.tick_attack_recovery(p, true, cfg)
	check_eq(p.attack_recovery_window_ticks, 0, "バーンアウトで回復窓を破棄")

func test_valid_normal_attack_grants_15_once_and_starts_window() -> void:
	if not HitResolver.new().has_method("_grant_valid_normal_attack"):
		check(false, "有効通常アタック付与APIが必要")
		return
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 40
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_attacker_id = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	var attack_id: int = s.ball_attack_id
	HitResolver._grant_valid_normal_attack(s, attack_id, 0, cfg)
	check_eq(p.drive_gauge, 55, "有効通常アタックで15回復")
	check_eq(p.attack_recovery_delay_ticks, 0, "通常アタックは遅延なし")
	check_eq(p.attack_recovery_window_ticks, cfg.attack_recovery_window_ticks,
		"通常アタックは即時に180tick窓を開始")
	HitResolver._grant_valid_normal_attack(s, attack_id, 0, cfg)
	check_eq(p.drive_gauge, 55, "同じ攻撃IDでは二重付与しない")

func test_normal_attack_marks_id_and_trajectory_grants_but_just_does_not() -> void:
	var normal := _world(); var sn = normal[0]; var cfg = normal[1]
	var pn = sn.players[0]
	pn.drive_gauge = 40
	pn.on_ground = 0
	pn.x = cfg.net_x - FP.from_int(80)
	pn.y = cfg.net_top_y - FP.from_int(100)
	sn.ball_x = pn.x
	sn.ball_y = pn.y
	HitResolver._apply_hit(sn, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		cfg.player_reach * cfg.player_reach)
	check(sn.ball_attack_id > 0, "通常アタックへ攻撃IDを採番")
	check_eq(sn.ball_attacker_id, 0, "攻撃者を記録")
	check_eq(sn.players[0].drive_gauge, 55,
		"相手プレイ可能領域へ向かう通常アタックは15回復")

	var just := _world(); var sj = just[0]; var pj = sj.players[0]
	pj.drive_gauge = 100
	pj.on_ground = 0
	HitResolver._apply_hit(sj, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(pj.drive_gauge, 75, "ジャストは25消費だけで15を得ない")
	check_eq(pj.attack_recovery_delay_ticks,
		cfg.just_attack_recovery_delay_ticks, "ジャストは60tick遅延を開始")

func test_special_starts_90_delay_without_normal_gain() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.char_id = Chars.CHAR_TOME
	p.drive_gauge = 100
	p.on_ground = 0
	p.y = cfg.net_top_y - FP.from_int(1)
	s.ball_x = p.x
	s.ball_y = p.y
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_ABILITY1 | Simulation.IN_DOWN, 0)
	check_eq(p.drive_gauge, 65, "必殺は35消費だけで15を得ない")
	check_eq(p.attack_recovery_delay_ticks,
		cfg.special_recovery_delay_ticks, "必殺は実効果から90tick遅延")

func test_opponent_contact_grants_unconfirmed_normal_attack_once() -> void:
	if not HitResolver.new().has_method("_grant_valid_normal_attack"):
		check(false, "有効通常アタック付与APIが必要")
		return
	var w := _world(); var s = w[0]; var cfg = w[1]
	var attacker = s.players[0]
	attacker.drive_gauge = 40
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_attacker_id = 0
	s.ball_attack_commit_tick = s.tick
	s.ball_normal_gain_granted = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.last_touch_team = 0
	s.players[2].on_ground = 1
	CombatResources.start_attack_recovery(s.players[2], 0, cfg)
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	check_eq(attacker.drive_gauge, 55, "相手選手への接触で未確定通常攻撃へ15付与")
	check_eq(s.players[2].attack_recovery_window_ticks, 0,
		"レシーブ接触で受け手の回復窓を破棄")

func test_opponent_block_contact_grants_attacker_but_not_blocker() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var attacker = s.players[0]
	var blocker = s.players[2]
	attacker.drive_gauge = 40
	blocker.drive_gauge = 40
	CombatResources.start_attack_recovery(blocker, 0, cfg)
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_attacker_id = 0
	s.ball_attack_commit_tick = s.tick
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.last_touch_team = 0
	blocker.x = cfg.net_x + FP.from_int(20)
	blocker.y = cfg.floor_y - FP.from_int(60)
	blocker.on_ground = 0
	s.ball_x = blocker.x
	s.ball_y = blocker.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(8)
	HitResolver._ball_vs_block(s, cfg,
		[0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0])
	check_eq(attacker.drive_gauge, 55, "相手ブロック接触でも攻撃者へ15付与")
	check_eq(blocker.drive_gauge, 30,
		"ブロッカーは回復15を得ず、開始5と接触5だけを支払う")
	check_eq(blocker.attack_recovery_window_ticks, 0,
		"ブロック開始でブロッカーの回復窓を破棄")

func test_defense_entry_and_rally_end_cancel_recovery() -> void:
	var crossing := _world(); var s = crossing[0]; var cfg = crossing[1]
	CombatResources.start_attack_recovery(s.players[2], 0, cfg)
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_x = cfg.net_x - FP.from_int(1)
	s.ball_y = cfg.net_top_y - FP.from_int(30)
	s.ball_vx = FP.from_int(3)
	s.ball_vy = 0
	BallPhysics._step_ball(s, cfg)
	check_eq(s.players[2].attack_recovery_window_ticks, 0,
		"相手球が自陣へ入った防御フェーズで回復窓を破棄")
	CombatResources.start_attack_recovery(s.players[0], 0, cfg)
	Simulation._award_point(s, 1, cfg)
	check_eq(s.players[0].attack_recovery_window_ticks, 0,
		"ラリー終了で回復窓を破棄")

func test_burnout_normal_attack_gets_no_gain_or_recovery_window() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 0
	p.burnout_ticks = cfg.burnout_recovery_ticks
	p.on_ground = 0
	p.x = cfg.net_x - FP.from_int(80)
	p.y = cfg.net_top_y - FP.from_int(100)
	s.ball_x = p.x
	s.ball_y = p.y
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		cfg.player_reach * cfg.player_reach)
	check_eq(p.drive_gauge, 0, "バーンアウト通常アタックは15を得ない")
	check_eq(p.attack_recovery_window_ticks, 0,
		"バーンアウト通常アタックは回復窓を開始しない")

func test_normal_attack_prediction_rejects_direct_net_and_wall_out() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_attacker_id = 0
	s.last_touch_team = 0
	s.ball_x = cfg.net_x - FP.from_int(20)
	s.ball_y = cfg.net_top_y + FP.from_int(10)
	s.ball_vx = FP.from_int(5)
	s.ball_vy = 0
	check(not BallPhysics.normal_attack_reaches_opponent_playable(s, cfg, 0),
		"自陣側からの直接ネットは有効通常アタックにしない")
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_x = cfg.court_width - cfg.ball_radius - FP.from_int(1)
	s.ball_y = cfg.net_top_y - FP.from_int(40)
	s.ball_vx = FP.from_int(20)
	s.ball_vy = 0
	check(not BallPhysics.normal_attack_reaches_opponent_playable(s, cfg, 0),
		"相手に触れない直接壁アウトは有効通常アタックにしない")
