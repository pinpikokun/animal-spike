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
		STANDARD_CHAR, STANDARD_CHAR])
	return [s, cfg]

func test_cpu_chases_ball_on_own_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = s.players[1].x - FP.from_int(57)
	s.ball_y = FP.from_int(100)
	# players[1](左チーム相方、spawn_front=202)から見てボールは左
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_LEFT, "ボールへ向かって左移動")

func test_cpu_hits_in_reach() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = s.players[1].x + FP.from_int(3)
	s.ball_y = s.players[1].y - FP.from_int(10)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION, "リーチ内でACTION")

func test_cpu_uses_shared_trait_aware_receive_reach() -> void:
	var cfg = SimConfig.new()
	check_eq(SimCpu._hit_reach(Chars.CHAR_MARIO, cfg.player_reach,
		HitResolver.INTENT_GROUND_RECEIVE),
		HitResolver.reach_for_intent(Chars.CHAR_MARIO, cfg.player_reach,
			HitResolver.INTENT_GROUND_RECEIVE), "CPUも共有レシーブリーチを使う")

func test_cpu_ignores_ball_on_other_side() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x + FP.from_int(126)
	s.ball_y = FP.from_int(100)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_ACTION), "敵陣のボールは打たない")

func test_cpu_auto_serves() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左チームのサーバーはplayers[0]。人間が相方(index1)を操作している想定で
	# tick経由でCPUサーバーの自動サーブを検証する
	s.controlled_l = 1
	var served := false
	# 2段階サーブ(トス→追走→打撃)のため猶予は遅延+トス滞空ぶん広く取る
	for i in cfg.serve_delay_ticks + 180:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUサーバーが自動サーブする")

func test_cpu_team_serves_via_team_input() -> void:
	# 1人プレイの配線(左=人間、右=完全CPU)で右チームにサーブ権が移っても
	# 試合が止まらないことの回帰テスト。表示層はこのパターンでtickを呼ぶ
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		var cpu_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "右チーム(完全CPU)のサーブで試合が進む")

func test_cpu_serve_crosses_net() -> void:
	# セルフトス方式のサーブでも、CPUは前トス(ネット方向)で確実にネットを越え自滅しない
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	# 左=人間が相方(index1)操作、CPUサーバー(index0)が自動サーブする配線
	s.controlled_l = 1
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "CPUがサーブ(トス→打撃)を実行")
	var crossed := false
	for i in 300:
		Simulation.tick(s, [0, 0], cfg)
		if s.ball_x > cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "CPUのサーブがネットを越え相手コートへ渡る(自滅しない)")

func test_cpu_serve_crosses_net_right_team() -> void:
	# 右チーム(serving_team=1)のCPUサーブも鏡像でネットを越え左コートへ渡る
	# (_serve_xやトス方向の符号ミスをゴールデンハッシュ頼みにしない直接検証)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	Simulation.reset_match(s, cfg, 1, [STANDARD_CHAR, STANDARD_CHAR,
		STANDARD_CHAR, STANDARD_CHAR])
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		var cpu_r: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "右CPUがサーブ(トス→打撃)を実行")
	var crossed := false
	for i in 300:
		var cpu_r2: int = SimCpu.decide(s, 2 + s.controlled_r, cfg)
		Simulation.tick(s, [0, cpu_r2], cfg)
		if s.ball_x < cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "右CPUのサーブがネットを越え左コートへ渡る")

func _prof(ab: int, delay := 0, aim := 0, miss := 0, sweet := 255, depth := 3, tiq := 0) -> int:
	# テスト用: 誤差・ミス・遅延のない純粋な能力プロファイル(既定)
	return SimCpu.make_profile(ab, delay, aim, miss, sweet, depth, tiq)

func _set_rally_attacker(s, idx: int, expected: bool) -> void:
	for seq in 1000:
		s.rally_seq = seq
		if SimCpu._is_rally_attacker(s, idx) == expected:
			return
	check(false, "狙ったアタッカー役になるrally_seqが見つかる")

