extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const FP := preload("res://src/sim/fp.gd")

func _world() -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = SimState.PHASE_RALLY
	return [s, cfg]

func _arm_flame(s, damage: int = 40) -> void:
	s.last_touch_team = 1
	s.ball_power = 1
	s.ball_flame = 1
	s.ball_guard_damage = damage
	s.ball_defense_class = Chars.DEFENSE_UNBLOCKABLE
	s.ball_attack_kind = SimState.BALL_ATTACK_NONE

func test_flame_catalog_power_is_fixed_across_attacker_power_ranks() -> void:
	var cfg = SimConfig.new()
	for rank in [Chars.Profile.RANK_A, Chars.Profile.RANK_E]:
		var rank_damage: int = cfg.power_guard_damage_for_rank(rank)
		check(rank_damage != 40, "ランク由来削り値と必殺技固定威力を混同しない")
		check_eq(Chars.super_def(Chars.SUPER_FLAME_ATTACK).power, 40,
			"攻撃側POWERランク%sでもカタログ固定40" % Chars.Profile.rank_name(rank))

func test_flame_two_hits_deal_eighty_without_stun() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 100
	for hit in 2:
		# 固定ダメージの累積だけを検証するため、前の炎上が明けた次の被弾を再現する。
		p.burn = 0
		p.on_ground = 1
		_arm_flame(s)
		HitResolver._apply_hit(s, 0, cfg,
			Simulation.IN_ACTION | Simulation.IN_DOWN,
			cfg.player_reach * cfg.player_reach)
	check_eq(p.guard, 20, "2発で合計80ダメージ")
	check_eq(p.stun, 0, "2発では耐久を割らず気絶しない")

func test_unblockable_class_not_visual_flame_blocks_just_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 100
	p.receive_stance = 1
	p.drive_gauge = 3000
	_arm_flame(s)
	s.ball_flame = 0
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(p.guard, 60, "炎表示なしでも防御不能分類なら固定40を受ける")
	check_eq(p.just_receive_event, 0, "分類フラグによりジャストレシーブ不可")
	check_eq(p.drive_gauge, 3000, "必殺技は相手ドライブを削らない")

func test_flame_attack_return_cancels_without_damage() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 40
	p.on_ground = 0
	_arm_flame(s)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN, 0)
	check_eq(p.guard, 40, "アタック返しは無傷")
	check_eq(s.ball_defense_class, Chars.DEFENSE_NONE, "防御不能分類を消去")
	check_eq(s.ball_flame, 0, "表示属性も消去")

func test_burnout_multiplies_fixed_flame_damage_to_sixty() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 100
	p.burnout_ticks = cfg.burnout_recovery_ticks
	_arm_flame(s)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	check_eq(p.guard, 40, "固定40へバーンアウト3/2を掛けて60")

func test_flame_hit_starts_configured_burn_knockback() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 100
	p.y = cfg.floor_y
	p.on_ground = 1
	_arm_flame(s)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	check_eq(p.burn, cfg.burn_stun_ticks, "炎上時間はrules.jsonの90tick")
	check(p.vx < 0, "左チームは自陣側へ炎上ノックバック")
	check(p.vy < 0, "炎上被弾で上へ舞い上がる")
	check_eq(p.on_ground, 0, "炎上ノックバックは空中物理へ移す")

func test_flame_guard_break_defers_stun_until_burn_ends() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.guard = 40
	_arm_flame(s)
	HitResolver._apply_hit(s, 0, cfg,
		Simulation.IN_ACTION | Simulation.IN_DOWN,
		cfg.player_reach * cfg.player_reach)
	check_eq(p.guard, 0, "炎上中は割れた耐久を0のまま保持")
	check_eq(p.stun, 0, "炎上被弾tickでは即気絶しない")
	check_eq(p.burn, cfg.burn_stun_ticks, "気絶より先に炎上状態へ入る")

func test_burning_player_cannot_ground_receive() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burn = 10
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	p.on_ground = 1
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(10)
	s.last_touch_team = 1
	HitResolver._resolve_hit(
		s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.last_touch_team, 1, "炎上中は地上レシーブで球に触れない")

func test_last_burn_tick_still_ignores_hit_input() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burn = 1
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	p.on_ground = 1
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(10)
	s.last_touch_team = 1
	Simulation._step_players_and_hits(
		s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(p.burn, 0, "最終tickの物理更新後に炎上解除")
	check_eq(s.last_touch_team, 1, "炎上最終tickも打撃入力を無視")

func test_burning_player_cannot_air_attack() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burn = 10
	p.x = FP.from_int(100)
	p.y = cfg.floor_y - FP.from_int(80)
	p.on_ground = 0
	s.ball_x = p.x
	s.ball_y = p.y
	s.last_touch_team = 1
	HitResolver._resolve_hit(
		s, [Simulation.IN_ACTION | Simulation.IN_DOWN, 0, 0, 0], cfg)
	check_eq(s.last_touch_team, 1, "炎上中は空中アタックで球に触れない")

func test_burning_player_cannot_block() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burn = 10
	p.x = cfg.net_x - FP.from_int(20)
	p.y = cfg.floor_y - FP.from_int(80)
	p.on_ground = 0
	s.ball_x = p.x
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(10)
	s.last_touch_team = 1
	HitResolver._ball_vs_block(
		s, cfg, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0])
	check_eq(s.ball_vx, -FP.from_int(10), "炎上中はブロック反射できない")
	check_eq(s.last_touch_team, 1, "炎上中のブロックはタッチにならない")

func test_last_burn_tick_still_cannot_block() -> void:
	var w := _world(); var s = w[0]; var cfg = w[1]
	var p = s.players[0]
	p.burn = 1
	p.x = cfg.net_x - FP.from_int(20)
	p.y = cfg.floor_y - FP.from_int(80)
	p.on_ground = 0
	s.ball_x = p.x - FP.from_int(10)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(10)
	s.last_touch_team = 1
	Simulation.step(s, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0], cfg)
	check_eq(p.burn, 0, "ブロック判定前に炎上最終tickの物理更新が終わる")
	check(s.ball_vx < 0, "炎上最終tickもブロック反射しない")
	check_eq(s.last_touch_team, 1, "炎上最終tickのブロックはタッチにならない")
