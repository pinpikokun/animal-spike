# 一時診断(コミットしない): 味方の「団子」をユーザーの言葉どおりに測り直す。
# 滞在時間の割合ではなく、目立つ事象の回数を数える。
# 使い方: godot --headless --path . --script res://tests/zz_cluster_probe.gd
extends SceneTree

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

const STANDARD_CHAR := 99

func _px(v: int) -> int:
	return v >> 16

func _run(preset: int, label: String, ticks: int) -> void:
	var cfg = SimConfig.new()
	cfg.points_to_win = 999
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	for p in s.players:
		p.cpu = preset
	# (1) 同じtickに味方2人がボールの打撃圏内にいる
	var both_in_reach := 0
	# (2) 味方2人が同じ方向へ同時に動いている
	var same_dir_move := 0
	# (3) 3タッチ使い切って相手に渡した回数(=組み立てが破綻)
	var three_touch_over := 0
	# (4) 味方2人の距離の最小値(最接近)
	var min_gap: int = 1 << 40
	# (5) 得点/アタック(比較用)
	var points := 0
	var spikes := 0
	var prev_score := 0
	var prev_hit := 0
	var move_ticks := 0
	for tick in ticks:
		var in_l: int = SimCpu.decide(s, s.controlled_l, cfg)
		var in_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		var pre_touches: int = s.touches
		Simulation.tick(s, [in_l, in_r], cfg)
		for team in 2:
			var a = s.players[team * 2]
			var b = s.players[team * 2 + 1]
			var gap: int = absi(a.x - b.x)
			# 自陣にボールがあるチームだけを評価(相手コートに居る間は関係ない)
			var own_side: bool = (s.ball_x < cfg.net_x) == (team == 0)
			if own_side:
				min_gap = mini(min_gap, gap)
				# (1) 両者がボールの打撃圏内(リーチの楕円)にいるか
				var in_reach := 0
				for p in [a, b]:
					var dx: int = s.ball_x - p.x
					var dy: int = s.ball_y - p.y
					var dy_n: int = dy * cfg.player_reach / cfg.player_reach_up
					if dx * dx + dy_n * dy_n <= cfg.player_reach * cfg.player_reach:
						in_reach += 1
				if in_reach == 2:
					both_in_reach += 1
				# (2) 同じ方向へ同時に移動
				if a.vx != 0 and b.vx != 0:
					move_ticks += 1
					if signi(a.vx) == signi(b.vx):
						same_dir_move += 1
		if s.last_hit_tick != prev_hit:
			prev_hit = s.last_hit_tick
			if s.ball_attack_kind != SimState.BALL_ATTACK_NONE:
				spikes += 1
			if pre_touches >= 3:
				three_touch_over += 1
		var score: int = s.score_l + s.score_r
		if score != prev_score:
			points += 1
			prev_score = score
	print("=== %s (%d tick) ===" % [label, ticks])
	print("  (1) 味方2人が同時にボールの打撃圏内 = %d tick" % both_in_reach)
	print("  (2) 味方2人が同じ方向へ同時移動     = %d / %d tick (%d%%)" % [
		same_dir_move, move_ticks, same_dir_move * 100 / maxi(move_ticks, 1)])
	print("  (3) 3タッチ使い切って相手へ渡した   = %d 回" % three_touch_over)
	print("  (4) 味方2人の最接近(自陣時)          = %d px" % _px(min_gap))
	print("  (5) 得点=%d アタック=%d" % [points, spikes])

func _init() -> void:
	_run(SimCpu.PRESET_MAX, "最強 vs 最強", 3600)
	_run(SimCpu.PRESET_NORMAL, "普通 vs 普通", 3600)
	quit(0)