func _set_rally_blocker(s, idx: int, expected: bool) -> void:
	for seq in 1000:
		s.rally_seq = seq
		if SimCpu._is_rally_blocker(s, idx) == expected:
			return
	check(false, "狙ったブロッカー役になるrally_seqが見つかる")

func test_rally_roles_are_deterministic() -> void:
	var s = SimState.new()
	s.rally_seq = 37
	for team in 2:
		var idx_a: int = team * 2
		var idx_b: int = idx_a + 1
		var expected: Array[bool] = [
			SimCpu._is_rally_attacker(s, idx_a),
			SimCpu._is_rally_attacker(s, idx_b),
			SimCpu._is_rally_blocker(s, idx_a),
			SimCpu._is_rally_blocker(s, idx_b),
		]
		for repeat in 8:
			s.tick = repeat * 17
			s.last_hit_tick = repeat * 31
			check_eq([
				SimCpu._is_rally_attacker(s, idx_a),
				SimCpu._is_rally_attacker(s, idx_b),
				SimCpu._is_rally_blocker(s, idx_a),
				SimCpu._is_rally_blocker(s, idx_b),
			], expected, "同じラリーとチームの役割は何度引いても同じ")

func test_every_rally_has_exactly_one_attacker_per_team() -> void:
	var s = SimState.new()
	for seq in 9:
		s.rally_seq = seq
		for team in 2:
			var idx_a: int = team * 2
			var attackers: int = (1 if SimCpu._is_rally_attacker(s, idx_a) else 0) \
				+ (1 if SimCpu._is_rally_attacker(s, idx_a + 1) else 0)
			check_eq(attackers, 1,
				"rally_seq=%s team=%sのアタッカーはちょうど1人" % [seq, team])

func test_rally_role_table_matches_all_nine_rolls() -> void:
	var expected_attacker_slot: Array[int] = [0, 0, 1, 1, 1, 0, 1, 1, 0]
	var expected_blocker_a: Array[bool] = [
		true, true, true, false, true, true, false, true, true,
	]
	var expected_blocker_b: Array[bool] = [
		true, false, true, false, false, true, false, false, true,
	]
	var s = SimState.new()
	for team in 2:
		var seen: Array[bool] = [
			false, false, false, false, false, false, false, false, false,
		]
		var seen_count: int = 0
		for seq in 1000:
			var role_roll: int = SimCpu._noise(SimCpu.SALT_ROLE, seq, team) % 9
			if seen[role_roll]:
				continue
			seen[role_roll] = true
			seen_count += 1
			s.rally_seq = seq
			var idx_a: int = team * 2
			check_eq(SimCpu._is_rally_attacker(s, idx_a),
				expected_attacker_slot[role_roll] == 0,
				"目%sのslot0アタッカー役" % role_roll)
			check_eq(SimCpu._is_rally_attacker(s, idx_a + 1),
				expected_attacker_slot[role_roll] == 1,
				"目%sのslot1アタッカー役" % role_roll)
			check_eq(SimCpu._is_rally_blocker(s, idx_a),
				expected_blocker_a[role_roll], "目%sのslot0ブロッカー役" % role_roll)
			check_eq(SimCpu._is_rally_blocker(s, idx_a + 1),
				expected_blocker_b[role_roll], "目%sのslot1ブロッカー役" % role_roll)
			if seen_count == 9:
				break
		check_eq(seen_count, 9, "0..8の全抽選結果をテストできる")

func _attack_priority_world() -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NONE
	var p = s.players[1]
	var mate = s.players[0]
	p.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
	mate.cpu = p.cpu
	p.x = cfg.net_x - FP.from_int(48)
	mate.x = p.x
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(160)
	s.ball_vx = 0
	s.ball_vy = 0
	_set_rally_attacker(s, 1, false)
	return w

func test_non_attacker_yields_when_role_mate_can_meet() -> void:
	var w := _attack_priority_world()
	var s = w[0]
	var cfg = w[1]
	check(SimCpu._jump_will_meet(s, s.players[0], cfg, cfg.player_reach),
		"前提: アタッカー役の相方も同じトスに会合できる")
	var input: int = SimCpu.decide(s, 1, cfg)
	check_eq(input & Simulation.IN_JUMP, 0,
		"両者が届く時は非アタッカー役がジャンプを譲る")

