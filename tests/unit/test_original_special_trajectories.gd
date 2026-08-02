extends "res://tests/test_case.gd"

const BallPhysics := preload("res://src/sim/ball_physics.gd")
const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SpecialBall := preload("res://src/sim/special_ball.gd")

func _world() -> Array:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_TOME, Chars.CHAR_HITO, Chars.CHAR_PIYO, Chars.CHAR_UME],
		0, 0)
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x - FP.from_int(100)
	s.ball_y = cfg.net_top_y - FP.from_int(80)
	s.ball_vx = FP.from_int(180) / cfg.tick_rate
	s.ball_vy = -FP.from_int(120) / cfg.tick_rate
	return [s, cfg]

func _original_vx(original_vx: int, cfg) -> int:
	var result: int = original_vx * (cfg.court_width / 2) \
		* cfg.original_tick_rate_milli / (72 * cfg.tick_rate * 1000)
	if result == 0 and original_vx != 0:
		return 1 if original_vx > 0 else -1
	return result

func _original_vy(original_vy: int, cfg) -> int:
	var result: int = original_vy * (cfg.floor_y - cfg.net_top_y) \
		* cfg.original_tick_rate_milli / (33 * cfg.tick_rate * 1000)
	if result == 0 and original_vy != 0:
		return 1 if original_vy > 0 else -1
	return result

func _below_original_line_y(original_y: int, cfg) -> int:
	var height: int = ((291 - original_y) * (cfg.floor_y - cfg.net_top_y) + 32) / 33
	return cfg.floor_y - height + 1

func _step_n(s, cfg, count: int) -> void:
	for _i in count:
		BallPhysics._step_ball(s, cfg)

func test_disappearing_ball_has_exact_slow_window_then_waits_for_descent_line() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var start_x: int = s.ball_x
	var expected_y: int = s.ball_y
	var expected_vy: int = s.ball_vy
	var vx: int = s.ball_vx
	SpecialBall.set_special(s, Chars.SUPER_DISAPPEARING_BALL, 1, vx)
	for tick in 21:
		if tick % 2 == 0:
			start_x += vx
		expected_y += expected_vy / 2
		expected_vy += cfg.gravity / 2
		BallPhysics._step_ball(s, cfg)
		check(not SpecialBall.is_visible(s), "減速中も不可視")
		check(not SpecialBall.is_contactable(s), "減速中も非接触")
	check_eq(s.ball_x, start_x, "21tickは横を隔tickで進める")
	check_eq(s.ball_y, expected_y, "21tickは縦を半速で進める")
	check_eq(s.ball_vy, expected_vy, "21tickは重力を半速で進める")
	check_eq(s.ball_special_phase, 1, "21tick後は通常速度待機へ移る")
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_special_id, Chars.SUPER_DISAPPEARING_BALL,
		"時間だけでは再出現しない")
	s.ball_y = _below_original_line_y(224, cfg)
	s.ball_vy = -cfg.gravity
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_special_id, Chars.SUPER_DISAPPEARING_BALL,
		"再出現線より下でも下降前は戻らない")
	s.ball_y = _below_original_line_y(224, cfg)
	s.ball_vy = 1
	var before_reappear_x: int = s.ball_x
	var before_reappear_vx: int = s.ball_vx
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_special_id, 0, "下降して原作y224線を越えると通常化")
	check_eq(s.ball_x, before_reappear_x + before_reappear_vx,
		"復帰tickの横移動は一回だけ")
	check_eq(s.ball_vx, before_reappear_vx / 2, "再出現時は横速度半分")
	check_eq(s.ball_vy, _original_vy(8, cfg), "再出現時は原作下8")

func test_feint_accelerates_on_twenty_first_tick_without_disappearing() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var initial_vx: int = s.ball_vx
	SpecialBall.set_special(s, Chars.SUPER_FEINT_ATTACK, 1, initial_vx)
	_step_n(s, cfg, 20)
	check_eq(s.ball_vx, initial_vx, "20tickまでは加速しない")
	check(SpecialBall.is_visible(s) and SpecialBall.is_contactable(s),
		"フェイントは遅延中も見えて触れる")
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_special_phase, 1, "21tickで攻撃段階へ移る")
	check_eq(s.ball_vx, initial_vx + _original_vx(2, cfg),
		"進行方向へ原作横2を加える")
	check_eq(s.ball_vy, _original_vy(16, cfg), "原作下16で落とす")
	check_eq(s.ball_special_id, Chars.SUPER_FEINT_ATTACK,
		"防御判定までフェイントIDを維持")

func test_transfer_uses_normal_motion_and_reappears_at_thirteen_ticks_or_line() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var initial_vx: int = s.ball_vx
	var expected_x: int = s.ball_x
	SpecialBall.set_special(s, Chars.SUPER_TRANSFER_BALL, 0, initial_vx)
	for _i in 12:
		expected_x += initial_vx
		BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_x, expected_x, "転送は消失中も通常横速度")
	check_eq(s.ball_special_id, Chars.SUPER_TRANSFER_BALL, "12tickは消失中")
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_special_id, 0, "13tickで再出現")
	check_eq(s.ball_vx, initial_vx / 2, "転送復帰時は横速度半分")
	check_eq(s.ball_vy, _original_vy(8, cfg), "転送復帰時は原作下8")

	var w2 := _world(); var line_state = w2[0]
	line_state.ball_y = _below_original_line_y(240, cfg)
	line_state.ball_vy = 0
	SpecialBall.set_special(line_state, Chars.SUPER_TRANSFER_BALL, 0,
		line_state.ball_vx)
	BallPhysics._step_ball(line_state, cfg)
	check_eq(line_state.ball_special_id, 0, "y240線なら13tick前でも再出現")

