extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")

func test_equal_states_equal_hash() -> void:
	var a = SimState.new()
	var b = SimState.new()
	check_eq(a.state_hash(), b.state_hash(), "初期状態のハッシュが一致")

func test_hash_changes_on_diff() -> void:
	var a = SimState.new()
	var b = SimState.new()
	b.ball_x = 1
	check(a.state_hash() != b.state_hash(), "1bitの差でハッシュが変わる")
	var c = SimState.new()
	c.players[3].vy = -1
	check(a.state_hash() != c.state_hash(), "プレイヤー差分でも変わる")

func test_serialize_length() -> void:
	# tick(1) + プレイヤー4体x5 + ボール4 = 25
	check_eq(SimState.new().to_int_array().size(), 25, "シリアライズ長")
