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
	# tick(1) + プレイヤー4体x11(stun/dive/guard/guard_max/cpu含む)
	# + ボール6(spin/power含む) + last_hit_tick(1)
	# + サーブ系4(aim/pow/tossed/flight) + hit_freeze(1) + slow_ticks(1) + フェーズ系(12) = 70
	# プレイヤー4x24=96 + 全体26 + エンティティ8スロットx8欄=64
	check_eq(SimState.new().to_int_array().size(), 186, "シリアライズ長(エンティティ枠を含む)")

func test_load_int_array_roundtrip() -> void:
	# to_int_array→load_int_arrayの往復で全フィールドが復元される(ロールバックの土台)
	var a = SimState.new()
	a.tick = 123
	a.ball_x = 456789
	a.phase = SimState.PHASE_RALLY
	a.score_l = 7
	a.winner = 1
	a.players[2].x = 999
	a.players[3].hit_cooldown = 5
	var b = SimState.new()
	b.load_int_array(a.to_int_array())
	check_eq(b.state_hash(), a.state_hash(), "往復でハッシュ一致")
	check_eq(b.players[2].x, 999, "プレイヤー座標の復元")
	check_eq(b.tick, 123, "tickの復元")

func test_load_int_array_overwrites_everything() -> void:
	# 汚れた状態に読み込んでも完全に上書きされる(ロールバック時は必ず過去へ戻す)
	var clean = SimState.new()
	var snapshot: Array[int] = clean.to_int_array()
	var dirty = SimState.new()
	dirty.tick = 555
	dirty.ball_vy = -777
	dirty.players[0].on_ground = 0
	dirty.load_int_array(snapshot)
	check_eq(dirty.state_hash(), clean.state_hash(), "汚れが完全に消える")
