static func keyed_hash(key: int, salt: int, actor_term: int) -> int:
	var z: int = key + salt * 1000003 + actor_term * 998244353
	z = (z ^ (z >> 16)) * 2246822519
	z = (z ^ (z >> 13)) * 3266489917
	z = z ^ (z >> 16)
	return z & 0x7FFFFFFFFFFFFFFF
