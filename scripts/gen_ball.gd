# ボール素材ジェネレーター(表示層ツール。float可)
# 使い方: tools\godot\Godot_v4.6-stable_win64.exe --headless --path . -s res://scripts/gen_ball.gd
# 出力:
#   assets/ball/volleyball*.svg      : 128px viewBoxの原版(大型表示用、繊細な線)
#   assets/ball/volleyball*_game.png : ゲーム内実寸へ焼き込んだドット絵版。
#     外周=硬い黒フチ、内側シーム=きっちり1px(高解像度連続マスク→Zhang-Suen細線化)、陰影は維持。
#     シーム色はパレット依存。白ボールは薄いグレー(採用③)。②に戻すならWHITE_SEAM_ALTへ。
# ball_radius_pxや配色を変えたら再実行してコミットすること。
extends SceneTree

const BALL_DIR := "res://assets/ball/"

# シーム3本(中心Y字の腕+セクター内平行線2本)を120度回転で3セクター=計9本
const ARM := "M64 64 C 86 56, 84 24, 64 7"
const D1 := "M100.6 20.3 C 112 45, 104 75, 84.1 92.9"
const D2 := "M120.1 54.1 C 119 72, 110 87, 98.3 95.1"
const PA := "M64 64 C 86 56, 84 24, 64 7 A 57 57 0 0 1 100.6 20.3 C 112 45, 104 75, 84.14 92.92 C 70.92 88.5, 61.56 77.83, 64 64 Z"
const PB := "M100.6 20.3 A 57 57 0 0 1 120.1 54.1 C 119 72, 110 87, 98.35 95.15 C 93.38 95.18, 88.55 94.4, 84.14 92.92 C 104 75, 112 45, 100.6 20.3 Z"
const PC := "M120.1 54.1 A 57 57 0 0 1 113.36 92.52 C 108.42 94.28, 103.31 95.12, 98.35 95.15 C 110 87, 119 72, 120.1 54.1 Z"
const SHADOW_WIDE := "M115.66 88.09 A 57 57 0 0 1 12.34 88.09 A 120 120 0 0 0 115.66 88.09 Z"
const SHADOW_DEEP := "M115.66 88.09 A 57 57 0 0 1 12.34 88.09 A 75 75 0 0 0 115.66 88.09 Z"

const SEAM_HIRES := 8        # 連続マスク生成の高解像度倍率
const SEAM_STROKE_HI := 2.1  # 高解像度側のシーム線幅(細線化前)
const ROLL_FRAMES := 16      # 転がり回転の焼き込みフレーム数(0〜360度を等分)

# 白ボールのシーム色: ③=薄い(採用)、②=やや濃い(キープ。切替はPALETTESの該当行)
const WHITE_SEAM := "#c6c1ba"      # ③採用
const WHITE_SEAM_ALT := "#b2aca4"  # ②キープ(戻す場合こちらに)

# [パネルA(白系), パネルB, パネルC, シーム色, 輪郭色]
const PALETTES := {
	"": ["#fcfcfa", "#fcfcfa", "#fcfcfa", WHITE_SEAM, "#2f2a26"],
	"_blue": ["#f7f5ef", "#3565a8", "#f2c14e", "#2f2a26", "#2f2a26"],
	"_green": ["#f7f5ef", "#55b06a", "#e0605c", "#2f2a26", "#2f2a26"],
	"_teal": ["#f0e7d6", "#3f8f85", "#e8a95a", "#2f2a26", "#2f2a26"],
}

# 大型表示用SVG(繊細な線・AAあり)。ゲームでは使わない
func build_svg(cols: Array, seam_w: float) -> String:
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

func build_seam_svg(rot_deg: float) -> String:
	# rot_deg=転がり回転(シームだけ回す。光沢・影・輪郭は固定=本体側で描く)
	var svg := '<svg viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">'
	svg += '<g transform="rotate(%s 64 64)">' % rot_deg
	svg += '<g fill="none" stroke="#000000" stroke-width="%s" stroke-linecap="round">' % SEAM_STROKE_HI
	for deg in [0, 120, 240]:
		var t: String = "" if deg == 0 else ' transform="rotate(%d 64 64)"' % deg
		svg += '<g%s><path d="%s"/><path d="%s"/><path d="%s"/></g>' % [t, ARM, D1, D2]
	svg += '</g></g></svg>'
	return svg

