# 個別フレームPNGからSpriteFramesをコード構築する。テクスチャ依存のため
# ヘッドレス自動テストの対象外(実描画はゲーム起動時のユーザー官能チェックで検証)。
extends RefCounted

const FOX := "res://assets/third_party/sunny_land/PNG/sprites/player"
const FROG := "res://assets/third_party/sunny_land/PNG/sprites/frog"
const MARIO := "res://assets/characters/mario"

# マリオのセル寸法(全アクション共通の枠)
const M_CW := 22
const M_CH := 29

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
	# 仮素材のキツネに専用アタック/トス絵は無いので既存を流用(名前を存在させる)
	_add(sf, "attack", FOX + "/jump/player-jump-%d.png", 2, 6.0, false)
	_add(sf, "toss", FOX + "/crouch/player-crouch-%d.png", 2, 8.0, false)
	_add(sf, "toss_fwd", FOX + "/crouch/player-crouch-%d.png", 2, 8.0, false)
	_add(sf, "brake", FOX + "/crouch/player-crouch-%d.png", 1, 8.0, false)
	_add(sf, "hipdrop", FOX + "/crouch/player-crouch-%d.png", 1, 8.0, false)
	_add(sf, "wallcling", FOX + "/crouch/player-crouch-%d.png", 1, 8.0, true)
	return sf

# シート(横並び等幅セル)から指定インデックスのコマを切り出してアニメ登録する。
# durs=各コマの保持フレーム数。速度を60に合わせるので duration=保持フレーム数 に一致する
# (原作の「このコマは何フレーム表示か」をそのまま再現。等間隔パチパチにしない)。
static func _add_sheet(sf: SpriteFrames, anim: String, path: String,
		indices: Array, durs: Array, loop: bool) -> void:
	var tex: Texture2D = load(path)
	sf.add_animation(anim)
	sf.set_animation_speed(anim, 60.0)
	sf.set_animation_loop(anim, loop)
	for k in indices.size():
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(indices[k] * M_CW, 0, M_CW, M_CH)
		sf.add_frame(anim, at, float(durs[k]))

# マリオ(参考素材)を、既存のバレー用アニメ名(idle/run/jump/crouch/hurt)に割り当てる。
# 素材はプラットフォーマーの動きなので「近いポーズ」を見繕う:
#   idle  = deadシートの直立コマ(静止の構え)
#   run   = walk 2ポーズを各5フレーム保持(実測タイミング)
#   jump  = ジャンプ3コマ(頂点を長め)。手上げ=空中の打撃(スパイク)にも流用
#   crouch= しゃがみ(接地ヒット硬直=レシーブ/ディグの姿勢)
#   hurt  = deadシートの目回しコマをループ(スタン)
static func build_mario() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	# 通常/サーブ前の構え=walk 2枚目(据わりのいい立ちポーズ)
	_add_sheet(sf, "idle", MARIO + "/walk/walk.png", [1], [1], true)
	_add_sheet(sf, "run", MARIO + "/walk/walk.png", [0, 1], [5, 5], true)
	# ジャンプ=上昇→頂点(長め)→下降の3コマ(着地まで。手上げポーズ)
	_add_sheet(sf, "jump", MARIO + "/jump/jump.png", [0, 1, 2], [3, 7, 4], false)
	# アタック(空中で打つ)=starの5〜12コマ(index4-11)。4-7=振り下ろし, 8-11=打った後
	_add_sheet(sf, "attack", MARIO + "/star/star.png",
		[4, 5, 6, 7, 8, 9, 10, 11], [3, 3, 3, 3, 3, 3, 3, 4], false)
	# 普通トス(上へ上げる)=hurtシート。前トス=ヒップアタックの2コマ目(前へ振る姿)
	_add_sheet(sf, "toss", MARIO + "/hurt/hurt.png", [0, 1, 2], [3, 4, 4], false)
	_add_sheet(sf, "toss_fwd", MARIO + "/hip-attack/hip-attack.png", [1], [1], false)
	_add_sheet(sf, "crouch", MARIO + "/crouch/crouch.png", [0], [1], false)
	_add_sheet(sf, "hurt", MARIO + "/dead/dead.png", [2, 3], [6, 6], true)
	# 急ブレーキ(踏ん張り1コマを滑ってる間ずっと表示)
	_add_sheet(sf, "brake", MARIO + "/brake/brake.png", [0], [1], false)
	# 帽子投げ(振りかぶって前へ投げるモーション)。溜め時間(30tick)に合わせてゆったり再生
	_add_sheet(sf, "hat-throw", MARIO + "/hat-throw/hat-throw.png",
		[0, 1, 2, 3, 4, 5], [5, 5, 5, 5, 5, 5], false)
	# 帽子キャッチ(戻ってきた帽子を被り直す)
	_add_sheet(sf, "hat-catch", MARIO + "/hat-catch/hat-catch.png",
		[0, 1, 2, 3], [3, 3, 3, 3], false)
	# ヒップアタック(1〜9番=空中静止で回転, 10番=急降下)。フレームは表示層がhipから選ぶ
	_add_sheet(sf, "hipdrop", MARIO + "/hip-attack/hip-attack.png",
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], false)
	# 壁張り付き(1コマをずるずる降下中ずっと表示)
	_add_sheet(sf, "wallcling", MARIO + "/wall-cling/wall-cling.png", [0], [1], true)
	# 勝利: starの1〜15番=地上クルクル回転, 16番=軽くジャンプ, 17番=高くジャンプして終了
	_add_sheet(sf, "victory", MARIO + "/star/star.png",
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
		[4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 10, 18], false)
	return sf

