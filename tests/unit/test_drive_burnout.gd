extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _arm_receive(s, cfg, i: int = 0) -> void:
	s.ball_x = cfg.net_x
	s.ball_y = 0
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(s.players[i].receive_stance > 0, "下レシーブ構えを経由")

func _incoming_just(s, cfg, i: int = 0, flame: bool = false) -> void:
	var p = s.players[i]
	s.last_touch_team = 1 - SimState.team_of(i)
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_power = 1
	s.ball_guard_damage = 40 if flame else \
		cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C)
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE if flame else Chars.DEFENSE_NONE
	s.ball_flame = 1 if flame else 0
	HitResolver._apply_hit(s, i, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)

func test_just_receive_from_stance_nullifies_drive_and_guard_without_healing() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 40
	_arm_receive(s, cfg)
	p.drive_gauge = 3000
	_incoming_just(s, cfg)
	check_eq(p.guard, 40, "ジャストレシーブはガード削りを無効化し回復もしない")
	check_eq(p.drive_gauge, 3000, "ジャストレシーブはドライブ削りを無効化し回復もしない")
	check(p.just_receive_flash > 0, "専用フラッシュ用カウンタ")
	check_eq(p.just_receive_event, 1, "専用SE用イベント番号")
	check(s.hit_freeze > 0, "専用ヒットストップ")

func test_moving_receive_does_not_trigger_just_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.drive_gauge = 3000
	p.receive_stance = 1
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_power = 1
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT, 0)
	check_eq(p.drive_gauge, 1000, "構え後でも横移動入力なら2本削りを受ける")
	check_eq(p.just_receive_event, 0, "移動レシーブでは専用演出なし")

func test_flame_cannot_be_nullified_by_just_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 100
	_arm_receive(s, cfg)
	p.drive_gauge = 3000
	_incoming_just(s, cfg, 0, true)
	check_eq(p.guard, 60, "防御不能系はカタログ固定40を通す")
	check_eq(p.drive_gauge, 1000, "人工的なジャスト属性分だけドライブを削る")
	check_eq(p.just_receive_event, 0, "炎球ではジャストレシーブ演出なし")

func test_just_toss_does_not_heal_guard() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 40
	s.last_touch_team = 1
	s.ball_power = 1
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)
	check_eq(p.guard, 40,
		"回復全廃によりジャストトスでもガードは増えない")

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
	p.receive_stance = 1
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
	p.drive_gauge = cfg.drive_gauge_stock
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	check_eq(p.drive_gauge, 0, "通常アタック1本削りでゼロになる")
	check_eq(p.burnout_ticks, cfg.burnout_recovery_ticks,
		"ドライブがゼロになった瞬間にバーンアウト開始")

func test_burnout_guard_damage_is_one_and_half_including_flame() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burnout_ticks = cfg.burnout_recovery_ticks
	p.guard = 100
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_guard_damage = cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(p.guard, 63, "POWER C絶対値25へバーンアウト*3/2を適用")
	p.guard = 100
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_flame = 1
	s.ball_guard_damage = 40
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, cfg.player_reach * cfg.player_reach)
	check_eq(p.guard, 40, "必殺技40へバーンアウト*3/2を適用して60")

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
	s.phase = SimState.PHASE_RALLY
	for i in cfg.burnout_recovery_ticks:
		Simulation._update_drive_recovery(s, cfg)
	check_eq(p.burnout_ticks, 0, "600ラリーtickでバーンアウト解除")
	check_eq(p.drive_gauge, cfg.drive_gauge_max, "解除時に6本全回復")
