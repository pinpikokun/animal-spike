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
	# 原作準拠の操作系: 上=ジャンプ(+上照準)、スペース=アクション(Xも可)、下=下照準
	if Input.is_key_pressed(KEY_UP):
		input |= SimInput.IN_JUMP | SimInput.IN_UP
	if Input.is_key_pressed(KEY_DOWN):
		input |= SimInput.IN_DOWN
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_X):
		input |= SimInput.IN_ACTION
	if Input.is_key_pressed(KEY_C):
		input |= SimInput.IN_SWITCH
	if Input.is_key_pressed(KEY_D):
		input |= SimInput.IN_ABILITY1
	return input
