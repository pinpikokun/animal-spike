extends "res://tests/test_case.gd"
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")

func _rally():
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0)
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

func test_hat_costs_guard() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var g0 = s.players[1].guard
	Sim.tick(s, [SimInput.IN_ABILITY1, 0], cfg)
	check(s.players[1].guard < g0, "帽子投げで耐久を消費 guard=%d" % s.players[1].guard)

func test_hat_without_stamina_stuns() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	s.players[1].guard = 5  # スタミナ不足
	Sim.tick(s, [SimInput.IN_ABILITY1, 0], cfg)
	check(s.players[1].stun > 0, "スタミナ切れで投げるとスタン stun=%d" % s.players[1].stun)
	check(_cap(s) == null, "帽子は出ない")
	check_eq(s.players[1].guard, s.players[1].guard_max, "スタン時に全快")
