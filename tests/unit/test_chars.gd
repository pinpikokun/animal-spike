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
	check_eq(Chars.stat(Chars.CHAR_PANDA, "speed"), 100, "レベル未対応キーは100")
	check_eq(Chars.stat(Chars.CHAR_DEBUG, "speed"), 130, "明示%値は最優先")
	check_eq(Chars.stat(999, "speed"), 100, "未知キャラは100(安全側)")
	check_eq(Chars.stat(999, "sc_toss"), 0, "未知キャラのばらつきは0(安全側)")

func test_level_conversion() -> void:
	# 10段階レベル→%換算(5=標準100)。パンダ:トス2/攻8/跳3/重8、マリオ:トス8/攻2/跳5/重5
	check_eq(Chars.stat(Chars.CHAR_PANDA, "jump"), 80, "パンダ跳Lv3=80%")
	check_eq(Chars.stat(Chars.CHAR_PANDA, "atk"), 130, "パンダ攻Lv8=130%")
	check_eq(Chars.stat(Chars.CHAR_PANDA, "weight"), 136, "パンダ重Lv8=136%")
	check_eq(Chars.stat(Chars.CHAR_PANDA, "absorb"), 70, "パンダはトス下手=受け流し70%")
	check_eq(Chars.stat(Chars.CHAR_PANDA, "sc_toss"), 64, "パンダのトスは大きく散る")
	check_eq(Chars.stat(Chars.CHAR_PANDA, "sc_atk"), 48, "強打型はアタックも荒れる")
	check_eq(Chars.stat(Chars.CHAR_MARIO, "jump"), 100, "マリオ跳Lv5=現行のまま")
	check_eq(Chars.stat(Chars.CHAR_MARIO, "atk"), 70, "マリオ攻Lv2=70%")
	check_eq(Chars.stat(Chars.CHAR_MARIO, "absorb"), 130, "マリオはトス上手=受け流し130%")
	check_eq(Chars.stat(Chars.CHAR_MARIO, "sc_toss"), 16, "マリオも完全にはブレなくならない")
	check_eq(Chars.stat(Chars.CHAR_MARIO, "sc_atk"), 0, "弱打型のアタックは正確")
	check_eq(Chars.stat(Chars.CHAR_FROG, "jump"), 130, "カエル跳Lv8=130%")
	check_eq(Chars.stat(Chars.CHAR_FROG, "weight"), 64, "カエル重Lv2=軽量")
	check_eq(Chars.stat(Chars.CHAR_FOX, "jump"), 100, "フォックスは全部Lv5=標準")

func test_roster_shape() -> void:
	check_eq(Chars.ROSTER.size(), 4, "ロスターは4slot")
	check_eq(Chars.ROSTER[1], Chars.CHAR_MARIO, "slot1=マリオ")
	for cid in Chars.ROSTER:
		check(Chars.DEFS.has(cid), "ロスター全員に定義がある")

func test_player_facing_stat_keys_are_complete() -> void:
	var expected := ["toss", "atk", "jump", "weight", "speed", "slide",
		"guard", "just_window", "just_reward", "absorb", "toss_stability",
		"recv_stability", "atk_stability", "block_stability"]
	for key in expected:
		var lv: int = Chars.level(Chars.CHAR_PANDA, key)
		check(lv >= 1 and lv <= 10, "%sを10段階で取得できる" % key)

func test_display_levels_use_player_facing_direction() -> void:
	check_eq(Chars.level(Chars.CHAR_PANDA, "toss"), 2, "パンダのトス")
	check_eq(Chars.level(Chars.CHAR_PANDA, "speed"), 5, "未設定能力は標準5")
	check_eq(Chars.level(Chars.CHAR_PANDA, "toss_stability"), 2,
		"トスの内部ばらつきを安定性へ反転する")
	check_eq(Chars.level(Chars.CHAR_PANDA, "atk_stability"), 4,
		"強打型パンダのアタック安定性")
	check_eq(Chars.level(Chars.CHAR_MARIO, "atk_stability"), 10,
		"内部ばらつき0は最高安定性")
	check_eq(Chars.level(Chars.CHAR_FOX, "block_stability"), 10,
		"内部ばらつき0は最高安定性")
