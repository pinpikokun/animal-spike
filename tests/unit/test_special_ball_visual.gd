extends "res://tests/test_case.gd"

const AnimSelect := preload("res://src/display/anim_select.gd")
const Chars := preload("res://src/sim/chars.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SpecialBall := preload("res://src/sim/special_ball.gd")
const SpecialBallVisual := preload("res://src/display/special_ball_visual.gd")

func _state(special_id: int, tick: int = 0):
	var s := SimState.new()
	s.ball_special_id = special_id
	s.tick = tick
	s.ball_special_ticks = tick
	return s

func test_original_ball_sheet_cells_are_selected_only_for_matching_effects() -> void:
	var rows: Array[Array] = [
		[Chars.SUPER_GUST_BALL, [4, 5]],
		[Chars.SUPER_GUST_ATTACK, [4, 5]],
		[Chars.SUPER_FLAME_ATTACK, [12, 13]],
		[Chars.SUPER_THUNDER_BALL, [18, 19, 20]],
		[Chars.SUPER_BUBBLE_PACK, [21, 22]],
	]
	for row: Array in rows:
		var cells: Array = row[1]
		for frame in cells.size():
			var s = _state(int(row[0]), frame * 4)
			check(SpecialBallVisual.uses_special_sheet(s),
				"専用球シートを使う: %d" % row[0])
			check_eq(SpecialBallVisual.cell_for(s), int(cells[frame]),
				"原作球セル: %d frame=%d" % [row[0], frame])
	for special_id in [Chars.SUPER_GHOST_BALL, Chars.SUPER_DISAPPEARING_BALL,
			Chars.SUPER_FEINT_ATTACK, Chars.SUPER_SNAKE_BALL,
			Chars.SUPER_TRANSFER_BALL, Chars.SUPER_REFRAIN_ATTACK]:
		var s = _state(special_id)
		check(not SpecialBallVisual.uses_special_sheet(s),
			"専用セルのない技は通常球表示を使う: %d" % special_id)
		check_eq(SpecialBallVisual.cell_for(s), -1,
			"専用セルのない技はセルなし: %d" % special_id)

func test_sim_visibility_is_the_single_source_for_hidden_special_balls() -> void:
	check(not SpecialBall.is_visible(_state(Chars.SUPER_DISAPPEARING_BALL)),
		"消える球は通常球も特殊球も隠す")
	check(not SpecialBall.is_visible(_state(Chars.SUPER_TRANSFER_BALL)),
		"異次元転送中は通常球も特殊球も隠す")
	check(SpecialBall.is_visible(_state(Chars.SUPER_GHOST_BALL)),
		"ゴーストの点滅は表示層で扱える存在状態")

func test_player_special_animation_priority_matches_the_approved_contract() -> void:
	var p := SimState.Player.new()
	p.stun_ticks = 1
	p.bubble_ticks = 1
	p.shock_ticks = 1
	p.burn = 1
	p.special_action = Chars.SUPER_SUCTION
	check_eq(AnimSelect.anim_for(p), "stun", "気絶が最優先")
	p.stun_ticks = 0
	check_eq(AnimSelect.anim_for(p), "bubble", "泡は感電と炎上より優先")
	p.bubble_ticks = 0
	check_eq(AnimSelect.anim_for(p), "shock", "感電は炎上より優先")
	p.shock_ticks = 0
	check_eq(AnimSelect.anim_for(p), "burn", "炎上は通常・特殊動作より優先")
	p.burn = 0
	check_eq(AnimSelect.anim_for(p), "fly", "吸引中は羽ばたき")
	p.special_action = Chars.SUPER_SUBSPACE_BLOCK
	check_eq(AnimSelect.anim_for(p), "fly_hover", "亜空間保持中は飛行静止")