func test_non_attacker_jumps_when_role_mate_cannot_meet() -> void:
	var w := _attack_priority_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(20)
	check(not SimCpu._jump_will_meet(s, s.players[0], cfg, cfg.player_reach),
		"前提: アタッカー役の相方はトスに会合できない")
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_JUMP,
		"役持ち相方が会合不能なら非アタッカー役が代わりにジャンプする")

func _own_toss_world(human_team_mask: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.human_team_mask = human_team_mask
	s.controlled_l = 0
	s.last_touch_team = 0
	s.last_touch_idx = 1
	s.touches = 1
	s.serve_flight = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NONE
	var p = s.players[1]
	p.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
	p.x = cfg.net_x - FP.from_int(48)
	s.players[0].x = FP.from_int(20)
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(160)
	s.ball_vx = 0
	s.ball_vy = 0
	_set_rally_attacker(s, 1, true)
	return w

func test_cpu_does_not_jump_for_own_toss_with_human_mate() -> void:
	var w := _own_toss_world(1)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check_eq(input & Simulation.IN_JUMP, 0,
		"人間の相方がいるチームでは自分が上げたトスを自分で打たない")

func test_cpu_jumps_for_own_toss_with_cpu_mate() -> void:
	var w := _own_toss_world(0)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check(input & Simulation.IN_JUMP,
		"同じ配置でもCPU同士のチームなら自分のトスへジャンプする")

func test_profile_pack_roundtrip() -> void:
	# プロファイルの詰め込み/取り出しが欄ごとに正しく往復する
	var prof: int = SimCpu.make_profile(127, 13, 15, 13, 153, 2, 2)
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_AB), 127, "能力")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_DELAY), 13, "遅延")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_AIM), 15, "誤差")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_MISS), 13, "ミス率")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_SWEET), 153, "ジャスト率")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_DEPTH), 2, "予測深度")
	check_eq(SimCpu.prof_byte(prof, SimCpu.P_TIQ), 2, "配球IQ")
	check_eq(prof, SimCpu.PRESET_STRONG, "強プリセットと一致")

func test_normal_attacks_without_sweet_aim() -> void:
	var abilities: int = SimCpu.prof_byte(SimCpu.PRESET_NORMAL, SimCpu.P_AB)
	check(abilities & SimCpu.AB_ATTACK, "普通CPUはジャンプアタックを使う")
	check(not (abilities & SimCpu.AB_SWEET), "普通CPUはジャスト狙いを持たない")
	check_eq(SimCpu.prof_byte(SimCpu.PRESET_NORMAL, SimCpu.P_SWEET), 0,
		"未使用のジャスト率は0")

func test_upper_presets_keep_jump_attack() -> void:
	check(SimCpu.prof_byte(SimCpu.PRESET_STRONG, SimCpu.P_AB) & SimCpu.AB_ATTACK,
		"強CPUはジャンプアタックを維持")
	check(SimCpu.prof_byte(SimCpu.PRESET_MAX, SimCpu.P_AB) & SimCpu.AB_ATTACK,
		"最強CPUはジャンプアタックを維持")
	check(SimCpu.prof_byte(SimCpu.PRESET_STRONG, SimCpu.P_AB) & SimCpu.AB_SWEET,
		"強CPUは設定済みジャスト率を実際の芯狙いに使う")

func test_all_presets_enable_roles() -> void:
	for preset in SimCpu.PRESETS:
		check(SimCpu.prof_byte(preset, SimCpu.P_AB) & SimCpu.AB_ROLES,
			"全CPUプリセットが味方との役割分担を使う")

func test_state_default_profile_is_max() -> void:
	# sim_state.gdの既定リテラルがsim_cpu.PRESET_MAXからずれない番人
	var s = SimState.new()
	check_eq(s.players[0].cpu, SimCpu.PRESET_MAX, "既定プロファイル=最強")

