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
			var spike := HitResolver._classify_intent(
				0, SimInput.IN_ACTION | SimInput.IN_DOWN | row[0],
				0, cfg.player_reach, false)
			check_eq(spike[0], HitResolver.INTENT_AIR_SPIKE, "下段3マスはアタック")
			check_eq(spike[1] * SimState._dir_of_team(team), row[1],
				"アタックの横軸は後ろ/中央/前")
			var toss := HitResolver._classify_intent(
				0, SimInput.IN_ACTION | row[0], 0, cfg.player_reach, false)
			check_eq(toss[0], HitResolver.INTENT_AIR_TOSS, "中段3マスはトス")
			check_eq(toss[1] * SimState._dir_of_team(team), row[1],
				"トスの横軸は後ろ/中央/前")
			var block := HitResolver._classify_intent(
				0, SimInput.IN_ACTION | SimInput.IN_UP | row[0],
				0, cfg.player_reach, false)
			check_eq(block[0], HitResolver.INTENT_AIR_BLOCK, "上段3マスはブロック")


func test_block_requires_air_up_action_and_ignores_horizontal_direction() -> void:
	var w := _rally_world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[1]
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(140)
	s.last_touch_team = 1
	s.ball_vx = -FP.from_int(8)
	for horizontal in [0, SimInput.IN_LEFT, SimInput.IN_RIGHT]:
		check(HitResolver._is_active_block(
			s, 1, SimInput.IN_ACTION | SimInput.IN_UP | horizontal, cfg),
			"空中上+ボタンは横方向に関係なく明示ブロック")
	check(not HitResolver._is_active_block(s, 1, SimInput.IN_ACTION, cfg),
		"上なしボタンではパッシブブロックしない")
	p.on_ground = 1
	check(not HitResolver._is_active_block(
		s, 1, SimInput.IN_ACTION | SimInput.IN_UP, cfg), "地上ではブロックしない")


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
	var p = s.players[1]
	p.cpu = SimCpu.make_profile(SimCpu.AB_BLOCK, 0, 0, 0, 0, 0, 0)
	p.on_ground = 0
	p.y = cfg.floor_y - FP.from_int(140)
	var attacker = s.players[2]
	attacker.on_ground = 0
	attacker.x = cfg.net_x + FP.from_int(40)
	attacker.y = p.y
	s.ball_x = attacker.x
	s.ball_y = attacker.y
	var blocker_role_found := false
	for seq in 1000:
		s.rally_seq = seq
		if SimCpu._is_rally_blocker(s, 1):
			blocker_role_found = true
			break
	check(blocker_role_found, "空中CPUがブロッカー役になるrally_seqが見つかる")
	var block_input: int = SimCpu._decide_block(
		s, 1, p, cfg, 0, SimCpu.AB_BLOCK, 0)
	check(block_input & SimInput.IN_ACTION, "空中CPUブロックはボタンを押す")
	check(block_input & SimInput.IN_UP, "空中CPUブロックは上を明示する")
