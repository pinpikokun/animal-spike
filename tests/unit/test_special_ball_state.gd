extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SpecialBall := preload("res://src/sim/special_ball.gd")

func test_special_state_roundtrips_and_changes_hash() -> void:
	var a := SimState.new()
	a.players[2].shock_ticks = 17
	a.players[2].bubble_ticks = 19
	a.players[2].special_action = Chars.SUPER_SUCTION
	a.players[2].special_action_ticks = 23
	a.players[2].ability_latch = 1
	a.ball_special_id = Chars.SUPER_SNAKE_BALL
	a.ball_special_phase = 2
	a.ball_special_ticks = 31
	a.ball_special_owner_idx = 2
	a.ball_special_origin_vx = -456
	a.ball_held_by = 2
	var snapshot: Array[int] = a.to_int_array()
	var b := SimState.new()
	b.load_int_array(snapshot)
	check_eq(b.to_int_array(), snapshot, "必殺技状態を完全復元")
	check_eq(b.state_hash(), a.state_hash(), "復元後のハッシュ一致")
	var clean := SimState.new()
	check(clean.state_hash() != a.state_hash(), "必殺技状態がハッシュへ入る")

func test_special_ball_set_replaces_previous_state_and_clear_uses_sentinels() -> void:
	var s := SimState.new()
	SpecialBall.set_special(s, Chars.SUPER_GHOST_BALL, 1, 123)
	s.ball_special_phase = 9
	s.ball_special_ticks = 8
	s.ball_held_by = 1
	SpecialBall.set_special(s, Chars.SUPER_SNAKE_BALL, 2, -456)
	check_eq(s.ball_special_id, Chars.SUPER_SNAKE_BALL, "特殊球は排他的")
	check_eq(s.ball_special_owner_idx, 2, "所有者を更新")
	check_eq(s.ball_special_origin_vx, -456, "基準速度を更新")
	check_eq(s.ball_special_phase, 0, "前効果の段階を残さない")
	check_eq(s.ball_special_ticks, 0, "前効果の時間を残さない")
	check_eq(s.ball_held_by, -1, "前効果の保持者を残さない")
	SpecialBall.clear_special(s)
	check_eq(s.ball_special_id, 0, "解除後は通常球")
	check_eq(s.ball_special_owner_idx, -1, "解除後は所有者なし")
	check_eq(s.ball_special_origin_vx, 0, "解除後は基準速度なし")
	check_eq(s.ball_held_by, -1, "解除後は保持者なし")

func test_original_tick_conversion_uses_integer_round_half_up() -> void:
	var cfg := SimConfig.new()
	check_eq(SpecialBall.original_ticks(6, cfg), 13, "原作6tick")
	check_eq(SpecialBall.original_ticks(10, cfg), 21, "原作10tick")
	check_eq(SpecialBall.original_ticks(16, cfg), 34, "原作16tick")
	check_eq(SpecialBall.original_ticks(20, cfg), 43, "原作20tick")

func test_original_height_check_is_strict_cross_multiplication() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	var rhs: int = (291 - 160) * (cfg.floor_y - cfg.net_top_y)
	var equal_or_below_height: int = rhs / 33
	s.ball_y = cfg.floor_y - equal_or_below_height
	check(not SpecialBall.is_above_original_y(s, 160, cfg),
		"境界以下は高所条件を満たさない")
	s.ball_y -= 1
	check(SpecialBall.is_above_original_y(s, 160, cfg),
		"固定小数点1だけ高ければ満たす")

func test_visibility_contact_and_minimal_step_are_derived_from_one_id() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	SpecialBall.set_special(s, Chars.SUPER_GHOST_BALL, 0)
	check(SpecialBall.is_visible(s), "ゴーストは点滅制御の対象だが存在する")
	check(SpecialBall.is_contactable(s), "ゴーストは接触可能")
	check(SpecialBall.step(s, cfg), "ゴーストは専用軌道が通常積分を消費")
	SpecialBall.set_special(s, Chars.SUPER_DISAPPEARING_BALL, 0)
	check(not SpecialBall.is_visible(s), "消える球は不可視")
	check(not SpecialBall.is_contactable(s), "消える球は接触不能")
	s.ball_held_by = 0
	check(SpecialBall.step(s, cfg), "保持中は通常積分を止める")

func test_rally_and_match_reset_clear_every_special_state() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	_dirty_special_state(s)
	Simulation.reset_rally(s, cfg, 0)
	_assert_special_state_clean(s, "ラリーリセット")
	_dirty_special_state(s)
	Simulation.reset_match(s, cfg, 1,
		[Chars.CHAR_TOME, Chars.CHAR_HITO, Chars.CHAR_PIYO, Chars.CHAR_UME],
		123, 456)
	_assert_special_state_clean(s, "試合・キャラ選択初期化")

func _dirty_special_state(s) -> void:
	for p in s.players:
		p.shock_ticks = 9
		p.bubble_ticks = 8
		p.special_action = Chars.SUPER_SUCTION
		p.special_action_ticks = 7
		p.ability_latch = 1
	s.ball_special_id = Chars.SUPER_REFRAIN_ATTACK
	s.ball_special_phase = 6
	s.ball_special_ticks = 5
	s.ball_special_owner_idx = 3
	s.ball_special_origin_vx = FP.from_int(4)
	s.ball_held_by = 3

func _assert_special_state_clean(s, label: String) -> void:
	for p in s.players:
		check_eq(p.shock_ticks, 0, label + " 感電")
		check_eq(p.bubble_ticks, 0, label + " 泡")
		check_eq(p.special_action, 0, label + " 特殊動作")
		check_eq(p.special_action_ticks, 0, label + " 特殊動作時間")
		check_eq(p.ability_latch, 0, label + " Dラッチ")
	check_eq(s.ball_special_id, 0, label + " 特殊球")
	check_eq(s.ball_special_phase, 0, label + " 特殊球段階")
	check_eq(s.ball_special_ticks, 0, label + " 特殊球時間")
	check_eq(s.ball_special_owner_idx, -1, label + " 特殊球所有者")
	check_eq(s.ball_special_origin_vx, 0, label + " 特殊球基準速度")
	check_eq(s.ball_held_by, -1, label + " 特殊球保持者")
