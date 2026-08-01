extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")


func _rally_world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	for p in s.players:
		p.y = cfg.floor_y
	s.players[0].x = cfg.net_x - FP.from_int(124)
	s.players[1].x = cfg.net_x - FP.from_int(20)
	s.players[2].x = cfg.net_x + FP.from_int(156)
	s.players[3].x = cfg.net_x + FP.from_int(46)
	return [s, cfg]


func test_up_alone_is_jump_and_not_ground_aim() -> void:
	var w := _rally_world()
	var p = w[0].players[0]
	PlayerMovement._step_player(p, SimInput.IN_JUMP | SimInput.IN_UP, w[1], 0)
	check_eq(p.on_ground, 0, "上キー単独でジャンプする")
	var intent := HitResolver._classify_intent(
		1, SimInput.IN_ACTION | SimInput.IN_UP, 0, w[1].player_reach, false)
	check_eq(intent[0], HitResolver.INTENT_GROUND_TOSS,
		"地上打球では上入力を照準に使わない")
	check_eq(intent[1], 0, "上入力は地上トスの横方向を変えない")


func test_ground_action_has_three_intents_and_two_own_toss_targets() -> void:
	var cfg = SimConfig.new()
	for team in 2:
		var forward := SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
		var backward := SimInput.IN_LEFT if team == 0 else SimInput.IN_RIGHT
		for row in [[backward, -1], [0, 0], [forward, 1]]:
			var intent := HitResolver._classify_intent(
				1, SimInput.IN_ACTION | row[0], 0, cfg.player_reach, false)
			check_eq(intent[0], HitResolver.INTENT_GROUND_TOSS,
				"地上ボタンは横3種ともトス: team=%d input=%d" % [team, row[0]])
			check_eq(intent[1] * SimState._dir_of_team(team), row[1],
				"後ろ/なし/前をチーム相対方向へ正規化: team=%d" % team)
		check(HitResolver.toss_target_x(team, -SimState._dir_of_team(team), cfg)
			!= HitResolver.toss_target_x(team, 0, cfg), "後ろとニュートラルは別目標")


func test_ground_down_action_is_receive_with_existing_reach_rules() -> void:
	var cfg = SimConfig.new()
	var intent := HitResolver._classify_intent(
		1, SimInput.IN_ACTION | SimInput.IN_DOWN, 0, cfg.player_reach, false)
	check_eq(intent[0], HitResolver.INTENT_GROUND_RECEIVE, "下+ボタンだけがレシーブ")
	check_eq(HitResolver.reach_for_intent(99, cfg.player_reach, intent[0]),
		cfg.player_reach, "標準レシーブのリーチは既存値を維持")


func test_air_nine_grid_classifies_vertical_kind_and_horizontal_depth() -> void:
	var cfg = SimConfig.new()
	for team in 2:
		var forward := SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
		var backward := SimInput.IN_LEFT if team == 0 else SimInput.IN_RIGHT
		for row in [[backward, -1], [0, 0], [forward, 1]]:
			var wager := HitResolver._classify_intent(
				0, SimInput.IN_ACTION | SimInput.IN_DOWN | row[0],
				0, cfg.player_reach, false)
			check_eq(wager[0], HitResolver.INTENT_AIR_SPIKE,
				"下段3マスはジャスト可アタック")
			check_eq(wager[1] * SimState._dir_of_team(team), row[1],
				"アタックの横軸は後ろ/中央/前")
			check_eq(wager[3], 1, "下段だけジャストを許可")
			var toss := HitResolver._classify_intent(
				0, SimInput.IN_ACTION | row[0], 0, cfg.player_reach, false)
			check_eq(toss[0], HitResolver.INTENT_AIR_TOSS, "中段3マスはトス")
			check_eq(toss[1] * SimState._dir_of_team(team), row[1],
				"トスの横軸は後ろ/中央/前")
			check_eq(toss[3], 0, "トスはジャスト判定を持たない")
			var safe := HitResolver._classify_intent(
				0, SimInput.IN_ACTION | SimInput.IN_UP | row[0],
				0, cfg.player_reach, false)
			check_eq(safe[0], HitResolver.INTENT_AIR_SPIKE,
				"上段3マスは通常アタック")
			check_eq(safe[1] * SimState._dir_of_team(team), row[1],
				"上アタックも横軸は後ろ/中央/前")
			check_eq(safe[3], 0, "上段はジャストを許可しない")


