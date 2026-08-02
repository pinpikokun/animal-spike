extends "res://tests/test_case.gd"

const BallPhysics := preload("res://src/sim/ball_physics.gd")
const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SpecialBall := preload("res://src/sim/special_ball.gd")

func _incoming(s, cfg, special_id: int, owner: int = 2) -> void:
	var entry: Dictionary = Chars.super_def(special_id)
	SpecialBall.set_special(s, special_id, owner, -cfg.spike_vx)
	s.ball_vx = -cfg.spike_vx
	s.ball_vy = cfg.spike_vy
	s.ball_power = 1 if int(entry.power) > 0 else 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL if int(entry.power) > 0 \
		else SimState.BALL_ATTACK_NONE
	s.ball_health_damage = int(entry.power)
	s.ball_defense_class = int(entry.defense_class)
	s.ball_attack_id = 31
	s.ball_attacker_id = owner
	s.ball_attack_commit_tick = 7
	s.last_touch_team = 1

func _receive_world(special_id: int, just: bool = false) -> Array:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_PANDA, Chars.CHAR_PANDA, Chars.CHAR_PIYO, Chars.CHAR_UME],
		0, 0)
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.x = FP.from_int(120)
	p.y = cfg.floor_y
	p.on_ground = 1
	p.health = 100
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(10)
	_incoming(s, cfg, special_id)
	if just:
		p.stance_active = 1
		p.receive_stance = cfg.just_receive_window_ticks
		p.stance_action_id = 4
		p.stance_started_tick = 0
		p.stance_committed_attack_id = s.ball_attack_id
		p.stance_pre_read_candidate = 1
	return [s, cfg, p]

func _block_world(special_id: int) -> Array:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_PANDA, Chars.CHAR_PANDA, Chars.CHAR_PIYO, Chars.CHAR_UME],
		0, 0)
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.drive_gauge = cfg.drive_gauge_max
	p.x = cfg.net_x - FP.from_int(20)
	p.y = cfg.floor_y
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	_incoming(s, cfg, special_id)
	return [s, cfg, p]

func _receive(s, cfg, just: bool = false) -> void:
	HitResolver._apply_hit(s, 0, cfg,
		SimInput.IN_ACTION | SimInput.IN_DOWN, 0, false)

func test_catalog_damage_uses_normal_receive_and_just_multipliers() -> void:
	var cases := [
		[Chars.SUPER_FEINT_ATTACK, 8],
		[Chars.SUPER_GUST_ATTACK, 8],
		[Chars.SUPER_BUMBLE_BALL, 8],
		[Chars.SUPER_THUNDER_BALL, 8],
		[Chars.SUPER_BUBBLE_PACK, 4],
		[Chars.SUPER_REFRAIN_ATTACK, 4],
		[Chars.SUPER_FLAME_ATTACK, 16],
	]
	for row in cases:
		var w := _receive_world(row[0])
		_receive(w[0], w[1])
		check_eq(w[2].health, 100 - row[1], "通常レシーブ倍率: %d" % row[0])
		var just_w := _receive_world(row[0], true)
		_receive(just_w[0], just_w[1], true)
		check_eq(just_w[2].health, 100, "ジャストは体力無傷: %d" % row[0])
		if row[0] == Chars.SUPER_FLAME_ATTACK:
			check_eq(just_w[2].burn, just_w[1].burn_stun_ticks,
				"炎はジャストでも炎上を残す")
		elif row[0] == Chars.SUPER_THUNDER_BALL:
			check_eq(just_w[2].shock_ticks, just_w[1].shock_ticks,
				"雷はジャストでも感電を残す")

func test_thunder_and_flame_status_survive_receive_and_block_but_not_air_return() -> void:
	var thunder := _receive_world(Chars.SUPER_THUNDER_BALL)
	_receive(thunder[0], thunder[1])
	check_eq(thunder[2].shock_ticks, thunder[1].shock_ticks,
		"雷はレシーブしても感電")
	var flame := _receive_world(Chars.SUPER_FLAME_ATTACK)
	_receive(flame[0], flame[1])
	check_eq(flame[2].burn, flame[1].burn_stun_ticks,
		"炎はレシーブしても炎上")

	var thunder_block := _block_world(Chars.SUPER_THUNDER_BALL)
	HitResolver._ball_vs_block(thunder_block[0], thunder_block[1],
		[SimInput.IN_ACTION | SimInput.IN_RIGHT, 0, 0, 0])
	check_eq(thunder_block[2].shock_ticks, thunder_block[1].shock_ticks,
		"雷はブロックしても感電")
	check_eq(thunder_block[2].health, 100, "通常ブロックは体力無傷")

	for special_id in [Chars.SUPER_FLAME_ATTACK, Chars.SUPER_THUNDER_BALL]:
		var w := _receive_world(special_id)
		var s = w[0]; var cfg = w[1]; var p = w[2]
		p.on_ground = 0
		p.y = s.ball_y
		HitResolver._apply_hit(s, 0, cfg,
			SimInput.IN_ACTION | SimInput.IN_DOWN, 0, false)
		check_eq(p.health, 100, "空中アタック返しは無傷: %d" % special_id)
		check_eq(p.burn + p.shock_ticks, 0, "空中返しは状態なし: %d" % special_id)
		check_eq(s.ball_special_id, 0, "空中返しで通常球化: %d" % special_id)

