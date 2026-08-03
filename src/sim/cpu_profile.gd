# CPUプロファイルのビット割当、組立、難易度プリセットの正本。
extends RefCounted

# 能力フラグ
const AB_PREDICT := 1
const AB_ROLES := 2
const AB_ATTACK := 4
const AB_SWEET := 8
const AB_SERVE_VAR := 16
const AB_BLOCK := 32
const AB_HAT := 64

# 8bitフィールド
const P_AB := 0
const P_DELAY := 8
const P_AIM := 16
const P_MISS := 24
const P_SWEET := 32
const P_DEPTH := 40
const P_TIQ := 48

# bit 56から58だけを使う3bitフィールド。bit 63は符号bitなので使わない。
const P_GROUND_SPECIAL_POLICY_SHIFT := 56
const GROUND_SPECIAL_POLICY_MASK := 0x7
const GROUND_SPECIAL_PROFILE := 0
const GROUND_SPECIAL_EASY := 1
const GROUND_SPECIAL_NORMAL := 2
const GROUND_SPECIAL_HARD := 3
const GROUND_SPECIAL_SUPER := 4

const PRESET_WEAK := AB_ROLES | (18 << P_DELAY) | (40 << P_AIM) \
	| (64 << P_MISS) | (26 << P_SWEET) \
	| (GROUND_SPECIAL_EASY << P_GROUND_SPECIAL_POLICY_SHIFT)
const PRESET_NORMAL := (AB_PREDICT | AB_ROLES | AB_ATTACK) \
	| (12 << P_DELAY) | (25 << P_AIM) \
	| (13 << P_MISS) | (0 << P_SWEET) | (1 << P_TIQ) \
	| (GROUND_SPECIAL_NORMAL << P_GROUND_SPECIAL_POLICY_SHIFT)
const PRESET_STRONG := (AB_PREDICT | AB_ROLES | AB_ATTACK | AB_SWEET \
	| AB_SERVE_VAR | AB_BLOCK | AB_HAT) | (6 << P_DELAY) \
	| (15 << P_AIM) | (13 << P_MISS) | (153 << P_SWEET) | (2 << P_DEPTH) \
	| (2 << P_TIQ) | (GROUND_SPECIAL_HARD << P_GROUND_SPECIAL_POLICY_SHIFT)
const PRESET_MAX := (AB_PREDICT | AB_ROLES | AB_ATTACK | AB_SWEET \
	| AB_SERVE_VAR | AB_BLOCK | AB_HAT) \
	| (0 << P_DELAY) | (8 << P_AIM) | (8 << P_MISS) | (191 << P_SWEET) \
	| (3 << P_DEPTH) | (3 << P_TIQ) \
	| (GROUND_SPECIAL_SUPER << P_GROUND_SPECIAL_POLICY_SHIFT)
const PRESETS: Array[int] = [PRESET_WEAK, PRESET_NORMAL, PRESET_STRONG, PRESET_MAX]

static func make_profile(ab: int, delay: int, aim: int, miss: int, sweet: int,
		depth: int, tiq: int,
		ground_special_policy: int = GROUND_SPECIAL_PROFILE) -> int:
	return (ab & 0xFF) | ((delay & 0xFF) << P_DELAY) | ((aim & 0xFF) << P_AIM) \
		| ((miss & 0xFF) << P_MISS) | ((sweet & 0xFF) << P_SWEET) \
		| ((depth & 0xFF) << P_DEPTH) | ((tiq & 0xFF) << P_TIQ) \
		| ((ground_special_policy & GROUND_SPECIAL_POLICY_MASK) \
			<< P_GROUND_SPECIAL_POLICY_SHIFT)

static func prof_byte(profile: int, shift: int) -> int:
	return (profile >> shift) & 0xFF

static func ground_special_policy(profile: int) -> int:
	return (profile >> P_GROUND_SPECIAL_POLICY_SHIFT) \
		& GROUND_SPECIAL_POLICY_MASK
