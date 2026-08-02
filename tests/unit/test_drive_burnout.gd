extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _press_receive(s, cfg, i: int = 0) -> void:
	var inputs: Array[int] = [0, 0, 0, 0]
	inputs[i] = Simulation.IN_ACTION | Simulation.IN_DOWN
	Simulation._update_receive_stances(s, inputs, cfg)
	check_eq(s.players[i].receive_stance, cfg.just_receive_window_ticks,
		"下+ボタンの押下エッジで10tick窓を開く")

func _incoming_just(s, cfg, i: int = 0, flame: bool = false) -> void:
	var p = s.players[i]
	s.last_touch_team = 1 - SimState.team_of(i)
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_power = 1
	s.ball_health_damage = 40 if flame else \
		cfg.power_health_damage_for_rank(Chars.Profile.RANK_C)
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE if flame else Chars.DEFENSE_NONE
	s.ball_special_id = Chars.SUPER_FLAME_ATTACK if flame else 0
	HitResolver._apply_hit(s, i, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)

func test_just_receive_during_timing_window_nullifies_drive_and_health_damage() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.health = 40
	_press_receive(s, cfg)
	p.drive_gauge = 65
	# 位置の芯判定は撤去。リーチ端相当でもタイミング窓だけで成立する。
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_power = 1
	s.ball_health_damage = cfg.power_health_damage_for_rank(Chars.Profile.RANK_C)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(p.health, 40, "ジャストレシーブは体力損害を無効化し回復もしない")
	check_eq(p.drive_gauge, 60, "反応ジャストは予約5を確定消費")
	check_eq(p.just_receive_flash, 30, "JUST表示と本体発光を約30tick維持")
	check_eq(p.just_receive_event, 1, "専用SE用イベント番号")
	check_eq(s.hit_freeze, 10, "ジャストレシーブのヒットストップは10tick")
	check(s.hit_freeze > 0, "専用ヒットストップ")

func test_moving_receive_does_not_trigger_just_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 65
	p.vx = 1
	Simulation._update_receive_stances(s,
		[Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_power = 1
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(p.drive_gauge, 65, "通常レシーブでもドライブは減らない")
	check_eq(p.just_receive_event, 0, "移動レシーブでは専用演出なし")

func test_flame_cannot_be_nullified_by_just_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.health = 100
	_press_receive(s, cfg)
	p.drive_gauge = 65
	_incoming_just(s, cfg, 0, true)
	check_eq(p.health, 60, "防御不能系はカタログ固定40を通す")
	check_eq(p.drive_gauge, 60, "防御不能技でも反応構えの予約5は確定")
	check_eq(p.just_receive_event, 0, "炎球ではジャストレシーブ演出なし")

func test_held_receive_after_window_expires_is_normal_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 65
	_press_receive(s, cfg)
	var held: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0]
	for i in cfg.just_receive_window_ticks:
		Simulation._update_receive_stances(s, held, cfg)
	check(p.receive_stance < 0, "押しっぱなしでは窓切れ後に再発動しない")
	_incoming_just(s, cfg)
	check_eq(p.drive_gauge, 60, "窓切れ後も反応構えの予約5は確定")
	check_eq(p.just_receive_event, 0, "窓切れ後はジャスト演出なし")

func test_releasing_and_pressing_again_opens_new_window() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	_press_receive(s, cfg)
	var held: Array[int] = [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0]
	for i in cfg.just_receive_window_ticks:
		Simulation._update_receive_stances(s, held, cfg)
	Simulation._update_receive_stances(s, [0, 0, 0, 0], cfg)
	for i in cfg.receive_stance_exit_recovery_ticks:
		var before: Array[int] = [s.players[0].stance_exit_recovery_ticks, 0, 0, 0]
		PlayerMovement._step_player(s.players[0], 0, cfg, 0)
		Simulation._advance_stance_exit_recovery(s, before)
	Simulation._update_receive_stances(s, held, cfg)
	check_eq(s.players[0].receive_stance, cfg.just_receive_window_ticks,
		"離して押し直すと新しい窓を開く")

func test_just_toss_does_not_heal_health() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.health = 40
	s.last_touch_team = 1
	s.ball_power = 1
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
	check_eq(p.health, 40,
		"回復全廃によりジャストトスでも体力は増えない")

func test_burnout_seals_just_attack_and_just_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 0
	p.burnout_ticks = cfg.burnout_recovery_ticks
	p.on_ground = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
		"バーンアウト中は芯でも通常アタック")
	p.on_ground = 1
	p.receive_stance = cfg.just_receive_window_ticks
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(p.just_receive_event, 0, "バーンアウト中はジャストレシーブ封印")

