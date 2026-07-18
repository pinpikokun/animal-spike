extends "res://tests/test_case.gd"

const FP := preload("res://src/sim/fp.gd")
const Cfg := preload("res://src/sim/sim_config.gd")
const St := preload("res://src/sim/sim_state.gd")
const Sim := preload("res://src/sim/simulation.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const Chars := preload("res://src/sim/chars.gd")

func _rally():
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0)
	s.phase = St.PHASE_RALLY
	s.serve_tossed = 1
	return [s, cfg]

func test_speed_stat_scales_movement() -> void:
	# CHAR_DEBUG=speed130。標準キャラと同入力で移動距離が130%になる
	var w = _rally(); var s = w[0]; var cfg = w[1]
	var x0: int = s.players[0].x
	Sim.tick(s, [SimInput.IN_RIGHT, 0], cfg)
	var base: int = s.players[0].x - x0
	var w2 = _rally(); var s2 = w2[0]
	s2.players[0].char_id = Chars.CHAR_DEBUG
	var x1: int = s2.players[0].x
	Sim.tick(s2, [SimInput.IN_RIGHT, 0], cfg)
	var fast: int = s2.players[0].x - x1
	check_eq(fast, base * 130 / 100, "speed130で移動が1.3倍")

func test_jump_stat_scales_jump() -> void:
	var w = _rally(); var s = w[0]; var cfg = w[1]
	Sim.tick(s, [SimInput.IN_JUMP, 0], cfg)
	var base_vy: int = s.players[0].vy
	var w2 = _rally(); var s2 = w2[0]
	s2.players[0].char_id = Chars.CHAR_DEBUG  # jump120
	Sim.tick(s2, [SimInput.IN_JUMP, 0], cfg)
	check(s2.players[0].vy < base_vy, "jump120で初速が強い(上向き=より負)")

func test_guard_max_stat_applies_on_reset() -> void:
	var w = _rally(); var cfg = w[1]
	var s = St.new()
	s.players[2].char_id = Chars.CHAR_DEBUG  # stats指定なし枠はguard_max=100%
	Sim.reset_match(s, cfg, 0)
	# reset_matchがROSTERでchar_idを上書きするため、既定ロスターは全員100
	for p in s.players:
		check_eq(p.guard_max, 100, "既定ロスターは耐久100")

func test_all_hundred_matches_legacy_values() -> void:
	# 全キャラ100(既定)なら従来の速度値と完全一致する(挙動不変の直接検証。
	# 全体の不変はtest_syncのゴールデンが担保する)
	var w = _rally(); var s = w[0]; var cfg = w[1]
	Sim.tick(s, [SimInput.IN_RIGHT, 0], cfg)
	check_eq(s.players[0].vx, cfg.move_speed, "speed100=cfg.move_speedそのまま")

func test_reset_match_custom_roster() -> void:
	# キャラ選択画面が渡すロスターがsimへ通る。省略時は既定ROSTER(挙動不変)
	var cfg = Cfg.new()
	var s = St.new()
	var roster: Array = [Chars.CHAR_MARIO, Chars.CHAR_MARIO, Chars.CHAR_PANDA, Chars.CHAR_FROG]
	Sim.reset_match(s, cfg, 0, roster)
	for i in 4:
		check_eq(s.players[i].char_id, roster[i], "slot%dのchar_id" % i)
	check_eq(s.players[0].has_hat, 1, "マリオ編成は帽子持ち")
	check_eq(s.players[2].has_hat, 0, "パンダは帽子無し")
	var s2 = St.new()
	Sim.reset_match(s2, cfg, 0)
	for i in 4:
		check_eq(s2.players[i].char_id, Chars.ROSTER[i], "省略時は既定ロスター")

func test_scatter_is_deterministic() -> void:
	# 同じtick/actor/saltなら同じ値(両ピア同値・ロールバック再現の土台)
	var s = St.new()
	s.tick = 1234
	var a: int = Sim._scatter(s, 1, 11)
	var b: int = Sim._scatter(s, 1, 11)
	check_eq(a, b, "同キーで同値")
	check(a >= -100 and a <= 100, "範囲は-100..100")
	var c: int = Sim._scatter(s, 2, 11)
	var d: int = Sim._scatter(s, 1, 13)
	check(a != c or a != d, "actor/saltで散る(縮退していない)")
