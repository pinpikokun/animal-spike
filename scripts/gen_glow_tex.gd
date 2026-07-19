extends SceneTree

# 発光エフェクトの基礎テクスチャ生成(表示層ツール。float可)。
# ROUNDS風の発光は「縁のくっきりした円盤」ではなく「中心が明るく外へ滑らかに減衰する
# やわらかい光の玉」でできている。手続きのdraw_circleでは出せないこの滑らかな減衰を、
# 事前生成のグラデ素材で得る。加算合成+HDRブルームと組み合わせて光らせる。
# 使い方: tools\godot\Godot_v4.6-stable_win64_console.exe --headless --path . -s res://scripts/gen_glow_tex.gd
# 出力: assets/fx/glow.png (64x64, 白RGB+ガウス状アルファ), assets/fx/spark.png (16x16, 細い光点)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/fx")
	_save_glow("res://assets/fx/glow.png", 64, 2.4)
	_save_glow("res://assets/fx/spark.png", 16, 3.2)
	# 煙用: 芯がふくよかで縁がとても柔らかい玉(falloff小)。重ねて「ホワン」とした雲にする
	_save_glow("res://assets/fx/smoke.png", 64, 1.15)
	# ブロブ用: 輪郭のはっきりした丸い塊(中心不透明→縁だけ少しぼかす)。
	# ROUNDSの土煙はガウスぼかしでなく、この「ペタッとした丸塊」を重ねたメタボール状
	_save_blob("res://assets/fx/blob.png", 48, 0.92)
	print("glow/blob textures generated")
	quit()

func _save_blob(path: String, size: int, solid_r: float) -> void:
	# ベタ塗りの丸塊: solid_rまで完全不透明(alpha=1)、そこから1〜2pxだけAAで0へ。
	# ROUNDSの土煙は不透明のベタ塗り=重なっても濃淡が出ず、縁もぼやけない。
	# 半透明のグラデにすると重なりに濃淡が出て「透けたエフェクト」に見えてしまう
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	var edge := 1.5 / c  # AAは1.5pxぶんだけ
	for y in size:
		for x in size:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var a := clampf((solid_r + edge - r) / edge, 0.0, 1.0)  # r<solid_rで1、縁で0
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	img.save_png(path)

func _save_glow(path: String, size: int, falloff: float) -> void:
	# 中心1.0→外周0.0のガウス状アルファ。RGBは白(色は描画時のmodulateで着ける)。
	# falloffが大きいほど芯が締まって外へ鋭く落ちる
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var r := sqrt(dx * dx + dy * dy)  # 0(中心)..~1(縁)
			var a := exp(-falloff * falloff * r * r)  # ガウス減衰
			# 縁を完全に0へ寄せる(タイル状の四角い切れ目を防ぐ)
			a *= clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	img.save_png(path)
