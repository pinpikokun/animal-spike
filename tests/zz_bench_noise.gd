extends SceneTree

# 使い捨て計測: 決定論ハッシュ(_noise)の実コストを、既にCPUが毎tick回している
# 弾道予測と並べて比べる。「毎回計算し直す方式は重いのか」を数字で答えるため。

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const STANDARD_CHAR := 99

const N := 200000

func _init() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x - FP.from_int(40)
	s.ball_y = cfg.net_top_y - FP.from_int(40)
	s.ball_vx = FP.from_int(80)
	s.ball_vy = FP.from_int(50)
	var p = s.players[2]

	# 1) 決定論ハッシュ1回ぶん
	var t0: int = Time.get_ticks_usec()
	var acc := 0
	for i in N:
		acc += SimCpu._noise(1, i, 2) % 9
	var t1: int = Time.get_ticks_usec()

	# 2) 落下点予測1回ぶん(CPUが毎tick呼んでいる既存処理)
	var t2: int = Time.get_ticks_usec()
	for i in N / 100:
		acc += SimCpu._predict_landing_x(s, cfg, cfg.floor_y, 3)
	var t3: int = Time.get_ticks_usec()

	# 3) 接触予測1回ぶん(構え判定で毎tick呼んでいる既存処理)
	var t4: int = Time.get_ticks_usec()
	for i in N / 100:
		acc += SimCpu._ticks_until_receive_at(s, p, cfg, cfg.player_reach, p.x)
	var t5: int = Time.get_ticks_usec()

	var noise_ns: int = (t1 - t0) * 1000 / N
	var land_ns: int = (t3 - t2) * 1000 / (N / 100)
	var contact_ns: int = (t5 - t4) * 1000 / (N / 100)
	print("1回あたりのコスト(ナノ秒)")
	print("  決定論ハッシュ _noise      : %d ns" % noise_ns)
	print("  落下点予測 _predict_landing: %d ns  (ハッシュの %d 倍)" % [
		land_ns, land_ns / maxi(noise_ns, 1)])
	print("  接触予測 _ticks_until_recv : %d ns  (ハッシュの %d 倍)" % [
		contact_ns, contact_ns / maxi(noise_ns, 1)])
	# 1秒ぶんの試合で、役割抽選のハッシュを4人x60tick引いた場合の総コスト
	var per_sec_ns: int = noise_ns * 4 * 60
	print("")
	print("役割抽選を4人x60tick=240回引いた場合の1秒あたり総コスト: %d ns (= %d マイクロ秒)" % [
		per_sec_ns, per_sec_ns / 1000])
	print("1tickの予算は 16666 マイクロ秒 (60fps)")
	print("acc=%d (最適化で消されていないことの確認)" % acc)
	quit(0)
