extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const SimRng := preload("res://src/sim/sim_rng.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

const STANDARD_CHAR := 99

const AITICK_BY_RESIDUE: Array[int] = [0, 1, 13, 2, 5, 3, 15, 11, 23, 10]

func test_air_shot_policy_mapping_is_three_three_three_one() -> void:
	var s = SimState.new()
	for residue in 10:
		s.aitick = AITICK_BY_RESIDUE[residue]
		check_eq(SimRng.derived_value(s.aitick, 0, 8) % 10, residue,
			"固定aitickが政策剰余を作る")
		var expected_policy: int = residue / 3 if residue < 9 else 3
		check_eq(SimCpu._air_shot_policy(s), expected_policy,
			"政策写像 residue=" + str(residue))

func test_air_shot_policy_does_not_change_state() -> void:
	var s = SimState.new()
	s.aitick = AITICK_BY_RESIDUE[8]
	var before: Array[int] = s.to_int_array()
	SimCpu._air_shot_policy(s)
	check_eq(s.to_int_array(), before, "政策抽選は同期状態を変更しない")

func _root_cause_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var actor := 0
	var p = s.players[actor]
	p.char_id = STANDARD_CHAR
	p.cpu = SimCpu.make_profile(SimCpu.AB_ATTACK, 0, 0, 0, 0, 3, 3)
	p.on_ground = 0
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x - FP.from_int(50)
	s.ball_y = cfg.net_top_y - FP.from_int(25)
	p.x = s.ball_x
	s.ball_vx = 0
	s.ball_vy = -FP.from_int(4)
	s.aitick = AITICK_BY_RESIDUE[3]
	return [s, cfg, actor]

func test_policy_two_uses_flat_spike_from_real_velocity() -> void:
	var w := _root_cause_world()
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var p = s.players[actor]
	var d2: int = cfg.player_reach * cfg.player_reach
	var input: int = Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT
	var actual_velocity: Vector2i = HitResolver.preview_air_spike_velocity(
		s, actor, cfg, input, d2)
	var old_vy: int = cfg.spike_vy * cfg.spike_normal_pct / 100 \
		- s.ball_vy * cfg.hit_inertia_num / cfg.hit_inertia_den
	var old_vx: int = HitResolver.toss_aim_vx(
		s.ball_x, s.ball_y, cfg.spike_vy * cfg.spike_normal_pct / 100,
		HitResolver.spike_target_x(0, 1, cfg), cfg) \
		- s.ball_vx * cfg.hit_inertia_num / cfg.hit_inertia_den
	check(not SimCpu._clears_net(s.ball_x, s.ball_y, old_vx, old_vy, cfg),
		"旧着地点逆算の③奥はネット判定で偽陰性")
	check(SimCpu._clears_net(
		s.ball_x, s.ball_y, actual_velocity.x, actual_velocity.y, cfg),
		"同じ状態の実打球速度はネットを越える")
	var decided: int = SimCpu._decide_air_hit(
		s, actor, p, cfg, 0, p.cpu, d2, 0)
	check_eq(decided, input, "政策2は有効な③奥を採用する")

func _all_candidates_world(residue: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var actor := 0
	var p = s.players[actor]
	p.char_id = STANDARD_CHAR
	p.cpu = SimCpu.make_profile(SimCpu.AB_ATTACK, 0, 0, 0, 0, 3, 3)
	p.on_ground = 0
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x - FP.from_int(60)
	s.ball_y = cfg.net_top_y - FP.from_int(100)
	p.x = s.ball_x
	s.ball_vx = 0
	s.ball_vy = 0
	s.players[2].x = cfg.net_x + FP.from_int(20)
	s.players[3].x = cfg.net_x + FP.from_int(40)
	s.aitick = AITICK_BY_RESIDUE[residue]
	return [s, cfg, actor]

func _decide_fixture(w: Array) -> int:
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	return SimCpu._decide_air_hit(
		s, actor, s.players[actor], cfg, 0, s.players[actor].cpu,
		cfg.player_reach * cfg.player_reach, 0)

func test_policy_one_uses_first_valid_candidate() -> void:
	var decided: int = _decide_fixture(_all_candidates_world(0))
	check_eq(decided,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		"政策1は①手前から走査して最初の有効候補で止まる")

func test_policy_three_uses_candidate_farthest_from_both_opponents() -> void:
	var w := _all_candidates_world(6)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var d2: int = cfg.player_reach * cfg.player_reach
	var lands: Array[int] = []
	for relative in [-1, 0, 1]:
		var input: int = Simulation.IN_ACTION | Simulation.IN_DOWN
		if relative < 0:
			input |= Simulation.IN_LEFT
		elif relative > 0:
			input |= Simulation.IN_RIGHT
		var velocity: Vector2i = HitResolver.preview_air_spike_velocity(
			s, actor, cfg, input, d2)
		check(SimCpu._clears_net(s.ball_x, s.ball_y, velocity.x, velocity.y, cfg),
			"政策3フィクスチャの候補はネットを越える")
		lands.append(SimCpu._land_x_from(
			s.ball_x, s.ball_y, velocity.x, velocity.y, cfg,
			cfg.floor_y - cfg.ball_radius, 3))
	check(lands[0] < lands[1] and lands[1] < lands[2],
		"③奥が両相手から最遠になる単調な着地点")
	check_eq(_decide_fixture(w),
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		"政策3は両相手から最も遠い③奥を選ぶ")

func test_policy_kou_tosses_without_trial_shot() -> void:
	var decided: int = _decide_fixture(_all_candidates_world(9))
	check_eq(decided, Simulation.IN_ACTION, "政策甲は最初からトス")

func test_all_invalid_candidates_use_same_toss_as_policy_kou() -> void:
	var w := _all_candidates_world(0)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	s.ball_x = cfg.net_x - FP.from_int(100)
	s.ball_y = cfg.net_top_y + FP.from_int(80)
	s.players[actor].x = s.ball_x
	var safety: int = SimCpu._pick_air_shot(
		s, actor, cfg, 0, true, cfg.player_reach * cfg.player_reach)
	s.aitick = AITICK_BY_RESIDUE[9]
	var policy_kou: int = SimCpu._pick_air_shot(
		s, actor, cfg, 0, true, cfg.player_reach * cfg.player_reach)
	check_eq(safety, Simulation.IN_ACTION, "全候補無効なら安全弁トス")
	check_eq(safety, policy_kou, "安全弁と政策甲は同じトス入力")

func test_selection_after_attack_permission_is_difficulty_independent() -> void:
	var w := _all_candidates_world(0)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var p = s.players[actor]
	var d2: int = cfg.player_reach * cfg.player_reach
	var selected: Array[int] = []
	for tiq in [1, 2, 3]:
		var prof: int = SimCpu.make_profile(
			SimCpu.AB_ATTACK, 0, 0, 0, 0, 3, tiq)
		selected.append(SimCpu._decide_air_hit(
			s, actor, p, cfg, 0, prof, d2, 0))
	check_eq(selected[0], selected[1], "攻撃許可後は弱中で同じ選択")
	check_eq(selected[1], selected[2], "攻撃許可後は中強で同じ選択")

func test_selection_series_ignores_actor_tick_and_profile() -> void:
	var w := _all_candidates_world(6)
	var s = w[0]
	var cfg = w[1]
	var d2: int = cfg.player_reach * cfg.player_reach
	s.players[1].char_id = s.players[0].char_id
	var expected: int = SimCpu._pick_air_shot(s, 0, cfg, 0, true, d2)
	s.tick += 777
	s.players[1].cpu = SimCpu.PRESET_WEAK
	var actual: int = SimCpu._pick_air_shot(s, 1, cfg, 0, true, d2)
	check_eq(actual, expected, "actor・tick・難易度だけでは選択系列が変わらない")

func test_air_hit_replaces_positioning_direction_bits() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var actor := 0
	var p = s.players[actor]
	p.char_id = STANDARD_CHAR
	p.cpu = SimCpu.make_profile(SimCpu.AB_ATTACK, 0, 0, 0, 0, 3, 3)
	p.on_ground = 0
	p.x = cfg.net_x - FP.from_int(70)
	p.y = cfg.floor_y - FP.from_int(120)
	s.phase = SimState.PHASE_RALLY
	s.ball_x = p.x + cfg.player_reach * 3 / 4
	s.ball_y = p.y
	s.ball_vx = FP.from_int(1)
	s.ball_vy = 0
	s.aitick = AITICK_BY_RESIDUE[9]
	var decided: int = SimCpu.decide(s, actor, cfg)
	check_eq(decided & (Simulation.IN_LEFT | Simulation.IN_RIGHT
		| Simulation.IN_UP | Simulation.IN_DOWN | Simulation.IN_ACTION),
		Simulation.IN_ACTION, "空中打撃は位置取りの方向入力を置き換える")

func _over_net_contact_world(team: int, inside: bool) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var actor: int = team * 2
	var dir: int = SimState._dir_of_team(team)
	var p = s.players[actor]
	p.char_id = STANDARD_CHAR
	p.cpu = SimCpu.make_profile(SimCpu.AB_ATTACK, 0, 0, 0, 0, 3, 3)
	p.on_ground = 0
	p.x = cfg.net_x - dir * FP.from_int(5)
	p.y = cfg.net_top_y - FP.from_int(45)
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x + dir * FP.from_int(5) if inside \
		else p.x + dir * (cfg.player_reach + 1)
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	s.aitick = AITICK_BY_RESIDUE[3]
	return [s, cfg, actor]

func test_ball_already_over_net_can_be_selected_and_hit_inside_ellipse() -> void:
	for team in 2:
		var w := _over_net_contact_world(team, true)
		var s = w[0]
		var cfg = w[1]
		var actor: int = w[2]
		var dir: int = SimState._dir_of_team(team)
		var spike_input: int = Simulation.IN_ACTION | Simulation.IN_DOWN \
			| (Simulation.IN_RIGHT if dir > 0 else Simulation.IN_LEFT)
		var velocity: Vector2i = HitResolver.preview_air_spike_velocity(
			s, actor, cfg, spike_input, 0)
		check(not SimCpu._clears_net(
			s.ball_x, s.ball_y, velocity.x, velocity.y, cfg),
			"通過済み球はネット再通過判定だけなら偽になる")
		check(not SimCpu._air_spike_candidate(
			s, actor, cfg, team, spike_input, 0).is_empty(),
			"通過済み球は相手コート着地なら有効候補")
		var input: int = SimCpu.decide(s, actor, cfg)
		check((input & Simulation.IN_ACTION) != 0,
			"楕円内の通過済み球へ打撃入力を返す")
		var hit_inputs: Array[int] = [0, 0, 0, 0]
		hit_inputs[actor] = input
		var result: int = HitResolver._resolve_hit(s, hit_inputs, cfg)
		check(result != HitResolver.NO_HIT,
			"楕円内の通過済み球へ実接触が成立する")
		check_eq(s.last_touch_idx, actor, "通過済み球の打ち手が記録される")

func test_ball_over_net_outside_ellipse_cannot_be_hit() -> void:
	for team in 2:
		var w := _over_net_contact_world(team, false)
		var s = w[0]
		var cfg = w[1]
		var actor: int = w[2]
		var input: int = SimCpu.decide(s, actor, cfg)
		check_eq(input & Simulation.IN_ACTION, 0,
			"楕円外の通過済み球へ打撃入力を返さない")
		var forced_inputs: Array[int] = [0, 0, 0, 0]
		forced_inputs[actor] = Simulation.IN_ACTION | Simulation.IN_DOWN
		check_eq(HitResolver._resolve_hit(s, forced_inputs, cfg), HitResolver.NO_HIT,
			"楕円外は強制入力でも実接触しない")
