extends SceneTree

# 使い捨て探索: 「水平では旧構え帯だが、その立ち位置では楕円リーチに入らない」
# 配置を総当たりで作り、CPUの入力を出力する。
# 修正前ツリーと修正後ツリーで同じ出力を取り、差が出る配置番号を特定するのが目的。

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const STANDARD_CHAR := 99

func _sweet_key(actor: int, threshold: int) -> int:
	for key in 4000:
		if SimCpu._noise(SimCpu.SALT_RECEIVE, key, actor) % 256 < threshold:
			return key
	return 0

func _init() -> void:
	var idx := 2
	var key: int = _sweet_key(idx,
		SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_SWEET))
	var offsets: Array[int] = [-40, -32, -24, -16, -8, 0, 8, 16, 24, 32, 40]
	var vxs: Array[int] = [40, 60, 80, 100, 140]
	var vys: Array[int] = [10, 30, 50, 80]
	var drops: Array[int] = [60, 90, 120, 150]
	var n := 0
	for drop in drops:
		for vx in vxs:
			for vy in vys:
				for off in offsets:
					n += 1
					var cfg = SimConfig.new()
					var s = SimState.new()
					Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR,
						STANDARD_CHAR, STANDARD_CHAR, STANDARD_CHAR])
					s.phase = SimState.PHASE_RALLY
					s.tick = 1000
					s.last_hit_tick = key
					s.last_touch_team = 0
					s.touches = 1
					s.serve_flight = 0
					s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
					s.ball_x = cfg.net_x + FP.from_int(20)
					s.ball_y = cfg.floor_y - FP.from_int(drop)
					s.ball_vx = FP.from_int(vx)
					s.ball_vy = FP.from_int(vy)
					var p = s.players[idx]
					p.cpu = SimCpu.PRESET_MAX
					p.y = cfg.floor_y
					p.vx = 0
					p.vy = 0
					p.on_ground = 1
					var land_x: int = SimCpu._receive_target_x(s, cfg, p.cpu)
					var rr: int = SimCpu._hit_reach(p.char_id, cfg.player_reach,
						HitResolver.INTENT_GROUND_RECEIVE)
					var sdz: int = cfg.player_reach * cfg.spike_sweet_pct / 200
					var old_zone: int = maxi(rr - sdz, sdz)
					p.x = land_x + FP.from_int(off)
					if p.x < cfg.player_reach \
							or p.x > cfg.court_width - cfg.player_reach:
						continue
					if absi(p.x - land_x) > old_zone:
						continue
					if SimCpu._ticks_until_receive_at(s, p, cfg, rr, p.x) != 181:
						continue
					var inp: int = SimCpu.decide(s, idx, cfg)
					var moves: int = 1 if inp & (Simulation.IN_LEFT \
						| Simulation.IN_RIGHT) else 0
					print("%d drop=%d vx=%d vy=%d off=%d land=%d 歩く=%d 入力=%d" % [
						n, drop, vx, vy, off, FP.to_int(land_x), moves, inp])
	quit(0)