func test_weak_chases_current_ball_predict_chases_landing() -> void:
	# 弱(能力なし)は現在のボール位置を追い、予測持ちは落下点を追う
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = s.players[1].x - FP.from_int(37)  # 今はplayers[1]の左
	s.ball_y = FP.from_int(100)
	s.ball_vx = FP.from_int(8)   # 右へ強く飛んでいる=落下点は右
	s.players[1].cpu = _prof(0)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "弱は現在位置(左)を追う")
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_RIGHT, "予測持ちは落下点(右)へ動く")

func test_roles_split_receiver_and_support() -> void:
	# 役割分担: 落下点に近い相方(p0)がレシーバー、遠いp1は持ち場へ戻る
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(cfg.spawn_back_px)  # 奥(p0の守備範囲)に落ちる
	s.ball_y = FP.from_int(100)
	s.players[1].x = s.ball_x + FP.from_int(44)
	var mask: int = SimCpu.AB_PREDICT | SimCpu.AB_ROLES
	s.players[0].cpu = _prof(mask)
	s.players[1].cpu = _prof(mask)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_RIGHT, "非レシーバーは持ち場(202)へ離れる")
	# 役割なしなら同じ状況でボールへ突っ込む(=みんなで追いかける問題)
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "役割なしはボールへ向かう")

func test_cpu_cover_target_keeps_configured_spacing_from_receiver() -> void:
	var w := _world()
	var cfg = w[1]
	var receiver = w[0].players[0]
	var cover = w[0].players[1]
	receiver.x = FP.from_int(100)
	cover.x = FP.from_int(120)
	var target: int = SimCpu._cover_target(cover, receiver, 1, cfg)
	check(absi(target - receiver.x) >= cfg.cpu_mate_spacing,
		"非レシーバーの目標はレシーバーから設定間隔以上離れる")

func _near_cpu_mate_receive_world() -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.controlled_l = 0
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_x = FP.from_int(110)
	s.ball_y = cfg.floor_y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = FP.from_int(1)
	s.players[0].x = FP.from_int(100)
	s.players[1].x = FP.from_int(110)
	s.players[0].cpu = SimCpu.PRESET_NORMAL
	s.players[1].cpu = SimCpu.PRESET_NORMAL
	return w

func test_non_receiver_suppresses_hit_when_cpu_mate_is_too_close() -> void:
	var w := _near_cpu_mate_receive_world()
	var input: int = SimCpu.decide(w[0], 0, w[1])
	check_eq(input & Simulation.IN_ACTION, 0,
		"近距離では非レシーバー側CPUが打撃を譲る")

func test_non_receiver_does_not_suppress_hit_when_cpu_mate_is_stunned() -> void:
	var w := _near_cpu_mate_receive_world()
	w[0].players[1].stun = 1
	var input: int = SimCpu.decide(w[0], 0, w[1])
	check(input & Simulation.IN_ACTION,
		"相方CPUがスタン中なら非レシーバーも打撃を試みる")

func test_yields_to_human_mate() -> void:
	# 人間の相方が同じ球を取れるならCPUは譲る(人間優先、お見合い事故の防止)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.human_team_mask = 1  # 左チームに人間がいる前提を明示する
	s.ball_x = FP.from_int(90)
	s.ball_y = FP.from_int(100)
	s.controlled_l = 0           # slot0=人間
	s.players[0].x = FP.from_int(100)  # 人間: 落下点から10px
	s.players[1].x = FP.from_int(85)   # CPU: 5pxでより近いが…
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ROLES)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(not (input & Simulation.IN_LEFT), "人間が取れる球にCPUは突っ込まない")

func test_cpu_only_team_does_not_treat_controlled_slot_as_human() -> void:
	var s = SimState.new()
	s.human_team_mask = 0
	s.controlled_l = 0
	check(not SimCpu._mate_is_human(s, 0, 0),
		"人間なしなら左CPUは操作スロットを人間と誤認しない")
	s.controlled_l = 1
	check(not SimCpu._mate_is_human(s, 0, 1),
		"人間なしなら相方側CPUも操作スロットを人間と誤認しない")

