extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

func _block_world(drive: int, contact: bool = true) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	var p = s.players[2]
	p.char_id = 99
	p.drive_gauge = drive
	p.guard = 100
	p.x = cfg.net_x + FP.from_int(20)
	p.y = cfg.floor_y - FP.from_int(60)
	p.on_ground = 0
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_attacker_id = 0
	s.ball_guard_damage = 20
	s.ball_power = 1
	s.ball_x = p.x if contact else p.x + cfg.player_reach
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate
	return [s, cfg, p]

func _block_input() -> Array[int]:
	return [0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0]

func test_block_spends_five_at_start_and_five_at_contact() -> void:
	var w = _block_world(100)
	HitResolver._ball_vs_block(w[0], w[1], _block_input())
	check_eq(w[2].drive_gauge, 90, "通常ブロック成功は開始5と接触5")
	check_eq(w[2].current_block_mode, SimState.BLOCK_NORMAL, "通常種別を行動中保持")
	check_eq(w[2].guard, 100, "通常ブロックは体力損害0")

func test_missed_block_only_spends_start_cost() -> void:
	var w = _block_world(100, false)
	HitResolver._ball_vs_block(w[0], w[1], _block_input())
	check_eq(w[2].drive_gauge, 95, "空振りでも開始5だけ確定")
	check_eq(w[2].current_block_mode, SimState.BLOCK_NORMAL, "空振り中も通常種別を保持")

func test_exact_five_keeps_current_block_normal_after_burnout() -> void:
	var w = _block_world(5)
	HitResolver._ball_vs_block(w[0], w[1], _block_input())
	check_eq(w[2].drive_gauge, 0, "開始5を全額消費")
	check(w[2].burnout_ticks > 0, "0到達後にバーンアウト")
	check_eq(w[2].current_block_mode, SimState.BLOCK_NORMAL, "現在行動は通常版を維持")
	check_eq(w[2].guard, 100, "現在行動保護で体力損害0")

func test_low_drive_and_existing_burnout_use_health_block() -> void:
	for row in [[4, 0], [0, 321]]:
		var w = _block_world(row[0])
		var p = w[2]
		p.burnout_ticks = row[1]
		HitResolver._ball_vs_block(w[0], w[1], _block_input())
		check_eq(p.drive_gauge, 0, "低残量は全消費、既バーンアウトは0のまま")
		check_eq(p.current_block_mode, SimState.BLOCK_BURNOUT, "体力版として固定")
		check_eq(p.guard, 90, "体力版ブロックは攻撃圧力の50%を受ける")
		if row[1] > 0:
			check_eq(p.burnout_ticks, row[1], "既存バーンアウト時間をリセットしない")

func test_burnout_block_half_damage_does_not_depend_on_power_visual() -> void:
	var w = _block_world(0)
	w[2].burnout_ticks = 321
	w[0].ball_power = 0
	HitResolver._ball_vs_block(w[0], w[1], _block_input())
	check_eq(w[2].guard, 90, "非パワー表示でも体力版ブロックは攻撃圧力の50%")

func test_block_marks_original_pressure_once_and_direct_return_exempt() -> void:
	var w = _block_world(100)
	var s = w[0]
	var original_attack_id: int = s.ball_attack_id
	HitResolver._ball_vs_block(s, w[1], _block_input())
	check_eq(s.ball_original_attack_pressure_consumed, 1, "元攻撃圧力を処理済みにする")
	check(s.ball_soft_block_action_id > 0, "ブロック行動IDを記録")
	check_eq(s.ball_attack_id, original_attack_id, "処理済み元攻撃IDを追跡用に保持")
	check_eq(s.aggressive_action_resolved, 1, "直接返球は防御返球10の対象外")
	var first_action_id: int = s.ball_soft_block_action_id
	HitResolver._ball_vs_block(s, w[1], _block_input())
	check_eq(s.ball_soft_block_action_id, first_action_id, "同じ接触を二重処理しない")

func test_soft_blocked_attack_id_cannot_damage_rear_receiver_again() -> void:
	var w = _block_world(100)
	var s = w[0]
	var cfg = w[1]
	HitResolver._ball_vs_block(s, cfg, _block_input())
	var receiver = s.players[0]
	receiver.guard = 100
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_guard_damage = 20
	s.ball_power = 1
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(receiver.guard, 100, "処理済みの同一攻撃IDは後衛へ体力損害を重ねない")
