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
	check_eq(Chars.stat(Chars.CHAR_PANDA, "speed"), 100, "ランクCの速度は100")
	check_eq(Chars.stat(Chars.CHAR_DEBUG, "speed"), 130, "明示%値は最優先")
	check_eq(Chars.stat(Chars.CHAR_DEBUG, "sc_atk"), 0, "旧攻撃ばらつきstatは撤去")
	check_eq(Chars.stat(999, "speed"), 100, "未知キャラは100(安全側)")
	check_eq(Chars.stat(999, "sc_toss"), 0, "未知キャラのばらつきは0(安全側)")

func test_rank_stats_feed_existing_physics_as_standard_values() -> void:
	for cid in Chars.SELECTABLE:
		check_eq(Chars.stat(cid, "atk"), 100, "パワーCは100%")
		check_eq(Chars.stat(cid, "speed"), 100, "スピードCは100%")
		check_eq(Chars.stat(cid, "slide"), 100, "ブレーキCは距離100%")
		check_eq(Chars.stat(cid, "guard_max"), 100, "ガードCは100%")
		check_eq(Chars.stat(cid, "weight"), 100, "重量は標準100%")

func test_roster_shape() -> void:
	check_eq(Chars.ROSTER.size(), 4, "ロスターは4slot")
	check_eq(Chars.ROSTER[1], Chars.CHAR_MARIO, "slot1=マリオ")
	for cid in Chars.ROSTER:
		check(Chars.DEFS.has(cid), "ロスター全員に定義がある")

func test_chars_exposes_profile_traits() -> void:
	check(Chars.has_trait(Chars.CHAR_MARIO, Chars.Profile.TRAIT_TOSS_GOOD),
		"chars窓口からマリオのトス上手を取得できる")
	check(Chars.has_trait(Chars.CHAR_PANDA, Chars.Profile.TRAIT_MURA),
		"chars窓口からパンダのむらっけを取得できる")
	check_eq(Chars.traits(Chars.CHAR_FOX), [], "キツネの付与能力は空")
