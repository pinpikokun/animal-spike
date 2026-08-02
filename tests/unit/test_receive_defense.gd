extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")

const CONTACT_TOSS := 0
const CONTACT_RECEIVE := 1
const CONTACT_JUST := 2
const CONTACT_DIVE := 3

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _air_attack(s, cfg, sweet: bool) -> void:
	var p = s.players[0]
	p.on_ground = 0
	s.last_touch_team = 0
	s.touches = 1
	var d2: int = 0 if sweet else cfg.player_reach * cfg.player_reach
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, d2)

func _resolve_contact(attack_kind: int, contact: int, base_damage: int,
		burnout: bool = false, guard: int = 100, dive_input: int = 0,
		d2: int = 0) -> Array:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[0]
	p.guard = guard
	p.burnout_ticks = cfg.burnout_recovery_ticks if burnout else 0
	s.last_touch_team = 1
	s.ball_attack_kind = attack_kind
	s.ball_power = 1 if attack_kind == SimState.BALL_ATTACK_JUST else 0
	s.ball_guard_damage = base_damage
	s.ball_vx = FP.from_int(600) / cfg.tick_rate
	s.ball_vy = FP.from_int(300) / cfg.tick_rate
	var input: int = Simulation.IN_ACTION
	var force_dive := false
	match contact:
		CONTACT_RECEIVE:
			input |= Simulation.IN_DOWN
		CONTACT_JUST:
			input |= Simulation.IN_DOWN
			p.receive_stance = 1
		CONTACT_DIVE:
			force_dive = true
			input |= dive_input
			p.on_ground = 0
			p.y = cfg.floor_y - FP.from_int(10)
			p.vy = -cfg.dive_receive_hop
			p.dive = 1
			p.dive_contact_ticks = cfg.dive_receive_contact_ticks
			p.dive_age_ticks = 1
			p.vx = cfg.dive_receive_speed
	HitResolver._apply_hit(s, 0, cfg, input, d2, force_dive)
	return [s, cfg, p]

func test_normal_attack_carries_power_guard_damage() -> void:
	for row in [[Chars.CHAR_SEC2, 35], [Chars.CHAR_PANDA, 25], [Chars.CHAR_PIYO, 15]]:
		var w := _world()
		var s = w[0]
		var cfg = w[1]
		s.players[0].char_id = row[0]
		_air_attack(s, cfg, false)
		check_eq(s.ball_attack_kind, SimState.BALL_ATTACK_NORMAL,
			"通常アタック属性: %s" % [row])
		check_eq(s.ball_guard_damage, row[1],
			"POWER基礎ガード損害: %s" % [row])

func test_standard_c_contact_matrix() -> void:
	for row in [
		[SimState.BALL_ATTACK_NORMAL, CONTACT_TOSS, 75, 100, true],
		[SimState.BALL_ATTACK_NORMAL, CONTACT_RECEIVE, 90, 100, false],
		[SimState.BALL_ATTACK_NORMAL, CONTACT_JUST, 100, 100, false],
		[SimState.BALL_ATTACK_NORMAL, CONTACT_DIVE, 75, 100, false],
		[SimState.BALL_ATTACK_JUST, CONTACT_TOSS, 75, 100, true],
		[SimState.BALL_ATTACK_JUST, CONTACT_RECEIVE, 90, 100, false],
		[SimState.BALL_ATTACK_JUST, CONTACT_JUST, 100, 100, false],
		[SimState.BALL_ATTACK_JUST, CONTACT_DIVE, 75, 100, false],
	]:
		var result := _resolve_contact(row[0], row[1], 25)
		var p = result[2]
		check_eq(p.guard, row[2], "標準C guard: %s" % [row])
		check_eq(p.drive_gauge, row[3], "標準C drive: %s" % [row])
		check_eq(p.flinch > 0, row[4], "標準C しりもち: %s" % [row])

func test_power_rank_guard_damage_matrix() -> void:
	var bases := [35, 30, 25, 20, 15]
	var receive_damage := [14, 12, 10, 8, 6]
	for i in bases.size():
		var toss = _resolve_contact(SimState.BALL_ATTACK_NORMAL,
			CONTACT_TOSS, bases[i])[2]
		var receive = _resolve_contact(SimState.BALL_ATTACK_NORMAL,
			CONTACT_RECEIVE, bases[i])[2]
		var just = _resolve_contact(SimState.BALL_ATTACK_NORMAL,
			CONTACT_JUST, bases[i])[2]
		var dive = _resolve_contact(SimState.BALL_ATTACK_NORMAL,
			CONTACT_DIVE, bases[i])[2]
		check_eq(100 - toss.guard, bases[i], "地上トス全量 rank=%d" % i)
		check_eq(100 - receive.guard, receive_damage[i], "通常レシーブ40%% rank=%d" % i)
		check_eq(100 - just.guard, 0, "ジャスト0 rank=%d" % i)
		check_eq(100 - dive.guard, bases[i], "飛びつき全量 rank=%d" % i)