func test_burnout_seals_special_inputs() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[1]
	p.burnout_ticks = cfg.burnout_recovery_ticks
	p.char_id = Chars.CHAR_TOME
	check_eq(HitResolver._special_for_input(
		p, Simulation.IN_ABILITY1 | Simulation.IN_UP, cfg), 0,
		"バーンアウト中は必殺技入力を無効化")
	p.char_id = Chars.CHAR_MARIO
	p.has_hat = 1
	Simulation._update_hat(s, [0, Simulation.IN_ABILITY1, 0, 0], cfg)
	check_eq(p.throw, 0, "バーンアウト中は帽子投げを封印")
	p.on_ground = 0
	PlayerMovement._step_player(
		p, Simulation.IN_DOWN | Simulation.IN_ABILITY1, cfg, 0)
	check_eq(p.hip, 0, "バーンアウト中はヒップアタックを封印")

func test_drive_reaching_zero_starts_burnout() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = cfg.just_attack_drive_cost
	p.on_ground = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_JUST,
		"25ちょうどならジャストアタック成立")
	check_eq(p.drive_gauge, 0, "ジャストアタック25消費でゼロになる")
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"ドライブがゼロになった瞬間にバーンアウト開始")

func test_burnout_does_not_multiply_normal_or_flame_damage() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burnout_ticks = cfg.burnout_recovery_ticks
	p.health = 100
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_health_damage = cfg.power_health_damage_for_rank(Chars.Profile.RANK_C)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(p.health, 75, "POWER C絶対値25を倍率なしで適用")
	p.health = 100
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_special_id = Chars.SUPER_FLAME_ATTACK
	s.ball_health_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(p.health, 60, "必殺技40も倍率なしで適用")

func test_burnout_recovers_after_600_rally_ticks_and_pauses_elsewhere() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 0
	p.burnout_ticks = cfg.burnout_recovery_ticks
	s.phase = SimState.PHASE_POINT_PAUSE
	for i in 100:
		Simulation._update_drive_recovery(s, cfg)
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"インターバル中は復帰カウント停止")
	s.phase = SimState.PHASE_SERVE
	for i in 100:
		Simulation._update_drive_recovery(s, cfg)
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"サーブ待機中も復帰カウント停止")
	Simulation.reset_rally(s, cfg, 1)
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"ポイントをまたいで残り時間を維持")
	s.phase = SimState.PHASE_RALLY
	for i in cfg.burnout_recovery_ticks:
		Simulation._update_drive_recovery(s, cfg)
	check_eq(p.burnout_ticks, 0, "600ラリーtickでバーンアウト解除")
	check_eq(p.drive_gauge, cfg.burnout_exit_drive, "解除時は30で復帰")

func test_tick_burnout_pauses_and_clears_attack_recovery_on_exit() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 0
	p.burnout_ticks = 1
	p.attack_recovery_delay_ticks = 10
	p.attack_recovery_window_ticks = 20
	p.attack_recovery_fraction_ticks = 29
	p.attack_recovery_granted = 3
	CombatResources.tick_burnout(p, false, cfg)
	check_eq(p.burnout_ticks, 1, "inactiveでは残り時間を維持")
	CombatResources.tick_burnout(p, true, cfg)
	check_eq(p.burnout_ticks, 0, "activeの最後の1tickで解除")
	check_eq(p.drive_gauge, cfg.burnout_exit_drive, "解除時は30で復帰")
	check_eq(p.attack_recovery_delay_ticks, 0, "旧攻撃回復の遅延を持ち込まない")
	check_eq(p.attack_recovery_window_ticks, 0, "旧攻撃回復窓を再開しない")
	check_eq(p.attack_recovery_fraction_ticks, 0, "旧攻撃回復の端数を持ち込まない")
	check_eq(p.attack_recovery_granted, 0, "旧攻撃回復の付与量を持ち込まない")
