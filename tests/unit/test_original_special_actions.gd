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
const SpecialMoves := preload("res://src/sim/special_moves.gd")

const D := SimInput.IN_ABILITY1
const ACTION := SimInput.IN_ACTION
const LEFT := SimInput.IN_LEFT
const RIGHT := SimInput.IN_RIGHT

func _world(char_id: int, actor: int = 0) -> Array:
	var cfg := SimConfig.new()
	var s := SimState.new()
	var roster := [Chars.CHAR_PANDA, Chars.CHAR_PANDA,
		Chars.CHAR_PANDA, Chars.CHAR_PANDA]
	roster[actor] = char_id
	Simulation.reset_match(s, cfg, 0, roster, 0, 0)
	s.phase = SimState.PHASE_RALLY
	s.serve_ball = 0
	s.serve_flight = 0
	s.last_touch_team = 1 - SimState.team_of(actor)
	var p = s.players[actor]
	p.drive_gauge = cfg.drive_gauge_max
	p.x = cfg.court_width / 4 if actor < 2 else cfg.court_width * 3 / 4
	p.y = cfg.floor_y - FP.from_int(120)
	p.on_ground = 0
	p.vx = 0
	p.vy = 0
	s.ball_x = p.x
	s.ball_y = p.y
	s.ball_vx = 0
	s.ball_vy = 0
	return [s, cfg, p]

func _suction_input(actor: int) -> int:
	return D | (LEFT if SimState.team_of(actor) == 0 else RIGHT)

func _block_world(drive: int = 100, contact: bool = true) -> Array:
	var w := _world(Chars.CHAR_SEC1, 2)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	p.drive_gauge = drive
	p.x = cfg.net_x + FP.from_int(20)
	p.y = cfg.floor_y - FP.from_int(60)
	s.last_touch_team = 0
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_attacker_id = 0
	s.ball_health_damage = 22
	s.ball_power = 1
	s.ball_special_id = Chars.SUPER_REFRAIN_ATTACK
	s.ball_special_owner_idx = 0
	s.ball_x = p.x if contact else p.x + cfg.player_reach
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = FP.from_int(400) / cfg.tick_rate
	s.ball_vy = FP.from_int(2)
	return [s, cfg, p]

func _block_input() -> Array[int]:
	return [0, 0, ACTION | LEFT | D, 0]

func test_suction_starts_only_for_a_forward_target_in_original_range() -> void:
	var w := _world(Chars.CHAR_DUO)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	var horizontal_range: int = (cfg.court_width / 2) * 32 / 72
	s.ball_x = p.x + horizontal_range - 1
	s.ball_y = p.y
	var before: int = p.drive_gauge
	check(SpecialMoves.try_start_action(s, 0, _suction_input(0), cfg),
		"原作範囲内の前方球なら吸引開始")
	check_eq(p.drive_gauge, before - 35, "開始時に35を一度だけ消費")
	check_eq(p.special_action, Chars.SUPER_SUCTION, "吸引行動を保持")
	var player_x: int = p.x
	check(not SpecialMoves.step_action(s, 0, LEFT, cfg), "未捕球ではトスへ接続しない")
	check(s.ball_vx < 0, "右側の球をDUOへ引く")
	check_eq(p.x, player_x, "吸引自体はDUOを移動させない")

	var out := _world(Chars.CHAR_DUO)
	var os = out[0]
	var oc = out[1]
	var op = out[2]
	os.ball_x = op.x + (oc.court_width / 2) * 32 / 72
	check(not SpecialMoves.try_start_action(os, 0, _suction_input(0), oc),
		"横範囲の境界同値は対象外")
	check_eq(op.drive_gauge, oc.drive_gauge_max, "対象なしでは消費しない")

func test_suction_accepts_friendly_attack_but_rejects_hidden_transfer() -> void:
	var friendly := _world(Chars.CHAR_DUO)
	var fs = friendly[0]
	var fc = friendly[1]
	var fp = friendly[2]
	fs.last_touch_team = 0
	fs.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	fs.ball_x = fp.x + FP.from_int(20)
	check(SpecialMoves.try_start_action(fs, 0, _suction_input(0), fc),
		"味方の攻撃球も原作どおり吸引対象")

	var hidden := _world(Chars.CHAR_DUO)
	var hs = hidden[0]
	var hc = hidden[1]
	var hp = hidden[2]
	hs.ball_x = hp.x + FP.from_int(20)
	SpecialBall.set_special(hs, Chars.SUPER_TRANSFER_BALL, 2, hs.ball_vx)
	check(not SpecialMoves.try_start_action(hs, 0, _suction_input(0), hc),
		"消失中の異次元転送球は対象外")
	check_eq(hp.drive_gauge, hc.drive_gauge_max, "対象外では消費しない")

func test_suction_does_not_start_while_normal_contact_is_on_cooldown() -> void:
	var w := _world(Chars.CHAR_DUO)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	p.hit_cooldown = 1
	s.ball_x = p.x + FP.from_int(20)
	check(not SpecialMoves.try_start_action(s, 0, _suction_input(0), cfg),
		"捕球後の通常空中トスが成立しない硬直中は開始しない")
	check_eq(p.drive_gauge, cfg.drive_gauge_max, "半成立へ35を払わない")

