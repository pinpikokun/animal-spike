extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _serve_world(serving: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, serving)
	return [s, cfg]

func test_reset_match_positions() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	check_eq(s.phase, SimState.PHASE_SERVE, "SERVEフェーズ")
	check_eq(s.players[0].x, FP.from_int(cfg.spawn_back_px), "左後衛の初期位置")
	check_eq(s.players[2].x, cfg.court_width - FP.from_int(cfg.spawn_back_px), "右後衛の初期位置")
	check_eq(s.touches, 0, "タッチ0")

func test_reset_rally_keeps_player_positions() -> void:
	# ラリー再開でキャラをワープさせない(気持ちよさ優先、ユーザー決定)。
	# キャラは自分の足でしか動かない。定位置への帰還はCPUの歩行が担う
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	var moved_x: int = FP.from_int(123)
	s.players[0].x = moved_x
	Simulation.reset_rally(s, cfg, 1)
	check_eq(s.players[0].x, moved_x, "reset_rallyでキャラ位置が変わらない")
	check_eq(s.phase, SimState.PHASE_SERVE, "フェーズはSERVEに戻る")
	check_eq(s.touches, 0, "タッチはリセット")

func test_ball_held_by_server() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	for i in 10:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.ball_x, s.players[0].x, "ボールはサーバー頭上に固定(x)")
	check_eq(s.ball_y, s.players[0].y - cfg.serve_hold_height, "ボールはサーバー頭上に固定(y)")

func test_serve_launches_ball() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_RALLY, "サーブでRALLYへ")
	check(s.ball_vx > 0, "左サーブは右向き")
	check(s.ball_vy < 0, "サーブは上向き成分")

func test_floor_scores_opponent() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "左コートに落ちたら右チームの得点")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "得点後はポーズ")

func test_pause_then_new_serve_by_scorer() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	for i in cfg.point_pause_ticks + 1:
		Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.phase, SimState.PHASE_SERVE, "ポーズ後は次のサーブ")
	check_eq(s.serving_team, 1, "得点チームがサーブ")

func test_players_move_during_point_pause() -> void:
	# 得点後のポーズ中も操作は生かす(操作が死ぬ時間を作らない)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	var x0: int = s.players[0].x
	Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.players[0].x > x0, "ポーズ中も右移動できる")

func test_players_jump_during_point_pause() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	Simulation.step(s, [Simulation.IN_JUMP, 0, 0, 0], cfg)
	check_eq(s.players[0].on_ground, 0, "ポーズ中もジャンプできる")

func test_ball_bounces_on_floor_during_pause() -> void:
	# 得点後のポーズ中、ボールは凍結せず床で減衰バウンドする(得点はしない)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = FP.from_int(300)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vy < 0, "ポーズ中の床接触で上向きに反射")
	check_eq(s.score_l, 0, "ポーズ中の床接触は得点にならない(左)")
	check_eq(s.score_r, 0, "ポーズ中の床接触は得点にならない(右)")

func test_ball_bounce_damps_during_pause() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = FP.from_int(300)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	var v0: int = FP.from_int(100)
	s.ball_vy = v0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(-s.ball_vy < v0, "バウンドで速度が減衰する")

func test_ball_rolls_into_wall_during_pause() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = cfg.ball_radius + FP.from_int(1)
	s.ball_y = cfg.floor_y - cfg.ball_radius
	s.ball_vx = -FP.from_int(5)
	s.ball_vy = 0
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check(s.ball_vx > 0, "ポーズ中も壁で跳ね返る(慣性維持)")

func test_players_move_after_game_over() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_GAME_OVER
	s.winner = 1
	var x0: int = s.players[0].x
	Simulation.step(s, [Simulation.IN_RIGHT, 0, 0, 0], cfg)
	check(s.players[0].x > x0, "ゲームオーバー後も移動できる")

func test_touch_over_scores_opponent() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches
	s.last_touch_team = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "4タッチ目で相手の得点")

func test_third_touch_is_legal() -> void:
	# 仕様2.3「3回以内に相手コートへ返球」= 3タッチ目は合法、4タッチ目が反則
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches - 1
	s.last_touch_team = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, cfg.max_touches, "3タッチ目が数えられる")
	check_eq(s.score_r, 0, "3タッチ目では失点しない")
	check_eq(s.phase, SimState.PHASE_RALLY, "ラリーは続行する")

func test_touch_over_at_floor_scores_once() -> void:
	# タッチ超過失点と床接触が同一tickに重なっても得点は1回だけ(1ラリー2点の禁止)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.touches = cfg.max_touches
	s.last_touch_team = 0
	var p = s.players[0]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(10)
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(2)
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.score_r, 1, "同一tickの床接触で二重得点しない")

func test_hit_disabled_during_point_pause() -> void:
	# 掟1の但し書き: ポーズ中は移動・ジャンプ可でもヒットは無効(転がり演出と得点整合を守る)
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "ポーズ中はタッチが増えない")
	check_eq(s.players[0].hit_cooldown, 0, "ポーズ中は硬直も付かない")
	check_eq(s.ball_vx, 0, "ポーズ中のヒット入力でボールが加速しない")

func test_hit_disabled_after_game_over() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_GAME_OVER
	s.winner = 0
	s.ball_x = s.players[0].x + FP.from_int(5)
	s.ball_y = s.players[0].y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(s.touches, 0, "勝敗確定後はタッチが増えない")
	check_eq(s.ball_vx, 0, "勝敗確定後のヒット入力でボールが加速しない")

func test_win_at_15() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.score_r = cfg.points_to_win - 1
	s.score_l = 5
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(100)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.winner, 1, "15点で右チームの勝ち")
	check_eq(s.phase, SimState.PHASE_GAME_OVER, "ゲーム終了フェーズ")

func test_deuce_requires_two_point_lead() -> void:
	var w := _serve_world(0)
	var s = w[0]
	var cfg = w[1]
	s.score_l = cfg.points_to_win - 1
	s.score_r = cfg.points_to_win - 1
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(500)
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(1)
	s.ball_vy = FP.from_int(10)
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(s.score_l, cfg.points_to_win, "左が15点")
	check_eq(s.winner, -1, "14-15はデュースで未決着")
	check_eq(s.phase, SimState.PHASE_POINT_PAUSE, "続行")
