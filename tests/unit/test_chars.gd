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
		check_eq(Chars.stat(cid, "atk"), Chars.Profile.power_pct(
			Chars.rank(cid, Chars.Profile.ABILITY_POWER)), "パワーランクを物理%へ変換")
		check_eq(Chars.stat(cid, "speed"), Chars.Profile.speed_pct(
			Chars.rank(cid, Chars.Profile.ABILITY_SPEED)), "スピードランクを物理%へ変換")
		check_eq(Chars.stat(cid, "slide"), Chars.Profile.brake_distance_pct(
			Chars.rank(cid, Chars.Profile.ABILITY_BRAKE)), "ブレーキランクを物理%へ変換")
		check_eq(Chars.stat(cid, "guard_max"), Chars.Profile.guard_pct(
			Chars.rank(cid, Chars.Profile.ABILITY_GUARD)), "ガードランクを物理%へ変換")
		check_eq(Chars.stat(cid, "weight"), 100, "重量は標準100%")

func test_original_character_ids_defs_names_and_visibility() -> void:
	var original_ids := [Chars.CHAR_TOME, Chars.CHAR_HITO, Chars.CHAR_PIYO, Chars.CHAR_UME,
		Chars.CHAR_CARBY, Chars.CHAR_DUO, Chars.CHAR_SEC1, Chars.CHAR_SEC2]
	var expected_names := ["TOME", "HITO", "PIYO", "UME", "CARBY", "DUO", "ALIEN", "UMA"]
	var all_ids := [Chars.CHAR_PANDA, Chars.CHAR_MARIO, Chars.CHAR_FOX, Chars.CHAR_FROG,
		Chars.CHAR_DEBUG] + original_ids
	var unique := {}
	for cid in all_ids:
		unique[cid] = true
	check_eq(unique.size(), all_ids.size(), "キャラIDは重複しない")
	for i in original_ids.size():
		var cid: int = original_ids[i]
		check(Chars.DEFS.has(cid), "原作キャラ定義あり: %d" % cid)
		check(Chars.NAMES.has(cid), "原作キャラ名あり: %d" % cid)
		check_eq(Chars.NAMES[cid], expected_names[i], "原作キャラ表示名: %d" % cid)
		check_eq(Chars.DEFS[cid].abilities, 0, "固有メカはステージ1では未実装")
		check_eq(Chars.DEFS[cid].stats, {}, "旧派生statは空")
	for cid in original_ids:
		check(Chars.SELECTABLE.has(cid), "%sは選択可能" % Chars.NAMES[cid])
	check_eq(Chars.SELECTABLE.size(), 12, "開発中は既存4体+原作8体を全公開")
	check_eq(Chars.NAMES[Chars.CHAR_SEC1], "ALIEN", "SEC1表示名")
	check_eq(Chars.NAMES[Chars.CHAR_SEC2], "UMA", "SEC2表示名")

func test_roster_shape() -> void:
	check_eq(Chars.ROSTER.size(), 4, "ロスターは4slot")
	check_eq(Chars.ROSTER, [Chars.CHAR_PANDA, Chars.CHAR_MARIO,
		Chars.CHAR_FOX, Chars.CHAR_FROG], "既定ロスターは変更しない")
	check_eq(Chars.ROSTER[1], Chars.CHAR_MARIO, "slot1=マリオ")
	for cid in Chars.ROSTER:
		check(Chars.DEFS.has(cid), "ロスター全員に定義がある")

func test_chars_exposes_profile_traits() -> void:
	check(Chars.has_trait(Chars.CHAR_MARIO, Chars.Profile.TRAIT_TOSS_GOOD),
		"chars窓口からマリオのトス上手を取得できる")
	check(Chars.has_trait(Chars.CHAR_PANDA, Chars.Profile.TRAIT_MURA),
		"chars窓口からパンダのむらっけを取得できる")
	check_eq(Chars.traits(Chars.CHAR_FOX), [], "キツネの付与能力は空")