func test_human_team_mask_keeps_human_mate_rule() -> void:
	var s = SimState.new()
	s.human_team_mask = 1
	s.controlled_l = 0
	check(SimCpu._mate_is_human(s, 0, 0),
		"左チームのビットがあれば操作スロットを人間として扱う")
	check(not SimCpu._mate_is_human(s, 0, 1),
		"操作スロットでない相方は人間として扱わない")

func test_attack_cpu_jumps_to_meet_toss() -> void:
	# 味方が上げた球に対し、会合できるならジャンプする(アタック準備)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	var p = s.players[1]
	p.x = cfg.net_x - FP.from_int(48)  # ネット際の前衛位置
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(160)  # 頭上高くから落ちてくる
	s.ball_vy = 0
	p.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
	_set_rally_attacker(s, 1, true)
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, "会合可能な球へジャンプする")
	# アタック能力なしなら跳ばない
	p.cpu = _prof(SimCpu.AB_PREDICT)
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "能力なしは跳ばない")

func test_support_zone_complements_human_mate() -> void:
	# 相方が操作キャラの時、CPUは相方の居ない前後ゾーンを守る
	# (相方に張り付いて随伴しない)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.human_team_mask = 1  # 左チームに人間がいる前提を明示する
	s.controlled_l = 0
	var cpu = s.players[1]
	cpu.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ROLES | SimCpu.AB_ATTACK)
	# ボールは操作キャラ(slot0)のすぐ側=レシーバーは相方、CPUは支援位置へ
	s.players[0].x = cfg.net_x - FP.from_int(24)  # 相方はネット近くの前衛圏
	s.ball_x = s.players[0].x
	s.ball_y = FP.from_int(150)
	cpu.x = FP.from_int(cfg.spawn_front_px)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_LEFT, "相方が前なのでCPUは後衛ゾーンへ下がる")
	# 相方が後衛に居るならCPUは前衛ゾーンへ出て、ゾーン内でボールを横に追う
	s.players[0].x = FP.from_int(cfg.spawn_back_px + 4)
	s.ball_x = s.players[0].x
	cpu.x = s.players[0].x + FP.from_int(30)
	input = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "相方が後ろなのでCPUは前衛ゾーンへ出る")

func test_cpu_jumps_to_block() -> void:
	# ブロック能力: 相手アタッカーがネット際で空中+ボールが打点圏なら、
	# ネット際に着いているCPUは跳ぶ
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 1
	s.tick = 200
	s.last_hit_tick = 100  # 反応遅延は消化済み
	var atk = s.players[2]  # 右チームのアタッカー
	atk.x = cfg.net_x + FP.from_int(40)
	atk.y = cfg.floor_y - FP.from_int(140)
	atk.on_ground = 0
	s.ball_x = atk.x + FP.from_int(5)
	s.ball_y = atk.y - FP.from_int(10)
	var blk = s.players[1]  # 左チームの前衛
	blk.x = cfg.net_x - FP.from_int(20)  # ネット際ポストに到着済み
	blk.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_BLOCK)
	_set_rally_blocker(s, 1, true)
	var block_input: int = SimCpu.decide(s, 1, cfg)
	check(block_input & Simulation.IN_JUMP, "ブロックへ跳ぶ")
	check(block_input & Simulation.IN_UP, "CPUも上入力でブロックを明示する")
	# 能力なしは跳ばない
	blk.cpu = _prof(SimCpu.AB_PREDICT)
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "能力なしは跳ばない")

func _block_priority_world() -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 1
	var attacker = s.players[2]
	attacker.x = cfg.net_x + FP.from_int(40)
	attacker.y = cfg.floor_y - FP.from_int(20)
	attacker.on_ground = 0
	s.ball_x = cfg.net_x + FP.from_int(1)
	s.ball_y = attacker.y
	s.ball_vx = -FP.from_int(1)
	s.ball_vy = 0
	var post: int = cfg.net_x - FP.from_int(20)
	s.players[0].x = post
	s.players[1].x = post
	s.players[0].cpu = _prof(SimCpu.AB_BLOCK)
	s.players[1].cpu = _prof(SimCpu.AB_BLOCK)
	var blocker_pair_found := false
	for seq in 1000:
		s.rally_seq = seq
		if SimCpu._is_rally_blocker(s, 0) \
				and not SimCpu._is_rally_blocker(s, 1):
			blocker_pair_found = true
			break
	check(blocker_pair_found, "slot0だけがブロッカー役になるrally_seqが見つかる")
	return w

