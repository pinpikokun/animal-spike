extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _start_stance(s, cfg, actor: int = 0) -> void:
	var inputs: Array[int] = [0, 0, 0, 0]
	var edges: Array[bool] = [false, false, false, false]
	inputs[actor] = Simulation.IN_ACTION | Simulation.IN_DOWN
	edges[actor] = true
	Simulation._update_receive_stances(s, inputs, cfg, edges)

func test_stance_reserves_five_holds_without_spending_and_locks_position() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	_start_stance(s, cfg)
	check_eq(p.stance_active, 1, "押下エッジで構え開始")
	check_eq(p.drive_gauge, 100, "構え開始では実体値を減らさない")
	check_eq(p.drive_reserved, 5, "構え開始で5を予約")
	check_eq(CombatResources.available_drive(p), 95, "予約5は他行動に使えない")
	var start_x: int = p.x
	var held: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN \
		| Simulation.IN_LEFT, 0, 0, 0]
	for tick in 60:
		Simulation._update_receive_stances(s, held, cfg)
		PlayerMovement._step_player(p, held[0], cfg, 0)
	check_eq(p.x, start_x, "構え中は左右入力で位置を変えない")
	check_eq(p.on_ground, 1, "構え中はジャンプしない")
	check_eq(p.stance_active, 1, "1秒保持しても構え継続")
	check_eq(p.receive_stance, -1, "10tick後は通常構えへ移行")
	check_eq(p.drive_gauge, 100, "長押しに時間消費なし")

func test_release_commits_once_and_applies_nine_tick_exit_recovery() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	_start_stance(s, cfg)
	var released: Array[int] = [0, 0, 0, 0]
	Simulation._update_receive_stances(s, released, cfg)
	check_eq(p.stance_active, 0, "入力解除で構え終了")
	check_eq(p.drive_gauge, 95, "解除で予約5を確定消費")
	check_eq(p.drive_reserved, 0, "解除で予約を除去")
	check_eq(p.stance_exit_recovery_ticks, 9, "解除後9tick硬直")
	CombatResources.commit_stance_reservation(p, cfg)
	check_eq(p.drive_gauge, 95, "同じ構えの費用を二重確定しない")
	for tick in 9:
		var before: Array[int] = [p.stance_exit_recovery_ticks, 0, 0, 0]
		PlayerMovement._step_player(p,
			Simulation.IN_LEFT | Simulation.IN_JUMP, cfg, 0)
		Simulation._advance_stance_exit_recovery(s, before)
	check_eq(p.stance_exit_recovery_ticks, 0, "9tickで解除硬直終了")
	check_eq(p.on_ground, 1, "解除硬直中はジャンプしない")

func test_pre_read_releases_reservation_but_reaction_spends_and_burns_out() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 5
	_start_stance(s, cfg)
	p.stance_committed_attack_id = 7
	p.stance_pre_read_candidate = 1
	var result: int = CombatResources.resolve_stance_contact(p, 7, s.tick, cfg)
	check_eq(result, 1, "同一攻撃の先読み成功")
	check_eq(p.drive_gauge, 5, "先読みは予約解放で開始値を維持")
	check_eq(p.burnout_ticks, 0, "先読みは5ちょうどでもバーンアウトしない")

	w = _world(); s = w[0]; cfg = w[1]; p = s.players[0]
	p.drive_gauge = 5
	_start_stance(s, cfg)
	result = CombatResources.resolve_stance_contact(p, 8, s.tick - 1, cfg)
	check_eq(result, 2, "commit後に始めた構えは反応成功")
	check_eq(p.drive_gauge, 0, "反応は予約5を確定消費")
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"反応結果確定後にバーンアウト")

