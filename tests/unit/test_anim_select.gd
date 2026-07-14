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

func test_ground_hit_is_toss() -> void:
	# 地上ヒット(既定hit_kind=0=上げ)はtoss。前トスのみtoss_fwd
	check_eq(AnimSelect.anim_for(_player(1, 0, 5)), "toss", "接地+ヒット硬直はtoss")

func test_ground_moving_is_run() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 180, 0)), "run", "接地+移動はrun")

func test_ground_moving_left_is_run() -> void:
	check_eq(AnimSelect.anim_for(_player(1, -180, 0)), "run", "接地+左移動もrun")

func test_ground_still_is_idle() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 0, 0)), "idle", "接地+静止はidle")

func test_air_hit_is_attack() -> void:
	# 空中でヒット中(hit_cooldown>0)=アタック(スパイク)。ただ飛んでるだけならjump
	check_eq(AnimSelect.anim_for(_player(0, 0, 9)), "attack", "空中+ヒットはattack")

func test_ground_toss_kinds() -> void:
	var t = _player(1, 0, 9)
	t.hit_kind = 1
	check_eq(AnimSelect.anim_for(t), "toss", "地上+hit_kind1は普通トス")
	var f = _player(1, 0, 9)
	f.hit_kind = 2
	check_eq(AnimSelect.anim_for(f), "toss_fwd", "地上+hit_kind2は前トス")
	var r = _player(1, 0, 9)
	r.hit_kind = 0
	check_eq(AnimSelect.anim_for(r), "toss", "地上+hit_kind0(ニュートラル上げ)もtoss")

func test_flip_team0_false() -> void:
	check_eq(AnimSelect.flip_for_team(0), false, "左チームは右向き(反転なし)")

func test_flip_team1_true() -> void:
	check_eq(AnimSelect.flip_for_team(1), true, "右チームは左向き(反転)")
