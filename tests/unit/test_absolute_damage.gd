extends "res://tests/test_case.gd"

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")
const FP := preload("res://src/sim/fp.gd")

func test_rank_tables_are_absolute_monotonic_and_evenly_spaced() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.guard_max_by_rank, [120, 110, 100, 90, 80],
		"GUARDランクは絶対値")
	check_eq(cfg.power_guard_damage_by_rank, [35, 30, 25, 20, 15],
		"POWERランクはジャスト削り絶対値")
	for rank in 4:
		check_eq(cfg.guard_max_by_rank[rank] - cfg.guard_max_by_rank[rank + 1], 10,
			"耐久は10刻みで単調減少")
		check_eq(cfg.power_guard_damage_by_rank[rank]
			- cfg.power_guard_damage_by_rank[rank + 1], 5,
			"削りは5刻みで単調減少")

func test_absolute_damage_hit_count_matrix() -> void:
	var cfg = SimConfig.new()
	check_eq(cfg.guard_max_for_rank(Chars.Profile.RANK_C)
		/ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_C), 4,
		"C対Cは4発")
	check_eq((cfg.guard_max_for_rank(Chars.Profile.RANK_E)
		+ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_A) - 1)
		/ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_A), 3,
		"POWER A対GUARD Eは3発")
	check_eq(cfg.guard_max_for_rank(Chars.Profile.RANK_A)
		/ cfg.power_guard_damage_for_rank(Chars.Profile.RANK_E), 8,
		"POWER E対GUARD Aは8発")

func test_reset_reads_guard_rank_as_absolute_value() -> void:
	var cfg = SimConfig.new()
	var s = SimState.new()
	Simulation.reset_match(s, cfg, 0,
		[Chars.CHAR_UME, Chars.CHAR_PIYO, Chars.CHAR_PANDA, Chars.CHAR_CARBY], 0, 0)
	check_eq(s.players[0].guard_max, 120, "GUARD A")
	check_eq(s.players[1].guard_max, 80, "GUARD E")
	check_eq(s.players[2].guard_max, 100, "GUARD C")
	check_eq(s.players[3].guard_max, 90, "GUARD D")

func test_stun_mash_uses_action_press_edges_only() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.stun = 20
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.stun, 16, "初回押下は通常1tick+連打3tick短縮")
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.stun, 15, "押しっぱなしは通常減衰のみ")
	PlayerMovement._step_player(p, 0, cfg, 0)
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.stun, 10, "離して再押下すると再び短縮")
	check_eq(p.stun_mash_event, 2, "表示用イベントも押下エッジだけ進む")

func test_stun_mashing_recovers_faster_than_no_input() -> void:
	var cfg = SimConfig.new()
	var mashed = SimState.Player.new()
	var idle = SimState.Player.new()
	mashed.stun = 20
	idle.stun = 20
	for tick in 8:
		var input: int = Simulation.IN_ACTION if tick % 2 == 0 else 0
		PlayerMovement._step_player(mashed, input, cfg, 0)
		PlayerMovement._step_player(idle, 0, cfg, 0)
	check_eq(mashed.stun, 0, "交互連打は8tick以内に復帰")
	check(idle.stun > 0, "非連打は同じ時間では気絶中")

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

func test_guard_break_waits_for_burn_expiry_before_stun() -> void:
	var cfg = SimConfig.new()
	var p = SimState.Player.new()
	p.guard_max = 100
	p.guard = 0
	p.burn = 2
	p.y = cfg.floor_y
	p.on_ground = 1
	PlayerMovement._step_player(p, Simulation.IN_ACTION, cfg, 0)
	check_eq(p.burn, 1, "炎上は連打で余分に減らない")
	check_eq(p.stun, 0, "炎上中の耐久0は即気絶させない")
	check_eq(p.guard, 0, "炎上中は耐久0を保持")
	PlayerMovement._step_player(p, 0, cfg, 0)
	check_eq(p.burn, 0, "炎上終了")
	check_eq(p.stun, cfg.stun_ticks, "炎上が明けてから気絶へ移行")
	check_eq(p.guard, p.guard_max, "気絶移行時に耐久を全回復")

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
