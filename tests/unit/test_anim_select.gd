extends "res://tests/test_case.gd"

const AnimSelect := preload("res://src/display/anim_select.gd")
const SimState := preload("res://src/sim/sim_state.gd")

func _player(on_ground: int, vx: int, cooldown: int):
	var p := SimState.Player.new()
	p.on_ground = on_ground
	p.vx = vx
	p.hit_cooldown = cooldown
	return p

func test_air_is_jump() -> void:
	check_eq(AnimSelect.anim_for(_player(0, 0, 0)), "jump", "空中はjump")

func test_ground_hit_is_ground_swing() -> void:
	# 原作セル8,9は地上のトス/レシーブ実打スイング。前トスだけ専用姿勢
	check_eq(AnimSelect.anim_for(_player(1, 0, 5)), "ground_swing",
		"接地+ヒット硬直は地上スイング")

func test_ground_moving_is_run() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 180, 0)), "run", "接地+移動はrun")

func test_ground_moving_left_is_run() -> void:
	check_eq(AnimSelect.anim_for(_player(1, -180, 0)), "run", "接地+左移動もrun")

func test_ground_still_is_idle() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 0, 0)), "idle", "接地+静止はidle")

func test_ground_receive_stance_is_visible() -> void:
	var p = _player(1, 0, 0)
	p.receive_stance = 1
	check_eq(AnimSelect.anim_for(p), "receive_stance", "接地+構え中はレシーブ構え")

func test_air_receive_stance_is_not_visible() -> void:
	var p = _player(0, 0, 0)
	p.receive_stance = -1
	check_eq(AnimSelect.anim_for(p), "jump", "空中の下+ボタンでは構え絵を出さない")

func test_ground_hit_takes_priority_over_receive_stance() -> void:
	var p = _player(1, 0, 5)
	p.receive_stance = 1
	check_eq(AnimSelect.anim_for(p), "ground_swing", "実打中は構えより地上スイング優先")

func test_air_hit_is_attack() -> void:
	# 空中でヒット中(hit_cooldown>0)=アタック(スパイク)。ただ飛んでるだけならjump
	check_eq(AnimSelect.anim_for(_player(0, 0, 9)), "attack", "空中+ヒットはattack")

func test_hit_kind_constants_are_explicit() -> void:
	var constants: Dictionary = SimState.new().get_script().get_script_constant_map()
	check_eq(constants.get("HIT_KIND_RECEIVE", -1), 0, "レシーブ種別を定数化")
	check_eq(constants.get("HIT_KIND_TOSS", -1), 1, "トス種別を定数化")
	check_eq(constants.get("HIT_KIND_FORWARD", -1), 2, "前トス種別を定数化")
	check_eq(constants.get("HIT_KIND_BLOCK", -1), 3, "ブロック種別を定数化")

func test_block_hit_uses_same_animation_on_ground_and_in_air() -> void:
	for on_ground in [0, 1]:
		var p = _player(on_ground, 0, 5)
		p.hit_kind = 3
		check_eq(AnimSelect.anim_for(p), "block",
			"地上・空中共通ブロック姿勢 ground=%d" % on_ground)

func test_ground_toss_kinds() -> void:
	var t = _player(1, 0, 9)
	t.hit_kind = 1
	check_eq(AnimSelect.anim_for(t), "ground_swing", "地上+hit_kind1は地上スイング")
	var f = _player(1, 0, 9)
	f.hit_kind = 2
	check_eq(AnimSelect.anim_for(f), "toss_fwd", "地上+hit_kind2は前トス")
	var r = _player(1, 0, 9)
	r.hit_kind = 0
	check_eq(AnimSelect.anim_for(r), "ground_swing",
		"地上+hit_kind0(ニュートラル上げ)も地上スイング")

func test_dive_uses_dive_animation() -> void:
	var p = _player(0, 0, 5)
	p.dive = 1
	check_eq(AnimSelect.anim_for(p), "dive", "飛びつき中は横っ飛びレシーブ")

func test_dive_takes_priority_over_non_hurt_actions() -> void:
	var p = _player(0, 0, 5)
	p.dive = 1
	p.hip = 1
	p.cling = 1
	check_eq(AnimSelect.anim_for(p), "dive", "飛び込みは固有動作と通常動作より優先")
	p.stun = 1
	check_eq(AnimSelect.anim_for(p), "stun", "スタンは飛び込みより優先")
	p.stun = 0
	p.flinch = 1
	check_eq(AnimSelect.anim_for(p), "hurt", "よろけは飛び込みより優先")

func test_dive_frame_is_derived_from_sim_age() -> void:
	var p = _player(0, 0, 0)
	p.dive = 1
	for row in [[0, 0], [1, 0], [2, 1], [4, 2], [6, 3], [99, 3]]:
		p.dive_age_ticks = row[0]
		check_eq(AnimSelect.dive_frame_for(p), row[1],
			"経過tickから横っ飛び4コマを固定: %s" % [row])

func test_dive_rotation_follows_direction_sign() -> void:
	var p = _player(0, 0, 0)
	for row in [[1, 0.9], [-1, -0.9], [0, 0.0]]:
		p.dive = row[0]
		check_eq(AnimSelect.dive_rotation_for(p), row[1],
			"横っ飛び方向と回転符号を一致: %s" % [row])

func test_flip_team0_false() -> void:
	check_eq(AnimSelect.flip_for_team(0), false, "左チームは右向き(反転なし)")

func test_flip_team1_true() -> void:
	check_eq(AnimSelect.flip_for_team(1), true, "右チームは左向き(反転)")
