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

# 固有技とテスト専用上書き。選択キャラの基礎能力・重量・付与能力はProfileが正本。
const DEFS := {
	CHAR_PANDA: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_MARIO: {"abilities": CA_HAT | CA_HIP | CA_CLING, "stats": {}, "supers": {}},
	CHAR_FOX: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_FROG: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_TOME: {"abilities": 0, "stats": {},
		"supers": {SUPER_GHOST_BALL: true, SUPER_FLAME_ATTACK: true}},
	CHAR_HITO: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_PIYO: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_UME: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_CARBY: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_DUO: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_SEC1: {"abilities": 0, "stats": {}, "supers": {}},
	CHAR_SEC2: {"abilities": 0, "stats": {}, "supers": {}},
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
	return bool(supers.get(super_id, false))

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
		"guard_max":
			return Profile.guard_pct(Profile.rank(char_id, Profile.ABILITY_GUARD))
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
