extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const Chars := preload("res://src/sim/chars.gd")

func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		# 基礎物理テストへパンダの付与能力を混入させない。
		p.char_id = Chars.CHAR_FOX
		p.y = cfg.floor_y
	s.players[0].x = cfg.net_x - FP.from_int(124)
	s.players[1].x = cfg.net_x - FP.from_int(49)
	s.players[2].x = cfg.net_x + FP.from_int(156)
	s.players[3].x = cfg.net_x + FP.from_int(46)
	return [s, cfg]

func test_wall_always_damps_reflection_to_half() -> void:
	# 原作ルール: 壁は設定分岐なしで横速度を50%維持する
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(2)
	s.ball_y = FP.from_int(100)
	var vin: int = -FP.from_int(200) / cfg.tick_rate
	s.ball_vx = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vx, -vin * 50 / 100, "壁反射50%で勢い半減")

func test_power_ball_loses_power_and_vertical_momentum_at_wall() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(2)
	s.ball_y = FP.from_int(100)
	var vin: int = -FP.from_int(200) / cfg.tick_rate
	s.ball_vx = vin
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	s.ball_power = 1
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vx, -vin * 50 / 100, "パワーボールも壁横速度50%")
	check_eq(s.ball_power, 0, "壁でパワー状態を失う")
	check(s.ball_vy < (FP.from_int(300) / cfg.tick_rate + cfg.gravity),
		"壁で縦の勢いも失う")

func test_net_top_always_bounces_and_pushes_out() -> void:
	# 原作ルール: 落下中に白帯へ当たると縦半減で跳ね、ネットから離れる横へ
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = cfg.net_x - FP.from_int(1)  # 左側からネット直上へ
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vx = 0
	var vin: int = FP.from_int(300) / cfg.tick_rate
	s.ball_vy = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_vy, -(vin + cfg.gravity) / 2,
		"上端で落下速度を半減して跳ね上がる")
	check_eq(s.ball_vx, -cfg.net_repel / 2,
		"左側の球は左(ネットから離れる向き)へ押し出される")

func test_traitless_toss_keeps_direct_output_without_global_toggle() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	var offset_vx: int = FP.from_int(5) * cfg.receive_offset_gain_pct \
		/ 100 / cfg.tick_rate
	check(absi(s.ball_vx - offset_vx) <= cfg.receive_scatter,
		"素レシーブ横速度は5pxの接触項から散り幅内に収まる")

func test_player_stops_before_net_face() -> void:
	# ネットめり込み防止: 体の半幅(8px)ぶん手前で止まる
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = FP.from_int(30)
	s.ball_y = -FP.from_int(2000)  # ボールを遠ざけて干渉させない
	s.ball_vy = -FP.from_int(500) / cfg.tick_rate
	for i in 60:
		Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	var face: int = cfg.net_x - cfg.net_half_w - FP.from_int(8)
	check_eq(s.players[0].x, face, "左チームはネット面の8px手前で停止")
	for i in 60:
		Simulation.step(s, [0, 0, Simulation.IN_LEFT, 0], cfg)
	var face_r: int = cfg.net_x + cfg.net_half_w + FP.from_int(8)
	check_eq(s.players[2].x, face_r, "右チームも対称に停止")

func _air_toss_vy(vin_px: int) -> int:
	# 空中ニュートラルトスを1回行い、直後のボール縦速度を返す。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(40)
	# スイート判定(24px)の外、リーチ(40px)の内に置く=通常ヒットで慣性30%が乗る
	s.ball_x = p.x + FP.from_int(30)
	s.ball_y = p.y
	s.ball_vy = FP.from_int(vin_px) / cfg.tick_rate
	s.ball_vx = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	return s.ball_vy

func test_air_opponent_return_keeps_existing_upward_speed() -> void:
	# 敵陣へ送る空中球は横の入射だけを新しい係数へ入れ、縦速度は既存値のまま。
	var soft: int = _air_toss_vy(100)
	var hard: int = _air_toss_vy(700)
	check(soft < 0 and hard < 0, "どちらも上向きに打ち上がる")
	check_eq(hard, soft, "入射の縦速度は空中返球の上向き速度を変えない")

func test_soft_ball_gives_full_control() -> void:
	# 特性なしキャラは緩い球を通常高度で完全制御する。
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(30)  # スイート外=通常ヒット
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = FP.from_int(100) / cfg.tick_rate  # 緩い球(閾値400未満)
	s.ball_vy = FP.from_int(200) / cfg.tick_rate
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "緩い球のニュートラルトスは自陣前方へ進む")
	check_eq(s.ball_vy, -cfg.ally_ground_toss_up + cfg.gravity,
		"特性なしの緩球トスは通常高度")

func test_fast_ball_still_pushes_through() -> void:
	# 強い入射球でもトスの縦速度は増幅しない
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.ball_x = s.players[0].x + FP.from_int(30)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = FP.from_int(700) / cfg.tick_rate  # 強い落下球
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.ball_vy, -cfg.ally_ground_toss_up + cfg.gravity,
		"強い球でも基準より高いトスにしない")

func test_loose_floor_bounce_is_half() -> void:
	# ポーズ中の床バウンドは勢い半分(設定なしの固定仕様)
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = 1000  # ポーズが明けないよう長めに
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	var vin: int = FP.from_int(300) / cfg.tick_rate
	s.ball_vy = vin
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "床で跳ね返る")
	var bounced: int = -(vin + cfg.gravity) * 50 / 100 + cfg.ball_rest_speed / 4
	check(absi(s.ball_vy - bounced) <= absi(bounced) / 5 + 1, "反発はおよそ勢い半分")
