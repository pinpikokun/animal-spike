# ボール素材ジェネレーター(表示層ツール。float可)
# 使い方: tools\godot\Godot_v4.6-stable_win64.exe --headless --path . -s res://scripts/gen_ball.gd
# 出力:
#   assets/ball/volleyball*.svg      : 128px viewBoxの原版(プレビュー/将来の大型表示用、繊細な線)
#   assets/ball/volleyball*_game.png : ゲーム内実寸へ焼き込んだドット絵版。
#                                      外周=硬い黒フチ、内側シーム=連続した単色線(高解像度描画→
#                                      マックスプール縮小で途切れ無し)、陰影は維持。キャラのドット絵に揃える
# ball_radius_pxや配色を変えたら再実行してコミットすること。
extends SceneTree

const BALL_DIR := "res://assets/ball/"

# シーム3本(中心Y字の腕+セクター内平行線2本)を120度回転で3セクター=計9本
const ARM := "M64 64 C 86 56, 84 24, 64 7"
const D1 := "M100.6 20.3 C 112 45, 104 75, 84.1 92.9"
const D2 := "M120.1 54.1 C 119 72, 110 87, 98.3 95.1"
# パネル閉パス。腕カーブのDe Casteljau分割(t=0.6, 0.8)がD1/D2終点と一致し、
# 境界は全てシームのストロークの下に隠れる
const PA := "M64 64 C 86 56, 84 24, 64 7 A 57 57 0 0 1 100.6 20.3 C 112 45, 104 75, 84.14 92.92 C 70.92 88.5, 61.56 77.83, 64 64 Z"
const PB := "M100.6 20.3 A 57 57 0 0 1 120.1 54.1 C 119 72, 110 87, 98.35 95.15 C 93.38 95.18, 88.55 94.4, 84.14 92.92 C 104 75, 112 45, 100.6 20.3 Z"
const PC := "M120.1 54.1 A 57 57 0 0 1 113.36 92.52 C 108.42 94.28, 103.31 95.12, 98.35 95.15 C 110 87, 119 72, 120.1 54.1 Z"
# 立体感: 右下三日月影2枚(広く薄い+狭く濃い)、左上ハイライト
const SHADOW_WIDE := "M115.66 88.09 A 57 57 0 0 1 12.34 88.09 A 120 120 0 0 0 115.66 88.09 Z"
const SHADOW_DEEP := "M115.66 88.09 A 57 57 0 0 1 12.34 88.09 A 75 75 0 0 0 115.66 88.09 Z"

const SEAM_HIRES := 8       # シーム連続化のための高解像度倍率
const SEAM_STROKE_HI := 2.1 # 高解像度側のシーム線幅

# [パネルA(白系), パネルB, パネルC, シーム色, 輪郭色]
const PALETTES := {
	"": ["#fcfcfa", "#fcfcfa", "#fcfcfa", "#87807a", "#2f2a26"],
	"_blue": ["#f7f5ef", "#3565a8", "#f2c14e", "#2f2a26", "#2f2a26"],
	"_green": ["#f7f5ef", "#55b06a", "#e0605c", "#2f2a26", "#2f2a26"],
	"_teal": ["#f0e7d6", "#3f8f85", "#e8a95a", "#2f2a26", "#2f2a26"],
}

# 大型表示用SVG(繊細な線・アンチエイリアスあり)。ゲームでは使わない
func build_svg(cols: Array, seam_w: float, outline_w: float) -> String:
	var svg := '<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">\n'
	svg += '<circle cx="64" cy="64" r="57" fill="%s"/>\n' % cols[0]
	for deg in [0, 120, 240]:
		var t: String = "" if deg == 0 else ' transform="rotate(%d 64 64)"' % deg
		svg += '<g%s><path d="%s" fill="%s"/><path d="%s" fill="%s"/><path d="%s" fill="%s"/></g>\n' % [t, PA, cols[0], PB, cols[1], PC, cols[2]]
	svg += '<g fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round">\n' % [cols[3], seam_w]
	for deg in [0, 120, 240]:
		var t2: String = "" if deg == 0 else ' transform="rotate(%d 64 64)"' % deg
		svg += '<g%s><path d="%s"/><path d="%s"/><path d="%s"/></g>\n' % [t2, ARM, D1, D2]
	svg += '</g>\n'
	svg += '<ellipse cx="37" cy="37" rx="13" ry="8" transform="rotate(-45 37 37)" fill="#ffffff" opacity="0.55"/>\n'
	svg += '<path d="%s" transform="rotate(-25 64 64)" fill="#141210" opacity="0.09"/>\n' % SHADOW_WIDE
	svg += '<path d="%s" transform="rotate(-25 64 64)" fill="#141210" opacity="0.13"/>\n' % SHADOW_DEEP
	svg += '<circle cx="64" cy="64" r="57" fill="none" stroke="%s" stroke-width="3.2"/>\n' % cols[4]
	svg += '</svg>\n'
	return svg

