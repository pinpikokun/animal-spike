# ボール素材ジェネレーター(表示層ツール。float可)
# 使い方: tools\godot\Godot_v4.6-stable_win64.exe --headless --path . -s res://scripts/gen_ball.gd
# 出力:
#   assets/ball/volleyball*.svg      : 128px viewBoxの原版(プレビュー/将来の大型表示用)
#   assets/ball/volleyball*_game.png : ゲーム内実寸(rules.jsonのball_radius_px*2)へ
#                                      直接ラスタした焼き込み版。縮小ぼやけゼロ
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

# [パネルA(白系), パネルB, パネルC, シーム色, 輪郭色]
const PALETTES := {
	"": ["#fcfcfa", "#fcfcfa", "#fcfcfa", "#9a938c", "#2f2a26"],
	"_blue": ["#f7f5ef", "#3565a8", "#f2c14e", "#3a342e", "#2f2a26"],
	"_green": ["#f7f5ef", "#55b06a", "#e0605c", "#3a342e", "#2f2a26"],
	"_teal": ["#f0e7d6", "#3f8f85", "#e8a95a", "#3a342e", "#2f2a26"],
}

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
	# 輪郭を太らせる分は内側へ寄せて外径(直径=viewBoxの114/128)を一定に保つ
	var rr := 57.0 - (outline_w - 3.2) * 0.5
	var r_str := str(int(rr)) if absf(rr - roundf(rr)) < 0.001 else String.num(rr, 2)
	svg += '<circle cx="64" cy="64" r="%s" fill="none" stroke="%s" stroke-width="%s"/>\n' % [r_str, cols[4], outline_w]
	svg += '</svg>\n'
	return svg

func _init() -> void:
	# ゲーム内実寸はルールから(表示直径px = ball_radius_px * 2)
	var f := FileAccess.open("res://data/rules.json", FileAccess.READ)
	var rules: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var game_px := int(rules["ball_radius_px"]) * 2
	for suffix in PALETTES:
		var cols: Array = PALETTES[suffix]
		# 原版SVG(128px viewBox、繊細な線)
		var svg := build_svg(cols, 2.6, 3.2)
		var sf := FileAccess.open(BALL_DIR + "volleyball" + str(suffix) + ".svg", FileAccess.WRITE)
		sf.store_string(svg)
		sf.close()
		# ゲームサイズ焼き込みPNG。直接ラスタで縮小ぼやけゼロ。
		# 小サイズで輪郭が消えないよう輪郭のみ約1px相当(4.6)へ補強
		var img := Image.new()
		img.load_svg_from_string(build_svg(cols, 2.6, 4.6), float(game_px) / 128.0)
		img.save_png(BALL_DIR + "volleyball" + str(suffix) + "_game.png")
	print("GEN BALL OK size=" + str(game_px))
	quit()
