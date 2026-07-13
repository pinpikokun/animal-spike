extends RefCounted
# 統一エフェクト・パーティクル(表示層。float可、sim状態には一切触れない)。
# ROUNDS研究で確立した全エフェクト共通の原理:
#   ・エフェクト=〇(不透明の丸/楕円)の集まり。大小さまざま
#   ・各〇は発生源の慣性を引き継いで移動(止まればその場/動けば流れる)+散開
#   ・移動しながらバラバラに散り、色は変えず(不透明のまま)縮小して消える
#   ・飛び散る粒は速度方向に伸びた楕円、中心の遅い粒は丸のまま
#   ・攻撃/衝突は火色+白熱の火花(加算発光)を上乗せ
# ゲーム(game_view)と検証デモ(gen_fx_anim)が同じこのコードを使う=単一の真実源。

const GLOW := preload("res://assets/fx/glow.png")
const BLOB := preload("res://assets/fx/blob.png")

# 全粒の大きさを一律で抑える倍率(ユーザー指示: 3/4)
const SIZE_SCALE := 0.75

# 各イベントの見た目。col=丸の色, spread=散開角(rad), n=粒数, sz=基準サイズ(px),
# grav=重力, life=寿命(秒), glow=白熱火花を乗せるか, ink=慣性の反映率(0で無反応)。
# dir(散開の中心方向)は発生時にイベント側から渡す(dash/attack/wall等は状況で変わる)
const KINDS := {
	"jump":       {"col": Color(0.88, 0.83, 0.74), "spread": 0.7,  "n": 16, "sz": 8.0,  "grav": 20.0, "life": 0.34, "glow": false, "ink": 0.8},
	"land":       {"col": Color(0.90, 0.85, 0.77), "spread": 1.3,  "n": 10, "sz": 8.5,  "grav": 6.0,  "life": 0.34, "glow": false, "ink": 0.6, "reach_mul": 1.1},
	"dash":       {"col": Color(0.88, 0.83, 0.74), "spread": 1.0,  "n": 11, "sz": 7.0,  "grav": 14.0, "life": 0.30, "glow": false, "ink": 0.7},
	"brake":      {"col": Color(0.90, 0.86, 0.78), "spread": 1.1,  "n": 13, "sz": 7.5,  "grav": 14.0, "life": 0.34, "glow": false, "ink": 0.8},
	"ring":       {"col": Color(0.80, 0.85, 0.95), "spread": 2.0,  "n": 11, "sz": 6.5,  "grav": 10.0, "life": 0.26, "glow": false, "ink": 0.9},
	"attack":     {"col": Color(0.90, 0.85, 0.77), "spread": 2.2,  "n": 16, "sz": 7.5,  "grav": 4.0,  "life": 0.30, "glow": false, "ink": 1.0},
	"just":       {"col": Color(1.0, 0.7, 0.3),    "spread": 1.9,  "n": 22, "sz": 8.5,  "grav": 6.0,  "life": 0.42, "glow": true,  "ink": 1.0},
	"block":      {"col": Color(0.90, 0.86, 0.80), "spread": 2.2,  "n": 14, "sz": 6.5,  "grav": 4.0,  "life": 0.32, "glow": false, "ink": 1.0},
	"wall":       {"col": Color(0.90, 0.85, 0.77), "spread": 2.0,  "n": 14, "sz": 6.5,  "grav": 4.0,  "life": 0.30, "glow": false, "ink": 1.0},
	"ballground": {"col": Color(0.90, 0.85, 0.77), "spread": 2.4,  "n": 14, "sz": 8.0,  "grav": 8.0,  "life": 0.32, "glow": false, "ink": 0.6},
	"score":      {"col": Color(1.0, 0.85, 0.4),   "spread": 2.6,  "n": 26, "sz": 8.5,  "grav": 8.0,  "life": 0.60, "glow": true,  "ink": 0.5},
}

static func hv(seed: int, i: int, ch: int) -> float:
	var h := (seed * 2654435761 + i * 40503 + ch * 19349663) & 0x7FFFFFFF
	return float(h % 100003) / 100003.0

