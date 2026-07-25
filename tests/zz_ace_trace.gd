extends SceneTree

# 使い捨て計測: デッドバンド中央(336px)へ落とした時の敵2人の毎tick挙動を出す。
# 構え(receive_stance)に入って静止しているのか、単に間に合っていないのかを見分ける。

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const STANDARD_CHAR := 99

const TARGETS: Array[int] = [336, 380]

func _in_str(v: int) -> String:
	var t := ""
	t += "L" if v & Simulation.IN_LEFT else "-"
	t += "R" if v & Simulation.IN_RIGHT else "-"
	t += "A" if v & Simulation.IN_ACTION else "-"
	t += "D" if v & Simulation.IN_DOWN else "-"
	return t

func _trace(prof: int, label: String, target_px: int) -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_hit_tick = s.tick
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	for i in 4:
		s.players[i].cpu = prof
	s.controlled_l = 0
	s.controlled_r = 0
	s.ball_x = cfg.net_x - FP.from_int(40)
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(40)
	s.ball_vy = cfg.spike_vy * cfg.spike_normal_pct / 100
	s.ball_vx = HitResolver.toss_aim_vx(
		s.ball_x, s.ball_y, s.ball_vy, FP.from_int(target_px), cfg)
	print("=== %s 着弾狙い%dpx ===" % [label, target_px])
	print("tick| ball x,y | 前衛x 構え 入力 | 後衛x 構え 入力")
	for tick in 60:
		var in2: int = SimCpu.decide(s, 2, cfg)
		var in3: int = SimCpu.decide(s, 3, cfg)
		var p2 = s.players[2]
		var p3 = s.players[3]
		print("%4d| %4d,%4d | %4d %3d %s | %4d %3d %s" % [
			tick, FP.to_int(s.ball_x), FP.to_int(s.ball_y),
			FP.to_int(p3.x), p3.receive_stance, _in_str(in3),
			FP.to_int(p2.x), p2.receive_stance, _in_str(in2)])
		s.controlled_r = 0
		Simulation.tick(s, [0, in2], cfg)
		if s.last_touch_team == 1:
			print("  -> %d tick目に返球成功" % tick)
			return
		if s.phase != SimState.PHASE_RALLY:
			print("  -> 落球(見送り)")
			return
	print("  -> 60tick経過")

func _init() -> void:
	for t in TARGETS:
		_trace(SimCpu.PRESET_MAX, "最強", t)
		_trace(SimCpu.PRESET_NORMAL, "普通", t)
	quit(0)
