extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")
const STANDARD_CHAR := 99

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR], 0, 0)
	return [s, cfg]

func _set_rally_attacker(s, idx: int) -> void:
	var team: int = idx / 2
	var role_roll: int = 0 if idx % 2 == 0 else 2
	if team == 0:
		s.rally_role_roll_team0 = role_roll
	else:
		s.rally_role_roll_team1 = role_roll
	check(SimCpu._is_rally_attacker(s, idx),
		"分岐表の保存rollで指定slotがアタッカー役になる")

func _air_attack_world(char_id: int, profile: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	s.tick = 1000
	var p = s.players[1]
	p.char_id = char_id
	p.cpu = profile
	p.on_ground = 0
	p.x = cfg.net_x - FP.from_int(24)
	# 下向きアタックがネット到達までに落ちても、球半径込みで上端を越える高さ。
	p.y = cfg.net_top_y - cfg.ball_radius - FP.from_int(48)
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	return [s, cfg]

func test_max_cpu_prefers_attack_over_air_toss() -> void:
	var w := _air_attack_world(STANDARD_CHAR, SimCpu.PRESET_MAX)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check(input & Simulation.IN_ACTION, "最強CPUは攻撃機会で打球する")
	check(input & Simulation.IN_DOWN, "成立するアタックを空中トスより優先する")

func test_max_tome_uses_flame_with_thirty_five_drive_at_high_contact() -> void:
	var w := _air_attack_world(Chars.CHAR_TOME, SimCpu.PRESET_MAX)
	var s = w[0]
	var cfg = w[1]
	s.players[1].drive_gauge = cfg.special_drive_cost_default
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ABILITY1, "最強TOMEは35以上の攻撃機会で炎を選ぶ")
	check(input & Simulation.IN_DOWN, "炎は空中の下+Dで明示入力する")

func test_max_tome_special_threshold_is_exactly_thirty_five() -> void:
	for row in [[34, false], [35, true]]:
		var w := _air_attack_world(Chars.CHAR_TOME, SimCpu.PRESET_MAX)
		var s = w[0]
		var cfg = w[1]
		s.players[1].drive_gauge = row[0]
		var input: int = SimCpu.decide(s, 1, cfg)
		check_eq((input & Simulation.IN_ABILITY1) != 0, row[1],
			"CPU必殺選択境界 drive=%d" % row[0])

func test_weak_cpu_does_not_use_flame_at_same_opportunity() -> void:
	var w := _air_attack_world(Chars.CHAR_TOME, SimCpu.PRESET_WEAK)
	var s = w[0]
	var cfg = w[1]
	s.players[1].drive_gauge = cfg.drive_gauge_max
	var input: int = SimCpu.decide(s, 1, cfg)
	check_eq(input & Simulation.IN_ABILITY1, 0, "弱CPUは必殺技を選ばない")

func _incoming_attack_world(profile: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_JUST
	var p = s.players[1]
	p.cpu = profile
	p.vx = 0
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up - FP.from_int(6)
	s.ball_vx = 0
	s.ball_vy = FP.from_int(1)
	if SimCpu.prof_byte(profile, SimCpu.P_TIQ) < 3:
		check(SimCpu.prof_byte(profile, SimCpu.P_SWEET) > 0,
			"無条件成功でないプロファイルは正のsweet閾値を持つ")
	s.aitick = 0
	check(SimCpu._sweet_ok(s, 1, profile),
		"固定aitick=0はレシーブsweet成功側")
	return [s, cfg]

func test_max_cpu_presses_receive_inside_predicted_timing_window() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_MAX)
	var s = w[0]
	var input: int = SimCpu.decide(s, 1, w[1])
	check(input & Simulation.IN_ACTION, "最強CPUは着弾直前にボタンを押す")
	check(input & Simulation.IN_DOWN, "タイミング入力は下+ボタン")
	check_eq(input & (Simulation.IN_LEFT | Simulation.IN_RIGHT), 0,
		"タイミング入力時は横入力を止める")
	Simulation._update_receive_stances(s, [0, input, 0, 0], w[1])
	check_eq(s.players[1].receive_stance, w[1].just_receive_window_ticks,
		"CPU入力でジャストレシーブ窓が開く")