# 高解像度描画→8x8マックスプールで連続した太めシームマスクを得る
func seam_mask_thick(n: int, rot_deg: float) -> Array:
	var hs := Image.new()
	hs.load_svg_from_string(build_seam_svg(rot_deg), float(n * SEAM_HIRES) / 128.0)
	var m := []
	for y in n:
		m.append([])
		for x in n:
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
			m[y].append(on)
	return m

func _nb(m: Array, x: int, y: int, n: int) -> Array:
	# P2..P9 = N,NE,E,SE,S,SW,W,NW
	var d := [[0,-1],[1,-1],[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1]]
	var r := []
	for e in d:
		var nx: int = x + e[0]
		var ny: int = y + e[1]
		r.append(1 if (nx >= 0 and ny >= 0 and nx < n and ny < n and m[ny][nx]) else 0)
	return r

# Zhang-Suen細線化: 連続を保ったまま1px幅へ削る
func zhang_suen(m: Array, n: int) -> Array:
	var changed := true
	while changed:
		changed = false
		for stp in [0, 1]:
			var todel := []
			for y in n:
				for x in n:
					if not m[y][x]:
						continue
					var p := _nb(m, x, y, n)
					var b := 0
					for v in p:
						b += v
					if b < 2 or b > 6:
						continue
					var a := 0
					for i in 8:
						if p[i] == 0 and p[(i + 1) % 8] == 1:
							a += 1
					if a != 1:
						continue
					if stp == 0:
						if p[0] * p[2] * p[4] != 0:
							continue
						if p[2] * p[4] * p[6] != 0:
							continue
					else:
						if p[0] * p[2] * p[6] != 0:
							continue
						if p[0] * p[4] * p[6] != 0:
							continue
					todel.append(Vector2i(x, y))
			for pt in todel:
				m[pt.y][pt.x] = false
				changed = true
	return m

func build_game_png(cols: Array, n: int, rot_deg: float) -> Image:
	var outline := Color(cols[4])
	var seam := Color(cols[3])
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
	# シーム: 連続マスク→1px細線化→塗り(球内のみ)。rot_degでシームだけ回転
	var mask := zhang_suen(seam_mask_thick(n, rot_deg), n)
	for y in n:
		for x in n:
			if ball.get_pixel(x, y).a >= 0.5 and mask[y][x]:
				ball.set_pixel(x, y, seam)
	# 外周を硬い黒フチ
	var out := ball.duplicate()
	for y in n:
		for x in n:
			if ball.get_pixel(x, y).a < 0.5:
				continue
			var edge := false
			for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + e.x
				var ny: int = y + e.y
				if nx < 0 or ny < 0 or nx >= n or ny >= n or ball.get_pixel(nx, ny).a < 0.5:
					edge = true
					break
			if edge:
				out.set_pixel(x, y, outline)
	return out

func _init() -> void:
	var f := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var rules: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var game_px := int(rules["ball_radius_px"]) * 2
	for suffix in PALETTES:
		var cols: Array = PALETTES[suffix]
		var svg := build_svg(cols, 2.6)
		var sf := FileAccess.open(BALL_DIR + "volleyball" + str(suffix) + ".svg", FileAccess.WRITE)
		sf.store_string(svg)
		sf.close()
		var png := build_game_png(cols, game_px, 0.0)
		png.save_png(BALL_DIR + "volleyball" + str(suffix) + "_game.png")
		# 転がり回転シート: ROLL_FRAMES枚を横並びに焼き込む。実行時回転を避け、
		# 表示層は状態から選んだクリーンなドット絵フレームを差し替えるだけにする
		var sheet := Image.create(game_px * ROLL_FRAMES, game_px, false, Image.FORMAT_RGBA8)
		for fidx in ROLL_FRAMES:
			var ang := 360.0 * float(fidx) / float(ROLL_FRAMES)
			var frame := build_game_png(cols, game_px, ang)
			sheet.blit_rect(frame, Rect2i(0, 0, game_px, game_px), Vector2i(fidx * game_px, 0))
		sheet.save_png(BALL_DIR + "volleyball" + str(suffix) + "_roll.png")
	print("GEN BALL OK size=" + str(game_px) + " roll_frames=" + str(ROLL_FRAMES))
	quit()
