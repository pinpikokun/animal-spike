extends "res://tests/test_case.gd"

const SimRng := preload("res://src/sim/sim_rng.gd")

func test_seed_from_clock_matches_original_vectors() -> void:
	var vectors: Array[Array] = [
		[0, 0, 0x0000],
		[1, 2, 0x0102],
		[12, 34, 0x0C22],
		[23, 59, 0x173B],
	]
	for v in vectors:
		check_eq(SimRng.seed_from_clock(v[0], v[1]), v[2],
			"時計種: hour=%d minute=%d" % [v[0], v[1]])

func test_advance_frame_matches_original_vectors() -> void:
	var vectors: Array[Array] = [
		[0x0000, 0x0000, 0x4017],
		[0x4017, 0x0000, 0x00B8],
		[0x00B8, 0x0000, 0x451F],
		[0x1234, 0x1234, 0xD1B7],
		[0xFFFF, 0xFFFF, 0x400F],
	]
	for v in vectors:
		check_eq(SimRng.advance_frame(v[0], v[1]), v[2],
			"原作PRNG: rng=0x%04X aitick=0x%04X" % [v[0], v[1]])

func test_advance_role_roll_matches_original_vectors() -> void:
	var vectors: Array[Array] = [
		[0x0000, 0x0001],
		[0x7FFF, 0xFFFF],
		[0x8000, 0x0001],
		[0xFFFF, 0xFFFF],
	]
	for v in vectors:
		check_eq(SimRng.advance_role_roll(v[0]), v[1],
			"原作role抽選: rng=0x%04X" % v[0])

func test_word_and_aitick_updates_wrap_to_16_bits() -> void:
	check_eq(SimRng.normalize_word(-1), 0xFFFF, "負数seedを16bitへ丸める")
	check_eq(SimRng.normalize_word(0x10001), 1, "上位bitを捨てる")
	check_eq(SimRng.advance_hit(0xFFFE, 3), 1, "打球加算を16bitへ丸める")
	check_eq(SimRng.advance_role_swap(0xFFFF), 0, "役割入替加算を16bitへ丸める")

func test_derived_value_matches_fixed_vectors_and_masks_aitick() -> void:
	# 設計書10節 VECTOR-003。実装から採取せず、承認済みの固定値を使う。
	var vectors: Array[Array] = [
		[0x0000, 0, 1, 2966470138605183947],
		[0xABCD, 2, 1, 2108330416775593002],
		[0xFFFF, 4, 31, 2482199174690399587],
	]
	for v in vectors:
		check_eq(SimRng.derived_value(v[0], v[1], v[2]), v[3],
			"派生値の固定ベクトル: aitick=0x%X actor=%d purpose=%d" \
				% [v[0], v[1], v[2]])

	check_eq(SimRng.derived_value(0x1ABCD, 2, 1), 2108330416775593002,
		"aitickの上位ビットを捨てて16bitへ正規化する")
	check(SimRng.derived_value(0xFFFF, 4, 31) > 0xFFFF,
		"派生値の出力を16bitへ切り詰めない")

func test_derived_value_separates_actor_and_purpose() -> void:
	# 設計書10節 VECTOR-003 のactor違い・purpose違い。
	var base: int = SimRng.derived_value(0xABCD, 2, 1)
	var actor_changed: int = SimRng.derived_value(0xABCD, 3, 1)
	var purpose_changed: int = SimRng.derived_value(0xABCD, 2, 2)

	check_eq(base, 2108330416775593002, "派生値の基準ベクトル")
	check_eq(actor_changed, 5469489065395195681, "actor違いの固定ベクトル")
	check_eq(purpose_changed, 6083307090805565555, "用途違いの固定ベクトル")
	check(actor_changed != base, "actorを派生値から落とさない")
	check(purpose_changed != base, "用途IDを派生値から落とさない")
	check_eq(SimRng.derived_value(0xABCD, 2, 1), base,
		"同じ入力は呼び出し回数によらず同じ派生値になる")