func test_cpu_receive_stance_threshold_is_exactly_five_available_drive() -> void:
	for row in [[4, false], [5, true]]:
		var w := _incoming_attack_world(SimCpu.PRESET_MAX)
		var s = w[0]
		var cfg = w[1]
		var p = s.players[1]
		p.drive_gauge = row[0]
		var planned: bool = SimCpu._plans_just_receive(s, 1, p, cfg, 0, p.cpu)
		check_eq(planned, row[1],
			"CPU構え選択境界 drive=%d" % row[0])
		var input: int = SimCpu.decide(s, 1, cfg)
		check_eq((input & Simulation.IN_ACTION) != 0 \
			and (input & Simulation.IN_DOWN) != 0, row[1],
			"CPUは共通予約可能時だけ構え入力 drive=%d" % row[0])

func _cpu_dive_world(drive: int, burnout_ticks: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[1]
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_hit_tick = 0
	s.last_touch_team = 1
	p.cpu = SimCpu.PRESET_MAX
	p.drive_gauge = drive
	p.burnout_ticks = burnout_ticks
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	p.on_ground = 1
	var receive_reach: int = HitResolver.reach_for_intent(
		p.char_id, cfg.player_reach, HitResolver.INTENT_GROUND_RECEIVE)
	s.ball_x = p.x + receive_reach + cfg.dive_receive_extra_reach / 2
	s.ball_y = cfg.floor_y - cfg.ball_radius - FP.from_int(2)
	s.ball_vx = 0
	s.ball_vy = FP.from_int(1)
	return [s, cfg, p]

func test_cpu_dive_selection_uses_common_normal_and_weak_fallbacks() -> void:
	for row in [
			[15, 0, SimState.DIVE_NORMAL],
			[14, 0, SimState.DIVE_WEAK],
			[0, 120, SimState.DIVE_WEAK]]:
		var w := _cpu_dive_world(row[0], row[1])
		var s = w[0]
		var cfg = w[1]
		var p = w[2]
		var input: int = SimCpu.decide(s, 1, cfg)
		check(input & Simulation.IN_ACTION,
			"CPUも飛びつき入力を選ぶ drive=%d burnout=%d" % [row[0], row[1]])
		Simulation.step(s, [0, input, 0, 0], cfg)
		check_eq(p.dive_resource_mode, row[2],
			"最終種別は人間と同じ共通APIが決める drive=%d" % row[0])

func test_max_cpu_can_press_timing_receive_while_reaction_is_frozen() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_MAX)
	var s = w[0]
	s.last_hit_tick = s.tick  # 最強CPUの反応遅延12tickが未消化
	var input: int = SimCpu.decide(s, 1, w[1])
	check(input & Simulation.IN_ACTION, "反応遅延中も位置取り済みなら押下できる")
	check(input & Simulation.IN_DOWN, "反応遅延中の例外は下レシーブだけ")
	check_eq(input & (Simulation.IN_LEFT | Simulation.IN_RIGHT), 0,
		"反応遅延中は移動せず静止押下だけを許可する")

func test_max_cpu_just_receive_actually_fires() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_MAX)
	var s = w[0]
	var cfg = w[1]
	var input: int = SimCpu.decide(s, 1, cfg)
	Simulation._update_receive_stances(s, [0, input, 0, 0], cfg)
	s.ball_y = s.players[1].y
	input = SimCpu.decide(s, 1, cfg)
	HitResolver._apply_hit(s, 1, cfg, input, 0)
	check_eq(s.players[1].just_receive_event, 1,
		"事前構えからCPUのジャストレシーブが実際に成立する")