func test_gust_and_snake_keep_base_speed_and_close_one_wave_in_thirty_four_ticks() -> void:
	var w := _world(); var gust = w[0]; var cfg = w[1]
	gust.ball_y = cfg.net_top_y - FP.from_int(400)
	gust.ball_vy = -FP.from_int(20) / cfg.tick_rate
	gust.ball_vx = FP.from_int(60) / cfg.tick_rate
	var snake := SimState.new()
	snake.load_int_array(gust.to_int_array())
	var base_vx: int = gust.ball_vx
	var start_x: int = gust.ball_x
	SpecialBall.set_special(gust, Chars.SUPER_GUST_BALL, 2, base_vx)
	SpecialBall.set_special(snake, Chars.SUPER_SNAKE_BALL, 3, base_vx)
	_step_n(gust, cfg, 34)
	_step_n(snake, cfg, 34)
	check_eq(gust.ball_x, start_x + base_vx * 34,
		"突風の一周期は基礎速度へ戻る")
	check_eq(snake.ball_x, start_x + base_vx * 34,
		"蛇の一周期も基礎速度へ戻る")
	check_eq(gust.ball_special_ticks, 34, "突風周期を同期状態で数える")
	check_eq(snake.ball_special_ticks, 34, "蛇周期を同期状態で数える")

	var w3 := _world(); var gust_one = w3[0]
	var snake_one := SimState.new(); snake_one.load_int_array(gust_one.to_int_array())
	SpecialBall.set_special(gust_one, Chars.SUPER_GUST_BALL, 2, base_vx)
	SpecialBall.set_special(snake_one, Chars.SUPER_SNAKE_BALL, 3, base_vx)
	var base_next_x: int = gust_one.ball_x + base_vx
	BallPhysics._step_ball(gust_one, cfg)
	BallPhysics._step_ball(snake_one, cfg)
	check_eq(snake_one.ball_x - base_next_x,
		(gust_one.ball_x - base_next_x) * 2, "蛇の横振幅は突風の2倍")

func test_ghost_uses_defender_avoidance_instead_of_plain_parabola() -> void:
	var w := _world(); var ghost = w[0]; var cfg = w[1]
	var plain := SimState.new(); plain.load_int_array(ghost.to_int_array())
	ghost.ball_x = cfg.net_x + FP.from_int(20)
	plain.ball_x = ghost.ball_x
	ghost.ball_y = cfg.net_top_y - FP.from_int(100)
	plain.ball_y = ghost.ball_y
	ghost.ball_vx = FP.from_int(60) / cfg.tick_rate
	plain.ball_vx = ghost.ball_vx
	ghost.ball_vy = FP.from_int(120) / cfg.tick_rate
	plain.ball_vy = ghost.ball_vy
	ghost.players[2].x = cfg.court_width - FP.from_int(40)
	ghost.players[3].x = cfg.court_width - FP.from_int(80)
	SpecialBall.set_special(ghost, Chars.SUPER_GHOST_BALL, 0, ghost.ball_vx)
	BallPhysics._step_ball(ghost, cfg)
	BallPhysics._step_ball(plain, cfg)
	check(ghost.ball_x > plain.ball_x, "守備者から遠い時は相手奥へ専用加速")
	check(ghost.ball_y < plain.ball_y, "守備者から遠い時は縦進行を抑える")
	check_eq(ghost.ball_special_id, Chars.SUPER_GHOST_BALL,
		"相手コートへ入ってもゴーストを維持")

	var near := SimState.new(); near.load_int_array(plain.to_int_array())
	near.ball_x = cfg.net_x + FP.from_int(20)
	near.ball_y = cfg.net_top_y - FP.from_int(100)
	near.ball_vx = FP.from_int(60) / cfg.tick_rate
	near.ball_vy = FP.from_int(120) / cfg.tick_rate
	near.players[2].x = near.ball_x + near.ball_vx
	near.players[3].x = cfg.court_width - FP.from_int(20)
	SpecialBall.set_special(near, Chars.SUPER_GHOST_BALL, 0, near.ball_vx)
	BallPhysics._step_ball(near, cfg)
	check(near.ball_x < ghost.ball_x, "守備者が近い時は遠方分岐と別の回避を行う")
	check(near.ball_y > ghost.ball_y, "近接分岐は原作下8相当で守備者をかわす")

func test_custom_trajectory_still_runs_wall_collision_pipeline() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	s.ball_x = cfg.court_width - cfg.ball_radius - 1
	s.ball_y = cfg.net_top_y - FP.from_int(60)
	s.ball_vx = FP.from_int(1200) / cfg.tick_rate
	s.ball_vy = 0
	SpecialBall.set_special(s, Chars.SUPER_GUST_BALL, 2, s.ball_vx)
	BallPhysics._step_ball(s, cfg)
	check(s.ball_vx < 0, "専用軌道でも壁で反射")
	check_eq(s.ball_special_id, 0, "壁接触で特殊球を解除")

func test_snapshot_restore_replays_special_trajectories_bit_exactly() -> void:
	for special_id in [Chars.SUPER_GHOST_BALL, Chars.SUPER_DISAPPEARING_BALL,
			Chars.SUPER_FEINT_ATTACK, Chars.SUPER_GUST_BALL,
			Chars.SUPER_SNAKE_BALL, Chars.SUPER_TRANSFER_BALL]:
		var w := _world(); var a = w[0]; var cfg = w[1]
		SpecialBall.set_special(a, special_id, 0, a.ball_vx)
		_step_n(a, cfg, 7)
		var b := SimState.new(); b.load_int_array(a.to_int_array())
		_step_n(a, cfg, 60)
		_step_n(b, cfg, 60)
		check_eq(a.state_hash(), b.state_hash(),
			"snapshot復元後も軌道一致: %d" % special_id)
