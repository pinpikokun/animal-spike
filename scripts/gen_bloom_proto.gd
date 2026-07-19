extends SceneTree

# ブルーム式エフェクトの実現性検証プロトタイプ(表示層ツール。float可)。
# 目的: (1)GodotのHDR 2D + WorldEnvironment Glow で「本物の発光(光の滲み)」が出て、
# しかもビューポート捕捉でPNGに写るかを実証する。(2)やわらか素材で足元煙が「ホワン」と
# 自然になるかを実証する。ダメならダメと分かるための最小検証。
# 使い方: tools\godot\...console.exe --path . -s res://scripts/gen_bloom_proto.gd -- OUT.png
# (ヘッドレスはダミー描画でGlowが出ないので、ウィンドウ有りで実行すること)

const GLOW := preload("res://assets/fx/glow.png")
const SPARK := preload("res://assets/fx/spark.png")
const SMOKE := preload("res://assets/fx/smoke.png")

const W := 900
const H := 460

func _init() -> void:
	var out_path := "res://bloom_proto.png"
	var glow_on := true
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_path = args[0]
	if args.size() > 1:
		glow_on = args[1] != "noglow"

	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.use_hdr_2d = true  # HDR(1.0超の明るさ)を許可。ブルームの前提
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# 背景(ゲームのコートに近い紺)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.065, 0.13)
	bg.size = Vector2(W, H)
	vp.add_child(bg)

	# Glow環境(ブルーム)。明るい部分が周囲に光を滲ませる。noglowで無効化して比較
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = glow_on
	env.glow_intensity = 1.5
	env.glow_strength = 1.3
	env.glow_bloom = 0.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.8
	# 複数レベルで大きく柔らかく滲ませる
	env.set("glow_levels/2", 1.0)
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 1.0)
	env.set("glow_levels/5", 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# 加算合成の発光レイヤー(爆発・火花)
	var addlayer := Node2D.new()
	var addmat := CanvasItemMaterial.new()
	addmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	addlayer.material = addmat
	var expl := ExplosionDraw.new()
	addlayer.add_child(expl)
	vp.add_child(addlayer)

	# 通常合成の煙レイヤー(足元のホワン)
	var smoke := SmokeDraw.new()
	vp.add_child(smoke)

	# ラベル
	var lbl := LabelDraw.new()
	lbl.glow_on = glow_on
	vp.add_child(lbl)

	root.add_child(vp)
	await process_frame
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(out_path)
	print("bloom proto saved: ", out_path, " (", W, "x", H, ")")
	quit()

# 爆発: 左に3つ、寿命t=0.1/0.4/0.75で「表示→フェード」を並べる。
# HDRの明るさ(modulate>1)でコアを白飛びさせ、ブルームで滲ませる。
# 光の玉(glow.png)を色付き・大きさ違いで重ね、細い火花(spark.png)を放射
class ExplosionDraw:
	extends Node2D
	func _draw() -> void:
		var ts := [0.1, 0.4, 0.75]
		var xs := [150.0, 300.0, 450.0]
		for i in 3:
			_burst(Vector2(xs[i], 150.0), ts[i], 9137 + i * 71)

	func _burst(pos: Vector2, t: float, seed: int) -> void:
		var a := pow(1.0 - t, 1.4)
		var flash := pow(1.0 - t, 3.0)
		var grow := 1.0 - pow(1.0 - t, 2.2)
		# 疑似ブルーム(焼き込み): ポストプロセス無しでも「光の滲み」を出すため、
		# 芯の外側に非常に大きく薄いハローを加算で重ねる。これが周囲への光漏れになる。
		# Compatibilityレンダラーでも動く(素材の加算だけ)
		_orb(pos, 130.0 + 60.0 * grow, Color(1.0, 0.6, 0.7) * (0.5 * a), 0.5)
		_orb(pos, 80.0 + 50.0 * grow, Color(1.0, 0.75, 0.5) * (0.8 * a), 0.6)
		# 白熱コア
		_orb(pos, (26.0 + 30.0 * grow), Color(1, 1, 1) * (0.6 + 2.0 * flash), 0.9)
		# 色付きの発光雲(マゼンタ〜オレンジ)
		_orb(pos, 34.0 + 46.0 * grow, Color(1.0, 0.45, 0.9) * (1.6 * a), 0.8)
		_orb(pos, 22.0 + 30.0 * grow, Color(1.0, 0.7, 0.35) * (2.2 * a), 0.85)
		# 放射する火花(白熱の頭)。決定的にばらまく
		for k in 20:
			var h := (seed * 2654435761 + k * 40503) & 0xFFFF
			var ang := float(h) / 65536.0 * TAU
			var dist := (30.0 + 70.0 * float((h >> 3) & 15) / 15.0) * grow
			var off := Vector2.from_angle(ang) * dist + Vector2(0, grow * grow * 10.0)
			var sc := maxf(0.15, 0.5 - 0.35 * t)
			_spark(pos + off, sc, Color(1, 0.85, 0.6) * (2.5 * a))

	func _orb(p: Vector2, diam: float, col: Color, alpha: float) -> void:
		var s := diam / float(GLOW.get_width())
		draw_set_transform(p, 0.0, Vector2(s, s))
		draw_texture(GLOW, -GLOW.get_size() * 0.5, Color(col.r, col.g, col.b, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _spark(p: Vector2, sc: float, col: Color) -> void:
		draw_set_transform(p, 0.0, Vector2(sc, sc))
		draw_texture(SPARK, -SPARK.get_size() * 0.5, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 足元煙: 右に3つ、t=0.1/0.4/0.75。やわらか素材を淡いグレー白で重ねて「ホワン」と広がる。
# 通常合成(加算しない)=光らず自然な煙。ブルームは芯をほんのり滲ませる程度に効く
class SmokeDraw:
	extends Node2D
	func _draw() -> void:
		var ts := [0.1, 0.4, 0.75]
		var xs := [600.0, 720.0, 840.0]
		for i in 3:
			_puff(Vector2(xs[i], 330.0), ts[i], 4423 + i * 53)

	func _puff(pos: Vector2, t: float, seed: int) -> void:
		# 立ち上がりで一気に膨らみ、淡く消える。大きく柔らかい玉を多数重ねて「ホワン」
		var a := pow(1.0 - t, 1.3) * 0.6
		var grow := 1.0 - pow(1.0 - t, 2.2)
		for s in [-1.0, 1.0]:
			for k in 4:
				var h := (seed * 2654435761 + int(s) * 977 + k * 40503) & 0xFFFF
				var jitter := Vector2((float((h) & 31) - 15.0) * 0.8, (float((h >> 5) & 31) - 15.0) * 0.8)
				var off := Vector2(s * (8.0 + 34.0 * grow + k * 6.0), -6.0 - 22.0 * grow - k * 5.0)
				var diam := (34.0 + 26.0 * grow) * (1.0 - 0.12 * k)
				_soft(pos + off + jitter, diam, Color(0.78, 0.81, 0.88, a * (1.0 - 0.18 * k)))

	func _soft(p: Vector2, diam: float, col: Color) -> void:
		var s := diam / float(SMOKE.get_width())
		draw_set_transform(p, 0.0, Vector2(s, s))
		draw_texture(SMOKE, -SMOKE.get_size() * 0.5, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class LabelDraw:
	extends Node2D
	var glow_on := true
	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var tag := "BLOOM=ON" if glow_on else "BLOOM=OFF"
		draw_string(f, Vector2(12, 24), "EXPLOSION [%s]  ->  t=0.1 / 0.4 / 0.75" % tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.9, 0.4) if glow_on else Color(0.7, 0.7, 0.7))
		draw_string(f, Vector2(560, 250), "FOOT SMOKE (soft texture)  ->  t=0.1 / 0.4 / 0.75",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 1.0))