# 帽子を投げてる間のマリオ(茶髪)。帽子中の状態表示に使う。hatlessフォルダに無い
# アクション(toss_fwd/crouch)は近いもので代用(投げ中の一瞬なので割り切り)
static func build_mario_hatless() -> SpriteFrames:
	var H := MARIO + "/hatless"
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add_sheet(sf, "idle", H + "/walk.png", [1], [1], true)
	_add_sheet(sf, "run", H + "/walk.png", [0, 1], [5, 5], true)
	_add_sheet(sf, "jump", H + "/jump.png", [0, 1, 2], [3, 7, 4], false)
	_add_sheet(sf, "attack", H + "/star.png",
		[4, 5, 6, 7, 8, 9, 10, 11], [3, 3, 3, 3, 3, 3, 3, 4], false)
	_add_sheet(sf, "toss", H + "/hurt.png", [0, 1, 2], [3, 4, 4], false)
	_add_sheet(sf, "toss_fwd", H + "/hurt.png", [0, 1, 2], [3, 4, 4], false)
	_add_sheet(sf, "crouch", H + "/walk.png", [1], [1], false)
	_add_sheet(sf, "hurt", H + "/dead.png", [2, 3], [6, 6], true)
	_add_sheet(sf, "brake", H + "/brake.png", [0], [1], false)
	# 帽子なしでも壁張り付きは起こりうる。ヒップアタックは帽子ありのみなので不要
	_add_sheet(sf, "wallcling", H + "/wall-cling.png", [0], [1], true)
	_add_sheet(sf, "hipdrop", H + "/spin.png", [0], [1], false)  # 保険(通常出ない)
	_add_sheet(sf, "victory", H + "/star.png",
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
		[4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 10, 18], false)
	return sf

# 飛んでる帽子(お邪魔ギミック)。cap.pngの8コマを回転再生
static func build_cap() -> SpriteFrames:
	var sf := SpriteFrames.new()
	# "default"は既定で存在する。ここに直接コマを足す(removeすると足せず透明になる)
	var tex: Texture2D = load(MARIO + "/cap/cap.png")
	var cw := 16
	var ch := 11
	var n := int(tex.get_width() / cw)
	sf.set_animation_speed("default", 16.0)
	sf.set_animation_loop("default", true)
	for f in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(f * cw, 0, cw, ch)
		sf.add_frame("default", at)
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
	_add(sf, "attack", FROG + "/jump/frog-jump-%d.png", 2, 6.0, false)
	_add(sf, "toss", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "toss_fwd", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "brake", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "hipdrop", FROG + "/idle/frog-idle-%d.png", 4, 8.0, false)
	_add(sf, "wallcling", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	return sf
