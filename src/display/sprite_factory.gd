# 原作スプライトは操作感確認用。製品には同梱しない(差し替え前提)。
# 個別フレームPNGからSpriteFramesをコード構築する。テクスチャ依存のため
# ヘッドレス自動テストの対象外(実描画はゲーム起動時のユーザー官能チェックで検証)。
extends RefCounted

const Chars := preload("res://src/sim/chars.gd")

const FOX := "res://assets/third_party/sunny_land/PNG/sprites/player"
const FROG := "res://assets/third_party/sunny_land/PNG/sprites/frog"
const MARIO := "res://assets/characters/mario"
const PANDA := "res://assets/characters/panda"
const ORIGINAL := "res://assets/reference/vb2211"

# マリオのセル寸法(全アクション共通の枠)
const M_CW := 22
const M_CH := 29

# 代役ルール: スプライトが無いアクションは連鎖の先頭から順に探して流用する
# (歩きか立ち1枚あればキャラが成立する=パンダ方式の公式化)。最後の砦はidle
const FALLBACK := {
	"run": ["idle"],
	"jump": ["run", "idle"],
	"attack": ["jump", "run", "idle"],
	"crouch": ["idle"],
	"toss": ["crouch", "idle"],
	"toss_fwd": ["toss", "crouch", "idle"],
	"brake": ["crouch", "idle"],
	"hurt": ["crouch", "idle"],
	"stun": ["hurt", "idle"],
	"victory": ["jump", "idle"],
	"hat-throw": ["toss_fwd", "idle"],
	"hat-catch": ["idle"],
	"hipdrop": ["crouch", "jump", "idle"],
	"wallcling": ["crouch", "idle"],
}

# char_id→SpriteFrames。キャラ追加時はここに1分岐足す(将来はキャラ定義から自動構築)
static func build_for(char_id: int) -> SpriteFrames:
	var sf: SpriteFrames
	match char_id:
		Chars.CHAR_PANDA:
			sf = build_panda()
		Chars.CHAR_MARIO:
			sf = build_mario()
		Chars.CHAR_FROG:
			sf = build_frog()
		Chars.CHAR_TOME:
			sf = build_original(ORIGINAL + "/tome_sheet.png")
		Chars.CHAR_HITO:
			sf = build_original(ORIGINAL + "/hito_sheet.png")
		Chars.CHAR_PIYO:
			sf = build_original(ORIGINAL + "/piyo_sheet.png")
		Chars.CHAR_UME:
			sf = build_original(ORIGINAL + "/ume_sheet.png")
		Chars.CHAR_CARBY:
			sf = build_original(ORIGINAL + "/carby_sheet.png")
		Chars.CHAR_DUO:
			sf = build_original(ORIGINAL + "/duo_sheet.png")
		Chars.CHAR_SEC1:
			sf = build_original(ORIGINAL + "/sec1_sheet.png")
		Chars.CHAR_SEC2:
			sf = build_original(ORIGINAL + "/sec2_sheet.png")
		_:
			sf = build_fox()
	ensure_fallbacks(sf)
	return sf

# 不足アクションを代役連鎖で埋める。埋めた場合は開発ログに警告を出す
static func ensure_fallbacks(sf: SpriteFrames) -> void:
	for anim: String in FALLBACK.keys():
		if sf.has_animation(anim):
			continue
		var chain: Array = FALLBACK[anim]
		var src := ""
		for cand: String in chain:
			if sf.has_animation(cand):
				src = cand
				break
		if src == "":
			push_warning("代役ルール: %s の代役が見つからない(idleすら無い)" % anim)
			continue
		sf.add_animation(anim)
		sf.set_animation_speed(anim, sf.get_animation_speed(src))
		sf.set_animation_loop(anim, sf.get_animation_loop(src))
		for f in sf.get_frame_count(src):
			sf.add_frame(anim, sf.get_frame_texture(src, f), sf.get_frame_duration(src, f))
		print("代役ルール: %s ← %s で代用" % [anim, src])

# 足元原点オフセット(セル寸法のキャラ差。表示層のみ)
static func foot_offset(char_id: int) -> Vector2:
	match char_id:
		Chars.CHAR_PANDA, Chars.CHAR_MARIO:
			return Vector2(-11, -29)  # セル22x29(足元中央原点)
		Chars.CHAR_TOME, Chars.CHAR_HITO, Chars.CHAR_PIYO, Chars.CHAR_UME, \
				Chars.CHAR_CARBY, Chars.CHAR_DUO, Chars.CHAR_SEC1, Chars.CHAR_SEC2:
			return Vector2(-16, -32)
		_:
			return Vector2(-16, -32)  # 32x32相当の仮素材

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
	_add(sf, "stun", FOX + "/hurt/player-hurt-%d.png", 2, 8.0, true)
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

