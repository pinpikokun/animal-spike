extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const SimRng := preload("res://src/sim/sim_rng.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const BallPhysics := preload("res://src/sim/ball_physics.gd")

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

func test_trial_band_cross_order_counts_and_zero_axis() -> void:
	var helper := Callable(SimCpu, "_trial_band_velocities")
	check(helper.is_valid(), "幅格子helperが存在する")
	if not helper.is_valid():
		return
	check_eq(helper.call(Vector2i(1000, -500), 1), [
		Vector3i(1000, -550, 1),
		Vector3i(900, -500, 1),
		Vector3i(1000, -500, 0),
		Vector3i(1100, -500, 1),
		Vector3i(1000, -450, 1),
	], "iy外側・ix内側の十字")
	check_eq(helper.call(Vector2i(0, -500), 1).size(), 3,
		"vxゼロのk1は横座標を除外")
	check_eq(helper.call(Vector2i(0, -500), 3).size(), 7,
		"vxゼロのk3は7論理点")
	check_eq(helper.call(Vector2i(1000, -500), 3).size(), 13,
		"非ゼロvxのk3は13論理点")
	check_eq(helper.call(Vector2i(1000, -500), 0), [
		Vector3i(1000, -500, 0),
	], "k0は正確速度の中心1点")
	var constants: Dictionary = SimCpu.new().get_script().get_script_constant_map()
	check(constants.has("TRIAL_BAND_CURRENT_STEPS"), "production幅定数が存在する")
	if constants.has("TRIAL_BAND_CURRENT_STEPS"):
		check_eq(constants["TRIAL_BAND_CURRENT_STEPS"], 0, "production幅はゼロ")

func test_trial_band_mirror_duplicates_and_invalid_k() -> void:
	var helper := Callable(SimCpu, "_trial_band_velocities")
	check(helper.is_valid(), "幅格子helperが存在する")
	if not helper.is_valid():
		return
	var left: Array = helper.call(Vector2i(1000, -500), 3)
	var right: Array = helper.call(Vector2i(-1000, -500), 3)
	check_eq(right.size(), left.size(), "左右鏡像の論理点数")
	for i in left.size():
		check_eq(right[i], Vector3i(-left[i].x, left[i].y, left[i].z),
			"左右鏡像 point=" + str(i))
	check_eq(helper.call(Vector2i(3, -4), 1), [
		Vector3i(3, -4, 1),
		Vector3i(3, -4, 1),
		Vector3i(3, -4, 0),
		Vector3i(3, -4, 1),
		Vector3i(3, -4, 1),
	], "歩幅0でも論理格子座標を重複排除しない")
	check_eq(helper.call(Vector2i(1000, -500), -1), [], "負のkは無効")
	check_eq(helper.call(Vector2i(1000, -500), 4), [], "最大超過kは無効")

func test_policy_three_k3_has_structural_limit_39_points() -> void:
	var helper := Callable(SimCpu, "_trial_band_velocities")
	check(helper.is_valid(), "幅格子helperが存在する")
	if not helper.is_valid():
		return
	var w := _all_candidates_world(6)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var d2: int = cfg.player_reach * cfg.player_reach
	var evaluated_points := 0
	for input in [
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
	]:
		var velocity: Vector2i = HitResolver.preview_air_spike_velocity(
			s, actor, cfg, input, d2)
		check(velocity.x != 0, "構造上限fixtureは横速度が非ゼロ")
		evaluated_points += helper.call(velocity, 3).size()
	check_eq(evaluated_points, 39, "政策3のk3構造上限は3候補×13点")

func _band_miss_world(team: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var actor: int = team * 2
	var dir: int = SimState._dir_of_team(team)
	var p = s.players[actor]
	p.char_id = STANDARD_CHAR
	p.on_ground = 0
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x - dir * FP.from_int(20)
	s.ball_y = cfg.net_top_y - FP.from_int(17)
	p.x = s.ball_x - dir * cfg.player_reach
	p.y = s.ball_y
	s.ball_vx = 0
	s.ball_vy = 0
	s.aitick = AITICK_BY_RESIDUE[0]
	return [s, cfg, actor]

func test_trial_band_candidate_adopts_believed_point_but_hits_real_net() -> void:
	var left := _band_miss_world(0)
	var s = left[0]
	var cfg = left[1]
	var actor: int = left[2]
	var d2: int = cfg.player_reach * cfg.player_reach
	var inputs: Array[int] = [
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
	]
	var before: Array[int] = s.to_int_array()
	check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, inputs[0], d2, 3), [],
		"①手前はk3でも無効")
	check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, inputs[1], d2, 3), [],
		"②中央はk3でも無効")
	var actual: Vector2i = HitResolver.preview_air_spike_velocity(
		s, actor, cfg, inputs[2], d2)
	var actual_land: int = SimCpu._land_x_from(
		s.ball_x, s.ball_y, actual.x, actual.y, cfg,
		cfg.floor_y - cfg.ball_radius, 3)
	check(actual_land > cfg.net_x, "中心実球は着地点だけなら相手コート")
	check(not SimCpu._clears_net(s.ball_x, s.ball_y, actual.x, actual.y, cfg),
		"中心実球はネットへ衝突する")
	check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, inputs[2], d2, 0), [],
		"k0の中心実球は無効")
	var step_y: int = absi(actual.y) * SimCpu.TRIAL_BAND_STEP_PCT / 100
	var believed_velocity := Vector2i(actual.x, actual.y - step_y)
	var believed_land: int = SimCpu._land_x_from(
		s.ball_x, s.ball_y, believed_velocity.x, believed_velocity.y, cfg,
		cfg.floor_y - cfg.ball_radius, 3)
	var selected: Array = SimCpu._air_spike_candidate(
		s, actor, cfg, 0, inputs[2], d2, 3)
	check_eq(selected, [inputs[2], believed_land],
		"k3は最小距離・走査順先着の幅点を信じる")
	if selected.size() != 2:
		return
	for k in range(1, 4):
		check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, inputs[2], d2, k),
			selected, "最短幅点が入った後はkを増やしても選択不変")
	check_eq(SimCpu._pick_air_shot(s, actor, cfg, 0, true, d2, 3), inputs[2],
		"政策1は幅点を信じて③奥の実入力を採用する")
	check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, inputs[2], d2, -1), [],
		"負のkは候補無効")
	check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, inputs[2], d2, 4), [],
		"最大超過kは候補無効")
	check_eq(s.to_int_array(), before, "非ゼロ幅の候補選択は同期状態を変更しない")
	var restored = SimState.new()
	restored.load_int_array(before)
	check_eq(SimCpu._air_spike_candidate(
		restored, actor, cfg, 0, inputs[2], d2, 3),
		selected, "snapshot復元後も同じ幅点を信じる")
	var hit_state = SimState.new()
	hit_state.load_int_array(before)
	var hit_inputs: Array[int] = [0, 0, 0, 0]
	hit_inputs[actor] = inputs[2]
	check_eq(HitResolver._resolve_hit(hit_state, hit_inputs, cfg),
		HitResolver.HIT_NO_POINT, "採用した中心実球が成立する")
	var reflected_by_net := false
	for _tick in 120:
		var vx_before: int = hit_state.ball_vx
		BallPhysics._step_ball(hit_state, cfg, hit_inputs)
		if vx_before > 0 and hit_state.ball_vx < 0:
			reflected_by_net = true
			break
	check(reflected_by_net, "幅点を信じて採用した中心実球は実物理でネット衝突する")
	var right := _band_miss_world(1)
	var rs = right[0]
	var rcfg = right[1]
	var ractor: int = right[2]
	var right_input: int = Simulation.IN_ACTION | Simulation.IN_DOWN \
		| Simulation.IN_LEFT
	var right_selected: Array = SimCpu._air_spike_candidate(
		rs, ractor, rcfg, 1, right_input, d2, 3)
	check_eq(right_selected.size(), 2, "右チームも有効候補を返す")
	if right_selected.size() != 2:
		return
	check_eq(right_selected[0], right_input, "右チームも鏡像の実入力を採用")
	check_eq(right_selected[1] + selected[1], cfg.court_width,
		"非ゼロ幅の信じる着地点は左右鏡像")

