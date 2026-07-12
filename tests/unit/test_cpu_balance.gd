extends "res://tests/test_case.gd"

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")

# KPI自動対戦ハーネス(調査doc §8)。決定論simの強み=CPU対CPUの試合結果が
# 毎回同一なので、プリセットの強さの単調性(弱<普通<強<最強)を回帰テストにできる。
# ノブの数値をいじって順序が壊れたらここが割れる

const MAX_TICKS := 120000  # 3点先取なら余裕(無限ラリー・進行停止の検出も兼ねる)

func _run_match(prof_l: int, prof_r: int, serve_first: int, seed: int = 0) -> Array[int]:
	# 両チーム完全CPUで短縮試合(3点先取)を回し[勝者, 左得点, 右得点]を返す。勝者-1=決着せず
	var cfg = SimConfig.new()
	cfg.points_to_win = 3
	var s = SimState.new()
	Simulation.reset_match(s, cfg, serve_first)
	# 乱数キー(last_hit_tick)の系列をずらして独立サンプル化(決定論のまま多試合化)
	s.tick = seed * 7919
	for i in 4:
		s.players[i].cpu = prof_l if i < 2 else prof_r
	for t in MAX_TICKS:
		var in_l: int = SimCpu.decide(s, s.controlled_l, cfg)
		var in_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [in_l, in_r], cfg)
		if s.phase == SimState.PHASE_GAME_OVER:
			return [s.winner, s.score_l, s.score_r]
	return [-1, s.score_l, s.score_r]

func _series(prof_a: int, prof_b: int) -> Array[int]:
	# aとbを左右・種違いで4試合戦わせ[bの勝数, 合計得点差(b-a)]を返す。
	# 1試合はサイコロの目(ミス抽選の巡り)が支配的なので必ず集計で判定する
	var wins_b := 0
	var diff_b := 0
	for seed in 2:
		var m1 := _run_match(prof_a, prof_b, seed % 2, seed)
		var m2 := _run_match(prof_b, prof_a, (seed + 1) % 2, seed + 100)
		check(m1[0] >= 0 and m2[0] >= 0, "全試合が決着する(進行停止の検出)")
		wins_b += (1 if m1[0] == 1 else 0) + (1 if m2[0] == 0 else 0)
		diff_b += (m1[2] - m1[1]) + (m2[1] - m2[2])
	return [wins_b, diff_b]

func test_preset_strength_is_monotonic() -> void:
	# 隣接プリセット間の強さの単調性(調査doc §8のKPI)。4試合中、強い側が
	# 勝ち越すこと(同数勝ちなら得点差で上回ること)。ノブ調整で割れたら数値を見直す
	var pairs := [
		[SimCpu.PRESET_WEAK, SimCpu.PRESET_NORMAL, "普通>弱"],
		[SimCpu.PRESET_NORMAL, SimCpu.PRESET_STRONG, "強>普通"],
		[SimCpu.PRESET_STRONG, SimCpu.PRESET_MAX, "最強>強"],
	]
	for pr in pairs:
		var r := _series(pr[0], pr[1])
		check(r[0] > 2 or (r[0] == 2 and r[1] > 0),
			"%s (勝数=%d/4, 得点差=%d)" % [pr[2], r[0], r[1]])

func test_max_beats_weak_both_sides() -> void:
	# 最強は弱に必ず勝つ(左右どちらに置いても=左右対称性の検証を兼ねる)
	check_eq(_run_match(SimCpu.PRESET_WEAK, SimCpu.PRESET_MAX, 0)[0], 1, "右の最強が勝つ")
	check_eq(_run_match(SimCpu.PRESET_MAX, SimCpu.PRESET_WEAK, 0)[0], 0, "左の最強が勝つ")

func test_weak_mirror_match_finishes() -> void:
	# 弱同士でも試合が止まらない(進行停止・無限ラリーの回帰検出)
	check(_run_match(SimCpu.PRESET_WEAK, SimCpu.PRESET_WEAK, 0)[0] >= 0, "弱同士でも決着する")
