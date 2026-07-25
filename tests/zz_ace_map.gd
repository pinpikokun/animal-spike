extends SceneTree

# 使い捨て計測: 人間のアタックサーブ(相当)の着弾xを4px刻みで動かし、
# 難易度ごとに「敵チームが返せたか」を地図にする。
# 目的: サービスエースになる着弾帯(デッドバンド)の位置と幅を修正前後で比較する。
# 使い方: godot --headless --path . --script res://tests/zz_ace_map.gd

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const STANDARD_CHAR := 99

const STEP_PX := 4
const FROM_PX := 260
const TO_PX := 490

func _preset_name(prof: int) -> String:
	if prof == SimCpu.PRESET_WEAK:
		return "弱"
	if prof == SimCpu.PRESET_NORMAL:
		return "普通"
	if prof == SimCpu.PRESET_STRONG:
		return "強い"
	if prof == SimCpu.PRESET_MAX:
		return "最強"
	if SimCpu.prof_byte(prof, SimCpu.P_AIM) == 0:
		return "最強-誤差なし"
	return "最強-ミスなし"

# 着弾target_pxを狙ったアタック球を、人間側(team0)が打った直後の状態で作る。
func _shot_world(prof: int, target_px: int, seed_tick: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	s.phase = SimState.PHASE_RALLY
	s.tick = seed_tick
	s.last_hit_tick = s.tick
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	for i in 4:
		s.players[i].cpu = prof
	s.controlled_l = 0
	s.controlled_r = 0
	# 打点: 自陣ネット際の空中(アタックサーブと同じ高さ帯)
	s.ball_x = cfg.net_x - FP.from_int(40)
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(40)
	s.ball_vy = cfg.spike_vy * cfg.spike_normal_pct / 100
	s.ball_vx = HitResolver.toss_aim_vx(
		s.ball_x, s.ball_y, s.ball_vy, FP.from_int(target_px), cfg)
	return [s, cfg]

# 敵チーム(team1)が球に触れたら true。触れずに落ちたら false。
func _returned(prof: int, target_px: int, seed_tick: int) -> bool:
	var w := _shot_world(prof, target_px, seed_tick)
	var s = w[0]
	var cfg = w[1]
	var score_l0: int = s.score_l
	for tick in 240:
		var in_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, in_r], cfg)
		if s.last_touch_team == 1:
			return true
		if s.score_l > score_l0 or s.phase != SimState.PHASE_RALLY:
			return false
	return false

func _init() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	print("敵チーム初期位置: p2.x=%d p3.x=%d net_x=%d 幅=%d" % [
		FP.to_int(s.players[2].x), FP.to_int(s.players[3].x),
		FP.to_int(cfg.net_x), FP.to_int(cfg.court_width)])
	# 診断用: 最強から狙い誤差(AIM)とミス率(MISS)だけを抜いたプロファイル。
	# この2つは落下点land_xを汚す。汚れた側と汚れていない側で担当を比べ合うと
	# 「両者譲り」が起きるはず、という仮説の検証。
	var ab: int = SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_AB)
	var max_clean: int = SimCpu.make_profile(ab,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_DELAY), 0, 0,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_SWEET),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_DEPTH),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_TIQ))
	var max_no_miss: int = SimCpu.make_profile(ab,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_DELAY),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_AIM), 0,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_SWEET),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_DEPTH),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_TIQ))
	var presets: Array[int] = [SimCpu.PRESET_WEAK, SimCpu.PRESET_NORMAL,
		SimCpu.PRESET_STRONG, SimCpu.PRESET_MAX, max_no_miss, max_clean]
	# 乱数の目(last_hit_tick)を16通り振る。1つの目だけ見ると頻度を語れない
	for prof in presets:
		var dead_total := 0
		var trials := 0
		var per_x: Dictionary = {}
		for seed_i in 16:
			var seed_tick: int = 1000 + seed_i * 137
			var x: int = FROM_PX
			while x <= TO_PX:
				trials += 1
				if not _returned(prof, x, seed_tick):
					dead_total += 1
					per_x[x] = int(per_x.get(x, 0)) + 1
				x += STEP_PX
		# 16回中8回以上見送る=その帯は常時穴、と見なす
		var always: Array[int] = []
		for k in per_x.keys():
			if int(per_x[k]) >= 8:
				always.append(k)
		always.sort()
		print("[%s] 見送り %d/%d (%d%%) 常時穴(16回中8回以上): %s" % [
			_preset_name(prof), dead_total, trials,
			dead_total * 100 / trials, str(always)])
	quit(0)
