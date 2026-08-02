extends "res://tests/test_case.gd"

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")

func test_reset_uses_one_hundred_health_for_every_character() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_UME, Chars.CHAR_PIYO, Chars.CHAR_PANDA, Chars.CHAR_CARBY], 0, 0)
	for p in s.players:
		check_eq(p.max_health, 100, "キャラ差なしの最大体力")
		check_eq(p.health, 100, "セット開始体力")

func test_burn_ignores_move_jump_and_mash_inputs() -> void:
	var cfg = SimConfig.new()
	var input_burn = SimState.Player.new()
	var idle_burn = SimState.Player.new()
	for p in [input_burn, idle_burn]:
		p.burn = 10
		p.x = FP.from_int(100)
		p.y = cfg.floor_y - FP.from_int(20)
		p.on_ground = 0
		p.vx = FP.from_int(3)
		p.vy = 0
	PlayerMovement._step_player(input_burn,
		Simulation.IN_LEFT | Simulation.IN_JUMP | Simulation.IN_ACTION, cfg, 0)
	PlayerMovement._step_player(idle_burn, 0, cfg, 0)
	check_eq(input_burn.x, idle_burn.x, "炎上中は左右入力を無視")
	check_eq(input_burn.y, idle_burn.y, "炎上中はジャンプ入力を無視")
	check_eq(input_burn.vx, idle_burn.vx, "炎上中の横物理は入力に依存しない")
	check_eq(input_burn.vy, idle_burn.vy, "炎上中の縦物理は入力に依存しない")
	check_eq(input_burn.burn, idle_burn.burn, "炎上は連打しても短縮されない")

func test_burn_expiry_returns_to_normal_control() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.burn = 1
	p.x = FP.from_int(100)
	p.y = cfg.floor_y
	p.on_ground = 1
	PlayerMovement._step_player(p, 0, cfg, 0)
	check_eq(p.burn, 0, "規定tickの終了で炎上解除")
	var before_x: int = p.x
	PlayerMovement._step_player(p, Simulation.IN_RIGHT, cfg, 0)
	check(p.x > before_x, "炎上解除後は通常の移動入力へ戻る")

func test_health_zero_waits_for_burn_expiry_before_stun() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.max_health = 100
	p.health = 0
	p.burn = 2
	p.y = cfg.floor_y
	p.on_ground = 1
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.burn, 1, "炎上は連打で余分に減らない")
	check_eq(p.stun_ticks, 0, "炎上中の体力0は即気絶させない")
	check_eq(p.health, 0, "炎上中は体力0を保持")
	PlayerMovement._step_player(p, 0, cfg, 0)
	check_eq(p.burn, 0, "炎上終了")
	check_eq(p.stun_ticks, cfg.stun_ticks, "炎上が明けてから気絶へ移行")
	check_eq(p.health, 0, "スタン解除までは体力0を維持")

func test_burn_physics_bounces_on_floor() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.burn = 10
	p.y = cfg.floor_y - FP.from_int(1)
	p.vy = FP.from_int(4)
	p.on_ground = 0
	PlayerMovement._step_player(p, 0, cfg, 0)
	check_eq(p.y, cfg.floor_y, "炎上中の落下は床面で止める")
	check(p.vy < 0, "炎上中は床で上向きに反発する")
	check(-p.vy > cfg.gravity, "重力1tick分を超える反発は2/3減衰バウンドを続ける")
	check_eq(p.on_ground, 0, "反発後は空中物理を継続")

func test_burn_bounce_converges_to_ground() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.burn = cfg.burn_stun_ticks
	p.y = cfg.floor_y
	p.vy = FP.from_int(4)
	p.on_ground = 0
	var bounced := false
	for tick in cfg.burn_stun_ticks - 1:
		PlayerMovement._step_player(p, 0, cfg, 0)
		if p.vy < 0:
			bounced = true
		if bounced and p.on_ground == 1:
			break
	check(bounced, "収束前には実際に床で反発する")
	check_eq(p.vy, 0, "小さい反発は速度0へ収束する")
	check_eq(p.on_ground, 1, "炎上中でも減衰後は接地状態になる")

func test_burn_expiry_keeps_converged_player_on_ground() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.burn = cfg.burn_stun_ticks
	p.y = cfg.floor_y
	p.vy = FP.from_int(4)
	p.on_ground = 0
	while p.burn > 1:
		PlayerMovement._step_player(p, 0, cfg, 0)
	check_eq(p.on_ground, 1, "炎上終了前にバウンドは接地へ収束済み")
	PlayerMovement._step_player(p, 0, cfg, 0)
	check_eq(p.burn, 0, "炎上が終了するtick")
	check_eq(p.on_ground, 1, "炎上が明けた最初のtickも接地を維持")

func test_burn_launch_uses_configured_apex_height() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.char_id = Chars.CHAR_UME
	HitResolver._ignite_player(p, 0, cfg)
	var apex: int = HitResolver.apex_height(p.vy, cfg.gravity)
	var target: int = FP.from_int(cfg.burn_launch_height_px)
	check(p.vy < 0, "炎上被弾で上向き初速を与える")
	check(absi(apex - target) <= FP.ONE, "炎上打ち上げ頂点は設定値の1px以内")
