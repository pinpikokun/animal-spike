extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

const TICKS := 3600

# 2段構えの決定論検証:
# (1) 同一入力2回実行のハッシュ一致 = プロセス内の非決定要素(グローバルRNG等)を検出
# (2) ゴールデンハッシュ = 挙動の意図しない変化を検出。マシンをまたげばfloat差異も
#     いずれ露見する。なお同一プロセス内のfloat混入は(1)では捕まらないため、
#     静的スキャン(test_no_float_in_sim.gd)が併走している
# 物理を意図的に変更した場合はGOLDEN_FINAL_HASHを新しい値に更新すること

const GOLDEN_FINAL_HASH := 9195335326355793263

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
	# 初速を与えて左右壁・天井・床の全反射経路を踏ませる
	s.ball_vx = FP.from_int(3)
	s.ball_vy = -FP.from_int(2)
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
	var mismatch := -1
	for i in a.size():
		if a[i] != b[i]:
			mismatch = i
			break
	check_eq(mismatch, -1, "デシンクなし(検出indexは-1)")

func test_golden_hash_regression() -> void:
	var a := _run_once()
	check_eq(a[a.size() - 1], GOLDEN_FINAL_HASH,
		"ゴールデンハッシュ一致(物理を意図的に変えた場合のみ更新する)")
