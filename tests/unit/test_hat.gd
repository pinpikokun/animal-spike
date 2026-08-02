extends "res://tests/test_case.gd"
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const Chars := preload("res://src/sim/chars.gd")

func _rally():
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = St.PHASE_RALLY
	s.serve_tossed = 1
	# 帽子持ちはマリオ(slot1)のみ。人間入力がslot1へ届くよう操作スロットを切り替える
	s.controlled_l = 1
	return [s, cfg]

# 帽子エンティティ(KIND_CAP)を返す。場に無ければnull
func _cap(s):
	var i: int = Sim.ent_find(s, Sim.KIND_CAP)
	return s.entities[i] if i >= 0 else null

func test_throw_and_return_cycle() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[1].face = 1
	Sim.tick(s, [SimInput.IN_ABILITY1, 0], cfg)
	check(s.players[1].throw > 0, "投げ溜め開始 throw=%d" % s.players[1].throw)
	check_eq(s.players[1].has_hat, 1, "溜め中はまだ帽子あり")
	# 溜めが終わると発射される
	for t in 40:
		Sim.tick(s, [0, 0], cfg)
		if _cap(s) != null:
			break
	check_eq(s.players[1].has_hat, 0, "発射で帽子を外す")
	check(_cap(s) != null, "帽子エンティティが場に出ている")
	# 十分な時間まわすと戻ってキャッチ(has_hat=1、スロット解放)する
	var caught := false
	for t in 400:
		Sim.tick(s, [0, 0], cfg)
		if s.players[1].has_hat == 1 and _cap(s) == null:
			caught = true
			break
	check(caught, "最終的に帽子が戻ってキャッチされスロットが解放される")

func test_no_throw_without_hat() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[1].has_hat = 0
	Sim.tick(s, [SimInput.IN_ABILITY1, 0], cfg)
	check(_cap(s) == null, "帽子が無ければ投げられない")

func test_cap_deflects_ball() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	# 帽子を滞在状態で場に置き、ボールを右から左へ突っ込ませる
	var slot: int = Sim.ent_spawn(s, Sim.KIND_CAP)
	var e = s.entities[slot]
	e.phase = 2
	e.x = cfg.net_x
	e.y = cfg.net_top_y
	e.owner = 0
	s.ball_x = cfg.net_x + FP_from(6)
	s.ball_y = cfg.net_top_y
	s.ball_vx = -FP_from(5)  # 左へ向かう
	s.ball_vy = 0
	Sim.tick(s, [0, 0], cfg)
	check(s.ball_vx > 0, "帽子の右側の球は右へ弾かれる vx=%d" % s.ball_vx)

func FP_from(v: int) -> int:
	return v << 16

func test_hat_costs_35_drive_without_health_cost() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var p = s.players[1]
	var health0: int = p.health
	var drive0: int = p.drive_gauge
	Sim.tick(s, [SimInput.IN_ABILITY1, 0], cfg)
	check_eq(p.drive_gauge, drive0 - cfg.special_drive_cost_default,
		"帽子投げはドライブゲージ1本消費")
	check_eq(p.health, health0,
		"帽子消費で回復ディレイ開始")
	check_eq(p.health, health0, "帽子投げで耐久は消費しない")

func test_hat_spends_exact_35_and_starts_burnout() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var p = s.players[1]
	p.drive_gauge = cfg.special_drive_cost_default
	var health0: int = p.health
	Sim.tick(s, [SimInput.IN_ABILITY1, 0], cfg)
	check(p.throw > 0, "残量が1以上なら1本未満でも帽子投げ発動")
	check_eq(p.drive_gauge, 0, "残量を全消費")
	check(p.burnout_ticks > 0, "使い切ってバーンアウト突入")
	check(s.hit_freeze > 0, "バーンアウト突入瞬間にヒットストップ")
	check_eq(p.health, health0, "使い切り発動でも耐久は変化しない")

func test_hat_at_zero_drive_does_nothing() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var p = s.players[1]
	p.drive_gauge = 0
	Sim._update_hat(s, [SimInput.IN_ABILITY1, 0, 0, 0], cfg)
	check_eq(p.throw, 0, "ゲージ0では帽子投げ不発")
