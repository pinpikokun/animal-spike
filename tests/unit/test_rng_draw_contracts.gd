extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")
const SimRng := preload("res://src/sim/sim_rng.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")


func _profile(sweet: int, tiq: int, abilities: int = 0) -> int:
	return SimCpu.make_profile(abilities, 0, 0, 0, sweet, 0, tiq)


func test_cpu_original_lotteries_read_raw_aitick() -> void:
	var s = SimState.new()
	s.aitick = 0
	s.rng = 0x1234
	s.last_hit_tick = 0x5678

	var sweet_zero: int = _profile(0, 0)
	var sweet_positive: int = _profile(1, 0)
	var attack_zero: int = _profile(0, 0, SimCpu.AB_ATTACK)
	var attack_positive: int = _profile(0, 1, SimCpu.AB_ATTACK)
	var rng_before: int = s.rng
	var aitick_before: int = s.aitick

	check(not SimCpu._sweet_ok(s, 0, sweet_zero),
		"aitick=0でもsweet閾値0なら0<0は偽")
	check(SimCpu._sweet_ok(s, 0, sweet_positive),
		"aitick=0かつsweet閾値が正なら成功")
	check(not SimCpu._attack_ok(s, 0, attack_zero),
		"aitick=0でもattack閾値0なら0<0は偽")
	check(SimCpu._attack_ok(s, 0, attack_positive),
		"aitick=0かつattack閾値64なら成功")
	check_eq(s.rng, rng_before, "原作対応抽選はrngを進めない")
	check_eq(s.aitick, aitick_before, "原作対応抽選はaitickを進めない")

	var sweet_64: int = _profile(64, 0)
	var attack_64: int = _profile(0, 1, SimCpu.AB_ATTACK)
	for word in [63, 64]:
		var expected: bool = word < 64
		for actor in 4:
			s.aitick = word
			s.rng = 0x1000 + actor * 0x111
			s.last_hit_tick = 0x7000 + actor * 0x101
			rng_before = s.rng
			aitick_before = s.aitick
			check_eq(SimCpu._sweet_ok(s, actor, sweet_64), expected,
				"sweetは生aitickの境界だけを読む: aitick=%d actor=%d" \
					% [word, actor])
			check_eq(SimCpu._attack_ok(s, actor, attack_64), expected,
				"attackはsweetと同じ生aitickを読む: aitick=%d actor=%d" \
					% [word, actor])
			check_eq(s.rng, rng_before, "判定中にrngを変えない")
			check_eq(s.aitick, aitick_before, "判定中にaitickを変えない")
			s.rng ^= 0xFFFF
			s.last_hit_tick ^= 0xFFFF
			check_eq(SimCpu._sweet_ok(s, actor, sweet_64), expected,
				"同じactorではrngとlast_hit_tickを変えてもsweet結果は不変")
			check_eq(SimCpu._attack_ok(s, actor, attack_64), expected,
				"同じactorではrngとlast_hit_tickを変えてもattack結果は不変")


func test_cpu_remake_lotteries_use_read_only_derived_aitick() -> void:
	var s = SimState.new()
	s.aitick = 0xABCD
	s.rng = 0x1234
	s.last_hit_tick = 0x5678
	var salts: Array[int] = [
		SimCpu.SALT_AIM,
		SimCpu.SALT_MISS,
		SimCpu.SALT_SUPER,
	]

	for salt in salts:
		var before: Array[int] = s.to_int_array().duplicate()
		var expected: int = SimRng.derived_value(s.aitick, 2, salt)
		var actual: int = SimCpu._derived_roll(salt, s, 2)
		check_eq(actual, expected, "CPU独自抽選はaitick・actor・saltの派生値を読む")
		check_eq(SimCpu._derived_roll(salt, s, 2), actual,
			"CPU独自抽選は同一状態で繰り返しても同じ")
		check_eq(s.to_int_array(), before, "CPU独自抽選はSimStateを変更しない")

	var base: int = SimCpu._derived_roll(SimCpu.SALT_AIM, s, 2)
	s.rng = 0xFEDC
	check_eq(SimCpu._derived_roll(SimCpu.SALT_AIM, s, 2), base,
		"CPU独自抽選の派生値へrngを混ぜない")

	s.rng = 0x1234
	s.aitick = 0xABCE
	check(SimCpu._derived_roll(SimCpu.SALT_AIM, s, 2) != base,
		"選んだ検査ベクトルではaitick違いを分離する")
	s.aitick = 0xABCD
	check_eq(SimCpu._derived_roll(SimCpu.SALT_AIM, s, 3), 5469489065395195681,
		"選んだ検査ベクトルではactor違いを分離する")
	check_eq(SimCpu._derived_roll(SimCpu.SALT_MISS, s, 2), 6083307090805565555,
		"選んだ検査ベクトルではsalt違いを分離する")