func test_trial_band_candidate_is_monotonic_and_k0_exact() -> void:
	var w := _all_candidates_world(6)
	var s = w[0]
	var cfg = w[1]
	var actor: int = w[2]
	var d2: int = cfg.player_reach * cfg.player_reach
	for input in [
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
	]:
		var old_center: Array[int] = SimCpu._air_spike_candidate(
			s, actor, cfg, 0, input, d2)
		check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, input, d2, 0),
			old_center, "k0は旧中心1点判定と完全一致")
		var previous_valid := false
		for k in 4:
			var current: Array = SimCpu._air_spike_candidate(
				s, actor, cfg, 0, input, d2, k)
			if previous_valid:
				check(not current.is_empty(), "kを増やしても既存有効候補が消えない")
			previous_valid = not current.is_empty()
		check_eq(SimCpu._air_spike_candidate(s, actor, cfg, 0, input, d2, 3),
			old_center, "中心有効ならk3でも中心landを信じる")

func _jump_serve_contact_world(team: int, residue: int) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var actor: int = team * 2
	var dir: int = SimState._dir_of_team(team)
	var p = s.players[actor]
	p.char_id = STANDARD_CHAR
	p.on_ground = 0
	p.cpu = SimCpu.PRESET_MAX
	s.phase = SimState.PHASE_SERVE
	s.serving_team = team
	s.serve_tossed = 1
	s.ball_x = cfg.net_x - dir * FP.from_int(60)
	s.ball_y = cfg.net_top_y - FP.from_int(100)
	p.x = s.ball_x
	p.y = s.ball_y
	s.players[(1 - team) * 2].x = cfg.net_x + dir * FP.from_int(20)
	s.players[(1 - team) * 2 + 1].x = cfg.net_x + dir * FP.from_int(40)
	s.aitick = AITICK_BY_RESIDUE[residue]
	return [s, cfg, actor]

