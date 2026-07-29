extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")

const SAMPLE_STEP_PX := 20
const FARTHEST_HIT_D_PX := 280
const NEAREST_HIT_D_PX := 40
const GROUND_HIT_H_PX := 20


func _fast_incoming_vx(cfg) -> int:
	var standard_spike_vx: int = cfg.spike_vx * cfg.spike_normal_pct / 100
	return maxi(standard_spike_vx, cfg.serve_power)


func _descending_samples(high: int, low: int) -> Array[int]:
	var result: Array[int] = []
	var value: int = high
	while value > low:
		result.append(value)
		value -= SAMPLE_STEP_PX
	if result.is_empty() or result[-1] != low:
		result.append(low)
	return result


func _ascending_samples(low: int, high: int) -> Array[int]:
	var result: Array[int] = []
	var value: int = low
	while value < high:
		result.append(value)
		value += SAMPLE_STEP_PX
	if result.is_empty() or result[-1] != high:
		result.append(high)
	return result


func _lands_cleanly_in_opponent(start_x: int, start_y: int, vx: int, vy: int,
		team: int, cfg) -> Array:
	var s = SimState.new()
	s.ball_x = start_x
	s.ball_y = start_y
	s.ball_vx = vx
	s.ball_vy = vy
	var crossed_net := false
	var hit_obstacle := false
	for _tick in 600:
		var before_vx: int = s.ball_vx
		var free_vy: int = s.ball_vy + cfg.gravity
		BallPhysics._step_ball(s, cfg)
		if s.ball_vx != before_vx or s.ball_vy != free_vy:
			hit_obstacle = true
		if (team == 0 and s.ball_x > cfg.net_x) \
				or (team == 1 and s.ball_x < cfg.net_x):
			crossed_net = true
		if s.ball_y >= cfg.floor_y - cfg.ball_radius and s.ball_vy > 0:
			var beyond_net: bool = s.ball_x > cfg.net_x \
				if team == 0 else s.ball_x < cfg.net_x
			var before_wall: bool = s.ball_x < cfg.court_width - cfg.ball_radius \
				if team == 0 else s.ball_x > cfg.ball_radius
			return [
				not hit_obstacle and crossed_net and beyond_net and before_wall,
				s.ball_x,
			]
	return [false, s.ball_x]


func test_every_return_sample_lands_cleanly_in_opponent_court() -> void:
	var cfg = SimConfig.new()
	# 6.4.5。距離端点と地上高20pxは5節の実測範囲、最高点は既存Aジャンプ。
	var distances: Array[int] = _descending_samples(
		FARTHEST_HIT_D_PX, NEAREST_HIT_D_PX)
	var highest_h: int = Chars.Profile.jump_height_px(Chars.Profile.RANK_A)
	var heights: Array[int] = _ascending_samples(GROUND_HIT_H_PX, highest_h)
	var incoming_max: int = _fast_incoming_vx(cfg)
	var incoming_speeds: Array[int] = [-incoming_max, 0, incoming_max]
	var traits: Array[int] = [
		Chars.CHAR_MARIO,
		Chars.CHAR_FOX,
		Chars.CHAR_PANDA,
	]
	var launch_speeds: Array[int] = [-cfg.bump_up_speed, -cfg.toss_fwd_vy]
	var cases := 0
	for team in 2:
		var dir: int = 1 if team == 0 else -1
		for d in distances:
			var start_x: int = cfg.net_x - dir * FP.from_int(d)
			for h in heights:
				var start_y: int = cfg.floor_y - FP.from_int(h)
				for char_id in traits:
					for incoming_vx in incoming_speeds:
						for launch_vy in launch_speeds:
							var vx: int = HitResolver.opponent_return_vx(
								start_x, start_y, incoming_vx, team, char_id, cfg)
							var result: Array = _lands_cleanly_in_opponent(
								start_x, start_y, vx, launch_vy, team, cfg)
							cases += 1
							check(result[0],
								("敵陣へ入る: team=%d d=%d h=%d char=%d incoming=%d "
								+ "launch=%d land=%d") % [
									team, d, h, char_id, incoming_vx,
									launch_vy, result[1],
								])
	check(cases > 0, "網羅検査が1通り以上を実行する")
	for i in distances.size() - 1:
		check(distances[i] - distances[i + 1] <= SAMPLE_STEP_PX,
			"打点距離の刻みは20px以下")
	for i in heights.size() - 1:
		check(heights[i + 1] - heights[i] <= SAMPLE_STEP_PX,
			"打点高さの刻みは20px以下")


