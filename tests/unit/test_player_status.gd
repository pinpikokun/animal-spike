extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")
const PlayerStatus := preload("res://src/sim/player_status.gd")
const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")

func _original_vx(value: int, cfg) -> int:
	return value * (cfg.court_width / 2) * cfg.original_tick_rate_milli \
		/ (72 * cfg.tick_rate * 1000)

func _original_vy(value: int, cfg) -> int:
	return value * (cfg.floor_y - cfg.net_top_y) * cfg.original_tick_rate_milli \
		/ (33 * cfg.tick_rate * 1000)

func test_shock_launch_reapply_and_last_tick_lock_are_exact() -> void:
	var cfg := SimConfig.new()
	var p := SimState.Player.new()
	p.char_id = Chars.CHAR_CARBY
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	PlayerStatus.apply_shock(p, 0, cfg)
	check_eq(p.shock_ticks, 60, "感電60tick")
	check_eq(p.vx, _original_vx(-2, cfg), "左チームは原作後方2")
	check_eq(p.vy, _original_vy(-2, cfg), "原作vy=vxを軸別換算")
	p.shock_ticks = 40
	PlayerStatus.apply_shock(p, 0, cfg)
	check_eq(p.shock_ticks, 60, "再付与は長い方")
	p.shock_ticks = 1
	check(PlayerStatus.input_locked(p), "最終tick開始時も入力不能")
	check(PlayerStatus.step(p, cfg, 0, 10, 0, 123), "感電物理が通常移動を消費")
	check_eq(p.shock_ticks, 0, "最終tick終了時に解除")
	check(not PlayerStatus.input_locked(p), "次tickから入力可能")

func test_shock_uses_burn_friction_gravity_and_floor_bounce() -> void:
	var cfg := SimConfig.new()
	var p := SimState.Player.new()
	p.x = FP.from_int(100)
	p.y = cfg.floor_y - 1
	p.vx = FP.from_int(8)
	p.vy = FP.from_int(4)
	p.shock_ticks = 2
	PlayerStatus.step(p, cfg, 0, 1, 0, 0)
	check_eq(p.vx, FP.from_int(6), "炎上と同じ4分の3摩擦")
	check_eq(p.y, cfg.floor_y, "床へ固定")
	check(p.vy < 0, "炎上と同じ3分の2反発")

func test_bubble_wave_rng_rise_timeout_and_top_exit_are_deterministic() -> void:
	var cfg := SimConfig.new()
	var a := SimState.Player.new()
	a.x = FP.from_int(200)
	a.y = cfg.floor_y
	PlayerStatus.apply_bubble(a, cfg)
	var b := SimState.Player.new()
	b.x = a.x; b.y = a.y; b.bubble_ticks = a.bubble_ticks
	for tick in 34:
		PlayerStatus.step(a, cfg, 0, tick, 0, 17)
		PlayerStatus.step(b, cfg, 0, tick, 0, 17)
	check_eq(a.x, b.x, "同じrngとactorで泡の横波が一致")
	check_eq(a.y, cfg.floor_y - _original_vy(8, cfg) * 34,
		"原作上8換算で34tick上昇")
	check_eq(a.bubble_ticks, 26, "34tick後の残り")
	for tick in 26:
		PlayerStatus.step(a, cfg, 0, 34 + tick, 0, 17)
	check_eq(a.bubble_ticks, 0, "60tickで解除")

	var top := SimState.Player.new()
	top.x = FP.from_int(100)
	top.y = _original_vy(8, cfg) - 1
	PlayerStatus.apply_bubble(top, cfg)
	PlayerStatus.step(top, cfg, 0, 1, 0, 9)
	check_eq(top.bubble_ticks, 0, "上端到達で早期解除")
	check_eq(top.y, 0, "画面上端へ固定")
	check_eq(top.on_ground, 0, "泡終了後は通常空中状態")

func test_status_timers_advance_together_but_physics_uses_priority() -> void:
	var cfg := SimConfig.new()
	var p := SimState.Player.new()
	p.x = FP.from_int(120)
	p.y = cfg.floor_y
	p.stun_ticks = 2
	p.bubble_ticks = 3
	p.shock_ticks = 4
	p.burn = 5
	var before_y: int = p.y
	check(not PlayerStatus.step(p, cfg, 0, 1, 0, 5),
		"最優先スタンは通常の入力ゼロ物理へ渡す")
	check_eq(p.stun_ticks, 1, "スタンも進む")
	check_eq(p.bubble_ticks, 2, "泡も進む")
	check_eq(p.shock_ticks, 3, "感電も進む")
	check_eq(p.burn, 4, "炎上も進む")
	check_eq(p.y, before_y, "下位の泡物理を実行しない")

func test_actual_status_application_is_cleared_by_rally_and_match_reset() -> void:
	var cfg := SimConfig.new()
	var s := SimState.new()
	Simulation.reset_match(s, cfg, 0, Chars.ROSTER, 1, 2)
	PlayerStatus.apply_shock(s.players[0], 0, cfg)
	PlayerStatus.apply_bubble(s.players[1], cfg)
	Simulation.reset_rally(s, cfg, 0)
	check_eq(s.players[0].shock_ticks, 0, "ラリー再開で感電解除")
	check_eq(s.players[1].bubble_ticks, 0, "ラリー再開で泡解除")
	PlayerStatus.apply_shock(s.players[0], 0, cfg)
	PlayerStatus.apply_bubble(s.players[1], cfg)
	Simulation.reset_match(s, cfg, 1, Chars.ROSTER, 3, 4)
	check_eq(s.players[0].shock_ticks, 0, "試合初期化で感電解除")
	check_eq(s.players[1].bubble_ticks, 0, "試合初期化で泡解除")