func test_burnout_has_no_extra_guard_damage_matrix() -> void:
	var bases := [35, 30, 25, 20, 15]
	var receive_damage := [14, 12, 10, 8, 6]
	for i in bases.size():
		for attack_kind in [SimState.BALL_ATTACK_NORMAL, SimState.BALL_ATTACK_JUST]:
			var toss = _resolve_contact(attack_kind,
				CONTACT_TOSS, bases[i], true)[2]
			var receive = _resolve_contact(attack_kind,
				CONTACT_RECEIVE, bases[i], true)[2]
			var just = _resolve_contact(attack_kind,
				CONTACT_JUST, bases[i], true)[2]
			var dive = _resolve_contact(attack_kind,
				CONTACT_DIVE, bases[i], true)[2]
			check_eq(100 - toss.guard, bases[i],
				"バーンアウト地上トスは倍率なし rank=%d kind=%d" % [i, attack_kind])
			check_eq(100 - receive.guard, receive_damage[i],
				"バーンアウト通常レシーブは倍率なし rank=%d kind=%d" % [i, attack_kind])
			check_eq(100 - just.guard, receive_damage[i],
				"バーンアウト中はジャスト封印で通常レシーブ相当 rank=%d kind=%d" % [i, attack_kind])
			check_eq(100 - dive.guard, bases[i],
				"バーンアウト飛びつきは倍率なし rank=%d kind=%d" % [i, attack_kind])

func test_dive_takes_full_guard_damage_without_butt_drop() -> void:
	for attack_kind in [SimState.BALL_ATTACK_NORMAL, SimState.BALL_ATTACK_JUST]:
		for dive_input in [0, Simulation.IN_DOWN]:
			var p = _resolve_contact(attack_kind, CONTACT_DIVE, 25,
				false, 100, dive_input)[2]
			check_eq(p.guard, 75, "飛びつきは全量: %d/%d" % [attack_kind, dive_input])
			check_eq(p.drive_gauge, 100,
				"飛びつきはdrive 0: %d/%d" % [attack_kind, dive_input])
			check_eq(p.flinch, 0,
				"飛びつき後にしりもちしない: %d/%d" % [attack_kind, dive_input])
			check(p.dive != 0, "dive表示は着地まで残す: %d/%d" % [attack_kind, dive_input])
			check_eq(p.vx, 0,
				"接触成功で専用水平速度は終了: %d/%d" % [attack_kind, dive_input])

func test_ground_toss_guard_break_stuns_without_blowback() -> void:
	var p = _resolve_contact(SimState.BALL_ATTACK_NORMAL, CONTACT_TOSS, 25,
		false, 25)[2]
	check(p.stun > 0, "地上トスのブレイクは気絶")
	check_eq(p.guard, p.guard_max, "地上トスのブレイクでguard満タン復帰")
	check_eq(p.vx, 0, "地上トスのブレイクは後方初速なし")
	check_eq(p.push, 0, "地上トスのブレイクは壁方向押し出しなし")

func test_normal_receive_guard_break_stuns_without_blowback() -> void:
	var p = _resolve_contact(SimState.BALL_ATTACK_JUST, CONTACT_RECEIVE, 25,
		false, 10)[2]
	check(p.stun > 0, "通常レシーブのブレイクは気絶")
	check_eq(p.guard, p.guard_max, "通常レシーブのブレイクでguard満タン復帰")
	check_eq(p.vx, 0, "通常レシーブのブレイクは後方初速なし")
	check_eq(p.push, 0, "通常レシーブのブレイクは壁方向押し出しなし")

func test_dive_guard_break_stuns_without_blowback() -> void:
	var result := _resolve_contact(SimState.BALL_ATTACK_JUST, CONTACT_DIVE, 25,
		false, 25)
	var cfg = result[1]
	var p = result[2]
	check(p.stun > 0, "飛びつきのブレイクは気絶")
	check_eq(p.guard, p.guard_max, "飛びつきのブレイクでguard満タン復帰")
	check_eq(p.vx, 0, "飛びつきのブレイクは後方初速なし")
	check_eq(p.push, 0, "飛びつきのブレイクは壁方向押し出しなし")
	check_eq(p.dive, 0, "気絶時はdive状態を終了")
	check_eq(p.vy, -cfg.dive_receive_hop, "気絶時も現在の縦速度を維持")

func test_regular_attack_guard_payload_does_not_damage_air_contacts() -> void:
	for input in [Simulation.IN_ACTION,
			Simulation.IN_ACTION | Simulation.IN_DOWN]:
		var w := _world()
		var s = w[0]
		var cfg = w[1]
		var p = s.players[0]
		p.on_ground = 0
		p.guard = 100
		s.last_touch_team = 1
		s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
		s.ball_guard_damage = 25
		HitResolver._apply_hit(s, 0, cfg, input, 0)
		check_eq(p.guard, 100, "空中接触は今回のガード損害対象外: input=%d" % input)

func test_regular_attack_guard_payload_does_not_damage_blocker() -> void:
	var w := _world()
	var s = w[0]
	var cfg = w[1]
	var p = s.players[2]
	p.x = cfg.net_x + FP.from_int(20)
	p.y = cfg.floor_y - FP.from_int(60)
	p.on_ground = 0
	p.guard = 100
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_guard_damage = 25
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate
	HitResolver._ball_vs_block(s, cfg,
		[0, 0, Simulation.IN_ACTION | Simulation.IN_LEFT, 0])
	check_eq(p.guard, 100, "ブロックは今回のガード損害対象外")

func test_just_attack_ground_contacts_keep_mangled_control_loss() -> void:
	for contact in [CONTACT_TOSS, CONTACT_RECEIVE, CONTACT_DIVE]:
		var probe := _world()
		var cfg = probe[1]
		var result := _resolve_contact(SimState.BALL_ATTACK_JUST, contact, 25,
			false, 100, 0, cfg.player_reach * cfg.player_reach)
		var s = result[0]
		var incoming_vx: int = FP.from_int(600) / cfg.tick_rate
		check(s.ball_vx < -incoming_vx / 2,
			"パワー球の芯外し制御喪失を維持: contact=%d vx=%d" % [contact, s.ball_vx])
