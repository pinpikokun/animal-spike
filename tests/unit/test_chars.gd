extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")

func test_mario_has_signature_abilities() -> void:
	check(Chars.has_ability(Chars.CHAR_MARIO, Chars.CA_HAT), "マリオ=帽子")
	check(Chars.has_ability(Chars.CHAR_MARIO, Chars.CA_HIP), "マリオ=ヒップ")
	check(Chars.has_ability(Chars.CHAR_MARIO, Chars.CA_CLING), "マリオ=壁貼り")
	check(not Chars.has_ability(Chars.CHAR_MARIO, Chars.CA_DASH), "マリオ=ダッシュ無し")

func test_panda_has_no_abilities() -> void:
	check(not Chars.has_ability(Chars.CHAR_PANDA, Chars.CA_HAT), "パンダ帽子なし")
	check(not Chars.has_ability(Chars.CHAR_PANDA, Chars.CA_HIP), "パンダヒップなし")
	check(not Chars.has_ability(Chars.CHAR_PANDA, Chars.CA_CLING), "パンダ壁貼りなし")

func test_stat_defaults() -> void:
	check_eq(Chars.stat(Chars.CHAR_PANDA, "speed"), 100, "未定義キーは100")
	check_eq(Chars.stat(Chars.CHAR_PANDA, "sc_toss"), 0, "ばらつき系の既定は0")
	check_eq(Chars.stat(Chars.CHAR_DEBUG, "speed"), 130, "定義キーは定義値")
	check_eq(Chars.stat(999, "speed"), 100, "未知キャラも100(安全側)")

func test_roster_shape() -> void:
	check_eq(Chars.ROSTER.size(), 4, "ロスターは4slot")
	check_eq(Chars.ROSTER[1], Chars.CHAR_MARIO, "slot1=マリオ")
	for cid in Chars.ROSTER:
		check(Chars.DEFS.has(cid), "ロスター全員に定義がある")