func test_non_blocker_yields_when_role_mate_can_meet() -> void:
	var w := _block_priority_world()
	var s = w[0]
	var cfg = w[1]
	check(SimCpu._jump_will_meet(s, s.players[0], cfg, cfg.player_reach),
		"前提: ブロッカー役の相方は相手球に会合できる")
	var input: int = SimCpu._decide_block(
		s, 1, s.players[1], cfg, 0, SimCpu.AB_BLOCK, 0)
	check_eq(input & Simulation.IN_JUMP, 0,
		"役持ち相方が届く時は非ブロッカー役が跳ばない")

func test_non_blocker_jumps_when_role_mate_cannot_meet() -> void:
	var w := _block_priority_world()
	var s = w[0]
	var cfg = w[1]
	s.players[0].x = FP.from_int(20)
	check(not SimCpu._jump_will_meet(s, s.players[0], cfg, cfg.player_reach),
		"前提: ブロッカー役の相方は相手球に会合できない")
	var input: int = SimCpu._decide_block(
		s, 1, s.players[1], cfg, 0, SimCpu.AB_BLOCK, 0)
	check(input & Simulation.IN_JUMP,
		"役持ち相方が会合不能なら非ブロッカー役が代わりに跳ぶ")

func test_no_jump_at_serve_in_flight() -> void:
	# サーブ打球がまだネットを越えていない間(serve_flight)は、味方の上げ球と
	# 同じ観測条件でもジャンプアタックしない(サーブに跳びつく誤反応の抑止)
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	var p = s.players[1]
	p.x = cfg.net_x - FP.from_int(48)
	s.ball_x = p.x
	s.ball_y = cfg.floor_y - FP.from_int(160)
	s.ball_vy = 0
	p.cpu = _prof(SimCpu.AB_PREDICT | SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
	_set_rally_attacker(s, 1, true)
	s.serve_flight = 1
	check(not (SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP), "サーブ飛行中は跳ばない")
	s.serve_flight = 0
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_JUMP, "越えた後は通常通り跳ぶ")

func test_reaction_delay_freezes_movement() -> void:
	# 相手の打球直後、遅延tickの間は移動しない(0tick超反応の禁止)。遅延後は動く
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = FP.from_int(60)
	s.ball_y = FP.from_int(100)
	s.last_touch_team = 1     # 相手が打った
	s.tick = 100
	s.last_hit_tick = 96      # 4tick前
	s.players[1].cpu = _prof(SimCpu.AB_PREDICT, 10)  # 遅延10tick
	check_eq(SimCpu.decide(s, 1, cfg) & (Simulation.IN_LEFT | Simulation.IN_RIGHT), 0,
		"遅延中は動かない")
	s.tick = 110              # 14tick経過=遅延明け
	check(SimCpu.decide(s, 1, cfg) & Simulation.IN_LEFT, "遅延明けは動く")

func test_predict_depth_zero_ignores_wall_bounce() -> void:
	# 予測深度0は壁反射を読めない=壁バウンド球の着地を壁側と誤認する
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.players[1].x = FP.from_int(100)
	s.ball_x = FP.from_int(40)
	s.ball_y = FP.from_int(60)
	s.ball_vx = -FP.from_int(6)  # 左壁へ向かい反射して右へ戻る球
	var deep: int = SimCpu._predict_landing_x(s, cfg, cfg.floor_y, 3)
	var shallow: int = SimCpu._predict_landing_x(s, cfg, cfg.floor_y, 0)
	check(deep > shallow, "深い予測は反射後(右)、浅い予測は壁際で止まる")

