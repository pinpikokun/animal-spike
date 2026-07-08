# 個別フレームPNGからSpriteFramesをコード構築する。テクスチャ依存のため
# ヘッドレス自動テストの対象外(実描画はゲーム起動時のユーザー官能チェックで検証)。
extends RefCounted

const FOX := "res://assets/third_party/sunny_land/PNG/sprites/player"
const FROG := "res://assets/third_party/sunny_land/PNG/sprites/frog"

static func _add(sf: SpriteFrames, anim: String, tmpl: String, count: int, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for i in range(1, count + 1):
		var tex: Texture2D = load(tmpl % i)
		sf.add_frame(anim, tex)

static func build_fox() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add(sf, "idle", FOX + "/idle/player-idle-%d.png", 4, 8.0, true)
	_add(sf, "run", FOX + "/run/player-run-%d.png", 6, 12.0, true)
	_add(sf, "jump", FOX + "/jump/player-jump-%d.png", 2, 6.0, false)
	_add(sf, "crouch", FOX + "/crouch/player-crouch-%d.png", 2, 8.0, false)
	_add(sf, "hurt", FOX + "/hurt/player-hurt-%d.png", 2, 8.0, false)
	return sf

static func build_frog() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add(sf, "idle", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "jump", FROG + "/jump/frog-jump-%d.png", 2, 6.0, false)
	# カエルにrun/crouch/hurt素材は無いのでidleを流用(仮素材段階)
	_add(sf, "run", FROG + "/idle/frog-idle-%d.png", 4, 10.0, true)
	_add(sf, "crouch", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "hurt", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	return sf
