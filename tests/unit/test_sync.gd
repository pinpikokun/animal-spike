extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

const TICKS := 3600

# 決定論の生命線。同一入力列を2回流して全ハッシュが一致すること
# ここが落ちたら最優先で直す。floatや未初期化状態の混入が疑わしい

func _next_rand(s: int) -> int:
	# xorshift64。乱数も整数のみで作る
	s ^= s << 13
	s ^= s >> 7
	s ^= s << 17
	return s

func _run_once() -> Array[int]:
	var cfg = SimConfig.new()
	var s = SimState.new()
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(220)
	s.players[2].x = FP.from_int(420)
	s.players[3].x = FP.from_int(540)
	s.ball_x = FP.from_int(320)
	s.ball_y = FP.from_int(60)
	var hashes: Array[int] = []
	var rng := 123456789
	for t in TICKS:
		var inputs: Array[int] = []
		for i in 4:
			rng = _next_rand(rng)
			inputs.append(rng & 7)
		Simulation.step(s, inputs, cfg)
		if t % 60 == 0:
			hashes.append(s.state_hash())
	hashes.append(s.state_hash())
	return hashes

func test_synctest_60_seconds() -> void:
	var a := _run_once()
	var b := _run_once()
	check_eq(a.size(), b.size(), "チェックポイント数が一致")
	for i in a.size():
		if a[i] != b[i]:
			check(false, "デシンク検出 checkpoint=" + str(i))
			return
