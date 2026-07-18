# 空中でパワーボールを芯外しタッチした時のノックバック実測
extends SceneTree
const FP := preload("res://src/sim/fp.gd")
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")

func _init() -> void:
	var cfg = Cfg.new()
	var s = St.new()
	s.phase = St.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(999999)
	s.players[2].x = FP.from_int(380)
	s.players[3].x = FP.from_int(270)
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_x = p.x + FP.from_int(30)
	s.ball_y = p.y
	s.ball_vx = -FP.from_int(600) / cfg.tick_rate
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	var x0: int = p.x
	Sim.step(s, [Sim.IN_ACTION | Sim.IN_UP, 0, 0, 0], cfg)
	print("hit直後: flinch=%d stun=%d vx=%d(fp/t) guard=%d" % [p.flinch, p.stun, p.vx, p.guard])
	for t in 60:
		Sim.step(s, [0, 0, 0, 0], cfg)
	print("60tick後: x変位=%dpx on_ground=%d" % [FP.to_int(p.x - x0), p.on_ground])
	quit()
