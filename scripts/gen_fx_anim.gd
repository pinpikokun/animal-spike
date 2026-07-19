extends SceneTree

# エフェクト統一モデルの検証アニメ(表示層ツール。float可)。連番PNG→ffmpegでMP4化。
# ROUNDSを1フレーム単位で研究して分かった「全エフェクト共通の原理」を実装:
#   ・エフェクト=〇(不透明の丸)の集まり。大小さまざま
#   ・各〇は発生源の慣性を引き継ぐ(右へ動いてたら右へ流れ、止まってたらその場)+散開速度
#   ・移動しながらバラバラに散り、色は変えずに(不透明のまま)縮小して消える
#   ・土煙の色はキャラの色。攻撃/着弾は火花(加算発光)を上乗せ
# 使い方: tools\godot\...console.exe --path . -s res://scripts/gen_fx_anim.gd -- OUTDIR

const GLOW := preload("res://assets/fx/glow.png")
const BLOB := preload("res://assets/fx/blob.png")

const W := 900
const H := 380
const GROUND_Y := 300.0
const FRAMES := 150

# シナリオ: 統一モデルを様々な状況で。inertia=発生源の速度(px/frame相当の係数)
# kind: puff(不透明の丸のみ) / burst(丸+火花発光)
const SHOTS := [
	# 土煙の色はキャラ色でなくクリーム/生成り(砂埃の色)で統一。以下は運動の違いだけ
	# ジャンプ(その場): 丸が真上へ。散開を狭めて「縦方向」に上がる。慣性0=横流れなし
	{"f0": 6,  "kind": "puff", "pos": Vector2(140, GROUND_Y), "dir": -1.5708, "spread": 0.7,
		"col": Color(0.88, 0.83, 0.74), "inertia": Vector2(0, -2.6), "n": 22, "life": 26, "grav": 20.0, "sz": 15.0},
	# ジャンプ(右へ移動): 縦方向に上がりつつ慣性で右へ流れる
	{"f0": 40, "kind": "puff", "pos": Vector2(360, GROUND_Y), "dir": -1.5708, "spread": 0.7,
		"col": Color(0.88, 0.83, 0.74), "inertia": Vector2(3.2, -2.4), "n": 22, "life": 26, "grav": 20.0, "sz": 15.0},
	# 着地: 地面で左右に散る土煙
	{"f0": 74, "kind": "puff", "pos": Vector2(600, GROUND_Y), "dir": 0.0, "spread": 3.14159,
		"col": Color(0.90, 0.85, 0.77), "inertia": Vector2(0, 0.5), "n": 26, "life": 26, "grav": 10.0, "sz": 16.0},
	# 攻撃(空中・右打ち→左へ): 火色の丸+白熱の火花。慣性は左
	{"f0": 108, "kind": "burst", "pos": Vector2(430, 150), "dir": 3.14159, "spread": 1.5,
		"col": Color(1.0, 0.6, 0.25), "inertia": Vector2(-2.5, 0), "n": 16, "life": 24, "grav": 26.0, "sz": 11.0},
]

func _init() -> void:
	var outdir := "res://fx_anim"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)

	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(SceneDraw.new())
	var opaque := OpaqueDraw.new()  # 不透明の丸(土煙・本体)
	vp.add_child(opaque)
	var glow := GlowDraw.new()      # 加算発光(火花・光)
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	vp.add_child(glow)
	var lbl := LabelDraw.new()
	vp.add_child(lbl)
	root.add_child(vp)

	for f in FRAMES:
		opaque.frame = f
		glow.frame = f
		lbl.frame = f
		opaque.queue_redraw(); glow.queue_redraw(); lbl.queue_redraw()
		await process_frame
		await process_frame
		var img: Image = vp.get_texture().get_image()
		img.save_png("%s/f_%03d.png" % [outdir, f])
	print("fx anim frames saved to: ", outdir, " (", FRAMES, " frames)")
	quit()