func test_hit_resolver_lotteries_use_read_only_derived_aitick() -> void:
	var s = SimState.new()
	s.aitick = 0xABCD
	s.rng = 0x1234
	s.tick = 0x5678
	var actor: int = 1
	var salts: Array[int] = [
		HitResolver.SALT_MURA,
		HitResolver.SALT_TOSS_BAD,
		HitResolver.SALT_RECEIVE_SCATTER,
	]

	for salt in salts:
		var before: Array[int] = s.to_int_array().duplicate()
		var expected: int = SimRng.derived_value(s.aitick, actor + 1, salt)
		check_eq(HitResolver._keyed_hash(s, actor, salt), expected,
			"HitResolverはactor+1を含むaitick派生値を読む")
		check_eq(s.to_int_array(), before, "_keyed_hashはSimStateを変更しない")

	var keyed_before_rng_change: int = HitResolver._keyed_hash(
		s, actor, HitResolver.SALT_MURA)
	s.rng = 0xFEDC
	check_eq(HitResolver._keyed_hash(s, actor, HitResolver.SALT_MURA),
		keyed_before_rng_change, "HitResolverの派生値へrngを混ぜない")

	var before_helpers: Array[int] = s.to_int_array().duplicate()
	var scatter_hash: int = SimRng.derived_value(
		s.aitick, actor + 1, HitResolver.SALT_RECEIVE_SCATTER)
	check_eq(HitResolver._scatter(s, actor, HitResolver.SALT_RECEIVE_SCATTER),
		scatter_hash % 201 - 100, "_scatterは派生値へ%201-100だけを適用")
	var mura_hash: int = SimRng.derived_value(
		s.aitick, actor + 1, HitResolver.SALT_MURA)
	check_eq(HitResolver._trait_roll_pct(s, actor, HitResolver.SALT_MURA),
		mura_hash % 100, "_trait_roll_pctは派生値へ%100だけを適用")
	check_eq(s.to_int_array(), before_helpers, "3つの呼び口はSimStateを変更しない")

	# 設計式から独立計算・実測済みの固定値で、全ての閾値分岐を通す。
	var threshold_vectors: Array[Array] = [
		[0x0001, 8, 50, 64, 100],
		[0x0007, 92, 150, 14, 70],
		[0xABCD, 24, 100, 67, 100],
	]
	for v in threshold_vectors:
		s.aitick = v[0]
		var before_thresholds: Array[int] = s.to_int_array().duplicate()
		check_eq(HitResolver._trait_roll_pct(s, actor, HitResolver.SALT_MURA), v[1],
			"むらっけの固定roll: aitick=0x%X" % v[0])
		check_eq(HitResolver._mura_power_pct(s, actor, Chars.CHAR_PANDA), v[2],
			"むらっけの10・90固定分岐: aitick=0x%X" % v[0])
		check_eq(HitResolver._trait_roll_pct(s, actor, HitResolver.SALT_TOSS_BAD), v[3],
			"トス下手の固定roll: aitick=0x%X" % v[0])
		check_eq(HitResolver._toss_apex_pct(s, actor, Chars.CHAR_PANDA), v[4],
			"トス下手の30固定分岐: aitick=0x%X" % v[0])
		check_eq(s.to_int_array(), before_thresholds,
			"特性の閾値判定はSimStateを変更しない")


func test_scatter_stream_snapshot() -> void:
	var s = SimState.new()
	var actual: Array[int] = []
	# 123456は16bit正規化で0xE240へ折り返す契約も同じ列で固定する。
	for aitick in [0, 1, 17, 999, 123456]:
		s.aitick = aitick
		for actor in [0, 1, 3]:
			for salt in [11, 13, 17, 19]:
				actual.append(HitResolver._scatter(s, actor, salt))
	check_eq(actual, [
		-52, 89, -94, 83, -59, -28, -35, -60, -27, -2, 49, -3,
		-42, -97, -85, 94, -73, -16, -93, 42, -61, -41, -87, 55,
		-89, -25, 9, 20, 25, 94, 18, 61, -92, -54, 25, 38,
		-64, 58, -50, -74, 71, -5, 35, -7, 3, 84, 31, -91,
		-69, 40, 93, -31, 29, 35, 57, -69, 80, -22, 0, -32,
	], "固定aitick/actor/saltの乱数列")


func test_scatter_is_deterministic_and_separates_actor_and_purpose() -> void:
	var s = SimState.new()
	s.aitick = 1234
	var a: int = HitResolver._scatter(s, 1, 11)
	var b: int = HitResolver._scatter(s, 1, 11)
	check_eq(a, b, "同じaitick・actor・用途IDなら同値")
	check(a >= -100 and a <= 100, "範囲は-100..100")
	var c: int = HitResolver._scatter(s, 2, 11)
	var d: int = HitResolver._scatter(s, 1, 13)
	check(a != c or a != d, "actorまたは用途IDで散る")


