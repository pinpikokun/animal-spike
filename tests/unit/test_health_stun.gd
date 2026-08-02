extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")

func test_match_starts_every_character_at_one_hundred_health() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, [0, 1, 2, 3], 1, 2)
	for p in s.players:
		check_eq(p.max_health, 100, "全キャラの最大体力を100へ統一")
		check_eq(p.health, 100, "セット開始時は体力100")

func test_health_zero_starts_three_hundred_tick_stun_and_blocks_damage() -> void:
	var cfg = SimConfig.new()
	var p = SimState.new().players[0]
	p.health = 10
	check_eq(CombatResources.apply_health_damage(p, 15, cfg), 10, "残体力分だけ損害")
	check_eq(p.health, 0, "初回0到達は0へクランプ")
	check_eq(p.stun_ticks, 300, "5秒スタンを開始")
	check_eq(p.stunned_this_rally, 1, "同一ラリーのスタン済みを記録")
	check_eq(CombatResources.apply_health_damage(p, 50, cfg), 0, "スタン中は追加損害0")
	check_eq(p.health, 0, "スタン中は体力0を維持")

func test_stun_lasts_exactly_three_hundred_ticks_without_mash_shortening() -> void:
	var cfg = SimConfig.new()
	var a = SimState.new().players[0]
	var b = SimState.new().players[0]
	for p in [a, b]:
		p.health = 0
		p.max_health = 100
		p.stun_ticks = 300
		p.stunned_this_rally = 1
	for _tick in 299:
		PlayerMovement._step_player(a, 0, cfg, 0)
		PlayerMovement._step_player(b, Simulation.IN_ACTION, cfg, 0)
	check_eq(a.stun_ticks, 1, "299tickではスタン継続")
	check_eq(b.stun_ticks, 1, "ACTION連打でも299tickでは継続")
	PlayerMovement._step_player(a, 0, cfg, 0)
	PlayerMovement._step_player(b, Simulation.IN_ACTION, cfg, 0)
	check_eq(a.stun_ticks, 0, "300tickで解除")
	check_eq(b.stun_ticks, 0, "連打なしと同じtickで解除")
	check_eq(a.health, 100, "時間解除で体力100")
	check_eq(b.health, 100, "連打側も体力100")

func test_same_rally_recovery_clamps_damage_to_one_then_next_rally_can_stun() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	var p = s.players[0]
	p.health = 100
	p.max_health = 100
	p.stunned_this_rally = 1
	CombatResources.apply_health_damage(p, 150, cfg)
	check_eq(p.health, 1, "同一ラリー復帰後は最低1")
	check_eq(p.stun_ticks, 0, "同一ラリーでは再スタンしない")
	Simulation.reset_rally(s, cfg, 0)
	check_eq(p.stunned_this_rally, 0, "次ラリーでスタン済みを解除")
	CombatResources.apply_health_damage(p, 150, cfg)
	check_eq(p.stun_ticks, 300, "次ラリーでは再びスタン可能")

func test_rally_end_recovers_stun_immediately_without_drive_changes() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.health = 0
	p.max_health = 100
	p.stun_ticks = 200
	p.stunned_this_rally = 1
	p.drive_gauge = 17
	p.burnout_ticks = 321
	Simulation._award_point(s, 1, cfg)
	check_eq(p.health, 100, "ラリー終了で即時全回復")
	check_eq(p.stun_ticks, 0, "ラリー終了でスタン解除")
	check_eq(p.drive_gauge, 17, "スタン解除はドライブを変えない")
	check_eq(p.burnout_ticks, 321, "スタン解除はバーンアウトを変えない")

func test_stun_and_burnout_advance_together_during_rally() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	s.ball_x = cfg.net_x
	s.ball_y = -FP.from_int(100000)
	var p = s.players[0]
	p.health = 0
	p.stun_ticks = 10
	p.stunned_this_rally = 1
	p.burnout_ticks = 10
	Simulation.step(s, [0, 0, 0, 0], cfg)
	check_eq(p.stun_ticks, 9, "ラリー中はスタン時間が進む")
	check_eq(p.burnout_ticks, 9, "スタン中もバーンアウト時間が進む")

func test_contact_on_recovery_tick_applies_damage_once_after_full_recovery() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	p.on_ground = 1
	p.health = 0
	p.max_health = 100
	p.stun_ticks = 1
	p.stunned_this_rally = 1
	s.last_touch_team = 1
	s.ball_attack_kind = SimState.BALL_ATTACK_NORMAL
	s.ball_attack_id = s.alloc_attack_id()
	s.ball_health_damage = 150
	s.ball_power = 1
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	Simulation.step(s, [Simulation.IN_ACTION, 0, 0, 0], cfg)
	check_eq(p.stun_ticks, 0, "解除tickの接触で再スタンしない")
	check_eq(p.health, 1, "100復帰後に一度損害を適用して最低1")