func test_jump_serve_uses_shared_three_candidates_and_four_policies() -> void:
	var left_expected: Array[int] = [
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		Simulation.IN_ACTION,
	]
	var right_expected: Array[int] = [
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_RIGHT,
		Simulation.IN_ACTION | Simulation.IN_DOWN | Simulation.IN_LEFT,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		Simulation.IN_ACTION,
	]
	var residues: Array[int] = [0, 3, 6, 9]
	for team in 2:
		for policy in 4:
			var w := _jump_serve_contact_world(team, residues[policy])
			var s = w[0]
			var cfg = w[1]
			var actor: int = w[2]
			var expected: int = left_expected[policy] \
				if team == 0 else right_expected[policy]
			var actual: int = SimCpu._decide_serve(
				s, actor, cfg, s.players[actor].cpu)
			check_eq(actual & (Simulation.IN_LEFT | Simulation.IN_RIGHT \
				| Simulation.IN_UP | Simulation.IN_DOWN | Simulation.IN_ACTION),
				expected, "ジャンプサーブ共通政策 team=%d policy=%d" % [team, policy])

func test_jump_serve_policy_is_actor_independent_and_stable_in_contact_window() -> void:
	var left := _jump_serve_contact_world(0, 6)
	var right := _jump_serve_contact_world(1, 6)
	var left_state = left[0]
	var right_state = right[0]
	var left_actor: int = left[2]
	var right_actor: int = right[2]
	var left_input: int = SimCpu._decide_serve(
		left_state, left_actor, left[1], left_state.players[left_actor].cpu)
	var right_input: int = SimCpu._decide_serve(
		right_state, right_actor, right[1], right_state.players[right_actor].cpu)
	check_eq(right_input, left_input,
		"同じaitickの左右サーバーはactorによらず同じ政策入力")
	left_state.tick += 777
	left_state.ball_x += FP.from_int(1)
	left_state.ball_y += FP.from_int(1)
	left_state.players[left_actor].x += FP.from_int(1)
	left_state.players[left_actor].y += FP.from_int(1)
	for opponent in [2, 3]:
		left_state.players[opponent].x += FP.from_int(1)
	check_eq(SimCpu._decide_serve(
		left_state, left_actor, left[1], left_state.players[left_actor].cpu),
		left_input, "同じaitickの接触窓ではtickと平行移動で政策入力が変わらない")

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
