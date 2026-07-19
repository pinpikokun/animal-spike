# パワーボール芯外し被弾: 地上vs空中の吹っ飛び距離比較
extends SceneTree
const FP := preload("res://src/sim/fp.gd")
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")

func _case(label: String, airborne: bool) -> void:
	var cfg = Cfg.new()
	var s = St.new()
	s.phase = St.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(150)
	s.players[1].x = FP.from_int(999999)
	s.players[2].x = FP.from_int(380)
	s.players[3].x = FP.from_int(270)
	var p = s.players[0]
	if airborne:
		p.on_ground = 0
		p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_x = p.x + FP.from_int(30)
	s.ball_y = p.y - FP.from_int(10)
	s.ball_vx = -FP.from_int(600) / cfg.tick_rate
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	var x0: int = p.x
	Sim.step(s, [Sim.IN_ACTION, 0, 0, 0], cfg)
	for t in 90:
		Sim.step(s, [0, 0, 0, 0], cfg)
	print("%s: 後退距離=%dpx" % [label, FP.to_int(x0 - p.x)])

func _init() -> void:
	_case("地上で芯外し被弾", false)
	_case("空中で芯外し被弾", true)
	quit()