static func _add_original_sheet(sf: SpriteFrames, anim: String, path: String,
		indices: Array, durs: Array, loop: bool) -> void:
	var tex: Texture2D = load(path)
	sf.add_animation(anim)
	sf.set_animation_speed(anim, 60.0)
	sf.set_animation_loop(anim, loop)
	for k in indices.size():
		var index: int = indices[k]
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((index % 12) * 32, (index / 12) * 32, 32, 32)
		sf.add_frame(anim, at, float(durs[k]))

static func build_original(sheet_path: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add_original_sheet(sf, "idle", sheet_path, [0, 1], [30, 30], true)
	_add_original_sheet(sf, "run", sheet_path, [2, 0], [6, 6], true)
	_add_original_sheet(sf, "jump", sheet_path, [8], [1], false)
	_add_original_sheet(sf, "attack", sheet_path, [9], [1], false)
	_add_original_sheet(sf, "toss", sheet_path, [3], [1], false)
	_add_original_sheet(sf, "toss_fwd", sheet_path, [3], [1], false)
	_add_original_sheet(sf, "crouch", sheet_path, [10], [1], false)
	_add_original_sheet(sf, "hurt", sheet_path, [11], [1], false)
	_add_original_sheet(sf, "brake", sheet_path, [10], [1], false)
	_add_original_sheet(sf, "stun", sheet_path, [14, 15], [8, 8], true)
	_add_original_sheet(sf, "victory", sheet_path, [21, 22], [8, 8], true)
	return sf

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
	# スタン(気絶): deadの3・4番を分かりやすい速度で交互(目回し)
	_add_sheet(sf, "stun", MARIO + "/dead/dead.png", [2, 3], [8, 8], true)
	# しりもち(ジャストアタック被弾): hurtシートで尻もちをつくリアクション
	_add_sheet(sf, "hurt", MARIO + "/hurt/hurt.png", [0, 1, 2, 3, 4], [3, 3, 4, 4, 6], false)
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

# パンダ(自作キャラ第1号)。セル寸法はマリオと同じ22x29。
# 現状walk 2コマしか無いので、全アクションをwalkの2ポーズで代用する
# (専用モーションが出来たら順次差し替える)。
static func build_panda() -> SpriteFrames:
	var W := PANDA + "/walk/walk.png"
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add_sheet(sf, "idle", W, [1], [1], true)
	_add_sheet(sf, "run", W, [0, 1], [5, 5], true)
	_add_sheet(sf, "jump", W, [0], [1], false)
	_add_sheet(sf, "attack", W, [0, 1], [4, 4], false)
	_add_sheet(sf, "toss", W, [1], [1], false)
	_add_sheet(sf, "toss_fwd", W, [1], [1], false)
	_add_sheet(sf, "crouch", W, [1], [1], false)
	_add_sheet(sf, "stun", W, [0, 1], [8, 8], true)
	_add_sheet(sf, "hurt", W, [0, 1], [4, 4], false)
	_add_sheet(sf, "brake", W, [1], [1], false)
	_add_sheet(sf, "hat-throw", W, [0, 1], [5, 5], false)
	_add_sheet(sf, "hat-catch", W, [1], [1], false)
	_add_sheet(sf, "hipdrop", W, [0], [1], false)
	_add_sheet(sf, "wallcling", W, [1], [1], true)
	_add_sheet(sf, "victory", W, [0, 1], [6, 6], false)
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
	_add_sheet(sf, "stun", H + "/dead.png", [2, 3], [8, 8], true)
	_add_sheet(sf, "hurt", H + "/hurt.png", [0, 1, 2, 3, 4], [3, 3, 4, 4, 6], false)
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
	_add(sf, "stun", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "attack", FROG + "/jump/frog-jump-%d.png", 2, 6.0, false)
	_add(sf, "toss", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "toss_fwd", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "brake", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	_add(sf, "hipdrop", FROG + "/idle/frog-idle-%d.png", 4, 8.0, false)
	_add(sf, "wallcling", FROG + "/idle/frog-idle-%d.png", 4, 8.0, true)
	return sf