func test_suction_contact_connects_to_normal_air_toss() -> void:
	var w := _world(Chars.CHAR_DUO)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	s.last_touch_team = 0
	s.touches = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_health_damage = 22
	s.ball_power = 1
	s.ball_x = p.x + FP.from_int(1)
	Simulation.step(s, [_suction_input(0), 0, 0, 0], cfg)
	check_eq(p.special_action, 0, "捕球時に吸引行動を終了")
	check_eq(p.hit_kind, SimState.HIT_KIND_TOSS, "通常空中トスへ接続")
	check_eq(s.ball_special_id, 0, "味方攻撃球を通常球へ戻す")
	check_eq(s.ball_power, 0, "通常空中トスは攻撃力を持ち越さない")
	check_eq(p.drive_gauge, cfg.drive_gauge_max - 35, "吸引費用は開始時の一回だけ")

func test_suction_ends_when_back_is_released_or_duo_lands() -> void:
	for landing in [false, true]:
		var w := _world(Chars.CHAR_DUO)
		var s = w[0]
		var cfg = w[1]
		var p = w[2]
		s.ball_x = p.x + FP.from_int(40)
		check(SpecialMoves.try_start_action(s, 0, _suction_input(0), cfg), "開始")
		if landing:
			p.on_ground = 1
		check(not SpecialMoves.step_action(s, 0, LEFT if landing else 0, cfg),
			"中断時は捕球扱いにしない")
		check_eq(p.special_action, 0,
			"%sで吸引終了" % ("着地" if landing else "後入力解除"))

func test_subspace_block_holds_only_after_normal_block_success() -> void:
	var w := _block_world(100)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	var incoming_vx: int = s.ball_vx
	var incoming_vy: int = s.ball_vy
	HitResolver._ball_vs_block(s, cfg, _block_input())
	var reflected_vx: int = -incoming_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
	reflected_vx = mini(reflected_vx, -cfg.net_repel)
	check_eq(p.drive_gauge, 55, "通常ブロック10の後に強化35を消費")
	check_eq(s.ball_held_by, 2, "成功したALIENが球を保持")
	check_eq(p.special_action, Chars.SUPER_SUBSPACE_BLOCK, "保持行動を記録")
	check_eq(s.ball_special_id, 0, "入射側リフレインを持ち越さない")
	check_eq(s.ball_vx, reflected_vx, "通常ブロック後の横速度を保存")
	check_eq(s.ball_vy, incoming_vy, "通常ブロック後の縦速度を保存")
	check_eq(s.touches, 1, "ブロック接触の一回だけ加算")

func test_subspace_miss_or_insufficient_upgrade_drive_remains_normal_block() -> void:
	var missed := _block_world(100, false)
	HitResolver._ball_vs_block(missed[0], missed[1], _block_input())
	check_eq(missed[2].drive_gauge, 95, "空振りは通常開始費5だけ")
	check_eq(missed[0].ball_held_by, -1, "空振りでは保持しない")

	var low := _block_world(44)
	HitResolver._ball_vs_block(low[0], low[1], _block_input())
	check_eq(low[2].drive_gauge, 34, "通常開始接触費は先に確定")
	check_eq(low[0].ball_held_by, -1, "強化35不足なら通常ブロック")
	check_eq(low[0].touches, 1, "強化失敗でも通常ブロックは成立")

func test_subspace_hold_follows_alien_and_requires_a_new_d_edge_to_release() -> void:
	var w := _block_world(100)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	HitResolver._ball_vs_block(s, cfg, _block_input())
	var held_vx: int = s.ball_vx
	var held_vy: int = s.ball_vy
	p.ability_latch = 1
	p.x += FP.from_int(7)
	check(not SpecialMoves.step_action(s, 2, D | LEFT, cfg),
		"開始Dの押しっぱなしでは解放しない")
	SpecialBall.step(s, cfg)
	check_eq(s.ball_held_by, 2, "押しっぱなし中は保持継続")
	check_eq(s.ball_vx, held_vx, "保持中も保存横速度は不変")
	check_eq(s.ball_vy, held_vy, "保持中も保存縦速度は不変")
	var held_x: int = s.ball_x
	p.x += FP.from_int(5)
	SpecialBall.step(s, cfg)
	check_eq(s.ball_x - held_x, FP.from_int(5), "ALIENの移動へ球が追従")

	p.ability_latch = 0
	check(not SpecialMoves.step_action(s, 2, D, cfg), "解放は捕球イベントではない")
	check_eq(s.ball_held_by, -1, "新しいD押下エッジで解放")
	check_eq(s.ball_vx, held_vx, "解放時も保存横速度を復元")
	check_eq(s.ball_vy, held_vy, "解放時も保存縦速度を復元")

func test_subspace_hold_times_out_at_forty_three_ticks_and_stops_physics() -> void:
	var w := _block_world(100)
	var s = w[0]
	var cfg = w[1]
	var p = w[2]
	HitResolver._ball_vs_block(s, cfg, _block_input())
	p.ability_latch = 0
	var held_vx: int = s.ball_vx
	var held_vy: int = s.ball_vy
	for tick in 42:
		check(not SpecialMoves.step_action(s, 2, 0, cfg), "保持中")
		BallPhysics._step_ball(s, cfg, [0, 0, 0, 0])
		check_eq(s.ball_vx, held_vx, "保持中は横物理停止")
		check_eq(s.ball_vy, held_vy, "保持中は重力停止")
		check_eq(s.touches, 1, "保持中にタッチを重ねない")
	check_eq(s.ball_held_by, 2, "42tickまでは保持")
	check(not SpecialMoves.step_action(s, 2, 0, cfg), "時間解放は捕球イベントではない")
	check_eq(s.ball_held_by, -1, "43tickで自動解放")