func test_derived_roll_is_stable_until_aitick_changes() -> void:
	var s = SimState.new()
	s.aitick = 0xABCD
	s.tick = 123
	s.last_hit_tick = 456
	var before: Array[int] = s.to_int_array().duplicate()
	var base: int = SimCpu._derived_roll(SimCpu.SALT_AIM, s, 2)
	check_eq(base, 2108330416775593002,
		"固定aitick・actor・用途IDの承認済み派生値")
	check_eq(s.to_int_array(), before, "派生値の読み取りはSimStateを変更しない")

	s.tick = 999
	s.last_hit_tick = 888
	check_eq(SimCpu._derived_roll(SimCpu.SALT_AIM, s, 2), base,
		"tickとlast_hit_tickを変えても派生値は変わらない")
	s.aitick = 0xABCE
	check(SimCpu._derived_roll(SimCpu.SALT_AIM, s, 2) != base,
		"承認済みベクトルではaitickが変わると派生値も変わる")
	s.aitick = 0xABCD
	check_eq(SimCpu._derived_roll(SimCpu.SALT_AIM, s, 3),
		5469489065395195681, "actor違いの承認済み派生値")
	check_eq(SimCpu._derived_roll(SimCpu.SALT_MISS, s, 2),
		6083307090805565555, "用途ID違いの承認済み派生値")


func test_mura_roll_is_deterministic_and_has_10_80_10_distribution() -> void:
	var s = SimState.new()
	var outcome_by_roll := {}
	for aitick in SimRng.WORD_MASK + 1:
		s.aitick = aitick
		var roll: int = HitResolver._trait_roll_pct(s, 0, HitResolver.SALT_MURA)
		var pct: int = HitResolver._mura_power_pct(s, 0, Chars.CHAR_PANDA)
		if outcome_by_roll.has(roll):
			check_eq(pct, outcome_by_roll[roll],
				"同じrollは全aitickで同じむらっけ倍率: roll=%d" % roll)
		else:
			outcome_by_roll[roll] = pct

	check_eq(outcome_by_roll.size(), 100, "全16bit aitickがroll 0..99を覆う")
	var counts := {50: 0, 100: 0, 150: 0}
	for roll in 100:
		check(outcome_by_roll.has(roll), "むらっけroll全域を含む: roll=%d" % roll)
		var expected_pct: int = 50 if roll < 10 else (100 if roll < 90 else 150)
		check_eq(outcome_by_roll[roll], expected_pct,
			"むらっけ閾値の全域写像: roll=%d" % roll)
		counts[expected_pct] += 1
	check_eq([counts[50], counts[100], counts[150]], [10, 80, 10],
		"むらっけは10%/80%/10%")

	s.aitick = 0xABCD
	check_eq(HitResolver._trait_roll_pct(s, 0, HitResolver.SALT_MURA), 96,
		"第3層用のactor 0固定roll")
	check_eq(HitResolver._mura_power_pct(s, 0, Chars.CHAR_PANDA), 150,
		"固定roll 96は150%側")
	check_eq(HitResolver._mura_power_pct(s, 0, Chars.CHAR_MARIO), 100,
		"むらっけ無しは常に100%")


func test_toss_bad_is_exactly_30_percent() -> void:
	var s = SimState.new()
	var outcome_by_roll := {}
	for aitick in SimRng.WORD_MASK + 1:
		s.aitick = aitick
		var roll: int = HitResolver._trait_roll_pct(
			s, 0, HitResolver.SALT_TOSS_BAD)
		var pct: int = HitResolver._toss_apex_pct(s, 0, Chars.CHAR_PANDA)
		if outcome_by_roll.has(roll):
			check_eq(pct, outcome_by_roll[roll],
				"同じrollは全aitickで同じトス頂点倍率: roll=%d" % roll)
		else:
			outcome_by_roll[roll] = pct

	check_eq(outcome_by_roll.size(), 100, "全16bit aitickがroll 0..99を覆う")
	var low_count := 0
	for roll in 100:
		check(outcome_by_roll.has(roll), "トス下手roll全域を含む: roll=%d" % roll)
		var expected_pct: int = 70 if roll < 30 else 100
		check_eq(outcome_by_roll[roll], expected_pct,
			"トス下手閾値の全域写像: roll=%d" % roll)
		if expected_pct == 70:
			low_count += 1
	check_eq(low_count, 30, "トス下手はroll全域の30%")

	for v in [[0, 10, 70], [1, 65, 100]]:
		s.aitick = v[0]
		check_eq(HitResolver._trait_roll_pct(s, 0, HitResolver.SALT_TOSS_BAD), v[1],
			"第3層用のactor 0固定roll: aitick=%d" % v[0])
		check_eq(HitResolver._toss_apex_pct(s, 0, Chars.CHAR_PANDA), v[2],
			"固定rollのトス頂点分岐: aitick=%d" % v[0])
	check_eq(HitResolver._toss_apex_pct(s, 0, Chars.CHAR_MARIO), 100,
		"トス上手は失敗なし")
	check_eq(HitResolver._toss_apex_pct(s, 0, Chars.CHAR_FOX), 100,
		"特性なしは失敗なし")
