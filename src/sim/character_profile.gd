# A-E基礎能力と付与能力の正本。simの葉ファイルとして他モジュールをpreloadしない。
extends RefCounted

const RANK_A := 0
const RANK_B := 1
const RANK_C := 2
const RANK_D := 3
const RANK_E := 4

const ABILITY_POWER := "power"
const ABILITY_JUMP := "jump"
const ABILITY_SPEED := "speed"
const ABILITY_BRAKE := "brake"
const ABILITY_GUARD := "guard"
const BASE_ABILITIES: Array[String] = [
	ABILITY_POWER, ABILITY_JUMP, ABILITY_SPEED, ABILITY_BRAKE, ABILITY_GUARD,
]

const RANK_NAMES: Array[String] = ["A", "B", "C", "D", "E"]
const POWER_PCT: Array[int] = [150, 125, 100, 75, 50]
const JUMP_HEIGHT_PX: Array[int] = [155, 145, 135, 120, 100]
const SPEED_PCT: Array[int] = [120, 110, 100, 90, 80]
const BRAKE_DISTANCE_PCT: Array[int] = [60, 80, 100, 125, 150]
const STANDARD_WEIGHT_PCT := 100

const TRAIT_TOSS_GOOD := 0
const TRAIT_RECEIVE_GOOD := 1
const TRAIT_SOFT_HANDS := 2
const TRAIT_BLOCK_GOOD := 3
const TRAIT_JUST_EXPERT := 4
const TRAIT_STRONG_HEART := 5
const TRAIT_IRON_WALL := 6
const TRAIT_AIR_CONTROL := 7
const TRAIT_QUICK := 8
const TRAIT_TOSS_BAD := 9
const TRAIT_RECEIVE_BAD := 10
const TRAIT_MURA := 11
const TRAIT_BLOCK_BAD := 12
const TRAIT_WEAK_HEART := 13
const TRAIT_FRAGILE := 14
const TRAIT_LANDING_LAG := 15
const TRAIT_POOR_BRAKING := 16
const TRAIT_AIR_CLUMSY := 17

const TRAIT_NAMES := {
	TRAIT_TOSS_GOOD: "トス上手",
	TRAIT_RECEIVE_GOOD: "レシーブ上手",
	TRAIT_SOFT_HANDS: "柔らかい手",
	TRAIT_BLOCK_GOOD: "ブロック上手",
	TRAIT_JUST_EXPERT: "ジャスト巧者",
	TRAIT_STRONG_HEART: "強心臓",
	TRAIT_IRON_WALL: "鉄壁",
	TRAIT_AIR_CONTROL: "空中制御",
	TRAIT_QUICK: "クイック",
	TRAIT_TOSS_BAD: "トス下手",
	TRAIT_RECEIVE_BAD: "レシーブ下手",
	TRAIT_MURA: "むらっけ",
	TRAIT_BLOCK_BAD: "ブロック下手",
	TRAIT_WEAK_HEART: "ノミの心臓",
	TRAIT_FRAGILE: "打たれ弱い",
	TRAIT_LANDING_LAG: "着地硬直",
	TRAIT_POOR_BRAKING: "急停止苦手",
	TRAIT_AIR_CLUMSY: "空中不器用",
}

const ACTIVE_TRAITS: Array[int] = [
	TRAIT_TOSS_GOOD, TRAIT_RECEIVE_GOOD, TRAIT_TOSS_BAD, TRAIT_RECEIVE_BAD, TRAIT_MURA,
]

const OPPOSITE_TRAITS: Array = [
	[TRAIT_TOSS_GOOD, TRAIT_TOSS_BAD],
	[TRAIT_RECEIVE_GOOD, TRAIT_RECEIVE_BAD],
	[TRAIT_BLOCK_GOOD, TRAIT_BLOCK_BAD],
	[TRAIT_STRONG_HEART, TRAIT_WEAK_HEART],
	[TRAIT_AIR_CONTROL, TRAIT_AIR_CLUMSY],
]

const ALL_C_RANKS := {
	ABILITY_POWER: RANK_C,
	ABILITY_JUMP: RANK_C,
	ABILITY_SPEED: RANK_C,
	ABILITY_BRAKE: RANK_C,
	ABILITY_GUARD: RANK_C,
}

# char_idはchars.gdの公開IDと一致する。重量は全員標準。
const PROFILES := {
	0: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT,
		"traits": [TRAIT_TOSS_BAD, TRAIT_RECEIVE_BAD, TRAIT_MURA]},
	1: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT,
		"traits": [TRAIT_TOSS_GOOD, TRAIT_RECEIVE_GOOD]},
	2: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	3: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	4: {"ranks": {
		ABILITY_POWER: RANK_C, ABILITY_JUMP: RANK_A, ABILITY_SPEED: RANK_E,
		ABILITY_BRAKE: RANK_C, ABILITY_GUARD: RANK_C,
	}, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	5: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	6: {"ranks": {
		ABILITY_POWER: RANK_C, ABILITY_JUMP: RANK_C, ABILITY_SPEED: RANK_D,
		ABILITY_BRAKE: RANK_C, ABILITY_GUARD: RANK_E,
	}, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	7: {"ranks": {
		ABILITY_POWER: RANK_C, ABILITY_JUMP: RANK_E, ABILITY_SPEED: RANK_A,
		ABILITY_BRAKE: RANK_C, ABILITY_GUARD: RANK_A,
	}, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	8: {"ranks": {
		ABILITY_POWER: RANK_C, ABILITY_JUMP: RANK_B, ABILITY_SPEED: RANK_A,
		ABILITY_BRAKE: RANK_C, ABILITY_GUARD: RANK_D,
	}, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	9: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	10: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
	11: {"ranks": ALL_C_RANKS, "weight_pct": STANDARD_WEIGHT_PCT, "traits": []},
}

static func rank(char_id: int, ability: String) -> int:
	var profile: Dictionary = PROFILES.get(char_id, {})
	var ranks: Dictionary = profile.get("ranks", ALL_C_RANKS)
	return int(ranks.get(ability, RANK_C))

static func rank_name(value: int) -> String:
	return RANK_NAMES[clampi(value, RANK_A, RANK_E)]

static func power_pct(value: int) -> int:
	return POWER_PCT[clampi(value, RANK_A, RANK_E)]

static func jump_height_px(value: int) -> int:
	return JUMP_HEIGHT_PX[clampi(value, RANK_A, RANK_E)]

static func speed_pct(value: int) -> int:
	return SPEED_PCT[clampi(value, RANK_A, RANK_E)]

static func brake_distance_pct(value: int) -> int:
	return BRAKE_DISTANCE_PCT[clampi(value, RANK_A, RANK_E)]

static func weight_pct(char_id: int) -> int:
	var profile: Dictionary = PROFILES.get(char_id, {})
	return int(profile.get("weight_pct", STANDARD_WEIGHT_PCT))

static func traits(char_id: int) -> Array:
	var profile: Dictionary = PROFILES.get(char_id, {})
	return profile.get("traits", []).duplicate()

static func has_trait(char_id: int, trait_id: int) -> bool:
	return traits(char_id).has(trait_id)

static func trait_names(char_id: int) -> Array[String]:
	var result: Array[String] = []
	for trait_id in traits(char_id):
		result.append(TRAIT_NAMES[trait_id])
	return result

static func traits_are_valid(values: Array) -> bool:
	for pair in OPPOSITE_TRAITS:
		if values.has(pair[0]) and values.has(pair[1]):
			return false
	return true
