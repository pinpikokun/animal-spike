# トス4種の実測プローブ: 同じ落下球を受けて最高到達高さと横移動を比較する
extends SceneTree

const FP := preload("res://src/sim/fp.gd")
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")

func _probe(label: String, input: int, vy_in_px: int) -> void:
	var cfg = Cfg.new()
	var s = St.new()
	s.phase = St.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(999999)  # 相方を遠ざける
	s.players[2].x = FP.from_int(380)
	s.players[3].x = FP.from_int(270)
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - FP.from_int(20)
	s.ball_vy = FP.from_int(vy_in_px) / cfg.tick_rate  # 落下中の入射
	s.ball_vx = 0
	var hit_y: int = s.ball_y
	# 数tick入力を保持(トス構えのホップ→ヒットの実序を再現)
	var hit_tick := -1
	for t in 10:
		Sim.step(s, [input, 0, 0, 0], cfg)
		if s.last_hit_tick > 0 and hit_tick < 0:
			hit_tick = t
			break
	if hit_tick < 0:
		print("%s: ヒットせず" % label)
		return
	var on_air := "空中" if s.players[0].on_ground == 0 else "地上"
	var top_y: int = s.ball_y
	var start_x: int = s.ball_x
	for t in 300:
		Sim.step(s, [0, 0, 0, 0], cfg)
		top_y = mini(top_y, s.ball_y)
		if s.ball_y >= cfg.floor_y - cfg.ball_radius:
			break
	var rise := FP.to_int(cfg.floor_y - top_y)
	var dx := FP.to_int(s.ball_x - start_x)
	print("%s: 判定=%s 上昇=%dpx 横移動=%dpx" % [label, on_air, rise, dx])

func _init() -> void:
	for vy in [300, 700]:
		print("=== 入射: 落下%dpx/s ===" % vy)
		_probe("ニュートラル(スペース)", Sim.IN_ACTION, vy)
		_probe("上+スペース", Sim.IN_ACTION | Sim.IN_JUMP | Sim.IN_UP, vy)
		_probe("右+スペース", Sim.IN_ACTION | Sim.IN_RIGHT, vy)
		_probe("上+右+スペース", Sim.IN_ACTION | Sim.IN_JUMP | Sim.IN_UP | Sim.IN_RIGHT, vy)
	quit()