func test_max_cpu_keeps_walking_when_horizontal_range_hides_ellipse_miss() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_x = cfg.net_x + FP.from_int(20)
	s.ball_y = cfg.floor_y - FP.from_int(120)
	s.ball_vx = FP.from_int(80)
	s.ball_vy = FP.from_int(50)
	var receiver_idx := 2
	var receiver = s.players[receiver_idx]
	receiver.cpu = SimCpu.PRESET_MAX
	receiver.y = cfg.floor_y
	receiver.vx = 0
	receiver.vy = 0
	receiver.on_ground = 1
	s.aitick = 0
	check(SimCpu._sweet_ok(s, receiver_idx, receiver.cpu),
		"固定aitick=0はレシーブsweet成功側")
	var land_x: int = SimCpu._receive_target_x(s, cfg, receiver.cpu)
	var receive_reach: int = SimCpu._hit_reach(
		receiver.char_id, cfg.player_reach, HitResolver.INTENT_GROUND_RECEIVE)
	var stance_deadzone: int = cfg.player_reach * cfg.spike_sweet_pct / 200
	var old_ready_zone: int = maxi(
		receive_reach - stance_deadzone, stance_deadzone)
	receiver.x = land_x - FP.from_int(24)
	check(absi(receiver.x - land_x) <= old_ready_zone,
		"テスト配置は旧水平判定の構え帯に入る")
	check_eq(SimCpu._ticks_until_receive_at(
		s, receiver, cfg, receive_reach, receiver.x), 181,
		"テスト配置は現在位置の楕円リーチに180tick以内に入らない")
	var input: int = SimCpu.decide(s, receiver_idx, cfg)
	check(input & (Simulation.IN_LEFT | Simulation.IN_RIGHT),
		"水平では構え帯でも楕円リーチ外なら落下点へ歩き続ける")
	check_eq(input & Simulation.IN_ACTION, 0,
		"楕円リーチ外ではその場で構えて空振りしない")

func test_max_cpu_still_holds_receive_chord_when_current_x_can_reach() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_MAX)
	var s = w[0]
	var cfg = w[1]
	var receiver = s.players[1]
	var receive_reach: int = SimCpu._hit_reach(
		receiver.char_id, cfg.player_reach, HitResolver.INTENT_GROUND_RECEIVE)
	check(SimCpu._ticks_until_receive_at(
		s, receiver, cfg, receive_reach, receiver.x) < 181,
		"テスト配置は現在位置から楕円リーチへ入る")
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION,
		"現在位置から届くCPUは従来どおり構えのアクションを出す")
	check(input & Simulation.IN_DOWN,
		"現在位置から届くCPUは従来どおり構えの下入力を出す")

func test_receive_contact_prediction_checks_last_position_before_floor() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_x = cfg.net_x - FP.from_int(40)
	s.ball_y = cfg.net_top_y - cfg.ball_radius - FP.from_int(40)
	s.ball_vy = cfg.spike_vy * cfg.spike_normal_pct / 100
	var target_x: int = s.players[2].x
	s.ball_vx = HitResolver.toss_aim_vx(
		s.ball_x, s.ball_y, s.ball_vy, target_x, cfg)
	var land_x: int = SimCpu._predict_landing_x(
		s, cfg, cfg.floor_y - cfg.player_reach_up / 2, 3)
	var receiver = s.players[2]
	receiver.x = land_x
	receiver.y = cfg.floor_y
	receiver.on_ground = 1
	var contact_ticks: int = SimCpu._ticks_until_receive_at(
		s, receiver, cfg, cfg.player_reach, land_x)
	check(contact_ticks > 0 and contact_ticks < 180,
		"通常アタックは落下点の守備者リーチへ床到達前に入る: "
		+ str(contact_ticks))

func test_max_cpu_receiver_covers_center_before_opponent_attack() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_hit_tick = s.tick
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NONE
	s.ball_x = cfg.net_x + FP.from_int(60)
	s.ball_y = cfg.net_top_y - FP.from_int(80)
	s.ball_vx = 0
	s.ball_vy = -FP.from_int(1)
	var receiver = s.players[0]
	var cover = s.players[1]
	receiver.cpu = SimCpu.PRESET_MAX
	cover.cpu = SimCpu.PRESET_MAX
	receiver.x = FP.from_int(30)
	cover.x = cfg.net_x - FP.from_int(30)
	var input: int = SimCpu.decide(s, 0, cfg)
	check(input & Simulation.IN_RIGHT,
		"opponent toss is read before the hit and the receiver covers mid-court")

