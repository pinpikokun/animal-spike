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
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
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

func test_jump_level_scales_height() -> void:
	check(Chars.Profile.jump_height_px(Chars.Profile.RANK_A)
		> Chars.Profile.jump_height_px(Chars.Profile.RANK_E),
		"ジャンプランクが高いほど最高高度が高い")

func test_character_rank_does_not_change_max_health() -> void:
	var w = _rally(); var cfg = w[1]
	var s = St.new()
	s.players[2].char_id = Chars.CHAR_DEBUG
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	# reset_matchがROSTERでchar_idを上書きするため、既定ロスターは全員100
	for p in s.players:
		check_eq(p.max_health, 100, "既定ロスターは最大体力100")

func test_all_hundred_matches_legacy_values() -> void:
	# 全キャラ100(既定)なら従来の速度値と完全一致する(挙動不変の直接検証。
	# 全体の不変はtest_syncのゴールデンが担保する)
	var w = _rally(); var s = w[0]; var cfg = w[1]
	Sim.tick(s, [SimInput.IN_RIGHT, 0], cfg)
	check_eq(s.players[0].vx, cfg.move_speed, "speed100=cfg.move_speedそのまま")

func test_reset_match_custom_roster() -> void:
	# キャラ選択画面が渡すロスターがsimへ通る。既定ROSTERも明示して渡す
	var cfg = Cfg.new()
	var s = St.new()
	var roster: Array = [Chars.CHAR_MARIO, Chars.CHAR_MARIO, Chars.CHAR_PANDA, Chars.CHAR_FROG]
	Sim.reset_match(s, cfg, 0, roster, 0, 0)
	for i in 4:
		check_eq(s.players[i].char_id, roster[i], "slot%dのchar_id" % i)
	check_eq(s.players[0].has_hat, 1, "マリオ編成は帽子持ち")
	check_eq(s.players[2].has_hat, 0, "パンダは帽子無し")
	var s2 = St.new()
	Sim.reset_match(s2, cfg, 0, Chars.ROSTER, 0, 0)
	for i in 4:
		check_eq(s2.players[i].char_id, Chars.ROSTER[i], "明示した既定ロスター")

func _measure_full_jump(char_id: int) -> Array[int]:
	var cfg = Cfg.new()
	var s = St.new()
	Sim.reset_match(s, cfg, 0, Chars.ROSTER, 0, 0)
	s.phase = St.PHASE_POINT_PAUSE
	s.timer = 1000000
	var p = s.players[0]
	p.char_id = char_id
	var floor_y: int = p.y
	var min_y: int = floor_y
	var apex_tick := -1
	var land_tick := -1
	for tick in 240:
		Sim.step(s, [SimInput.IN_JUMP, 0, 0, 0], cfg)
		min_y = mini(min_y, p.y)
		if apex_tick < 0 and p.on_ground == 0 and p.vy >= 0:
			apex_tick = tick + 1
		if tick > 0 and p.on_ground == 1:
			land_tick = tick + 1
			break
	return [FP.to_int(floor_y - min_y), apex_tick, land_tick - apex_tick]

func test_jump_level_targets_foot_height() -> void:
	var panda := _measure_full_jump(Chars.CHAR_PANDA)
	var mario := _measure_full_jump(Chars.CHAR_MARIO)
	var frog := _measure_full_jump(Chars.CHAR_FROG)
	check(absi(panda[0] - 140) <= 2, "パンダのジャンプCは140px: actual=%d" % panda[0])
	check(absi(mario[0] - 140) <= 2, "マリオのジャンプCは140px: actual=%d" % mario[0])
	check(absi(frog[0] - 140) <= 2, "カエルのジャンプCは140px: actual=%d" % frog[0])

func test_original_character_full_jump_uses_shared_rank_height() -> void:
	var expected := {
		Chars.CHAR_TOME: 200,
		Chars.CHAR_HITO: 140,
		Chars.CHAR_PIYO: 140,
		Chars.CHAR_UME: 110,
		Chars.CHAR_CARBY: 170,
		Chars.CHAR_DUO: 140,
		Chars.CHAR_SEC1: 140,
		Chars.CHAR_SEC2: 140,
	}
	for cid in expected:
		var measured := _measure_full_jump(cid)
		check(absi(measured[0] - expected[cid]) <= 2,
			"%sの足元最高点は%dpx: actual=%d" \
			% [Chars.NAMES[cid], expected[cid], measured[0]])

func test_original_jump_extremes_stay_playable_on_court() -> void:
	var cfg = Cfg.new()
	var tome := _measure_full_jump(Chars.CHAR_TOME)
	check(FP.to_int(cfg.floor_y) - tome[0] >= 0,
		"最高ジャンプTOMEの足元は画面上端を越えない")
	var ume := _measure_full_jump(Chars.CHAR_UME)
	var ume_hand_y := FP.to_int(cfg.floor_y) - ume[0] - FP.to_int(cfg.player_reach_up)
	check(ume_hand_y <= FP.to_int(cfg.net_top_y),
		"最低ジャンプEのUMEも上リーチがネット上へ届く: hand_y=%d" % ume_hand_y)

func test_jump_level_height_table() -> void:
	var expected := [200, 170, 140, 120, 110]
	for i in expected.size():
		check_eq(Chars.Profile.jump_height_px(i), expected[i],
			"ジャンプ%sの指定高度" % Chars.Profile.rank_name(i))

func test_standard_weight_gives_same_airtime() -> void:
	var panda := _measure_full_jump(Chars.CHAR_PANDA)
	var mario := _measure_full_jump(Chars.CHAR_MARIO)
	var frog := _measure_full_jump(Chars.CHAR_FROG)
	check_eq(panda.slice(1), mario.slice(1), "パンダとマリオの滞空時間は同じ")
	check_eq(mario.slice(1), frog.slice(1), "マリオとカエルの滞空時間は同じ")
