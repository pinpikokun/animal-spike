extends "res://tests/test_case.gd"

const SimRng := preload("res://src/sim/sim_rng.gd")

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

func test_word_and_aitick_updates_wrap_to_16_bits() -> void:
	check_eq(SimRng.normalize_word(-1), 0xFFFF, "負数seedを16bitへ丸める")
	check_eq(SimRng.normalize_word(0x10001), 1, "上位bitを捨てる")
	check_eq(SimRng.advance_hit(0xFFFE, 3), 1, "打球加算を16bitへ丸める")
	check_eq(SimRng.advance_role_swap(0xFFFF), 0, "役割入替加算を16bitへ丸める")
