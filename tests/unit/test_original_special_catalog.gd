extends "res://tests/test_case.gd"

const Chars := preload("res://src/sim/chars.gd")

func test_original_roster_owns_every_approved_special() -> void:
	var expected := {
		Chars.CHAR_TOME: [Chars.SUPER_GHOST_BALL, Chars.SUPER_FLAME_ATTACK],
		Chars.CHAR_HITO: [Chars.SUPER_DISAPPEARING_BALL, Chars.SUPER_FEINT_ATTACK],
		Chars.CHAR_PIYO: [Chars.SUPER_GUST_BALL, Chars.SUPER_GUST_ATTACK],
		Chars.CHAR_UME: [Chars.SUPER_SNAKE_BALL, Chars.SUPER_BUMBLE_BALL],
		Chars.CHAR_CARBY: [Chars.SUPER_GHOST_BALL, Chars.SUPER_THUNDER_BALL],
		Chars.CHAR_DUO: [Chars.SUPER_SUCTION, Chars.SUPER_BUBBLE_PACK],
		Chars.CHAR_SEC1: [Chars.SUPER_TRANSFER_BALL, Chars.SUPER_SUBSPACE_BLOCK],
		Chars.CHAR_SEC2: [Chars.SUPER_REFRAIN_ATTACK],
	}
	for char_id in expected:
		for special_id in expected[char_id]:
			check(Chars.has_super(char_id, special_id),
				"%sが承認済み必殺技%dを所有" % [Chars.NAMES[char_id], special_id])

func test_catalog_has_all_fourteen_effects_and_required_fields() -> void:
	check_eq(Chars.SUPER_CATALOG.size(), 14, "共有技と複数入力を一効果へ統合した14種")
	for special_id in Chars.SUPER_CATALOG:
		var entry: Dictionary = Chars.super_def(special_id)
		for field in ["power", "activations", "defense_class", "visual"]:
			check(entry.has(field), "必殺技%dに%sがある" % [special_id, field])
		check(entry.activations.size() > 0, "必殺技には一つ以上の発動経路がある")
		for activation in entry.activations:
			for field in ["contact", "direction", "requires_ability",
					"original_height_y", "friendly_ball", "requires_apex",
					"requires_normal_ball"]:
				check(activation.has(field), "発動経路に%sがある" % field)

func test_approved_damage_values_are_fixed() -> void:
	var zero_damage := [Chars.SUPER_GHOST_BALL, Chars.SUPER_DISAPPEARING_BALL,
		Chars.SUPER_GUST_BALL, Chars.SUPER_SNAKE_BALL, Chars.SUPER_SUCTION,
		Chars.SUPER_TRANSFER_BALL, Chars.SUPER_SUBSPACE_BLOCK]
	for special_id in zero_damage:
		check_eq(Chars.super_def(special_id).power, 0, "非ダメージ技")
	for special_id in [Chars.SUPER_FEINT_ATTACK, Chars.SUPER_GUST_ATTACK,
			Chars.SUPER_BUMBLE_BALL, Chars.SUPER_THUNDER_BALL]:
		check_eq(Chars.super_def(special_id).power, 22, "標準攻撃型")
	for special_id in [Chars.SUPER_BUBBLE_PACK, Chars.SUPER_REFRAIN_ATTACK]:
		check_eq(Chars.super_def(special_id).power, 11, "原作半減型")
	check_eq(Chars.super_def(Chars.SUPER_FLAME_ATTACK).power, 40, "既存炎技")

func test_multi_route_and_automatic_activations_are_explicit() -> void:
	check_eq(Chars.super_def(Chars.SUPER_DISAPPEARING_BALL).activations.size(), 2,
		"消える魔球は地上と空中")
	check_eq(Chars.super_def(Chars.SUPER_GUST_BALL).activations.size(), 2,
		"突風ボールは地上と空中連携")
	check_eq(Chars.super_def(Chars.SUPER_BUMBLE_BALL).activations.size(), 2,
		"バンブルは地上と空中連携")
	var gust_attack: Dictionary = Chars.super_def(Chars.SUPER_GUST_ATTACK).activations[0]
	check_eq(gust_attack.contact, Chars.SPECIAL_CONTACT_AUTO_AIR_ATTACK,
		"突風アタックは通常空中アタックから自動派生")
	check_eq(gust_attack.requires_ability, 0, "自動派生はD不要")
	check_eq(gust_attack.direction, Chars.SPECIAL_DIR_AUTO, "自動派生は方向不要")

func test_original_height_thresholds_are_catalog_data() -> void:
	check_eq(_activation_with_contact(Chars.SUPER_FLAME_ATTACK,
		Chars.SPECIAL_CONTACT_AIR_HIT).original_height_y, 152, "炎の原作Y境界")
	check_eq(_activation_with_contact(Chars.SUPER_DISAPPEARING_BALL,
		Chars.SPECIAL_CONTACT_AIR_HIT).original_height_y, 160, "空中消える球の原作Y境界")
	check_eq(_activation_with_contact(Chars.SUPER_BUBBLE_PACK,
		Chars.SPECIAL_CONTACT_AIR_HIT).original_height_y, 160, "泡の原作Y境界")
	check_eq(_activation_with_contact(Chars.SUPER_REFRAIN_ATTACK,
		Chars.SPECIAL_CONTACT_AIR_HIT).original_height_y, 192, "リフレインの原作Y境界")

func _activation_with_contact(special_id: int, contact: int) -> Dictionary:
	for activation in Chars.super_def(special_id).activations:
		if activation.contact == contact:
			return activation
	return {}