# 本体(円+パネル+陰影)。シームと外周フチは含めない。ゲームPNGの下地
func build_body_svg(cols: Array) -> String:
	var svg := '<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">'
	svg += '<circle cx="64" cy="64" r="57" fill="%s"/>' % cols[0]
	for deg in [0, 120, 240]:
		var t: String = "" if deg == 0 else ' transform="rotate(%d 64 64)"' % deg
		svg += '<g%s><path d="%s" fill="%s"/><path d="%s" fill="%s"/><path d="%s" fill="%s"/></g>' % [t, PA, cols[0], PB, cols[1], PC, cols[2]]
	svg += '<ellipse cx="37" cy="37" rx="13" ry="8" transform="rotate(-45 37 37)" fill="#ffffff" opacity="0.55"/>'
	svg += '<path d="%s" transform="rotate(-25 64 64)" fill="#141210" opacity="0.09"/>' % SHADOW_WIDE
	svg += '<path d="%s" transform="rotate(-25 64 64)" fill="#141210" opacity="0.13"/>' % SHADOW_DEEP
	svg += '</svg>'
	return svg

# シームのみ(黒・高解像度用)。マスク生成に使う
func build_seam_svg() -> String:
	var svg := '<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">'
	svg += '<g fill="none" stroke="#000000" stroke-width="%s" stroke-linecap="round">' % SEAM_STROKE_HI
	for deg in [0, 120, 240]:
		var t: String = "" if deg == 0 else ' transform="rotate(%d 64 64)"' % deg
		svg += '<g%s><path d="%s"/><path d="%s"/><path d="%s"/></g>' % [t, ARM, D1, D2]
	svg += '</g></svg>'
	return svg

# ゲーム実寸のドット絵PNGを生成
func build_game_png(cols: Array, n: int) -> Image:
	var outline := Color(cols[4])
	var seam := Color(cols[3])
	# 下地(陰影あり・シーム無し)を実寸ラスタし不透明化
	var body := Image.new()
	body.load_svg_from_string(build_body_svg(cols), float(n) / 128.0)
	var ball := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c: Color = body.get_pixel(x, y)
			if c.a < 0.5:
				ball.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				c.a = 1.0
				ball.set_pixel(x, y, c)
	# シームを高解像度で描き、8x8ブロックに1画素でも線があれば点灯=途切れない連続線
	var hs := Image.new()
	hs.load_svg_from_string(build_seam_svg(), float(n * SEAM_HIRES) / 128.0)
	for y in n:
		for x in n:
			if ball.get_pixel(x, y).a < 0.5:
				continue
			var on := false
			for by in SEAM_HIRES:
				for bx in SEAM_HIRES:
					var px: int = x * SEAM_HIRES + bx
					var py: int = y * SEAM_HIRES + by
					if px < hs.get_width() and py < hs.get_height() and hs.get_pixel(px, py).a > 0.5:
						on = true
						break
				if on:
					break
			if on:
				ball.set_pixel(x, y, seam)
	# 外周を硬い黒フチ(透明と隣接する不透明画素)
	var out := ball.duplicate()
	for y in n:
		for x in n:
			if ball.get_pixel(x, y).a < 0.5:
				continue
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= n or ny >= n or ball.get_pixel(nx, ny).a < 0.5:
					edge = true
					break
			if edge:
				out.set_pixel(x, y, outline)
	return out

func _init() -> void:
	# ゲーム内実寸はルールから(表示直径px = ball_radius_px * 2)
	var f := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var rules: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var game_px := int(rules["ball_radius_px"]) * 2
	for suffix in PALETTES:
		var cols: Array = PALETTES[suffix]
		# 原版SVG(大型表示用)
		var svg := build_svg(cols, 2.6, 3.2)
		var sf := FileAccess.open(BALL_DIR + "volleyball" + str(suffix) + ".svg", FileAccess.WRITE)
		sf.store_string(svg)
		sf.close()
		# ゲーム実寸ドット絵PNG
		var png := build_game_png(cols, game_px)
		png.save_png(BALL_DIR + "volleyball" + str(suffix) + "_game.png")
	print("GEN BALL OK size=" + str(game_px))
	quit()