# 決定的乱数と統一パーティクル計算。inner classから P.hv / P.particle で呼ぶ
class P:
	static func hv(seed: int, i: int, ch: int) -> float:
		var h := (seed * 2654435761 + i * 40503 + ch * 19349663) & 0x7FFFFFFF
		return float(h % 100003) / 100003.0

	# 統一パーティクル: 1個の〇の「今の」位置・大きさ・楕円(角度と伸び)を返す(決定的)。
	# 発生源慣性inertiaを時間で積算=移動しながら散る。色は不変、末で縮小して消える。
	# 速い粒ほど速度方向に伸びた楕円に(=飛び散る煙は楕円、中心の遅い粒は丸のまま)。
	# 戻り値 [pos, size, alive, ellipse_angle, elong]
	static func particle(sp: Dictionary, i: int, t: float, ground_y: float) -> Array:
		var seed := int(sp["f0"]) * 131 + 17
		var plife: float = 0.55 + 0.45 * hv(seed, i, 0)  # 個々の寿命ずらし
		var lt := t / plife
		if lt >= 1.0:
			return [Vector2.ZERO, 0.0, false, 0.0, 1.0]
		var ease := 1.0 - pow(1.0 - lt, 2.0)   # 出だし速く外へ、末で減速
		var ang: float = sp["dir"] + (hv(seed, i, 1) - 0.5) * sp["spread"]
		var spd_n: float = hv(seed, i, 2)
		var big: float = hv(seed, i, 3)           # 0=小 1=大
		var reach := (30.0 + 90.0 * spd_n) * (1.2 - 0.6 * big)  # 大きい粒は近く
		var scatter: Vector2 = Vector2.from_angle(ang) * reach * ease
		var inertia: Vector2 = sp["inertia"] * (lt * 60.0)  # 慣性を時間積算
		var grav := Vector2(0.0, float(sp["grav"]) * lt * lt)
		var pos: Vector2 = sp["pos"] + scatter + inertia + grav
		if pos.y > ground_y:
			pos.y = ground_y
		var size0: float = float(sp["sz"]) * (0.4 + 1.1 * big)
		var shrink := 1.0 - smoothstep(0.35, 1.0, lt)  # 途中まで一定→末で縮小
		var size := size0 * shrink
		# 楕円: 進行方向(散開角+重力の下向き)に伸ばす。速い粒ほど伸び、遅い中心粒は丸
		var vel := Vector2.from_angle(ang) + Vector2(0.0, 0.9 * lt)
		var e_ang := vel.angle()
		var elong := 1.0 + 2.6 * spd_n * (1.0 - big * 0.6)  # 小さく速い粒=よく伸びる
		return [pos, size, size > 0.5, e_ang, elong]

class SceneDraw:
	extends Node2D
	func _draw() -> void:
		draw_rect(Rect2(0, 0, W, H), Color(0.055, 0.065, 0.13))
		draw_rect(Rect2(0, GROUND_Y, W, H - GROUND_Y), Color(0.10, 0.09, 0.14))

# 不透明の丸レイヤー(土煙・本体)。色そのまま・縮小して消える=重なりに濃淡なし
class OpaqueDraw:
	extends Node2D
	var frame := 0
	func _draw() -> void:
		for sp in SHOTS:
			var t := float(frame - sp["f0"]) / float(sp["life"])
			if t < 0.0 or t >= 1.0:
				continue
			var col: Color = sp["col"]
			for i in int(sp["n"]):
				var r := P.particle(sp, i, t, GROUND_Y)
				if not r[2]:
					continue
				var p: Vector2 = r[0]
				var sz: float = r[1]
				var e_ang: float = r[3]
				var elong: float = r[4]
				# 不透明(alpha=1)の楕円: 速度方向(e_ang)にelong倍伸ばす。遅い中心粒は丸
				var bw := float(BLOB.get_width())
				draw_set_transform(p, e_ang, Vector2(sz * elong, sz) / bw)
				draw_texture(BLOB, -BLOB.get_size() * 0.5, Color(col.r, col.g, col.b, 1.0))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 加算発光レイヤー(火花)。burst種のみ。丸の動きに白熱の火花を上乗せ
class GlowDraw:
	extends Node2D
	var frame := 0
	func _draw() -> void:
		for sp in SHOTS:
			if sp["kind"] != "burst":
				continue
			var t := float(frame - sp["f0"]) / float(sp["life"])
			if t < 0.0 or t >= 1.0:
				continue
			# 発生地点の光は不要(ユーザー指摘)。中心の閃光は描かない。
			# 火花の白熱の頭だけ、速い粒に小さく乗せる(飛び散る火の粉の輝き)
			var seed := int(sp["f0"]) * 131 + 17
			for i in int(sp["n"]):
				var r := P.particle(sp, i, t, GROUND_Y)
				if not r[2]:
					continue
				var spd_n := P.hv(seed, i, 2)
				if spd_n < 0.5:
					continue  # 遅い中心粒には輝きを乗せない(中心の光を作らない)
				var lt := t / (0.55 + 0.45 * P.hv(seed, i, 0))
				var fade := pow(1.0 - lt, 1.4)
				var p: Vector2 = r[0]
				_orb(p, 3.0 + 3.0 * fade, Color(1, 1, 0.9, 0.7 * fade))

	func _orb(p: Vector2, diam: float, col: Color) -> void:
		draw_set_transform(p, 0.0, Vector2(diam, diam) / float(GLOW.get_width()))
		draw_texture(GLOW, -GLOW.get_size() * 0.5, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class LabelDraw:
	extends Node2D
	var frame := 0
	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var txt := ""
		for sp in SHOTS:
			if frame >= int(sp["f0"]) and frame < int(sp["f0"]) + 32:
				var inv: Vector2 = sp["inertia"]
				match int(sp["f0"]):
					6: txt = "JUMP その場: 青い丸が真上へ上がり散開・縮小(慣性0=横流れなし)"
					40: txt = "JUMP 右移動: 同じ丸が慣性で右へ流れながら上がる"
					74: txt = "LAND 着地: 赤い丸が左右へ散り縮小"
					108: txt = "ATTACK 右打ち→左: 火色の丸+白熱火花、慣性で左へ"
		draw_string(f, Vector2(12, 26), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.7))
