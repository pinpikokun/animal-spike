# キャラ定義の正本(4層構造の第2層=性能シート+第3層=固有技ビット)。
# 葉ファイル: 何もpreloadしない(simulation/sim_cpu双方から安全に参照できる)。
# キャラ追加=DEFSに1エントリ追加。当面GDScript定数、MOD開放段階でJSONローダ化
extends RefCounted

const Profile := preload("res://src/sim/character_profile.gd")

# キャラID(sim状態のchar_idに入る値。slot番号との暗黙対応を排除する)
const CHAR_PANDA := 0
const CHAR_MARIO := 1
const CHAR_FOX := 2
const CHAR_FROG := 3
const CHAR_TOME := 4
const CHAR_HITO := 5
const CHAR_PIYO := 6
const CHAR_UME := 7
const CHAR_CARBY := 8
const CHAR_DUO := 9
const CHAR_SEC1 := 10
const CHAR_SEC2 := 11
const CHAR_DEBUG := 15  # テスト専用: 全能力持ち+個性値

# 固有技ビット(第3層。付け外し自由。CPUのAB_*は「やりたがるか」、こちらは「できるか」)
const CA_HAT := 1    # 帽子投げ
const CA_HIP := 2    # ヒップアタック
const CA_CLING := 4  # 壁張り付き
const CA_DASH := 8   # ダブルタップダッシュ

# 必殺技ID。DEFSのsupers辞書に登録されたキャラだけが使用できる。
const SUPER_GHOST_BALL := 1
const SUPER_FLAME_ATTACK := 2
const SUPER_DISAPPEARING_BALL := 3
const SUPER_FEINT_ATTACK := 4
const SUPER_GUST_BALL := 5
const SUPER_GUST_ATTACK := 6
const SUPER_SNAKE_BALL := 7
const SUPER_BUMBLE_BALL := 8
const SUPER_THUNDER_BALL := 9
const SUPER_SUCTION := 10
const SUPER_BUBBLE_PACK := 11
const SUPER_TRANSFER_BALL := 12
const SUPER_SUBSPACE_BLOCK := 13
const SUPER_REFRAIN_ATTACK := 14

enum DefenseClass {
	DEFENSE_NONE,
	DEFENSE_UNBLOCKABLE,
	DEFENSE_KNOCKBACK,
	DEFENSE_DELAYED,
}

enum SuperCondition {
	CONDITION_GROUND_UP_ABILITY,
	CONDITION_AIR_DOWN_ABILITY_ABOVE_NET,
}

enum SpecialContact {
	SPECIAL_CONTACT_GROUND_HIT,
	SPECIAL_CONTACT_AIR_HIT,
	SPECIAL_CONTACT_AIR_ACTION,
	SPECIAL_CONTACT_BLOCK,
	SPECIAL_CONTACT_AUTO_AIR_ATTACK,
}

enum SpecialDirection {
	SPECIAL_DIR_NEUTRAL,
	SPECIAL_DIR_UP,
	SPECIAL_DIR_DOWN,
	SPECIAL_DIR_FORWARD,
	SPECIAL_DIR_BACK,
	SPECIAL_DIR_AUTO,
}

const DEFENSE_NONE := DefenseClass.DEFENSE_NONE
const DEFENSE_UNBLOCKABLE := DefenseClass.DEFENSE_UNBLOCKABLE
const DEFENSE_KNOCKBACK := DefenseClass.DEFENSE_KNOCKBACK
const DEFENSE_DELAYED := DefenseClass.DEFENSE_DELAYED
const CONDITION_GROUND_UP_ABILITY := SuperCondition.CONDITION_GROUND_UP_ABILITY
const CONDITION_AIR_DOWN_ABILITY_ABOVE_NET := \
	SuperCondition.CONDITION_AIR_DOWN_ABILITY_ABOVE_NET
