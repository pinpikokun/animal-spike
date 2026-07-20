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
# ゴールデンは全チェックポイント(60tickごと+最終)の合成ハッシュで比較する。
# 最終ハッシュのみだとreset_rallyの状態正規化で途中の物理変化を見逃すため
# 物理を意図的に変更した場合はGOLDEN_COMBINED_HASHを新しい値に更新すること

# ball_ghost/ball_flame追加による状態配列拡張(190→192)。
# 物理挙動の変更ではなくハッシュ構造の変化。
const GOLDEN_COMBINED_HASH := 8640764298994872477

func _next_rand(s: int) -> int:
	# xorshift64。乱数も整数のみで作る
	s ^= s << 13
	s ^= s >> 7
	s ^= s << 17
	return s

func _run_once() -> Array[int]:
	# フルゲーム(サーブ→ラリー→得点→再サーブ)を人間2系統のランダム入力で回す。
	# 全入力ビット(0-127)を含み、切替・ヒット・トス照準・CPU相方も検証対象に入る
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	var hashes: Array[int] = []
	var rng := 123456789
	for t in TICKS:
		var inputs: Array[int] = []
		for i in 2:
			rng = _next_rand(rng)
			inputs.append(rng & 127)
		Simulation.tick(s, inputs, cfg)
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

func _combined(hashes: Array[int]) -> int:
	# チェックポイント群をFNV-1a 64bitで1本に畳む(state_hashと同じ方式)
	var h := -3750763034362895579
	for v in hashes:
		for i in 8:
			h ^= (v >> (i * 8)) & 0xFF
			h *= 1099511628211
	return h

func test_golden_hash_regression() -> void:
	var a := _run_once()
	check_eq(a.size(), 61, "チェックポイント数(60tickごと+最終)")
	check_eq(_combined(a), GOLDEN_COMBINED_HASH,
		"合成ゴールデンハッシュ一致(物理を意図的に変えた場合のみ更新する)")

func _run_endgame() -> Array[int]:
	# 3600tickの主走行はGAME_OVERに到達しないため、勝敗決定(デュース2点差)と
	# GAME_OVERフェーズの決定論はこの終盤戦シナリオで別途検証する
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0)
	# 14-0開始: CPU同士は点の取り合いが交互に近く、僅差デュースだと決着しないため
	# 大差から確実に勝利遷移へ到達させる(左の1点で15点・2点差以上が確定する)
	s.score_l = cfg.points_to_win - 1
	var out: Array[int] = []
	var rng := 987654321
	for t in 3600:
		var inputs: Array[int] = []
		for i in 2:
			rng = _next_rand(rng)
			inputs.append(rng & 127)
		Simulation.tick(s, inputs, cfg)
		if t % 60 == 0:
			out.append(s.state_hash())
	out.append(s.state_hash())
	out.append(s.phase)
	out.append(s.winner)
	return out

func test_endgame_reaches_game_over_deterministically() -> void:
	var a := _run_endgame()
	check_eq(a[a.size() - 2], SimState.PHASE_GAME_OVER, "3600tick以内に勝敗が付く")
	check(a[a.size() - 1] >= 0, "勝者が確定している")
	var b := _run_endgame()
	var mismatch := -1
	for i in a.size():
		if a[i] != b[i]:
			mismatch = i
			break
	check_eq(mismatch, -1, "終盤戦デシンクなし(検出indexは-1)")