func test_miss_roll_is_stable_within_touch() -> void:
	# 乱数はタッチ毎1抽選: 同じlast_hit_tickなら何tick経っても同じ値(震えない)
	var w := _world()
	var s = w[0]
	s.last_hit_tick = 777
	var a: int = SimCpu._roll(SimCpu.SALT_AIM, s, 1)
	s.tick += 30
	var b: int = SimCpu._roll(SimCpu.SALT_AIM, s, 1)
	check_eq(a, b, "タッチ内で値が変わらない")
	s.last_hit_tick = 778
	check(SimCpu._roll(SimCpu.SALT_AIM, s, 1) != a, "次のタッチでは変わる")
	check(SimCpu._roll(SimCpu.SALT_MISS, s, 1) != SimCpu._roll(SimCpu.SALT_AIM, s, 1),
		"saltで判定種別が分離される")

func test_serve_variation_reaches_target_and_crosses() -> void:
	# サーブ多様化: スコアで狙いが変わり、選んだ角度/威力は安全域(24..40/100..125)。
	# 実際にその照準までスイープしてサーブし、ネットを越える
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.score_l = 2
	s.score_r = 1
	s.controlled_l = 1  # サーバー(index0)はCPU
	var served := false
	for i in cfg.serve_delay_ticks + 180:
		Simulation.tick(s, [0, 0], cfg)
		if s.phase == SimState.PHASE_RALLY:
			served = true
			break
	check(served, "多様化サーブでもサーブは実行される")
	check(s.serve_aim >= 8 and s.serve_aim <= 24, "角度が安全域内: " + str(s.serve_aim))
	check(s.serve_pow >= 100 and s.serve_pow <= 125, "威力が安全域内: " + str(s.serve_pow))
	check(s.serve_aim != 25 or s.serve_pow != 100, "既定(25/100)から狙いが変わっている")
	var crossed := false
	for i in 300:
		Simulation.tick(s, [0, 0], cfg)
		if s.ball_x > cfg.net_x:
			crossed = true
			break
		if s.phase != SimState.PHASE_RALLY:
			break
	check(crossed, "多様化サーブもネットを越える(自滅しない)")

func test_serve_variation_differs_by_score() -> void:
	# 違うスコアなら違う狙いになる(決定論の疑似乱数)
	var w := _world()
	var s = w[0]
	s.score_l = 0
	s.score_r = 0
	var a: Array[int] = SimCpu._serve_target(s, 0)
	s.score_l = 5
	s.score_r = 3
	var b: Array[int] = SimCpu._serve_target(s, 0)
	check(a[0] != b[0] or a[1] != b[1], "スコアが違えば狙いも変わる")

func test_cpu_walks_home_during_pause() -> void:
	# 得点後のポーズ中、CPUは棒立ちせず持ち場へ歩いて戻る
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_POINT_PAUSE
	s.timer = cfg.point_pause_ticks
	s.players[1].x = FP.from_int(cfg.spawn_front_px) - FP.from_int(57)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "ポーズ中は持ち場(spawn_front=202)へ戻る")

func test_cpu_returns_to_spawn() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x + FP.from_int(126)
	s.ball_y = FP.from_int(100)
	s.players[1].x = FP.from_int(cfg.spawn_front_px) - FP.from_int(57)
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_RIGHT, "持ち場(spawn_front=202)へ戻る")

func test_sweet_jump_plan_returns_two_values_when_plan_exists() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[1]
	p.x = cfg.net_x - FP.from_int(48)
	s.ball_x = p.x + FP.from_int(40)
	s.ball_y = cfg.floor_y - FP.from_int(160)
	s.ball_vy = 0
	var plan: Array[int] = SimCpu._sweet_jump_plan(
		s, p, cfg, cfg.player_reach)
	check_eq(plan.size(), 2, "sweet jump plan has delay and target")
	check(plan[0] > 0, "high reachable toss waits before launch")
	check(plan[0] < 180, "launch delay stays inside the search horizon")

func test_sweet_jump_plan_returns_two_values_when_no_plan_exists() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[1]
	s.ball_x = p.x
	s.ball_y = cfg.floor_y
	s.ball_vy = 0
	var plan: Array[int] = SimCpu._sweet_jump_plan(s, p, cfg, 0)
	check_eq(plan.size(), 2, "missing sweet jump plan has sentinel and target")
	check_eq(plan[0], -1, "unreachable toss produces the sentinel")

