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

func test_ground_hit_is_crouch() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 0, 5)), "crouch", "接地+ヒット硬直はcrouch")

func test_ground_moving_is_run() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 180, 0)), "run", "接地+移動はrun")

func test_ground_moving_left_is_run() -> void:
	check_eq(AnimSelect.anim_for(_player(1, -180, 0)), "run", "接地+左移動もrun")

func test_ground_still_is_idle() -> void:
	check_eq(AnimSelect.anim_for(_player(1, 0, 0)), "idle", "接地+静止はidle")

func test_air_priority_over_hit() -> void:
	check_eq(AnimSelect.anim_for(_player(0, 0, 9)), "jump", "空中はヒット中でもjump優先")

func test_flip_team0_false() -> void:
	check_eq(AnimSelect.flip_for_team(0), false, "左チームは右向き(反転なし)")

func test_flip_team1_true() -> void:
	check_eq(AnimSelect.flip_for_team(1), true, "右チームは左向き(反転)")