func test_bubble_and_knockback_apply_only_when_defense_fails() -> void:
	var bubble_receive := _receive_world(Chars.SUPER_BUBBLE_PACK)
	_receive(bubble_receive[0], bubble_receive[1])
	check_eq(bubble_receive[2].bubble_ticks, 0, "レシーブ成功なら泡なし")
	var bubble_fail := _receive_world(Chars.SUPER_BUBBLE_PACK)
	HitResolver._apply_hit(bubble_fail[0], 0, bubble_fail[1], SimInput.IN_ACTION, 0)
	check_eq(bubble_fail[2].bubble_ticks, bubble_fail[1].bubble_ticks,
		"通常トス接触は防御失敗で泡")
	for special_id in [Chars.SUPER_GUST_ATTACK, Chars.SUPER_BUMBLE_BALL]:
		var w := _receive_world(special_id)
		HitResolver._apply_hit(w[0], 0, w[1], SimInput.IN_ACTION, 0)
		check(w[2].flinch > 0, "防御失敗で横ノックバック: %d" % special_id)

func test_any_piyo_air_attack_derives_gust_attack_for_free() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_PANDA, Chars.CHAR_PIYO, Chars.CHAR_PIYO, Chars.CHAR_UME],
		0, 0)
	s.phase = SimState.PHASE_RALLY
	var p = s.players[1]
	p.on_ground = 0
	p.drive_gauge = 0
	p.burnout_ticks = 0
	p.x = FP.from_int(180)
	p.y = cfg.net_top_y - FP.from_int(80)
	s.ball_x = p.x; s.ball_y = p.y
	s.last_touch_team = 0
	SpecialBall.set_special(s, Chars.SUPER_GUST_BALL, 0, cfg.spike_vx)
	s.ball_vx = cfg.spike_vx; s.ball_vy = 0
	HitResolver._apply_hit(s, 1, cfg,
		SimInput.IN_ACTION | SimInput.IN_DOWN, 0)
	check_eq(s.ball_special_id, Chars.SUPER_GUST_ATTACK,
		"作成者でないPIYOでも自動派生")
	check_eq(p.drive_gauge, 0, "Dなし・残量0でも追加消費なし")
	check_eq(s.ball_health_damage, 22, "突風アタック威力22")

	var other := SimState.new()
	other.load_int_array(s.to_int_array())
	other.players[1].char_id = Chars.CHAR_PANDA
	other.ball_special_id = Chars.SUPER_GUST_BALL
	other.ball_health_damage = 0
	other.ball_power = 0
	HitResolver._apply_hit(other, 1, cfg,
		SimInput.IN_ACTION | SimInput.IN_DOWN, 0)
	check(other.ball_special_id != Chars.SUPER_GUST_ATTACK,
		"PIYO以外は派生しない")

func test_refrain_receive_waits_twenty_one_ticks_and_block_ends_repeat() -> void:
	var w := _receive_world(Chars.SUPER_REFRAIN_ATTACK)
	var s = w[0]; var cfg = w[1]
	s.ball_y = cfg.net_top_y - FP.from_int(60)
	_receive(s, cfg)
	check_eq(s.ball_special_id, Chars.SUPER_REFRAIN_ATTACK, "レシーブ後も技を維持")
	check_eq(s.ball_special_phase, 1, "レシーブで待機開始")
	check(not SpecialBall.is_contactable(s), "待機中は再接触不能")
	check_eq(s.ball_attack_id, 31, "同じ攻撃IDを維持")
	check_eq(s.ball_health_damage, 11, "反復中も威力11")
	var wait_x: int = s.ball_x
	for _i in 20:
		BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_x, wait_x, "20tickまでは停止")
	BallPhysics._step_ball(s, cfg)
	check_eq(s.ball_special_phase, 2, "21tickで再発射")
	check(s.ball_x != wait_x, "21tick目に攻撃方向へ再移動")

	var blocked := _block_world(Chars.SUPER_REFRAIN_ATTACK)
	HitResolver._ball_vs_block(blocked[0], blocked[1],
		[SimInput.IN_ACTION | SimInput.IN_RIGHT, 0, 0, 0])
	check_eq(blocked[0].ball_special_id, 0, "ブロックで反復終了")

func test_invisible_and_waiting_special_balls_cannot_contact_players() -> void:
	for special_id in [Chars.SUPER_DISAPPEARING_BALL, Chars.SUPER_TRANSFER_BALL]:
		var w := _receive_world(special_id)
		check_eq(HitResolver._resolve_hit(w[0],
			[SimInput.IN_ACTION | SimInput.IN_DOWN, 0, 0, 0], w[1]),
			HitResolver.NO_HIT, "消失中は接触不能: %d" % special_id)
	var refrain := _receive_world(Chars.SUPER_REFRAIN_ATTACK)
	refrain[0].ball_special_phase = 1
	check_eq(HitResolver._resolve_hit(refrain[0],
		[SimInput.IN_ACTION | SimInput.IN_DOWN, 0, 0, 0], refrain[1]),
		HitResolver.NO_HIT, "リフレイン待機中は接触不能")