func test_block_requires_forward_action_and_existing_context_boundaries() -> void:
	for team in 2:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var blocker_idx: int = 1 if team == 0 else 3
		var p = s.players[blocker_idx]
		var forward := SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
		var backward := SimInput.IN_LEFT if team == 0 else SimInput.IN_RIGHT
		var block_input: int = SimInput.IN_ACTION | forward
		p.x = cfg.net_x - SimState._dir_of_team(team) * FP.from_int(20)
		p.y = cfg.floor_y - FP.from_int(140)
		s.last_touch_team = 1 - team
		s.ball_vx = -SimState._dir_of_team(team) * FP.from_int(8)
		for on_ground in [0, 1]:
			p.on_ground = on_ground
			check(HitResolver._is_active_block(s, blocker_idx, block_input, cfg),
				"前+ボタンは地上・空中共通ブロック team=%d ground=%d" % [
					team, on_ground])
		check(not HitResolver._is_active_block(
			s, blocker_idx, SimInput.IN_ACTION | backward, cfg),
			"後+ボタンはブロックしない")
		check(not HitResolver._is_active_block(
			s, blocker_idx, SimInput.IN_ACTION | SimInput.IN_UP, cfg),
			"上+ボタンはブロックしない")
		check(not HitResolver._is_active_block(
			s, blocker_idx, block_input | SimInput.IN_DOWN, cfg),
			"上下を含む前+ボタンはブロックしない")
		s.last_touch_team = team
		check(not HitResolver._is_active_block(s, blocker_idx, block_input, cfg),
			"自チームが最後に触った球はブロックしない")
		s.last_touch_team = 1 - team
		p.x = cfg.net_x - SimState._dir_of_team(team) * FP.from_int(61)
		check(not HitResolver._is_active_block(s, blocker_idx, block_input, cfg),
			"ネットから60pxを越えたらブロックしない")
		p.x = cfg.net_x - SimState._dir_of_team(team) * FP.from_int(20)
		s.ball_vx = SimState._dir_of_team(team) * FP.from_int(8)
		check(not HitResolver._is_active_block(s, blocker_idx, block_input, cfg),
			"自陣から離れる球はブロックしない")


func test_cpu_emits_new_toss_receive_and_block_inputs() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var ground_toss: int = SimCpu._ground_shot_keys(s, 0, cfg, 0,
		SimCpu.make_profile(SimCpu.AB_ATTACK, 0, 0, 0, 0, 0, 0))
	check_eq(ground_toss, 0, "CPUの組み立てトスは旧上照準を出さない")
	s.last_touch_team = 1
	check_eq(SimCpu._ground_hit_keys(s, 0, cfg, 0, s.players[0].cpu),
		SimInput.IN_DOWN, "CPUは相手球へ下レシーブを明示する")


func test_cpu_attack_vertical_uses_drive_and_burnout() -> void:
	var helper := Callable(SimCpu, "_cpu_attack_vertical")
	check(helper.is_valid(), "CPUアタック縦入力の共通helperが存在する")
	if not helper.is_valid():
		return
	var cfg = SimConfig.new()
	var p = SimState.new().players[0]
	p.drive_gauge = cfg.drive_gauge_stock
	check_eq(helper.call(p, cfg), SimInput.IN_DOWN,
		"1本以上ならジャスト可能アタック")
	p.drive_gauge = cfg.drive_gauge_stock - 1
	check_eq(helper.call(p, cfg), SimInput.IN_UP,
		"1本未満なら通常アタック")
	p.drive_gauge = cfg.drive_gauge_max
	p.burnout_ticks = 1
	check_eq(helper.call(p, cfg), SimInput.IN_UP,
		"バーンアウト中は通常アタック")


func test_cpu_air_block_uses_team_relative_forward_action() -> void:
	for team in 2:
		var w := _rally_world()
		var s = w[0]
		var cfg = w[1]
		var dir: int = SimState._dir_of_team(team)
		var blocker_idx: int = team * 2 + 1
		var p = s.players[blocker_idx]
		p.cpu = SimCpu.make_profile(SimCpu.AB_BLOCK, 0, 0, 0, 0, 0, 0)
		p.on_ground = 0
		p.x = cfg.net_x - dir * FP.from_int(20)
		p.y = cfg.floor_y - FP.from_int(140)
		var attacker = s.players[(1 - team) * 2]
		attacker.on_ground = 0
		attacker.x = cfg.net_x + dir * FP.from_int(40)
		attacker.y = p.y
		s.ball_x = attacker.x
		s.ball_y = attacker.y
		if team == 0:
			s.rally_role_roll_team0 = 0
		else:
			s.rally_role_roll_team1 = 0
		check(SimCpu._is_rally_blocker(s, blocker_idx),
			"roll=0の両者ブロッカー枝で空中CPUが役を持つ team=%d" % team)
		var block_input: int = SimCpu._decide_block(
			s, blocker_idx, p, cfg, team, SimCpu.AB_BLOCK, 0)
		var forward: int = SimInput.IN_RIGHT if team == 0 else SimInput.IN_LEFT
		check_eq(block_input, SimInput.IN_ACTION | forward,
			"空中CPUブロックはチーム相対の前+ボタン team=%d" % team)