const SPECIAL_CONTACT_GROUND_HIT := SpecialContact.SPECIAL_CONTACT_GROUND_HIT
const SPECIAL_CONTACT_AIR_HIT := SpecialContact.SPECIAL_CONTACT_AIR_HIT
const SPECIAL_CONTACT_AIR_ACTION := SpecialContact.SPECIAL_CONTACT_AIR_ACTION
const SPECIAL_CONTACT_BLOCK := SpecialContact.SPECIAL_CONTACT_BLOCK
const SPECIAL_CONTACT_AUTO_AIR_ATTACK := SpecialContact.SPECIAL_CONTACT_AUTO_AIR_ATTACK
const SPECIAL_DIR_NEUTRAL := SpecialDirection.SPECIAL_DIR_NEUTRAL
const SPECIAL_DIR_UP := SpecialDirection.SPECIAL_DIR_UP
const SPECIAL_DIR_DOWN := SpecialDirection.SPECIAL_DIR_DOWN
const SPECIAL_DIR_FORWARD := SpecialDirection.SPECIAL_DIR_FORWARD
const SPECIAL_DIR_BACK := SpecialDirection.SPECIAL_DIR_BACK
const SPECIAL_DIR_AUTO := SpecialDirection.SPECIAL_DIR_AUTO

