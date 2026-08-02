extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const Chars := preload("res://src/sim/chars.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
		p.drive_gauge = cfg.drive_gauge_max
	s.players[0].x = cfg.net_x - FP.from_int(124)
	s.players[1].x = cfg.net_x - FP.from_int(49)
	s.players[2].x = cfg.net_x + FP.from_int(156)
	s.players[3].x = cfg.net_x + FP.from_int(46)
	return [s, cfg]

func test_just_attack_recoils_attacker() -> void:
	# ジャストアタックの反作用: 打った本人がネットと逆(自陣側)へ小さく後退する
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(5)  # スイート内=ジャスト成立
	s.ball_y = p.y - FP.from_int(5)
	var x0: int = p.x
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 1, "ジャスト成立の前提確認")
	check(p.push < 0, "左チームの反動は左向き(ネットと逆)")
	# ジャスト後は瞬止+スローモーションで実時間が延びるため長めに待つ
	for i in 60:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check(p.x < x0, "反動で後退している")
	check(x0 - p.x < FP.from_int(40), "後退はコートの1割未満(吹っ飛びすぎない)")
	check_eq(p.push, 0, "反動は減衰して消える")

func test_normal_attack_no_recoil() -> void:
	# 芯を外した通常アタックは無反動
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.ball_x = p.x + FP.from_int(30)  # スイート外
	s.ball_y = p.y
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.ball_power, 0, "通常アタックの前提確認")
	check_eq(p.push, 0, "通常アタックは無反動")

func test_power_ball_touch_loses_control() -> void:
	# パワーボールを芯を外してトスすると制御を失う: 狙い成分3割+入射の全反射
	# =来た方向へ弾き返されるだけの球になる(まともなトスにならない)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	s.last_touch_team = 1  # 敵の打球
	s.ball_power = 1
	s.ball_x = p.x + FP.from_int(30)  # スイート外
	s.ball_y = cfg.floor_y - FP.from_int(10)
	var vin_x: int = FP.from_int(600) / cfg.tick_rate  # 右向きの強い入射
	s.ball_vx = vin_x
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check(s.ball_vx < -vin_x / 2, "下レシーブでも大きく左へ弾かれる(制御喪失)")
	check(p.flinch > 0 or p.stun_ticks > 0, "被弾リアクションも発生")

func test_just_receive_keeps_control() -> void:
	# ジャストで受ければパワーボールでも完全制御(狙い100%+慣性10%)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	# タイミング式の正規手順: 静止中の下+ボタン押下エッジで有効窓を開く。
	var receive_input: int = Simulation.IN_ACTION | Simulation.IN_DOWN
	Simulation._update_receive_stances(s, [receive_input, 0, 0, 0], cfg)
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	s.ball_x = p.x + FP.from_int(5)  # スイート内
	s.ball_y = cfg.floor_y - FP.from_int(10)
	var vin_x: int = FP.from_int(600) / cfg.tick_rate
	s.ball_vx = vin_x
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	Simulation.step(s, [receive_input, 0, 0, 0], cfg)
	check(absi(s.ball_vx) < vin_x / 2, "ジャスト受けは流されずほぼ狙い通り")
	check_eq(p.flinch, 0, "ジャスト受けは被弾しない")

func test_health_stun_does_not_blow_player_toward_wall() -> void:
	# 体力スタンはその場で転倒し、壁方向へ吹き飛ばさない。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.health = cfg.power_health_damage_for_rank(Chars.Profile.RANK_C)
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_health_damage = cfg.power_health_damage_for_rank(Chars.Profile.RANK_C)
	s.ball_x = p.x + FP.from_int(30)  # スイート外
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = -FP.from_int(600) / cfg.tick_rate
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION,
		cfg.player_reach * cfg.player_reach)
	check(p.stun_ticks > 0, "気絶の前提確認")
	check_eq(p.vx, 0, "体力スタンは後方初速なし")
	check_eq(p.push, 0, "体力スタンは壁方向押し出しなし")

func test_power_ball_block_pushes_blocker() -> void:
	# パワーボールをブロックすると小さく押し込まれる。通常球は無反動
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[2]  # 右チームのブロッカー
	p.x = cfg.net_x + FP.from_int(20)
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 0
	s.ball_power = 1
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate  # 右へ=右チームへ向かう
	s.ball_vy = 0
	Simulation.step(s, [0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0], cfg)
	check_eq(s.last_touch_team, 1, "ブロック成立の前提確認")
	check(p.push > 0, "右チームのブロッカーは右(後ろ)へ押し込まれる")

func test_normal_ball_block_no_push() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[2]
	p.x = cfg.net_x + FP.from_int(20)
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 0
	s.ball_power = 0
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate
	s.ball_vy = 0
	Simulation.step(s, [0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0], cfg)
	check_eq(s.last_touch_team, 1, "ブロック成立の前提確認")
	check_eq(p.push, 0, "通常球のブロックは無反動")