# 1個の粒の今の [pos, size, alive, ellipse_angle, elong, spd_n] を決定的に返す
static func _particle(kd: Dictionary, pos0: Vector2, base_dir: float, inertia: Vector2,
		seed: int, i: int, t: float, ground_y: float) -> Array:
	var plife: float = 0.55 + 0.45 * hv(seed, i, 0)  # 個々の寿命ずらし
	var lt := t / plife
	if lt >= 1.0:
		return [Vector2.ZERO, 0.0, false, 0.0, 1.0, 0.0]
	var ease := 1.0 - pow(1.0 - lt, 2.0)
	# 発生ごとの"揺らぎ"(粒indexに依存しないseed由来の乱数)。丸の見た目は変えず
	# 「塊全体の広がり・傾き・飛距離」だけを毎回散らして同じ煙に見えなくする
	var ev_spread := 0.5 + 1.0 * hv(seed, 900, 0)   # 扇の広がり倍率(0.5〜1.5)
	var ev_bias := (hv(seed, 900, 1) - 0.5) * 1.0   # 扇の傾き(左右の偏り, ±0.5rad)
	var ev_reach := 0.6 + 0.8 * hv(seed, 900, 2)    # 飛距離倍率(0.6〜1.4)
	var ang: float = base_dir + ev_bias + (hv(seed, i, 1) - 0.5) * float(kd["spread"]) * ev_spread
	var spd_n: float = hv(seed, i, 2)
	var big: float = hv(seed, i, 3)
	# 散開距離はキャラ(~48px)を大きく超えない範囲に抑える(以前の約1/3)。
	# 横移動でコート半分まで飛ぶ・ジャンプ煙が頭を越えるのを防ぐ
	var reach := (5.0 + 15.0 * spd_n) * (1.2 - 0.6 * big) * float(kd.get("reach_mul", 1.0)) * ev_reach
	var scatter := Vector2.from_angle(ang) * reach * ease
	var inert := inertia * (lt * 2.5) * float(kd["ink"])  # 慣性の流れをさらに半分に
	var grav := Vector2(0.0, float(kd["grav"]) * 0.35 * lt * lt)
	var pos := pos0 + scatter + inert + grav
	if pos.y > ground_y:
		pos.y = ground_y
	var size0: float = float(kd["sz"]) * SIZE_SCALE * (0.4 + 1.1 * big)
	var shrink := 1.0 - smoothstep(0.35, 1.0, lt)
	var size := size0 * shrink
	var vel := Vector2.from_angle(ang) + Vector2(0.0, 0.2 * lt)
	var elong := 1.0 + 2.6 * spd_n * (1.0 - big * 0.6)
	return [pos, size, size > 0.5, vel.angle(), elong, spd_n]

# 寿命が尽きたか(呼び出し側の破棄判定用)
static func expired(kind: String, f0: int, cur_frame: int) -> bool:
	if not KINDS.has(kind):
		return true
	return float(cur_frame - f0) / (60.0 * float(KINDS[kind]["life"])) >= 1.0

static func _seed(kind: String, f0: int) -> int:
	return f0 * 131 + hash(kind) % 997

# 発生ごとの粒数(基準の0.7〜1.3倍)。丸の見た目は不変、密度だけ毎回変える
static func _count(kd: Dictionary, seed: int) -> int:
	return maxi(3, int(round(float(kd["n"]) * (0.55 + 0.9 * hv(seed, 900, 3)))))

# 不透明の丸/楕円(本体)を通常合成レイヤーに描く。opaque/glowでレイヤーを分けるのは
# 丸=不透明(加算だと透ける)、火花=加算発光、を正しく合成するため
static func draw_opaque(c: CanvasItem, kind: String, pos: Vector2, base_dir: float,
		inertia: Vector2, f0: int, cur_frame: int, ground_y: float) -> void:
	if not KINDS.has(kind):
		return
	var kd: Dictionary = KINDS[kind]
	var t := float(cur_frame - f0) / (60.0 * float(kd["life"]))
	if t >= 1.0:
		return
	var seed := _seed(kind, f0)
	var col: Color = kd["col"]
	var bw := float(BLOB.get_width())
	for i in _count(kd, seed):
		var r := _particle(kd, pos, base_dir, inertia, seed, i, t, ground_y)
		if not r[2]:
			continue
		var sz: float = r[1]
		c.draw_set_transform(r[0], r[3], Vector2(sz * float(r[4]), sz) / bw)
		c.draw_texture(BLOB, -BLOB.get_size() * 0.5, Color(col.r, col.g, col.b, 1.0))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 火花(白熱の頭)を加算合成レイヤーに描く。glow種のみ。発生地点の中心光は作らない
static func draw_glow(c: CanvasItem, kind: String, pos: Vector2, base_dir: float,
		inertia: Vector2, f0: int, cur_frame: int, ground_y: float) -> void:
	if not KINDS.has(kind) or not KINDS[kind]["glow"]:
		return
	var kd: Dictionary = KINDS[kind]
	var t := float(cur_frame - f0) / (60.0 * float(kd["life"]))
	if t >= 1.0:
		return
	var seed := _seed(kind, f0)
	var gw := float(GLOW.get_width())
	for i in _count(kd, seed):
		var spd_n := hv(seed, i, 2)
		if spd_n < 0.5:
			continue  # 遅い中心粒には輝きを乗せない
		var r := _particle(kd, pos, base_dir, inertia, seed, i, t, ground_y)
		if not r[2]:
			continue
		var plife: float = 0.55 + 0.45 * hv(seed, i, 0)
		var fade := pow(1.0 - clampf(t / plife, 0.0, 1.0), 1.4)
		var hd := 3.0 + 3.0 * fade
		c.draw_set_transform(r[0], 0.0, Vector2(hd, hd) / gw)
		c.draw_texture(GLOW, -GLOW.get_size() * 0.5, Color(1, 1, 0.9, 0.7 * fade))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
