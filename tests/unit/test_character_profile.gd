extends "res://tests/test_case.gd"

const Profile := preload("res://src/sim/character_profile.gd")
const Chars := preload("res://src/sim/chars.gd")

func test_rank_tables_match_accepted_values() -> void:
	var expected := {
		Profile.RANK_A: [150, 155, 120, 60, 150],
		Profile.RANK_B: [125, 145, 110, 80, 125],
		Profile.RANK_C: [100, 135, 100, 100, 100],
		Profile.RANK_D: [75, 120, 90, 125, 75],
		Profile.RANK_E: [50, 100, 80, 150, 50],
	}
	for rank in expected:
		check_eq(Profile.power_pct(rank), expected[rank][0], "パワー%s" % Profile.rank_name(rank))
		check_eq(Profile.jump_height_px(rank), expected[rank][1], "ジャンプ%s" % Profile.rank_name(rank))
		check_eq(Profile.speed_pct(rank), expected[rank][2], "スピード%s" % Profile.rank_name(rank))
		check_eq(Profile.brake_distance_pct(rank), expected[rank][3], "ブレーキ%s" % Profile.rank_name(rank))
		check_eq(Profile.guard_pct(rank), expected[rank][4], "ガード%s" % Profile.rank_name(rank))

func test_selectable_roster_has_explicit_profile_and_standard_weight() -> void:
	for cid in Chars.SELECTABLE:
		check(Profile.PROFILES.has(cid), "%sのプロファイルが明示されている" % Chars.NAMES[cid])
		check_eq(Profile.weight_pct(cid), 100, "%sの重量は標準" % Chars.NAMES[cid])

func test_original_character_rank_assignments() -> void:
	var expected := {
		Chars.CHAR_TOME: [Profile.RANK_C, Profile.RANK_A, Profile.RANK_E,
			Profile.RANK_C, Profile.RANK_C],
		Chars.CHAR_HITO: [Profile.RANK_C, Profile.RANK_C, Profile.RANK_C,
			Profile.RANK_C, Profile.RANK_C],
		Chars.CHAR_PIYO: [Profile.RANK_C, Profile.RANK_C, Profile.RANK_D,
			Profile.RANK_C, Profile.RANK_E],
		Chars.CHAR_UME: [Profile.RANK_C, Profile.RANK_E, Profile.RANK_A,
			Profile.RANK_C, Profile.RANK_A],
		Chars.CHAR_CARBY: [Profile.RANK_C, Profile.RANK_B, Profile.RANK_A,
			Profile.RANK_C, Profile.RANK_D],
		Chars.CHAR_DUO: [Profile.RANK_C, Profile.RANK_C, Profile.RANK_C,
			Profile.RANK_C, Profile.RANK_C],
		Chars.CHAR_SEC1: [Profile.RANK_C, Profile.RANK_C, Profile.RANK_C,
			Profile.RANK_C, Profile.RANK_C],
		Chars.CHAR_SEC2: [Profile.RANK_C, Profile.RANK_C, Profile.RANK_C,
			Profile.RANK_C, Profile.RANK_C],
	}
	for cid in expected:
		for i in Profile.BASE_ABILITIES.size():
			check_eq(Profile.rank(cid, Profile.BASE_ABILITIES[i]), expected[cid][i],
				"%sの%sランク" % [Chars.NAMES[cid], Profile.BASE_ABILITIES[i]])
		check_eq(Profile.traits(cid), [], "%sの付与能力は空" % Chars.NAMES[cid])
		check_eq(Profile.weight_pct(cid), 100, "%sの重量は標準" % Chars.NAMES[cid])

func test_trait_catalog_reserves_all_accepted_ids() -> void:
	var expected_names := [
		"トス上手", "レシーブ上手", "柔らかい手", "ブロック上手", "ジャスト巧者",
		"強心臓", "鉄壁", "空中制御", "クイック", "トス下手", "レシーブ下手",
		"むらっけ", "ブロック下手", "ノミの心臓", "打たれ弱い", "着地硬直",
		"急停止苦手", "空中不器用",
	]
	check_eq(Profile.TRAIT_NAMES.size(), expected_names.size(), "付与能力IDを全件予約する")
	for name in expected_names:
		check(Profile.TRAIT_NAMES.values().has(name), "%sのIDが予約済み" % name)
	check_eq(Profile.ACTIVE_TRAITS.size(), 5, "初回に有効な付与能力は5つだけ")

func test_initial_trait_assignments() -> void:
	check_eq(Profile.traits(Chars.CHAR_MARIO),
		[Profile.TRAIT_TOSS_GOOD, Profile.TRAIT_RECEIVE_GOOD], "マリオの付与能力")
	check_eq(Profile.traits(Chars.CHAR_PANDA),
		[Profile.TRAIT_TOSS_BAD, Profile.TRAIT_RECEIVE_BAD, Profile.TRAIT_MURA],
		"パンダの付与能力")
	check_eq(Profile.traits(Chars.CHAR_FOX), [], "キツネは付与能力なし")
	check_eq(Profile.traits(Chars.CHAR_FROG), [], "カエルは付与能力なし")

func test_opposite_traits_cannot_coexist() -> void:
	check(not Profile.traits_are_valid(
		[Profile.TRAIT_TOSS_GOOD, Profile.TRAIT_TOSS_BAD]), "トス上手と下手は排他")
	check(not Profile.traits_are_valid(
		[Profile.TRAIT_RECEIVE_GOOD, Profile.TRAIT_RECEIVE_BAD]), "レシーブ上手と下手は排他")
	check(Profile.traits_are_valid([Profile.TRAIT_MURA]), "むらっけ単独は有効")