func test_opponent_return_is_deterministic() -> void:
	var cfg = SimConfig.new()
	var start_x: int = cfg.net_x - FP.from_int(120)
	var start_y: int = cfg.floor_y - FP.from_int(80)
	var incoming_vx: int = -_fast_incoming_vx(cfg)
	var first: int = HitResolver.opponent_return_vx(
		start_x, start_y, incoming_vx, 0, Chars.CHAR_PANDA, cfg)
	var second: int = HitResolver.opponent_return_vx(
		start_x, start_y, incoming_vx, 0, Chars.CHAR_PANDA, cfg)
	check_eq(first, second, "同じ打点・入射・特性なら横速度が完全一致")


func test_third_air_toss_uses_same_opponent_return_formula() -> void:
	for team in 2:
		var cfg = SimConfig.new()
		var s = SimState.new()
		var actor: int = team * 2
		var dir: int = SimState._dir_of_team(team)
		var p = s.players[actor]
		p.char_id = Chars.CHAR_PANDA
		p.on_ground = 0
		p.y = cfg.floor_y - FP.from_int(80)
		s.last_touch_team = team
		s.touches = cfg.max_touches - 1
		s.ball_x = cfg.net_x - dir * FP.from_int(120)
		s.ball_y = p.y
		s.ball_vx = -dir * _fast_incoming_vx(cfg)
		var expected_vx: int = HitResolver.opponent_return_vx(
			s.ball_x, s.ball_y, s.ball_vx, team, p.char_id, cfg)
		HitResolver._apply_hit(s, actor, cfg, SimInput.IN_ACTION, 0)
		check_eq(s.ball_vx, expected_vx,
			"3打目の空中トスは地上と同じ敵陣返球式: team=%d" % team)
		check_eq(s.ball_vy, -cfg.toss_fwd_vy,
			"空中トスの上向き速度は既存値を維持: team=%d" % team)


func test_ground_opponent_return_ignores_mangled_aim_reduction() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var p = s.players[0]
	p.char_id = Chars.CHAR_FOX
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_x = cfg.net_x - FP.from_int(120)
	s.ball_y = cfg.floor_y - FP.from_int(20)
	s.ball_vx = -_fast_incoming_vx(cfg)
	var expected_vx: int = HitResolver.opponent_return_vx(
		s.ball_x, s.ball_y, s.ball_vx, 0, p.char_id, cfg)
	HitResolver._apply_hit(
		s, 0, cfg, SimInput.IN_ACTION | SimInput.IN_RIGHT,
		cfg.player_reach * cfg.player_reach)
	check_eq(s.ball_vx, expected_vx,
		"芯外しでも敵陣返球の横速度は4要素の式だけで決まる")
	check_eq(s.ball_vy, -cfg.bump_up_speed,
		"芯外しでも敵陣返球の上向き速度は既存値を維持")


func test_toss_good_and_bad_land_differently_but_both_stay_in() -> void:
	var cfg = SimConfig.new()
	var start_x: int = cfg.ball_radius
	var start_y: int = cfg.floor_y - FP.from_int(20)
	var incoming_vx: int = _fast_incoming_vx(cfg)
	var good_vx: int = HitResolver.opponent_return_vx(
		start_x, start_y, incoming_vx, 0, Chars.CHAR_MARIO, cfg)
	var bad_vx: int = HitResolver.opponent_return_vx(
		start_x, start_y, incoming_vx, 0, Chars.CHAR_PANDA, cfg)
	var good: Array = _lands_cleanly_in_opponent(
		start_x, start_y, good_vx, -cfg.bump_up_speed, 0, cfg)
	var bad: Array = _lands_cleanly_in_opponent(
		start_x, start_y, bad_vx, -cfg.bump_up_speed, 0, cfg)
	check(good[0], "トス上手の速い入射返球も敵陣へ入る")
	check(bad[0], "トス下手の速い入射返球も敵陣へ入る")
	check(good[1] != bad[1], "トス上手と下手で速い入射の落下点が変わる")
