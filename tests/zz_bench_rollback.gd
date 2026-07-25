extends SceneTree

# 使い捨て計測: ネット対戦のカクつき懸念に数字で答える。
# ロールバックは「1表示フレームの中で、巻き戻した分のtickをまとめて再計算する」。
# そこで測るのは (a) 1tickの総コスト (b) 巻き戻し時のまとめ計算のコスト
# (c) 状態の保存/復元のコスト。60fpsの予算16.6ミリ秒に対する割合で出す。

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const STANDARD_CHAR := 99

const WARM := 600
const N := 6000

func _fresh() -> Array:
	var cfg = SimConfig.new()
	cfg.points_to_win = 999
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	for p in s.players:
		p.cpu = SimCpu.PRESET_MAX
	return [s, cfg]

func _init() -> void:
	var w := _fresh()
	var s = w[0]
	var cfg = w[1]
	# 静止画面でなくラリー中の重い状態を測るため、先に暖機して試合を進める
	for t in WARM:
		Simulation.tick(s, [SimCpu.decide(s, s.controlled_l, cfg),
			SimCpu.decide(s, 2 + s.controlled_r, cfg)], cfg)

	# (a) 1tickの総コスト(CPU2人ぶんの思考 + 物理 + 判定)
	var t0: int = Time.get_ticks_usec()
	for t in N:
		Simulation.tick(s, [SimCpu.decide(s, s.controlled_l, cfg),
			SimCpu.decide(s, 2 + s.controlled_r, cfg)], cfg)
	var t1: int = Time.get_ticks_usec()
	var tick_ns: int = (t1 - t0) * 1000 / N

	# (b) 状態の保存と復元(ロールバックのたびに走る)
	var snap: Array[int] = s.serialize()
	var t2: int = Time.get_ticks_usec()
	for t in N:
		snap = s.serialize()
	var t3: int = Time.get_ticks_usec()
	var save_ns: int = (t3 - t2) * 1000 / N
	var t4: int = Time.get_ticks_usec()
	for t in N:
		s.load_int_array(snap)
	var t5: int = Time.get_ticks_usec()
	var load_ns: int = (t5 - t4) * 1000 / N

	var budget_ns: int = 16666666  # 60fpsの1フレーム
	print("=== 1回あたりのコスト(ナノ秒) ===")
	print("  1tickのシミュレーション全部 : %8d ns" % tick_ns)
	print("  状態の保存(serialize)       : %8d ns" % save_ns)
	print("  状態の復元(load)            : %8d ns" % load_ns)
	print("")
	print("=== 巻き戻しが起きた1フレームの総コスト ===")
	print("  遅延コマ数 | 再計算コスト | 60fps予算に占める割合")
	for rb in [1, 2, 4, 8, 12, 16]:
		var cost: int = load_ns + rb * (tick_ns + save_ns)
		print("  %8d | %9d ns | %d.%02d %%" % [
			rb, cost, cost * 100 / budget_ns,
			(cost * 10000 / budget_ns) % 100])
	print("")
	print("参考: 役割抽選のハッシュ4回ぶん = 748 ns")
	print("      これは1tickのシミュレーション全部の %d.%02d %% にあたる" % [
		748 * 100 / tick_ns, (748 * 10000 / tick_ns) % 100])
	quit(0)
