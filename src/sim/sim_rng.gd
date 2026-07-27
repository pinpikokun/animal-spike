const WORD_MASK := 0xFFFF

static func normalize_word(value: int) -> int:
	return value & WORD_MASK

static func advance_frame(rng: int, aitick: int) -> int:
	return (rng * 7 + 0x4017 + aitick) & WORD_MASK

static func advance_hit(aitick: int, rng: int) -> int:
	return (aitick + rng) & WORD_MASK

static func advance_role_swap(aitick: int) -> int:
	return (aitick + 1) & WORD_MASK

static func keyed_hash(key: int, salt: int, actor_term: int) -> int:
	var z: int = key + salt * 1000003 + actor_term * 998244353
	z = (z ^ (z >> 16)) * 2246822519
	z = (z ^ (z >> 13)) * 3266489917
	z = z ^ (z >> 16)
	return z & 0x7FFFFFFFFFFFFFFF
