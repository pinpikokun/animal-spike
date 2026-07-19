# キャラ定義の正本(4層構造の第2層=性能シート+第3層=固有技ビット)。
# 葉ファイル: 何もpreloadしない(simulation/sim_cpu双方から安全に参照できる)。
# キャラ追加=DEFSに1エントリ追加。当面GDScript定数、MOD開放段階でJSONローダ化
extends RefCounted

# キャラID(sim状態のchar_idに入る値。slot番号との暗黙対応を排除する)
const CHAR_PANDA := 0
const CHAR_MARIO := 1
const CHAR_FOX := 2
const CHAR_FROG := 3
const CHAR_DEBUG := 15  # テスト専用: 全能力持ち+個性値

# 固有技ビット(第3層。付け外し自由。CPUのAB_*は「やりたがるか」、こちらは「できるか」)
const CA_HAT := 1    # 帽子投げ
const CA_HIP := 2    # ヒップアタック
const CA_CLING := 4  # 壁張り付き
const CA_DASH := 8   # ダブルタップダッシュ

# 性能シート(第2層)。キーが無ければ100(=標準)、ばらつき系(sc_*)は0。
# speed=移動速度% / jump=ジャンプ力% / weight=重さ%(落下加速) / guard_max=耐久値%
# slide=急ブレーキ滑走距離% / atk=アタック威力% / just_reward=ジャスト報酬%
# just_window=ジャスト窓の広さ%(0=ジャスト不可) / absorb=トス反動受け流し%
# sc_toss/sc_recv/sc_atk/sc_blk=アクション別ばらつき%(0=散らばり無し)
const DEFS := {
	CHAR_PANDA: {"abilities": 0, "stats": {}},
	CHAR_MARIO: {"abilities": CA_HAT | CA_HIP | CA_CLING, "stats": {}},
	CHAR_FOX: {"abilities": 0, "stats": {}},
	CHAR_FROG: {"abilities": 0, "stats": {}},
	CHAR_DEBUG: {"abilities": CA_HAT | CA_HIP | CA_CLING | CA_DASH,
		"stats": {"speed": 130, "jump": 120, "atk": 140, "sc_atk": 40}},
}

# 既定ロスター: slot(0..3)→char_id。キャラ選択画面を通らない場合に使う
const ROSTER: Array[int] = [CHAR_PANDA, CHAR_MARIO, CHAR_FOX, CHAR_FROG]

# キャラ選択画面に並ぶ顔ぶれ(CHAR_DEBUGは載せない)
const SELECTABLE: Array[int] = [CHAR_PANDA, CHAR_MARIO, CHAR_FOX, CHAR_FROG]

# 表示名(選択画面用。simは参照しない)
const NAMES := {
	CHAR_PANDA: "PANDA",
	CHAR_MARIO: "MARIO",
	CHAR_FOX: "FOX",
	CHAR_FROG: "FROG",
	CHAR_DEBUG: "DEBUG",
}

# 10段階レベル表(5=標準)。キャラの個性はここを書き換えるだけで変わる。
# toss=トス技術(受け流し+ブレの少なさ) / atk=アタック(威力が上がるほどブレも増す)
# jump=ジャンプ力 / weight=重さ(落下速度・吹っ飛ばされにくさ。ジャンプとは独立)
const LEVELS := {
	CHAR_PANDA: {"toss": 2, "atk": 8, "jump": 3, "weight": 8},
	CHAR_MARIO: {"toss": 8, "atk": 2, "jump": 5, "weight": 5},
	CHAR_FOX: {"toss": 5, "atk": 5, "jump": 5, "weight": 5},
	CHAR_FROG: {"toss": 5, "atk": 5, "jump": 8, "weight": 2},
}

const PLAYER_STAT_KEYS: Array[String] = [
	"toss", "atk", "jump", "weight", "speed", "slide", "guard",
	"just_window", "just_reward", "absorb", "toss_stability",
	"recv_stability", "atk_stability", "block_stability",
]

static func level(char_id: int, key: String) -> int:
	var lv: Dictionary = LEVELS.get(char_id, {})
	if lv.has(key):
		return int(lv[key])
	match key:
		"absorb":
			return int(lv.get("toss", 5))
		"toss_stability":
			return clampi(10 - stat(char_id, "sc_toss") / 8, 1, 10)
		"recv_stability":
			return clampi(10 - stat(char_id, "sc_recv") / 8, 1, 10)
		"atk_stability":
			return clampi(10 - stat(char_id, "sc_atk") / 8, 1, 10)
		"block_stability":
			return clampi(10 - stat(char_id, "sc_blk") / 8, 1, 10)
		"guard":
			return clampi((stat(char_id, "guard_max") - 50) / 10, 1, 10)
		"speed", "slide", "just_window", "just_reward":
			return clampi((stat(char_id, key) - 50) / 10, 1, 10)
	return int(lv.get(key, 5))

static func has_ability(char_id: int, bit: int) -> bool:
	var def: Dictionary = DEFS.get(char_id, {})
	return (int(def.get("abilities", 0)) & bit) != 0

static func stat(char_id: int, key: String) -> int:
	# 優先順: 明示%値(statsに直書き) > 10段階レベルからの換算 > 既定(100/0)
	var def: Dictionary = DEFS.get(char_id, {})
	var stats: Dictionary = def.get("stats", {})
	if stats.has(key):
		return int(stats[key])
	if LEVELS.has(char_id):
		match key:
			"jump":  # Lv5=100%。Lv1=60..Lv10=150
				return 50 + 10 * level(char_id, "jump")
			"atk":   # 威力%も同スケール
				return 50 + 10 * level(char_id, "atk")
			"weight":  # 重さは振れ幅を大きく: Lv2=64(ふわふわ)..Lv8=136(どっしり)
				return 40 + 12 * level(char_id, "weight")
			"absorb":  # トス技術の物理面=入射の受け流し。上手いほど流されない
				return 50 + 10 * level(char_id, "toss")
			"sc_toss", "sc_recv":  # トス技術の精度面=下手ほど狙いが散る
				return (10 - level(char_id, "toss")) * 8
			"sc_atk":  # 強打型ほど荒れる(威力とブレの表裏一体)。Lv2以下はブレなし
				return maxi(0, level(char_id, "atk") - 2) * 8
	var fallback: int = 0 if key.begins_with("sc_") else 100
	return fallback
