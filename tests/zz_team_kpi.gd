extends SceneTree

# 使い捨て計測: CPU位置取り再設計(#66)の前後比較に使う基準値を取る。
# 難易度ごとにCPU同士の試合を回し、次を数える。
#   4タッチ目の発生回数 ... 超えると必ず失点する。妨害の唯一まともな指標
#   発生時のペア距離   ... 団子で起きているかの裏取り
#   常時の平均ペア距離 ... 団子そのものの度合い
#   32px以内の時間割合 ... 同上
#   アタック/ジャスト/ジャストレシーブ回数 ... 「重なりを消したら攻めなくなった」の検出
#   得点                ... 試合が成立し続けているかの確認

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const STANDARD_CHAR := 99

const MATCHES := 6
const TICKS := 4000

func _preset_name(prof: int) -> String:
	if prof == SimCpu.PRESET_WEAK:
		return "弱"
	if prof == SimCpu.PRESET_NORMAL:
		return "普通"
	if prof == SimCpu.PRESET_STRONG:
		return "強い"
	return "最強"

func _run(prof: int) -> void:
	var over_events := 0
	var over_dist_sum := 0
	var dist_sum := 0
	var dist_n := 0
	var close_ticks := 0
	var attacks := 0
	var just_attacks := 0
	var just_receives := 0
	var points := 0
	for m in MATCHES:
		var cfg = SimConfig.new()
		cfg.points_to_win = 999
		var s = SimState.new()
		Simulation.reset_match(s, cfg, m % 2, [STANDARD_CHAR, STANDARD_CHAR,
			STANDARD_CHAR, STANDARD_CHAR])
		for p in s.players:
			p.cpu = prof
		# 試合ごとに乱数の目をずらす(1つの目で語らない)
		s.tick = m * 977
		var prev_touches: int = s.touches
		var jr_before := 0
		for p in s.players:
			jr_before += p.just_receive_event
		for t in TICKS:
			var before_hit: int = s.last_hit_tick
			var in_l: int = SimCpu.decide(s, s.controlled_l, cfg)
			var in_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
			Simulation.tick(s, [in_l, in_r], cfg)
			if s.touches > cfg.max_touches and prev_touches <= cfg.max_touches:
				over_events += 1
				var team: int = s.last_touch_team
				if team >= 0:
					over_dist_sum += FP.to_int(absi(
						s.players[team * 2].x - s.players[team * 2 + 1].x))
			prev_touches = s.touches
			if s.phase == SimState.PHASE_RALLY:
				for team in 2:
					var d: int = FP.to_int(absi(
						s.players[team * 2].x - s.players[team * 2 + 1].x))
					dist_sum += d
					dist_n += 1
					if d <= 32:
						close_ticks += 1
			if s.last_hit_tick != before_hit \
					and s.ball_attack_kind != SimState.BALL_ATTACK_NONE:
				attacks += 1
				if s.ball_attack_kind == SimState.BALL_ATTACK_JUST:
					just_attacks += 1
		var jr_after := 0
		for p in s.players:
			jr_after += p.just_receive_event
		just_receives += jr_after - jr_before
		points += s.score_l + s.score_r
	var avg_over: int = over_dist_sum / over_events if over_events > 0 else -1
	print(("[%s] 4タッチ目=%d回 発生時距離=%dpx 常時距離=%dpx 32px以内=%d%%"
		+ " アタック=%d ジャスト=%d ジャストレシーブ=%d 得点=%d") % [
		_preset_name(prof), over_events, avg_over,
		dist_sum / dist_n if dist_n > 0 else 0,
		close_ticks * 100 / dist_n if dist_n > 0 else 0,
		attacks, just_attacks, just_receives, points])

func _init() -> void:
	print("CPU同士 %d試合 x %dtick" % [MATCHES, TICKS])
	for prof in [SimCpu.PRESET_WEAK, SimCpu.PRESET_NORMAL,
			SimCpu.PRESET_STRONG, SimCpu.PRESET_MAX]:
		_run(prof)
	quit(0)
