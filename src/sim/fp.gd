# 固定小数点演算 16.16 (1.0 = 65536)。int64のみ、float禁止
# シミュレーション層の数値は全てこの形式で持つ
extends RefCounted

const SHIFT := 16
const ONE := 1 << SHIFT

static func from_int(v: int) -> int:
	return v << SHIFT

static func to_int(v: int) -> int:
	return v >> SHIFT

static func mul(a: int, b: int) -> int:
	return (a * b) >> SHIFT

static func div(a: int, b: int) -> int:
	return (a << SHIFT) / b