func test_attack_commit_marks_existing_stance_but_later_stance_is_reaction() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var defender = s.players[0]
	_start_stance(s, cfg, 0)
	var attacker = s.players[2]
	attacker.on_ground = 0
	s.last_touch_team = 1
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	var attack_id: int = s.ball_attack_id
	check(attack_id > 0, "攻撃commitでID採番")
	check_eq(defender.stance_committed_attack_id, attack_id,
		"commit前の相手構えへ同一攻撃IDを記録")
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(defender.drive_gauge, 100, "同一球の先読み成功は予約5を解放")

	w = _world(); s = w[0]; cfg = w[1]
	defender = s.players[0]
	attacker = s.players[2]
	attacker.on_ground = 0
	s.last_touch_team = 1
	HitResolver._apply_hit(s, 2, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	attack_id = s.ball_attack_id
	_start_stance(s, cfg, 0)
	check_eq(defender.stance_committed_attack_id, 0,
		"commit後に始めた構えは先読み候補ではない")
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(defender.drive_gauge, 95, "commit後の反応成功は予約5を確定")

func test_low_drive_and_burnout_fall_back_without_starting_stance() -> void:
	for drive in [1, 4]:
		var w := _world(); var s = w[0]; var cfg = w[1]
		var p = s.players[0]
		p.drive_gauge = drive
		_start_stance(s, cfg)
		check_eq(p.stance_active, 0, "5未満は構えを開始しない drive=%d" % drive)
		check_eq(p.drive_gauge, drive, "5未満で入力だけ消費しない drive=%d" % drive)
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burnout_ticks = cfg.burnout_recovery_ticks
	_start_stance(s, cfg)
	check_eq(p.stance_active, 0, "バーンアウト中は構えを開始しない")

func test_false_edge_does_not_start_and_just_window_is_exactly_ten_ticks() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var held: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0]
	var no_edges: Array[bool] = [false, false, false, false]
	Simulation._update_receive_stances(s, held, cfg, no_edges)
	check_eq(s.players[0].stance_active, 0, "押下エッジなしでは構えを開始しない")
	_start_stance(s, cfg)
	for tick in 9:
		Simulation._update_receive_stances(s, held, cfg, no_edges)
	check_eq(s.players[0].receive_stance, 1, "開始tickを含む10tick目まではジャスト")
	Simulation._update_receive_stances(s, held, cfg, no_edges)
	check_eq(s.players[0].receive_stance, -1, "11tick目から通常構え")
	check_eq(s.players[0].stance_active, 1, "窓終了後も長押し構えは継続")

func test_intervening_contact_and_alternate_action_commit_reserved_five_once() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	_start_stance(s, cfg)
	p.stance_committed_attack_id = 7
	p.stance_pre_read_candidate = 1
	var result: int = CombatResources.resolve_stance_contact(p, 0, -1, cfg)
	check_eq(result, 2, "壁・味方・ブロックで攻撃IDが消えた接触は読み外し")
	check_eq(p.drive_gauge, 95, "介在接触後は予約5を確定")

	w = _world(); s = w[0]; cfg = w[1]; p = s.players[0]
	_start_stance(s, cfg)
	var alternate: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN \
		| Simulation.IN_UP | Simulation.IN_ABILITY1, 0, 0, 0]
	Simulation._update_receive_stances(s, alternate, cfg,
		[false, false, false, false])
	check_eq(p.stance_active, 0, "別行動入力は構えだけを解除")
	check_eq(p.drive_gauge, 95, "別行動入力で予約5を確定")
	check_eq(alternate[0], 0, "解除同tickにブロックや必殺を開始しない")

func test_exit_recovery_allows_plain_receive_but_blocks_other_actions_and_dive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	_start_stance(s, cfg)
	Simulation._update_receive_stances(s, [0, 0, 0, 0], cfg)
	var receive: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0]
	Simulation._update_receive_stances(s, receive, cfg,
		[true, false, false, false])
	check_eq(receive[0], Simulation.IN_ACTION | Simulation.IN_DOWN,
		"解除硬直中も構えなしレシーブ入力を残す")
	check_eq(p.stance_active, 0, "解除硬直中は再構えしない")
	var blocked: Array[int] = [Simulation.IN_ACTION | Simulation.IN_UP \
		| Simulation.IN_JUMP | Simulation.IN_ABILITY1, 0, 0, 0]
	Simulation._update_receive_stances(s, blocked, cfg,
		[true, false, false, false])
	check_eq(blocked[0], Simulation.IN_ACTION,
		"解除硬直中はジャンプ・ブロック・必殺を除去")
	check(not Simulation._can_start_dive_receive(p),
		"解除硬直中は飛びつきを開始しない")

func test_burnout_with_impossible_reservation_discards_it_without_timer_reset() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	_start_stance(s, cfg)
	p.burnout_ticks = 321
	var held: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0]
	Simulation._update_receive_stances(s, held, cfg,
		[false, false, false, false])
	check_eq(p.stance_active, 0, "異常予約を検出したら構え解除")
	check_eq(p.drive_reserved, 0, "異常予約は消費せず破棄")
	check_eq(p.drive_gauge, 100, "異常予約で実体値を削らない")
	check_eq(p.burnout_ticks, 321, "異常予約でバーンアウト時間を変えない")

func test_rally_end_commits_reservation_and_keeps_next_action_id_monotonic() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	_start_stance(s, cfg)
	var first_action_id: int = s.players[0].stance_action_id
	Simulation._award_point(s, 1, cfg)
	check_eq(s.players[0].drive_gauge, 95, "ラリー終了は予約5を確定")
	check_eq(s.players[0].stance_active, 0, "ラリー終了で構え解除")
	Simulation.reset_rally(s, cfg, 1)
	s.phase = SimState.PHASE_RALLY
	s.players[0].action_latch = 0
	_start_stance(s, cfg)
	check_eq(s.players[0].stance_action_id, first_action_id + 1,
		"次ラリーでaction IDを再利用しない")
