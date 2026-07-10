# キーボード状態をsim入力ビットへ変換する。表示層(Input使用可)。
# ローカルプレイ(game_view)とネット対戦(net_input_node)の両方が共用する
extends RefCounted

const SimInput := preload("res://src/sim/sim_input.gd")

static func poll() -> int:
	var input := 0
	if Input.is_key_pressed(KEY_LEFT):
		input |= SimInput.IN_LEFT
	if Input.is_key_pressed(KEY_RIGHT):
		input |= SimInput.IN_RIGHT
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_SPACE):
		input |= SimInput.IN_JUMP
	if Input.is_key_pressed(KEY_X):
		input |= SimInput.IN_ACTION
	if Input.is_key_pressed(KEY_C):
		input |= SimInput.IN_SWITCH
	return input
