extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const SimRng := preload("res://src/sim/sim_rng.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")

func _match(seed: int = 0) -> Array:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, seed)
	return [s, cfg]

func _gameplay_snapshot(s) -> Array[int]:
	var out: Array[int] = s.to_int_array()
	out[1] = 0
	out[2] = 0
	return out

func _prepare_ground_hit(s, cfg) -> void:
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.y = cfg.floor_y
	p.on_ground = 1
	s.ball_x = p.x
	s.ball_y = p.y - FP.from_int(10)
	s.ball_vx = 0
	s.ball_vy = 0
	s.last_touch_team = 1

func _apply_ground_hit(s, cfg) -> void:
	_prepare_ground_hit(s, cfg)
	HitResolver._apply_hit(s, 0, cfg, Simulation.IN_ACTION, 0)

func _apply_block_hit(s, cfg) -> void:
	s.phase = SimState.PHASE_RALLY
	var p = s.players[0]
	p.x = cfg.net_x - FP.from_int(30)
	p.y = cfg.floor_y - FP.from_int(140)
	p.on_ground = 0
	s.last_touch_team = 1
	s.ball_x = p.x + FP.from_int(5)
	s.ball_y = p.y - cfg.player_reach_up
	s.ball_vx = -FP.from_int(8)
	s.ball_vy = FP.from_int(6)
	HitResolver._ball_vs_block(
		s, cfg, [Simulation.IN_ACTION | Simulation.IN_UP, 0, 0, 0])

func test_rng_fields_roundtrip_and_affect_hash() -> void:
	var original = SimState.new()
	original.rng = 0x1234
	original.aitick = 0xABCD
	var restored = SimState.new()
	restored.load_int_array(original.to_int_array())
	check_eq(restored.rng, 0x1234, "rngを復元")
	check_eq(restored.aitick, 0xABCD, "aitickを復元")
	check_eq(restored.state_hash(), original.state_hash(), "状態往復でハッシュ一致")

	var base = SimState.new()
	var rng_changed = SimState.new()
	rng_changed.rng = 1
	var aitick_changed = SimState.new()
	aitick_changed.aitick = 1
	check(rng_changed.state_hash() != base.state_hash(), "rngが同期ハッシュへ入る")
	check(aitick_changed.state_hash() != base.state_hash(), "aitickが同期ハッシュへ入る")

func test_reset_match_seeds_both_words_and_reset_rally_preserves_them() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 0x12345)
	check_eq(s.rng, 0x2345, "reset_matchでrngを16bit seedへ初期化")
	check_eq(s.aitick, 0x2345, "reset_matchでaitickを同じseedへ初期化")

	s.rng = 0x1111
	s.aitick = 0x2222
	Simulation.reset_rally(s, cfg, 1)
	check_eq(s.rng, 0x1111, "reset_rallyはrngを維持")
	check_eq(s.aitick, 0x2222, "reset_rallyはaitickを維持")

	Simulation.reset_match(s, cfg, 1, Chars.ROSTER, -1)
	check_eq(s.rng, 0xFFFF, "次の試合だけrngを再初期化")
	check_eq(s.aitick, 0xFFFF, "次の試合だけaitickを再初期化")