func test_max_cpu_converts_high_team_toss_to_just_attack() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.tick = 1000
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	var attacker_idx := 1
	_set_rally_attacker(s, attacker_idx)
	var attacker = s.players[attacker_idx]
	attacker.cpu = SimCpu.PRESET_MAX
	attacker.x = cfg.net_x - FP.from_int(64)
	attacker.y = cfg.floor_y
	attacker.vx = 0
	attacker.vy = 0
	attacker.on_ground = 1
	s.ball_x = attacker.x
	s.ball_y = cfg.floor_y - FP.from_int(72)
	s.ball_vx = 0
	s.ball_vy = -cfg.bump_up_speed
	var jumped := false
	var just_contact := false
	for tick in 120:
		var input: int = SimCpu.decide(s, attacker_idx, cfg)
		if input & Simulation.IN_JUMP:
			jumped = true
		Simulation.step(s, [0, input, 0, 0], cfg)
		if s.ball_power == 1:
			just_contact = true
			break
	check(jumped, "max CPU launches for a predictable high team toss")
	check(just_contact,
		"max CPU contacts the high toss inside the configured 45 percent sweet window")

func test_weak_cpu_does_not_prepare_just_receive() -> void:
	var w := _incoming_attack_world(SimCpu.PRESET_WEAK)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check_eq(input & (Simulation.IN_ACTION | Simulation.IN_DOWN), 0,
		"弱CPUは攻撃球に対するジャストレシーブ構えを使わない")

func _serve_attack_world(profile: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_SERVE
	s.serving_team = 0
	s.serve_tossed = 1
	s.tick = 1000
	var p = s.players[0]
	p.cpu = profile
	p.x = FP.from_int(cfg.spawn_back_px)
	p.y = cfg.floor_y
	p.on_ground = 1
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(100)
	s.ball_vx = 0
	s.ball_vy = 0
	return [s, cfg]

func _check_attack_serve(profile: int, label: String) -> void:
	var w := _serve_attack_world(profile)
	var s = w[0]
	var cfg = w[1]
	s.aitick = 0
	check(SimCpu._attack_ok(s, 0, profile),
		label + "の固定aitick=0はアタックサーブ成功側")
	var jump_input: int = SimCpu.decide(s, 0, cfg)
	check(jump_input & Simulation.IN_JUMP, label + "は高いサーブトスへジャンプする")
	var p = s.players[0]
	p.on_ground = 0
	p.y = s.ball_y
	var hit_input: int = SimCpu.decide(s, 0, cfg)
	check(hit_input & Simulation.IN_ACTION, label + "は空中でサーブを打つ")
	check_eq(hit_input, SimCpu._pick_air_shot(s, 0, cfg, 0, true, 0),
		label + "は空中サーブで共通候補・政策を使う")

func test_strong_cpu_uses_shared_jump_serve_on_successful_profile_roll() -> void:
	_check_attack_serve(SimCpu.PRESET_STRONG, "強CPU")

func test_max_cpu_uses_shared_jump_serve() -> void:
	_check_attack_serve(SimCpu.PRESET_MAX, "最強CPU")

func test_max_mirror_offense_and_just_receive_kpi() -> void:
	var cfg = SimConfig.new()
	cfg.points_to_win = 999
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR], 0, 0)
	for p in s.players:
		p.cpu = SimCpu.PRESET_MAX
	var attacks := 0
	var just_attacks := 0
	var receive_events_before := 0
	for p in s.players:
		receive_events_before += p.just_receive_event
	for tick in 3000:
		var before_hit: int = s.last_hit_tick
		var in_l: int = SimCpu.decide(s, s.controlled_l, cfg)
		var in_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [in_l, in_r], cfg)
		if s.last_hit_tick != before_hit \
				and s.ball_attack_kind != SimState.BALL_ATTACK_NONE:
			attacks += 1
			if s.ball_attack_kind == SimState.BALL_ATTACK_JUST:
				just_attacks += 1
	var receive_events_after := 0
	for p in s.players:
		receive_events_after += p.just_receive_event
	var just_receives: int = receive_events_after - receive_events_before
	var evidence := " attacks=%d just_attacks=%d just_receives=%d" % [
		attacks, just_attacks, just_receives]
	check(attacks >= 5, "3000tickでアタック5回以上。" + evidence)
	check(just_attacks >= 1, "3000tickでジャストアタック1回以上。" + evidence)
	check(just_receives >= 1, "3000tickでジャストレシーブ1回以上。" + evidence)
