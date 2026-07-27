extends "res://tests/test_case.gd"

const SimState := preload("res://src/sim/sim_state.gd")
const SimRng := preload("res://src/sim/sim_rng.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const HitResolver := preload("res://src/sim/hit_resolver.gd")
const Chars := preload("res://src/sim/chars.gd")


func _profile(sweet: int, tiq: int, abilities: int = 0) -> int:
	return SimCpu.make_profile(abilities, 0, 0, 0, sweet, 0, tiq)


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