const ACT_GROUND_UP := {
	"contact": SPECIAL_CONTACT_GROUND_HIT, "direction": SPECIAL_DIR_UP,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_GROUND_NEUTRAL := {
	"contact": SPECIAL_CONTACT_GROUND_HIT, "direction": SPECIAL_DIR_NEUTRAL,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_AIR_DOWN_152 := {
	"contact": SPECIAL_CONTACT_AIR_HIT, "direction": SPECIAL_DIR_DOWN,
	"requires_ability": 1, "original_height_y": 152, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_AIR_DOWN_160 := {
	"contact": SPECIAL_CONTACT_AIR_HIT, "direction": SPECIAL_DIR_DOWN,
	"requires_ability": 1, "original_height_y": 160, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_AIR_DOWN_ANY := {
	"contact": SPECIAL_CONTACT_AIR_HIT, "direction": SPECIAL_DIR_DOWN,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_AIR_DOWN_192 := {
	"contact": SPECIAL_CONTACT_AIR_HIT, "direction": SPECIAL_DIR_DOWN,
	"requires_ability": 1, "original_height_y": 192, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_AIR_FORWARD_FRIENDLY := {
	"contact": SPECIAL_CONTACT_AIR_HIT, "direction": SPECIAL_DIR_FORWARD,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 1,
	"requires_apex": 0,
}
const ACT_AIR_NEUTRAL_APEX := {
	"contact": SPECIAL_CONTACT_AIR_HIT, "direction": SPECIAL_DIR_NEUTRAL,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 1,
}
const ACT_AIR_BACK_ACTION := {
	"contact": SPECIAL_CONTACT_AIR_ACTION, "direction": SPECIAL_DIR_BACK,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_BLOCK_FORWARD := {
	"contact": SPECIAL_CONTACT_BLOCK, "direction": SPECIAL_DIR_FORWARD,
	"requires_ability": 1, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 0,
}
const ACT_AUTO_AIR_ATTACK := {
	"contact": SPECIAL_CONTACT_AUTO_AIR_ATTACK, "direction": SPECIAL_DIR_AUTO,
	"requires_ability": 0, "original_height_y": -1, "friendly_ball": 0,
	"requires_apex": 0,
}

const GHOST_BALL_DEF := {
	"power": 0,
	"condition": CONDITION_GROUND_UP_ABILITY,
	"activations": [ACT_GROUND_UP],
	"defense_class": DEFENSE_DELAYED,
	"visual": "ghost",
}
const FLAME_ATTACK_DEF := {
	"power": 40,
	"condition": CONDITION_AIR_DOWN_ABILITY_ABOVE_NET,
	"activations": [ACT_AIR_DOWN_152],
	"defense_class": DEFENSE_UNBLOCKABLE,
	"visual": "flame",
}
const DISAPPEARING_BALL_DEF := {"power": 0,
	"activations": [ACT_GROUND_UP, ACT_AIR_DOWN_160],
	"defense_class": DEFENSE_NONE, "visual": "disappearing"}
const FEINT_ATTACK_DEF := {"power": 22, "activations": [ACT_GROUND_NEUTRAL],
	"defense_class": DEFENSE_NONE, "visual": "feint"}
const GUST_BALL_DEF := {"power": 0,
	"activations": [ACT_GROUND_UP, ACT_AIR_FORWARD_FRIENDLY],
	"defense_class": DEFENSE_NONE, "visual": "gust"}
const GUST_ATTACK_DEF := {"power": 22, "activations": [ACT_AUTO_AIR_ATTACK],
	"defense_class": DEFENSE_KNOCKBACK, "visual": "gust_attack"}
const SNAKE_BALL_DEF := {"power": 0, "activations": [ACT_GROUND_UP],
	"defense_class": DEFENSE_NONE, "visual": "snake"}
const BUMBLE_BALL_DEF := {"power": 22,
	"activations": [ACT_GROUND_NEUTRAL, ACT_AIR_FORWARD_FRIENDLY],
	"defense_class": DEFENSE_KNOCKBACK, "visual": "bumble"}
const THUNDER_BALL_DEF := {"power": 22, "activations": [ACT_AIR_NEUTRAL_APEX],
	"defense_class": DEFENSE_UNBLOCKABLE, "visual": "thunder"}
const SUCTION_DEF := {"power": 0, "activations": [ACT_AIR_BACK_ACTION],
	"defense_class": DEFENSE_NONE, "visual": "suction"}
const BUBBLE_PACK_DEF := {"power": 11, "activations": [ACT_AIR_DOWN_160],
	"defense_class": DEFENSE_NONE, "visual": "bubble"}
const TRANSFER_BALL_DEF := {"power": 0, "activations": [ACT_AIR_DOWN_ANY],
	"defense_class": DEFENSE_NONE, "visual": "transfer"}
const SUBSPACE_BLOCK_DEF := {"power": 0, "activations": [ACT_BLOCK_FORWARD],
	"defense_class": DEFENSE_NONE, "visual": "subspace"}
const REFRAIN_ATTACK_DEF := {"power": 11, "activations": [ACT_AIR_DOWN_192],
	"defense_class": DEFENSE_DELAYED, "visual": "refrain"}
const SUPER_CATALOG := {
	SUPER_GHOST_BALL: GHOST_BALL_DEF,
	SUPER_FLAME_ATTACK: FLAME_ATTACK_DEF,
	SUPER_DISAPPEARING_BALL: DISAPPEARING_BALL_DEF,
	SUPER_FEINT_ATTACK: FEINT_ATTACK_DEF,
	SUPER_GUST_BALL: GUST_BALL_DEF,
	SUPER_GUST_ATTACK: GUST_ATTACK_DEF,
	SUPER_SNAKE_BALL: SNAKE_BALL_DEF,
	SUPER_BUMBLE_BALL: BUMBLE_BALL_DEF,
	SUPER_THUNDER_BALL: THUNDER_BALL_DEF,
	SUPER_SUCTION: SUCTION_DEF,
	SUPER_BUBBLE_PACK: BUBBLE_PACK_DEF,
	SUPER_TRANSFER_BALL: TRANSFER_BALL_DEF,
	SUPER_SUBSPACE_BLOCK: SUBSPACE_BLOCK_DEF,
	SUPER_REFRAIN_ATTACK: REFRAIN_ATTACK_DEF,
}

# 固有技とテスト専用上書き。選択キャラの基礎能力・重量・付与能力はProfileが正本。
const DEFS := {
	CHAR_PANDA: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_MARIO: {"abilities": CA_HAT | CA_HIP | CA_CLING, "stats": {}, "supers": {}},
	CHAR_FOX: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_FROG: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_TOME: {"abilities": 0, "stats": {},
		"supers": {
			SUPER_GHOST_BALL: GHOST_BALL_DEF,
			SUPER_FLAME_ATTACK: FLAME_ATTACK_DEF,
		}},
	CHAR_HITO: {"abilities": 0, "stats": {}, "supers": {
		SUPER_DISAPPEARING_BALL: DISAPPEARING_BALL_DEF,
		SUPER_FEINT_ATTACK: FEINT_ATTACK_DEF}},
	CHAR_PIYO: {"abilities": 0, "stats": {}, "supers": {
		SUPER_GUST_BALL: GUST_BALL_DEF, SUPER_GUST_ATTACK: GUST_ATTACK_DEF}},
	CHAR_UME: {"abilities": 0, "stats": {}, "supers": {
		SUPER_SNAKE_BALL: SNAKE_BALL_DEF, SUPER_BUMBLE_BALL: BUMBLE_BALL_DEF}},
	CHAR_CARBY: {"abilities": 0, "stats": {}, "supers": {
		SUPER_GHOST_BALL: GHOST_BALL_DEF, SUPER_THUNDER_BALL: THUNDER_BALL_DEF}},
	CHAR_DUO: {"abilities": 0, "stats": {}, "supers": {
		SUPER_SUCTION: SUCTION_DEF, SUPER_BUBBLE_PACK: BUBBLE_PACK_DEF}},
	CHAR_SEC1: {"abilities": 0, "stats": {}, "supers": {
		SUPER_TRANSFER_BALL: TRANSFER_BALL_DEF,
		SUPER_SUBSPACE_BLOCK: SUBSPACE_BLOCK_DEF}},
	CHAR_SEC2: {"abilities": 0, "stats": {}, "supers": {
		SUPER_REFRAIN_ATTACK: REFRAIN_ATTACK_DEF}},
	CHAR_DEBUG: {"abilities": CA_HAT | CA_HIP | CA_CLING | CA_DASH,
		"stats": {"speed": 130, "jump": 120, "atk": 140}, "supers": {}},
}

# 既定ロスター: slot(0..3)→char_id。キャラ選択画面を通らない場合に使う
const ROSTER: Array[int] = [CHAR_PANDA, CHAR_MARIO, CHAR_FOX, CHAR_FROG]

# キャラ選択画面に並ぶ顔ぶれ。開発中は全公開。製品時に隠し扱いを再検討。
# CHAR_DEBUGは載せない。
const SELECTABLE: Array[int] = [CHAR_PANDA, CHAR_MARIO, CHAR_FOX, CHAR_FROG,
	CHAR_TOME, CHAR_HITO, CHAR_PIYO, CHAR_UME, CHAR_CARBY, CHAR_DUO,
	CHAR_SEC1, CHAR_SEC2]

# 表示名(選択画面用。simは参照しない)
const NAMES := {
	CHAR_PANDA: "PANDA",
	CHAR_MARIO: "MARIO",
	CHAR_FOX: "FOX",
	CHAR_FROG: "FROG",
	CHAR_TOME: "TOME",
	CHAR_HITO: "HITO",
	CHAR_PIYO: "PIYO",
	CHAR_UME: "UME",
	CHAR_CARBY: "CARBY",
	CHAR_DUO: "DUO",
	CHAR_SEC1: "ALIEN",
	CHAR_SEC2: "UMA",
	CHAR_DEBUG: "DEBUG",
}

static func has_ability(char_id: int, bit: int) -> bool:
	var def: Dictionary = DEFS.get(char_id, {})
	return (int(def.get("abilities", 0)) & bit) != 0

static func has_super(char_id: int, super_id: int) -> bool:
	var def: Dictionary = DEFS.get(char_id, {})
	var supers: Dictionary = def.get("supers", {})
	return supers.has(super_id)

static func super_def(super_id: int) -> Dictionary:
	return SUPER_CATALOG.get(super_id, {})

static func stat(char_id: int, key: String) -> int:
	# 既存物理への整数%窓口。基礎5能力はA-E表、重量は標準値から解決する。
	if key.begins_with("sc_"):
		return 0
	var def: Dictionary = DEFS.get(char_id, {})
	var stats: Dictionary = def.get("stats", {})
	if stats.has(key):
		return int(stats[key])
	match key:
		"atk":
			return Profile.power_pct(Profile.rank(char_id, Profile.ABILITY_POWER))
		"speed":
			return Profile.speed_pct(Profile.rank(char_id, Profile.ABILITY_SPEED))
		"slide":
			return Profile.brake_distance_pct(Profile.rank(char_id, Profile.ABILITY_BRAKE))
		"weight":
			return Profile.weight_pct(char_id)
	var fallback: int = 0 if key.begins_with("sc_") else 100
	return fallback

static func rank(char_id: int, ability: String) -> int:
	return Profile.rank(char_id, ability)

static func traits(char_id: int) -> Array:
	return Profile.traits(char_id)

static func has_trait(char_id: int, trait_id: int) -> bool:
	return Profile.has_trait(char_id, trait_id)