func test_tick_advances_only_rng_once_during_normal_freeze_and_slow_ticks() -> void:
	var normal := _match(0x1234)
	normal[0].phase = SimState.PHASE_GAME_OVER
	var normal_aitick: int = normal[0].aitick
	var normal_expected: int = SimRng.advance_frame(normal[0].rng, normal_aitick)
	Simulation.tick(normal[0], [0, 0], normal[1])
	check_eq(normal[0].rng, normal_expected, "通常tickでrngを1回進める")
	check_eq(normal[0].aitick, normal_aitick, "通常tickでaitickを進めない")

	var frozen := _match(0x2345)
	frozen[0].phase = SimState.PHASE_GAME_OVER
	frozen[0].hit_freeze = 1
	var frozen_aitick: int = frozen[0].aitick
	var frozen_expected: int = SimRng.advance_frame(frozen[0].rng, frozen_aitick)
	Simulation.tick(frozen[0], [0, 0], frozen[1])
	check_eq(frozen[0].rng, frozen_expected, "hit freeze中もrngを1回進める")
	check_eq(frozen[0].aitick, frozen_aitick, "hit freeze中もaitickを進めない")

	var slowed := _match(0x3456)
	slowed[0].phase = SimState.PHASE_GAME_OVER
	slowed[0].slow_ticks = 2
	var slowed_aitick: int = slowed[0].aitick
	var slowed_expected: int = SimRng.advance_frame(slowed[0].rng, slowed_aitick)
	Simulation.tick(slowed[0], [0, 0], slowed[1])
	check_eq(slowed[0].rng, slowed_expected, "slow早期returnでもrngを1回進める")
	check_eq(slowed[0].aitick, slowed_aitick, "slow中もaitickを進めない")

	var direct := _match(0x4567)
	direct[0].phase = SimState.PHASE_GAME_OVER
	var direct_rng: int = direct[0].rng
	var direct_aitick: int = direct[0].aitick
	Simulation.step(direct[0], [0, 0, 0, 0], direct[1])
	check_eq(direct[0].rng, direct_rng, "step直呼びはrngを進めない")
	check_eq(direct[0].aitick, direct_aitick, "step直呼びはaitickを進めない")

func test_hit_and_role_swap_update_aitick_in_fixed_order() -> void:
	var normal := _match()
	normal[0].rng = 3
	normal[0].aitick = 0xFFFE
	_apply_ground_hit(normal[0], normal[1])
	check_eq(normal[0].aitick, 1, "通常打撃でaitick += rngを1回")

	var serve := _match()
	serve[0].rng = 7
	serve[0].aitick = 5
	serve[0].serve_tossed = 1
	HitResolver._apply_hit(serve[0], 0, serve[1], Simulation.IN_ACTION, 0)
	check_eq(serve[0].aitick, 12, "サーブ打撃もaitick += rngを1回")

	var block := _match()
	block[0].rng = 2
	block[0].aitick = 40
	_apply_block_hit(block[0], block[1])
	check_eq(block[0].aitick, 42, "ブロック打撃もaitick += rngを1回")

	var role_swap := _match()
	role_swap[0].rng = 20
	role_swap[0].aitick = 10
	role_swap[0].cpu_hit_count = HitResolver.CPU_ROLE_SWAP_HITS - 1
	role_swap[0].cpu_back_role_mask = 0
	_apply_ground_hit(role_swap[0], role_swap[1])
	check_eq(role_swap[0].aitick, 31, "打球加算の後に役割周期の+1を1回")
	check_eq(role_swap[0].cpu_back_role_mask, 0xF, "両CPUチームの位置取り役を入れ替える")

func test_rng_scaffold_keeps_cpu_inputs_and_gameplay_state_seed_independent() -> void:
	var cfg = SimConfig.new()
	var a = SimState.new()
	var b = SimState.new()
	Simulation.reset_match(a, cfg, 0, Chars.ROSTER, 0x0000)
	Simulation.reset_match(b, cfg, 0, Chars.ROSTER, 0xFFFF)
	a.controlled_l = 1
	b.controlled_l = 1
	a.controlled_r = 1
	b.controlled_r = 1

	for t in 120:
		var cpu_a: Array[int] = []
		var cpu_b: Array[int] = []
		for i in SimState.PLAYER_COUNT:
			cpu_a.append(SimCpu.decide(a, i, cfg))
			cpu_b.append(SimCpu.decide(b, i, cfg))
		check_eq(cpu_a, cpu_b, "seed差でCPU入力を変えない tick=%d" % t)
		Simulation.tick(a, [0, 0], cfg)
		Simulation.tick(b, [0, 0], cfg)
		check_eq(_gameplay_snapshot(a), _gameplay_snapshot(b),
			"seed差で既存ゲーム状態を変えない tick=%d" % t)
