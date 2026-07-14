extends Node2D
# マリオ参考モーションのショーケース(表示確認専用。simには一切関与しない)。
# 各アクションのスプライトシートを均等セルで切り出し、AnimatedSprite2Dでループ再生する。

# [フォルダ/ファイル名, セル幅, セル高, 表示fps]
const SHEETS := [
	["walk", 22, 29, 8.0],
	["brake", 22, 29, 6.0],
	["jump", 22, 29, 8.0],
	["spin", 22, 29, 14.0],
	["hurt", 22, 29, 10.0],
	["dead", 22, 29, 8.0],
	["hat-throw", 22, 29, 12.0],
	["hat-catch", 22, 29, 12.0],
	["wall-cling", 22, 29, 6.0],
	["crouch", 22, 29, 6.0],
	["hip-attack", 22, 29, 12.0],
	["star", 22, 29, 14.0],
	["cap", 16, 11, 16.0],
]

const SCALE := 4
const COLS := 5
const CELL_PX := 118  # 1枠の画面上サイズ

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.16, 0.17, 0.22))
	var i := 0
	for entry in SHEETS:
		var name: String = entry[0]
		var cw: int = entry[1]
		var ch: int = entry[2]
		var fps: float = entry[3]
		var path := "res://assets/characters/mario/%s/%s.png" % [name, name]
		var tex := load(path) as Texture2D
		var col := i % COLS
		var row := i / COLS
		var ox := 40 + col * CELL_PX
		var oy := 60 + row * (CELL_PX + 24)
		if tex == null:
			_add_label(name + " (無)", ox, oy - 20, Color(1, 0.4, 0.4))
			i += 1
			continue
		var frames := int(tex.get_width() / cw)
		var sf := SpriteFrames.new()
		sf.set_animation_speed("default", fps)
		sf.set_animation_loop("default", true)
		sf.clear("default")
		for f in frames:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(f * cw, 0, cw, ch)
			sf.add_frame("default", at)
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = sf
		spr.centered = false
		spr.scale = Vector2(SCALE, SCALE)
		# セル下端(足)を基準に接地させて配置
		spr.position = Vector2(ox + (CELL_PX - cw * SCALE) / 2.0, oy)
		add_child(spr)
		spr.play("default")
		_add_label("%s (%d)" % [name, frames], ox, oy - 20, Color(1, 0.92, 0.35))
		i += 1

func _add_label(text: String, x: int, y: int, col: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = Vector2(x, y)
	lb.add_theme_color_override("font_color", col)
	add_child(lb)