func test_jump_serve_holds_jump_while_rising() -> void:
	# 実在するジャンプランクはA/B/C/E。Dのキャラクターは現在存在しない。
	var rank_chars: Array[int] = [
		Chars.CHAR_TOME, Chars.CHAR_CARBY, Chars.CHAR_HITO, Chars.CHAR_UME,
	]
	for char_id in rank_chars:
		var w := _world()
		var s = w[0]
		var cfg = w[1]
		s.phase = SimState.PHASE_SERVE
		s.serving_team = 0
		s.controlled_l = 1
		s.serve_tossed = 1
		var p = s.players[0]
		p.char_id = char_id
		p.cpu = _prof(SimCpu.AB_ATTACK, 0, 0, 0, 255, 3, 3)
		p.on_ground = 0
		p.vy = -FP.from_int(4)
		s.ball_x = p.x
		s.ball_y = p.y
		var input: int = SimCpu.decide(s, 0, cfg)
		var rank_name: String = Chars.Profile.rank_name(
			Chars.rank(char_id, Chars.Profile.ABILITY_JUMP))
		check(input & Simulation.IN_ACTION,
			"jump rank %s serve attacks while rising" % rank_name)
		check(input & Simulation.IN_JUMP,
			"jump rank %s serve holds jump on attack tick" % rank_name)

func _reachable_rally_ball_world(last_touch_team: int, attack_kind: int) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = last_touch_team
	s.ball_attack_kind = attack_kind
	var p = s.players[1]
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	return w

func test_cpu_suppresses_action_for_own_team_attack_ball() -> void:
	var w := _reachable_rally_ball_world(0, SimState.BALL_ATTACK_NORMAL)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check_eq(input & Simulation.IN_ACTION, 0,
		"CPU does not touch its own team's attack ball")

func test_cpu_keeps_action_for_opponent_attack_ball() -> void:
	var w := _reachable_rally_ball_world(1, SimState.BALL_ATTACK_NORMAL)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check(input & Simulation.IN_ACTION,
		"CPU still receives an opponent attack ball")

func test_cpu_keeps_action_for_own_team_toss_ball() -> void:
	var w := _reachable_rally_ball_world(0, SimState.BALL_ATTACK_NONE)
	var input: int = SimCpu.decide(w[0], 1, w[1])
	check(input & Simulation.IN_ACTION,
		"CPU still plays its own team's non-attack toss")

func test_rally_attack_holds_jump_while_rising() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	var p = s.players[1]
	p.cpu = SimCpu.PRESET_MAX
	p.on_ground = 0
	p.vy = -FP.from_int(4)
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION, "rally attacker swings while rising")
	check(input & Simulation.IN_JUMP, "rally attack holds jump while rising")

func test_air_attack_uses_position_after_this_tick_movement() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	s.phase = SimState.PHASE_RALLY
	s.last_touch_team = 0
	s.touches = 1
	s.serve_flight = 0
	var p = s.players[1]
	p.cpu = SimCpu.PRESET_MAX
	p.on_ground = 0
	p.y = FP.from_int(220)
	p.vy = -FP.from_int(5)
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(18)
	s.ball_vx = 0
	s.ball_vy = 0
	var input: int = SimCpu.decide(s, 1, cfg)
	check(input & Simulation.IN_ACTION,
		"air attacker swings when this tick movement enters the sweet window")
	check(input & Simulation.IN_JUMP,
		"predicted air attack keeps variable jump held")

func test_landing_prediction_uses_wall_reflection_not_floor_bounce() -> void:
	var cfg := {
		"ball_radius": 10,
		"court_width": 100,
		"gravity": 1,
		"wall_bounce_num": 50,
		"ball_bounce_num": 78,
		"ball_bounce_den": 100,
	}
	check_eq(SimCpu._land_x_from(11, 0, -4, 0, cfg, 3, 1), 15,
		"CPUの壁反射予測は実物理と同じ50%")
