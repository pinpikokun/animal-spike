extends "res://tests/test_case.gd"
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const PlayerMovement := preload("res://src/sim/player_movement.gd")
const Chars := preload("res://src/sim/chars.gd")

func _rally():
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = St.PHASE_RALLY
	s.serve_tossed = 1
	# 帽子持ち(ヒップアタック可)はマリオ(slot1)のみ。人間入力をslot1へ向ける
	s.controlled_l = 1
	return [s, cfg]

func test_hip_attack_hover_then_drop() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	# ジャンプして空中に
	Sim.tick(s, [SimInput.IN_JUMP, 0], cfg)
	for t in 3:
		Sim.tick(s, [0, 0], cfg)
	check_eq(s.players[1].on_ground, 0, "空中にいる")
	# 下だけでは不発、空中で下+Dの明示入力なら発動して静止する
	var drive0: int = s.players[1].drive_gauge
	Sim.tick(s, [SimInput.IN_DOWN, 0], cfg)
	check_eq(s.players[1].hip, 0, "空中で下だけでは発動しない")
	Sim.tick(s, [SimInput.IN_DOWN | SimInput.IN_ABILITY1, 0], cfg)
	check(s.players[1].hip > 0, "ヒップアタックで空中静止 hip=%d" % s.players[1].hip)
	check_eq(s.players[1].drive_gauge, drive0 - cfg.special_drive_cost_default,
		"ヒップアタックはドライブ35消費")
	check_eq(s.players[1].vy, 0, "静止中は落下しない")
	# 静止が終わると急降下して着地
	var landed := false
	for t in 120:
		Sim.tick(s, [0, 0], cfg)
		if s.players[1].on_ground == 1:
			landed = true
			break
	check(landed, "急降下して着地しhipが解ける")
	check_eq(s.players[1].hip, 0, "着地でhip解除")
	check_eq(s.hip_quake_event, 1, "着地地震イベントが発生")
	for p in s.players:
		check_eq(p.quake_stun, cfg.hip_quake_stun_ticks,
			"敵味方全員へ同じ地震硬直")

func test_hip_works_without_hat() -> void:
	# 固有技として独立: 帽子を投げてる最中(has_hat=0)でもヒップは出せる
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[1].has_hat = 0
	Sim.tick(s, [SimInput.IN_JUMP, 0], cfg)
	for t in 3:
		Sim.tick(s, [0, 0], cfg)
	Sim.tick(s, [SimInput.IN_DOWN | SimInput.IN_ABILITY1, 0], cfg)
	check(s.players[1].hip > 0, "帽子なしでもヒップ可(CA_HIPが条件)")

func test_hip_needs_ability() -> void:
	# CA_HIPを持たないキャラ(パンダ=slot0)はヒップ不可
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.controlled_l = 0
	Sim.tick(s, [SimInput.IN_JUMP, 0], cfg)
	for t in 3:
		Sim.tick(s, [0, 0], cfg)
	Sim.tick(s, [SimInput.IN_DOWN | SimInput.IN_ABILITY1, 0], cfg)
	check_eq(s.players[0].hip, 0, "CA_HIP無しはヒップ不可")

func test_hip_spends_exact_35_and_starts_burnout() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var p = s.players[1]
	p.y = cfg.floor_y - (20 << 16)
	p.on_ground = 0
	p.drive_gauge = cfg.special_drive_cost_default
	Sim.tick(s, [SimInput.IN_DOWN | SimInput.IN_ABILITY1, 0], cfg)
	check(p.hip > 0, "残量35ちょうどでヒップアタック発動")
	check_eq(p.drive_gauge, 0, "ヒップで残量を全消費")
	check_eq(p.drive_gauge, 0,
		"ヒップ消費で回復ディレイ開始")
	check(p.burnout_ticks > 0, "使い切ってバーンアウト突入")

func test_hip_at_zero_drive_does_nothing() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var p = s.players[1]
	p.y = cfg.floor_y - (20 << 16)
	p.on_ground = 0
	p.drive_gauge = 0
	PlayerMovement._step_player(p,
		SimInput.IN_DOWN | SimInput.IN_ABILITY1, cfg, 0)
	check_eq(p.hip, 0, "ゲージ0ではヒップアタック不発")

func test_hip_quake_stops_everyone_for_configured_ticks() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var hip = s.players[1]
	hip.hip = -1
	hip.on_ground = 0
	hip.y = cfg.floor_y - (1 << 16)
	Sim.tick(s, [0, 0], cfg)
	var before: Array[int] = []
	for p in s.players:
		before.append(p.x)
	Sim.tick(s, [SimInput.IN_RIGHT, SimInput.IN_LEFT], cfg)
	for i in s.players.size():
		check_eq(s.players[i].x, before[i], "地震硬直中は全員移動不能")

func test_wall_cling_slides() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	# 左壁際・空中に置いて左を押す
	var p = s.players[1]
	p.x = 0
	p.y = cfg.floor_y - (20 << 16)
	p.on_ground = 0
	p.vy = 0
	Sim.tick(s, [SimInput.IN_LEFT, 0], cfg)
	check(s.players[1].cling == 1, "左壁に張り付く cling=%d" % s.players[1].cling)
	check(s.players[1].vy > 0, "ずるずる降下 vy=%d" % s.players[1].vy)

func test_cling_needs_ability() -> void:
	# CA_CLINGを持たないキャラ(パンダ=slot0)は壁貼り不可(従来の全キャラ可はバグ)
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.controlled_l = 0
	var p = s.players[0]
	p.x = 0
	p.y = cfg.floor_y - (20 << 16)
	p.on_ground = 0
	p.vy = 0
	Sim.tick(s, [SimInput.IN_LEFT, 0], cfg)
	check_eq(s.players[0].cling, 0, "CA_CLING無しは張り付かない")
