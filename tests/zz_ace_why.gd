extends SceneTree

# 使い捨て計測: デッドバンド中央へ落とした時、CPUの内部判断を毎tick表示する。
# 「誰がレシーバーか」「構えを選んだか」「その根拠の数値」を並べて、
# 入力ゼロで固まる理由を特定する。

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const STANDARD_CHAR := 99

func _in_str(v: int) -> String:
	var t := ""
	t += "L" if v & Simulation.IN_LEFT else "-"
	t += "R" if v & Simulation.IN_RIGHT else "-"
	t += "A" if v & Simulation.IN_ACTION else "-"
	t += "D" if v & Simulation.IN_DOWN else "-"
	return t

func _row(s, cfg, idx: int) -> String:
	var p = s.players[idx]
	var prof: int = p.cpu
	var land_x: int = SimCpu._receive_target_x(s, cfg, prof)
	var recv: bool = SimCpu._is_cpu_mate_receiver(s, idx, 1, land_x)
	var plans: bool = SimCpu._plans_just_receive(s, idx, p, 1, prof)
	var rr: int = HitResolver.reach_for_intent(
		p.char_id, cfg.player_reach, HitResolver.INTENT_GROUND_RECEIVE)
	var sdz: int = cfg.player_reach * cfg.spike_sweet_pct / 200
	var rz: int = maxi(rr - sdz, sdz)
	var can: bool = SimCpu._can_prepare_just_receive(s, p, cfg, rr, land_x, rz)
	var ct: int = SimCpu._ticks_until_receive_at(s, p, cfg, rr, land_x)
	var ct_here: int = SimCpu._ticks_until_receive_at(s, p, cfg, rr, p.x)
	var inp: int = SimCpu.decide(s, idx, cfg)
	var pos: int = SimCpu._decide_positioning(
		s, idx, p, cfg, 1, prof, cfg.player_reach / 2)
	var own: bool = (s.ball_x < cfg.net_x) == false
	return "x=%3d %s 位置取%s 自陣%s 落%3d 差%3d 担当%s 構想%s 準備%s 接触%3d ここ%3d" % [
		FP.to_int(p.x), _in_str(inp), _in_str(pos), "○" if own else "×",
		FP.to_int(land_x), FP.to_int(land_x) - FP.to_int(p.x),
		"○" if recv else "×", "○" if plans else "×", "○" if can else "×",
		ct, ct_here]

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
	print("=== %s 着弾狙い%dpx  遅延=%dtick リーチ=%d 間隔=%d ===" % [
		label, target_px, SimCpu.prof_byte(prof, SimCpu.P_DELAY),
		FP.to_int(cfg.player_reach), FP.to_int(cfg.cpu_mate_spacing)])
	for tick in 40:
		var frozen: bool = s.tick - s.last_hit_tick \
			< SimCpu.prof_byte(prof, SimCpu.P_DELAY)
		var in2: int = SimCpu.decide(s, 2, cfg)
		print("%3d %s | 前衛 %s" % [
			tick, "凍" if frozen else "動", _row(s, cfg, 3)])
		print("        | 後衛 %s" % _row(s, cfg, 2))
		Simulation.tick(s, [0, in2], cfg)
		if s.last_touch_team == 1:
			print("  -> %d tick目に返球成功" % tick)
			return
		if s.phase != SimState.PHASE_RALLY:
			print("  -> 落球(見送り)")
			return

func _init() -> void:
	# ミス抽選と狙い誤差を抜いた最強。残る構造的な穴だけを見る
	var ab: int = SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_AB)
	var clean: int = SimCpu.make_profile(ab,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_DELAY), 0, 0,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_SWEET),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_DEPTH),
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_TIQ))
	_trace(clean, "最強-誤差ミスなし", 344)
	_trace(clean, "最強-誤差ミスなし", 352)
	quit(0)
