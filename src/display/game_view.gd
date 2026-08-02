# 本番ゲームビュー。sim状態を読んでスプライトを駆動する。表示層(float可)。
extends Node2D

const SimConfig := preload("res://src/sim/sim_config.gd")
const SimState := preload("res://src/sim/sim_state.gd")
const Simulation := preload("res://src/sim/simulation.gd")
const SimCpu := preload("res://src/sim/sim_cpu.gd")
const ViewTransform := preload("res://src/display/view_transform.gd")
const SpriteFactory := preload("res://src/display/sprite_factory.gd")
const AnimSelect := preload("res://src/display/anim_select.gd")
const InputPoll := preload("res://src/display/input_poll.gd")
const Chars := preload("res://src/sim/chars.gd")

const SPRITE_HALF_H := 16.0  # キャラ素材32px高の半分(足元をノード原点に合わせる)
const RECEIVE_HOP_PX := 4.0  # レシーブ時の小ホップ量(接地ヒットの手続き演出)
# ボールのへしゃげ(原作: アタック時は弾が潰れて速い)。強度指標は
# |横速度| + 下向き速度x0.6: 上昇中のトスは横が無いかぎり潰れず、
# 通常アタックは軽く、パワーボールは最大まで潰れる=威力の緩急
const SQUASH_V0 := 8.0
const SQUASH_V1 := 15.0
const SQUASH_MAX := 0.45
const SQUASH_VY_W := 0.6  # 下向き速度の寄与率

var cfg
var state
var _sprites: Array = []  # AnimatedSprite2D x4
var _ball: Sprite2D
var _flame_ball: Sprite2D
var _fx: Node2D  # エフェクト最前面レイヤー(FxLayer、通常合成)
var _fxg: Node2D  # 発光エフェクトレイヤー(FxGlowLayer、加算合成)
var _ball_frame_w := 0     # 転がりシート1フレームの辺(px)
var _ball_base_scale := 1.0  # 真円時のボール表示スケール(へしゃげの基準)
var _ball_roll_frames := 1  # 転がりシートのフレーム数
# ネット対戦モード。cfg/stateは外部(SimRoot)が所有しtickも外部が回す。
# ここは状態を読んでスプライトを駆動する表示専任になる
var external_sim := false
var _base_pos := Vector2.ZERO  # 画面揺れの基準位置(揺れはここからのオフセット)
# ワンショットエフェクト(表示層のみのジュース)。sim状態の遷移(踏切/着地/走り出し/
# 切り返し/ヒット/ジャスト)を検知して発火し、寿命が尽きたら消える。
# ロールバック再シミュで稀に重複発火しても一瞬濃く見えるだけで無害
var _fx_events: Array = []
var _prev_ground: Array[int] = [1, 1, 1, 1]
var _prev_vx: Array[int] = [0, 0, 0, 0]
var _prev_cd: Array[int] = [0, 0, 0, 0]
var _prev_flinch: Array[int] = [0, 0, 0, 0]  # しりもち検知用(0→>0で砂煙)
var _prev_stun: Array[int] = [0, 0, 0, 0]
var _prev_just_receive_event: Array[int] = [0, 0, 0, 0]
var _prev_hip_quake_event: int = 0
var _prev_power := 0
var _prev_bvy := 0
var _prev_score := Vector2i.ZERO
var _last_dust_frame: Array[int] = [-99, -99, -99, -99]
var _flash: Array[int] = [0, 0, 0, 0]  # 被弾白フラッシュの残りフレーム
# キャラの向き(表示層のみ)。移動中はvx符号で更新し、静止中は最後の向きを保持。
# 既定はチーム0(左)=右向き(+1)、チーム1(右)=左向き(-1)。アタック時だけネット向きに上書き
var _facing: Array[int] = [1, 1, -1, -1]
# ジャンプの絵をvyで固定選択するための着地検知(表示層のみ)。
# _was_air=前フレーム空中だったか、_land=着地ポーズ(jump3枚目)の残り表示フレーム
var _was_air: Array[bool] = [false, false, false, false]
var _land: Array[int] = [0, 0, 0, 0]
# 帽子投げ表示: 帽子中はhatlessスプライトに差し替え、戻った瞬間キャッチ演出。
var _mario_hat: SpriteFrames       # 帽子ありマリオ
var _mario_hatless: SpriteFrames   # 帽子投げ中(茶髪)
var _prev_hat: Array[int] = [1, 1, 1, 1]
var _catch: Array[int] = [0, 0, 0, 0]  # キャッチ演出(hat-catch)の残りフレーム
var _victory_on: bool = false  # 勝利演出の発動フラグ(ゲームセット後ボールが止まってから)
var _cap: AnimatedSprite2D          # 飛んでる帽子
# スカッシュ&ストレッチ(表示層のみのジュース)。踏切で縦伸び/着地で横潰れを
# バネで0へ戻す。当たり判定サイズには一切触れない。ロールバック無関係の飾り
var _squash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _squash_v: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _shake_amp := 0.0  # 画面揺れの減衰インパルス(衝撃でドンと入り数フレームで収束)
var _ball_hist: Array[Vector2] = []    # 残像トレイル用のボール位置履歴
var _sfx: Dictionary = {}              # 仮SE(自前合成WAV)。無ければ黙って鳴らさない
const FxParticles := preload("res://src/display/fx_particles.gd")
# kiranのみ旧発光方式(タイミングUI)。粒エフェクトはFxParticles.KINDSが寿命を持つ
const FX_LIFE := {"kiran": 0.30}
var _prev_bvx := 0  # 壁反射検知用(ボールvxの符号反転)
var _prev_bground := false  # ボール着地検知用
const KIRAN_MIN_H_FP := 120 << 16  # 頂点キランを出す最低高度(床から120px、fp)
# ローカルプレイヤーのチーム(0=左,1=右)。▽マーカーとサーブ軌跡は自チームのみ
# 表示する(相手のサーブ予測軌跡が見えると駆け引きが死ぬ)。ネット対戦では
# net_match.gdがホスト=0/クライアント=1を設定する
var local_team := 0
# キャラ選択画面が渡すロスター(slot0..3のchar_id)。空なら既定Chars.ROSTER。
# add_child前に設定すること(_readyのreset_matchで使う)
var roster: Array = []
# ローカル本編の開始時乱数2ワード。rootがadd_child前に設定する。
var rng_word: Variant = null
var aitick_word: Variant = null
func attach_external(cfg_in, state_ref) -> void:
	# instantiate直後・add_child前に呼ぶこと(_readyがcfg/stateを自前生成しないため)
	external_sim = true
	cfg = cfg_in
	state = state_ref

func _ready() -> void:
	if not external_sim:
		if rng_word == null or aitick_word == null:
			push_error("開始時乱数2ワード未設定のためローカルGameViewを初期化できない")
			get_tree().quit(1)
			return
		cfg = SimConfig.new()
		if not cfg.valid:
			push_error("rules.jsonの読み込みに失敗したため起動を中止する")
			return
		state = SimState.new()
		var r: Array = roster if not roster.is_empty() else Chars.ROSTER
		Simulation.reset_match(state, cfg, 0, r, int(rng_word), int(aitick_word))
		state.human_team_mask = 1
	# 表示のみの一括シフト(ScoreUIはCanvasLayerで不動):
	# コートが画面より狭いぶん中央寄せ。縦は上へ寄せて下端の顔HUD帯(y=332..356)と
	# コート床(floor_y=320)・キャラの足元が重ならないようにする
	_base_pos = Vector2((640.0 - ViewTransform.to_px(cfg.court_width)) * 0.5, -12.0)
	position = _base_pos
	Engine.physics_ticks_per_second = cfg.tick_rate
	$Court.setup(cfg)
	$ScoreUI.setup(cfg)
	_setup_sfx()
	_mario_hat = SpriteFactory.build_for(Chars.CHAR_MARIO)
	_mario_hatless = SpriteFactory.build_mario_hatless()
	SpriteFactory.ensure_fallbacks(_mario_hatless)
	for i in 4:
		var s := AnimatedSprite2D.new()
		# キャラの見た目はsim状態のchar_idから引く(slot=キャラのハードコード禁止)
		var cid: int = state.players[i].char_id
		s.sprite_frames = _mario_hat if cid == Chars.CHAR_MARIO \
			else SpriteFactory.build_for(cid)
		# 非センター+整数オフセットで足元原点・整数ピクセル描画にする
		s.centered = false
		s.offset = SpriteFactory.foot_offset(cid)
		# 手前レーン(偶数slot)を前面に描く(奥のキャラと重なった時に自然な前後関係)
		s.z_index = 1 if i % 2 == 0 else 0
		s.play("idle")
		$Players.add_child(s)
		_sprites.append(s)
	# 飛んでる帽子(お邪魔ギミック)。cap_phase!=0のとき表示・回転
	_cap = AnimatedSprite2D.new()
	_cap.sprite_frames = SpriteFactory.build_cap()
	_cap.centered = true
	_cap.z_index = 2
	_cap.visible = false
	_cap.play("default")
	$Players.add_child(_cap)
	_ball = $Ball
	_ball.centered = true
	# ボール素材はscripts/gen_ball.gdがゲーム実寸へ直接ラスタした焼き込みPNG。
	# 転がり回転は焼き込みフレームを差し替える方式(実行時回転はドット絵が
	# ガビガビになるため使わない)。シートは横並びROLL_FRAMES枚、フレームは正方。
	# rules.jsonのball_radius_pxを変えたらジェネレーター再実行が必要
	var roll: Texture2D = load("res://assets/ball/volleyball_roll.png")
	_ball.texture = roll
	_ball.region_enabled = true
	_ball_frame_w = roll.get_height()  # フレームは正方なので高さ=1フレーム辺
	_ball_roll_frames = int(roll.get_width() / _ball_frame_w)
	_ball.region_rect = Rect2(0, 0, _ball_frame_w, _ball_frame_w)
	var ball_px := ViewTransform.to_px(cfg.ball_radius) * 2.0
	if _ball_frame_w != int(ball_px):
		push_warning("ボール素材(%dpx)と表示直径(%dpx)が不一致。scripts/gen_ball.gdを再実行推奨" % [_ball_frame_w, int(ball_px)])
	_ball_base_scale = ball_px / float(_ball_frame_w)
	_ball.scale = Vector2.ONE * _ball_base_scale
	# 原作BALL.DAT由来の炎球。特殊球IDとtickだけで表示コマを決める。
	_flame_ball = Sprite2D.new()
	_flame_ball.texture = load("res://assets/reference/vb2211/ball_sheet.png")
	_flame_ball.centered = true
	_flame_ball.region_enabled = true
	_flame_ball.region_rect = Rect2(32, 32, 32, 32)  # index13
	_flame_ball.visible = false
	_flame_ball.z_index = _ball.z_index
	_ball.get_parent().add_child(_flame_ball)
	# エフェクトレイヤーは最後に追加し、z_indexでも最前面を保証する。
	# 通常レイヤー(_fx)=影/マーカー等の暗色・単色UI。
	# 加算合成レイヤー(_fxg)=発光エフェクト(重なると白飛びして光る=ROUNDS風)
	_fx = FxLayer.new()
	_fx.view = self
	_fx.z_index = 10
	add_child(_fx)
	_fxg = FxGlowLayer.new()
	_fxg.view = self
	_fxg.z_index = 11
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fxg.material = glow_mat
	add_child(_fxg)

func _physics_process(_delta: float) -> void:
	if external_sim:
		# ネット対戦: tickはSimRootがSyncManager経由で回す。ここは表示だけ
		_sync_sprites()
		$ScoreUI.update_from(state)
		return
	var input := InputPoll.poll()
	# 右チームは完全CPU(1人プレイ)。操作キャラ枠の入力もsim層のCPUが決定論的に生成する
	var cpu_r: int = SimCpu.decide(state, 2 + state.controlled_r, cfg)
	Simulation.tick(state, [input, cpu_r], cfg)
	_sync_sprites()
	$ScoreUI.update_from(state)

# 2軸の見た目(原作準拠): 後衛slotは手前(下)、前衛slotは奥(上)。
# court.gdの中央対称収束に沿った表示専用の上下オフセット。simには影響しない
static func _depth_offset(i: int) -> Vector2:
	if i % 2 == 0:
		return Vector2(0.0, 5.0)
	return Vector2(0.0, -5.0)

func _setup_sfx() -> void:
	# 仮SE(tools/gen_sfx.gdが合成したWAV)。ファイルが無ければ無音のまま動く
	for sfx_name in ["hit", "just", "just_receive", "block", "score"]:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(path):
			var pl := AudioStreamPlayer.new()
			pl.stream = load(path)
			pl.volume_db = -8.0
			add_child(pl)
			_sfx[sfx_name] = pl

func _play_sfx(sfx_name: String) -> void:
	if _sfx.has(sfx_name):
		_sfx[sfx_name].play()

func _spawn_fx(kind: String, pos: Vector2, dir: float = 0.0,
		inertia: Vector2 = Vector2.ZERO) -> void:
	if _fx_events.size() >= 32:
		_fx_events.pop_front()
	_fx_events.append({"k": kind, "p": pos, "f0": Engine.get_frames_drawn(),
		"d": dir, "iner": inertia})

func _prune_fx(f: int) -> void:
	# 期限切れイベントを破棄。粒はFxParticles.KINDSの寿命、kiranはFX_LIFE
	for e_i in range(_fx_events.size() - 1, -1, -1):
		var e: Dictionary = _fx_events[e_i]
		var k: String = e["k"]
		var expired := false
		if k == "kiran":
			expired = float(f - e["f0"]) / (60.0 * FX_LIFE["kiran"]) >= 1.0
		else:
			expired = FxParticles.expired(k, e["f0"], f)
		if expired:
			_fx_events.remove_at(e_i)

func _detect_fx() -> void:
	# sim状態の1フレーム差分からエフェクト発火点を検知する。
	# 入力は見ない(観測できるのは物理状態だけ=ネット対戦でも同じ絵になる)
	var f := Engine.get_frames_drawn()
	var bpos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	var bvel := Vector2(ViewTransform.to_px(state.ball_vx), ViewTransform.to_px(state.ball_vy))
	var up := -PI / 2.0
	var just_fired: bool = _prev_power == 0 and state.ball_power == 1
	if state.hip_quake_event > _prev_hip_quake_event:
		_shake_amp = maxf(_shake_amp, 7.0)
		_prev_hip_quake_event = state.hip_quake_event
	# 期限切れイベントを掃除(粒=KINDS寿命 / kiran=FX_LIFE)
	_prune_fx(f)
	for i in state.players.size():
		var p = state.players[i]
		var foot := ViewTransform.pos_of(p) + _depth_offset(i)
		var pvel := Vector2(ViewTransform.to_px(p.vx), ViewTransform.to_px(p.vy))
		if _prev_ground[i] == 1 and p.on_ground == 0:
			_spawn_fx("jump", foot, up, pvel)          # 縦へ+横速度で流れる
			_squash[i] = 0.42                          # 踏切: 縦にビヨーンと伸びる
			_squash_v[i] = 0.0
		elif _prev_ground[i] == 0 and p.on_ground == 1:
			# 着地: キャラの左右へ地を這うように土煙。右(dir=0)と左(dir=PI)の2枚に分ける
			_spawn_fx("land", foot, 0.0, pvel)
			_spawn_fx("land", foot, PI, pvel)
			_squash[i] = -0.48                         # 着地: 横にペチャッと潰れる
			_squash_v[i] = 0.0
		elif p.on_ground == 1 and f - _last_dust_frame[i] > 12:
			# 走り出し=進行の逆へ蹴る煙、切り返し=元の進行方向へ蹴る
			if _prev_vx[i] == 0 and p.vx != 0:
				_spawn_fx("dash", foot, (0.0 if p.vx < 0 else PI), pvel)
				_last_dust_frame[i] = f
			elif _prev_vx[i] != 0 and p.vx != 0 and signi(p.vx) != signi(_prev_vx[i]):
				_spawn_fx("brake", foot, (0.0 if _prev_vx[i] > 0 else PI), pvel)
				_last_dust_frame[i] = f
		if p.cling != 0 and f - _last_dust_frame[i] > 7:
			# 壁張り付き中のずり落ち煙(少量)。壁と反対側へ小さく漂わせる
			_spawn_fx("land", foot, (0.0 if p.cling > 0 else PI), Vector2(0, 12))
			_last_dust_frame[i] = f
		# しりもち(ジャストアタック被弾)の砂煙: 尻をついた瞬間に控えめに1回
		if p.flinch > 0 and _prev_flinch[i] == 0:
			_spawn_fx("land", foot, 0.0, Vector2(0, 6))
		_prev_flinch[i] = p.flinch
		if p.just_receive_event > _prev_just_receive_event[i]:
			_spawn_fx("just", bpos, up, bvel * 0.2)
			_play_sfx("just_receive")
			_shake_amp = maxf(_shake_amp, 3.0)
		_prev_just_receive_event[i] = maxi(
			_prev_just_receive_event[i], p.just_receive_event)
		if _prev_cd[i] < cfg.hit_cooldown_ticks and p.hit_cooldown == cfg.hit_cooldown_ticks:
			# ヒットの瞬間。打った逆方向へ散る(=-ボール速度の向き)
			var away := (-bvel).angle() if bvel.length() > 0.5 else up
			_squash[i] = 0.30                          # 打撃の瞬間: グッと伸びる張り
			_squash_v[i] = 0.0
			if just_fired:
				_spawn_fx("just", bpos, away, bvel * 0.25)
				_play_sfx("just")
				_shake_amp = maxf(_shake_amp, 4.5)     # ジャスト: 画面がドンと揺れる
			elif p.on_ground == 0 and state.touches == 0:
				_spawn_fx("block", bpos, up, bvel * 0.25)
				_play_sfx("block")
			elif p.on_ground == 1:
				_spawn_fx("ring", bpos, up, bvel * 0.3)
				_play_sfx("hit")
			else:
				_spawn_fx("attack", bpos, away, bvel * 0.25)
				_play_sfx("hit")
		# 被弾フラッシュ: よろけ/気絶の開始フレームで白く点滅させる
		if _prev_stun[i] == 0 and p.stun_ticks > 0:
			_flash[i] = 14 if p.stun_ticks > cfg.stagger_ticks else 8
			# 体力スタンは画面も揺らす。よろけ(stagger)は軽くする。
			_shake_amp = maxf(_shake_amp, 3.0 if p.stun_ticks > cfg.stagger_ticks else 1.4)
		_prev_ground[i] = p.on_ground
		_prev_vx[i] = p.vx
		_prev_cd[i] = p.hit_cooldown
		_prev_stun[i] = p.stun_ticks
	# ボールが壁で跳ねた瞬間: vxの符号反転を壁際で検知→壁から離れる向きに火花
	var w := ViewTransform.to_px(cfg.court_width)
	var bx := bpos.x
	if signi(state.ball_vx) != signi(_prev_bvx) and _prev_bvx != 0 \
			and (bx < 24.0 or bx > w - 24.0) and state.phase == SimState.PHASE_RALLY:
		var wall_dir := 0.0 if state.ball_vx > 0 else PI  # 離れる向き
		_spawn_fx("wall", Vector2(clampf(bx, 2.0, w - 2.0), bpos.y), wall_dir, bvel)
	_prev_bvx = state.ball_vx
	# ボールが地面に着いた瞬間: 入射慣性で土煙(真下→左右/斜め→横)
	var floor_px := ViewTransform.to_px(cfg.floor_y)
	var bground := bpos.y >= floor_px - ViewTransform.to_px(cfg.ball_radius)
	if bground and not _prev_bground and state.phase == SimState.PHASE_RALLY:
		_spawn_fx("ballground", Vector2(bpos.x, floor_px), up, Vector2(bvel.x, 0.0))
		# 速い球の着弾ほど地面が揺れる(パワーボールの突き刺さりが決まる)
		var impact := clampf((bvel.y - 6.0) / 12.0, 0.0, 1.0)
		if impact > 0.0:
			_shake_amp = maxf(_shake_amp, 1.5 + 2.0 * impact)
	_prev_bground = bground
	# (トス頂点のキランは廃止=ユーザー指定で不要)
	_prev_power = state.ball_power
	# 得点の瞬間: 落下点に金色のバースト
	var score_now := Vector2i(state.score_l, state.score_r)
	if score_now != _prev_score:
		if _prev_score != Vector2i.ZERO or score_now.x + score_now.y == 1:
			_spawn_fx("score", bpos, up, bvel * 0.2)
			_play_sfx("score")
		_prev_score = score_now
	# 残像トレイル: ボール位置の履歴(描画側が速度に応じて使う)
	_ball_hist.append(bpos)
	if _ball_hist.size() > 10:
		_ball_hist.pop_front()

func _sync_sprites() -> void:
	_detect_fx()
	# 勝利演出のトリガー: ゲームセット後、ボールがほぼ止まってから発動(一度立てば継続)。
	# 決着直後にすぐ踊り出すのを防ぐ
	if state.phase != SimState.PHASE_GAME_OVER:
		_victory_on = false
	elif not _victory_on:
		var bvx := absf(ViewTransform.to_px(state.ball_vx))
		var bvy := absf(ViewTransform.to_px(state.ball_vy))
		if bvx < 1.0 and bvy < 1.0:
			_victory_on = true
	# 画面揺れ: インパルス減衰式。大きな衝撃(ジャスト/速い球の着弾/体力スタン)で
	# ドンと入り数フレームで収束する。impulseは_detect_fxが衝撃の瞬間に積む。
	# 表示層のみ(floatも描画フレーム由来の乱れも許される・ロールバック無関係)
	_shake_amp *= 0.78
	if _shake_amp < 0.1:
		_shake_amp = 0.0
	if _shake_amp > 0.0:
		var f := Engine.get_frames_drawn()
		position = _base_pos + Vector2(
			(float(f % 2) * 2.0 - 1.0) * _shake_amp,
			(float((f / 2) % 2) * 2.0 - 1.0) * _shake_amp * 0.7)
	else:
		position = _base_pos
	for i in _sprites.size():
		var p = state.players[i]
		var spr: AnimatedSprite2D = _sprites[i]
		# スカッシュ&ストレッチ: 踏切/着地/打撃で立てた_squashをバネで0へ戻す
		# (行き過ぎて軽く反動=ゴムまり感)。足元が原点なので地に足を着けたまま潰れる。
		# 表示層のみの飾りで当たり判定サイズには影響しない
		var dt := 1.0 / 60.0
		_squash_v[i] += (-120.0 * _squash[i] - 16.0 * _squash_v[i]) * dt
		_squash[i] += _squash_v[i] * dt
		var sq: float = clampf(_squash[i], -0.6, 0.6)
		spr.scale = Vector2(1.0 - 0.5 * sq, 1.0 + 0.5 * sq)
		var pos := ViewTransform.pos_of(p) + _depth_offset(i)
		# レシーブの小ホップ: 接地ヒット中はhit_cooldownから上下オフセットを導出。
		# 打った瞬間(cooldown最大)に最も持ち上がり、硬直が抜けるにつれ着地する。
		# 状態から導出するのでロールバック再描画でも一貫する
		if p.on_ground == 1 and p.hit_cooldown > 0:
			var t := float(p.hit_cooldown) / float(cfg.hit_cooldown_ticks)
			pos.y -= RECEIVE_HOP_PX * t
		var anim := AnimSelect.anim_for(p)
		var cid: int = p.char_id
		# 帽子投げ中(has_hat=0)は帽子なしスプライトに差し替え(帽子なし版を持つキャラのみ)。
		# 戻った瞬間はキャッチ演出。form(姿)の対応表はキャラ拡張の本実装で正式化する
		if Chars.has_ability(cid, Chars.CA_HAT):
			if _prev_hat[i] == 0 and p.has_hat == 1:
				_catch[i] = 12
			_prev_hat[i] = p.has_hat
			if cid == Chars.CHAR_MARIO:
				# 溜め中(p.throw>0)は帽子ありのまま投げモーション。発射後は茶髪へ
				var frames: SpriteFrames = _mario_hat if p.has_hat == 1 else _mario_hatless
				if spr.sprite_frames != frames:
					spr.sprite_frames = frames
			if p.throw > 0:
				anim = "hat-throw"
			elif _catch[i] > 0:
				anim = "hat-catch"
				_catch[i] -= 1
		# 勝利: ゲームセット後、ボールが止まってから勝者チームが演出開始(全キャラ、
		# 専用スプライトが無いキャラは代役ルールのvictoryが出る)
		if _victory_on and Simulation.team_of(i) == state.winner:
			anim = "victory"
			if cid == Chars.CHAR_MARIO and spr.sprite_frames != _mario_hat:
				spr.sprite_frames = _mario_hat
		if p.burn > 0:
			anim = "burn"
		# 向き: 移動中はvxの符号で更新、静止中は保持。
		# ただしアタック(空中打撃)だけはネット(相手)側を向く
		if p.vx > 0:
			_facing[i] = 1
		elif p.vx < 0:
			_facing[i] = -1
		var face: int = _facing[i]
		# アタック中はネット(相手)側を向く。サーブ準備中は「静止時だけ」ネット向き
		# (開始で後ろを向くのを防ぐ)。移動中はvxの向きに従う=左移動で左を向く
		if anim == "attack" or (state.phase == SimState.PHASE_SERVE and p.vx == 0):
			face = 1 if Simulation.team_of(i) == 0 else -1
			_facing[i] = face
		elif anim == "brake":
			# 急ブレーキ中は「これから向かう方向」を向く(滑るのは逆方向)
			face = -signi(p.brake)
			_facing[i] = face
		elif anim == "wallcling":
			# 壁張り付きは張り付いてる壁側を向く(左壁=cling1→左向き)。相手球でも一定
			face = -signi(p.cling)
			_facing[i] = face
		# 全キャラ素材は右向き基準(マリオのjumpシートも右向きに正規化済み)。
		# 左を向きたい(face<0)ときだけ反転する
		spr.flip_h = face < 0
		# 着地検知(前フレーム空中→今接地)。着地ポーズ(jump3枚目)を数フレーム出す
		if _was_air[i] and p.on_ground == 1:
			_land[i] = 6
		_was_air[i] = p.on_ground == 0
		# ジャンプは時間再生でなくvy(上下速度)で絵を固定選択する:
		# 上昇中(vy<0)=1枚目をずっと / 落下中(vy>=0)=2枚目をずっと / 着地=3枚目を数フレーム
		if anim == "burn":
			if spr.animation != "burn":
				spr.animation = "burn"
			spr.pause()
			var burn_frames: int = spr.sprite_frames.get_frame_count("burn")
			var burn_hold_ticks := 3 if SpriteFactory.is_original_char(cid) else 4
			spr.frame = int(state.tick / burn_hold_ticks) % burn_frames \
				if burn_frames > 0 else 0
		elif anim == "hipdrop":
			# ヒップアタック: 空中静止中(hip>0)は回転コマ0-8を進行に合わせて,
			# 急降下中(hip==-1)は10枚目(index9)。フレームはhipから導出(時間再生しない)
			if spr.animation != "hipdrop":
				spr.animation = "hipdrop"
			spr.pause()
			if p.hip > 0:
				spr.frame = clampi(int(float(36 - p.hip) * 9.0 / 36.0), 0, 8)
			else:
				spr.frame = 9
		elif anim == "dive":
			if spr.animation != "dive":
				spr.animation = "dive"
			spr.pause()
			spr.frame = AnimSelect.dive_frame_for(p)
		elif SpriteFactory.is_original_char(cid) \
				and (anim == "attack" or anim == "ground_swing" or anim == "toss_fwd"):
			if spr.animation != anim:
				spr.animation = anim
			spr.pause()
			spr.frame = AnimSelect.attack_frame_for(p, cfg.hit_cooldown_ticks) \
				if anim == "attack" else \
				AnimSelect.ground_swing_frame_for(p, cfg.hit_cooldown_ticks)
		elif anim == "jump":
			_land[i] = 0
			if spr.animation != "jump":
				spr.animation = "jump"
			spr.pause()
			var jump_frames: int = spr.sprite_frames.get_frame_count("jump")
			spr.frame = 0 if jump_frames < 2 or p.vy < 0 else 1
		elif spr.sprite_frames.get_frame_count("jump") >= 3 and _land[i] > 0 \
				and (anim == "idle" or anim == "run"):
			# 着地ポーズ=jumpの3枚目(3コマ以上のジャンプ素材を持つキャラのみ)
			if spr.animation != "jump":
				spr.animation = "jump"
			spr.pause()
			spr.frame = 2
			_land[i] -= 1
		else:
			if _land[i] > 0:
				_land[i] -= 1
			if spr.animation != anim:
				spr.play(anim)
		# カエル素材はidle系の足元に5pxの透明余白があり浮いて見える補正。
		# キツネ・マリオは補正不要
		if cid == Chars.CHAR_FROG and anim != "jump":
			pos.y += 5.0
		# 横っ飛び方向の符号から傾きを固定する。フレームと同じくsim状態だけで決まり、
		# ロールバック後も描画時刻に左右されない。
		if anim == "dive":
			spr.rotation = AnimSelect.dive_rotation_for(p)
		else:
			spr.rotation = 0.0
		# 被弾直後は白/赤の高速点滅(ダメージフラッシュ)。その後スタン中は薄い赤み。
		# 頭上の渦巻きはFxLayerが描く
		if p.just_receive_flash > 24:
			# 実機フィードバックで減光。成立直後6tickだけ低彩度の水色を薄く乗せる。
			# 約30tick残るJUST!表示が主表示なので、本体を長時間発光させない。
			spr.modulate = Color(0.82, 0.92, 1.0)
		elif _flash[i] > 0:
			_flash[i] -= 1
			spr.modulate = Color.WHITE if (_flash[i] / 2) % 2 == 0 \
				else Color(1.0, 0.3, 0.3)
		elif p.burnout_ticks > 0:
			spr.modulate = Color(0.72, 0.72, 0.76) \
				if (state.tick / 5) % 2 == 0 else Color(0.38, 0.38, 0.42)
		elif p.burn > 0 and not (cid in [Chars.CHAR_TOME, Chars.CHAR_HITO,
				Chars.CHAR_PIYO, Chars.CHAR_UME, Chars.CHAR_CARBY, Chars.CHAR_DUO,
				Chars.CHAR_SEC1, Chars.CHAR_SEC2]):
			spr.modulate = Color(1.0, 0.55, 0.2)
		elif p.stun_ticks > 0:
			spr.modulate = Color(1.0, 0.75, 0.75)
		else:
			spr.modulate = Color.WHITE
		# 整数ピクセルにスナップ(小数座標のままだとドットが滲む)
		# 勝利演出の締め: 16番=軽く跳ぶ, 17番=もっと高く跳ぶ(表示だけ持ち上げ)
		if anim == "victory":
			if spr.frame == 15:
				pos.y -= 5.0
			elif spr.frame == 16:
				pos.y -= 13.0
		spr.position = pos.round()
	var ball_pos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	if state.phase == SimState.PHASE_SERVE and state.serve_tossed == 0:
		# 保持中はサーバーの奥行きオフセットに合わせる(頭上からずれないように)
		ball_pos += _depth_offset(SimState._server_index(state))
	_ball.position = ball_pos.round()
	_flame_ball.position = ball_pos.round()
	if _cap != null:
		var cap_i := Simulation.ent_find(state, Simulation.KIND_CAP)
		if cap_i >= 0:
			var cap = state.entities[cap_i]
			_cap.visible = true
			_cap.position = Vector2(
				ViewTransform.to_px(cap.x), ViewTransform.to_px(cap.y)).round()
		else:
			_cap.visible = false
	# へしゃげ: 速度がスパイク級のとき進行方向に伸び垂直に潰れる。
	# sim速度から毎フレーム導出しビューに状態を持たない(ロールバック安全)
	var bv := Vector2(ViewTransform.to_px(state.ball_vx), ViewTransform.to_px(state.ball_vy))
	var sq_speed := absf(bv.x) + maxf(bv.y, 0.0) * SQUASH_VY_W
	var squash := clampf((sq_speed - SQUASH_V0) / (SQUASH_V1 - SQUASH_V0), 0.0, 1.0) * SQUASH_MAX
	if squash > 0.01 and state.phase != SimState.PHASE_SERVE:
		_ball.rotation = bv.angle()
		_ball.scale = Vector2(_ball_base_scale * (1.0 + squash), _ball_base_scale * (1.0 - squash))
	else:
		_ball.rotation = 0.0
		_ball.scale = Vector2.ONE * _ball_base_scale
	# ゴーストは8tick周期で点滅。炎球は原作シートindex13/14を4tickごとに交互表示。
	_flame_ball.visible = state.ball_special_id == Chars.SUPER_FLAME_ATTACK
	var flame_index: int = 13 if state.tick % 8 < 4 else 14
	_flame_ball.region_rect = Rect2((flame_index % 12) * 32,
		(flame_index / 12) * 32, 32, 32)
	_ball.visible = state.ball_special_id != Chars.SUPER_FLAME_ATTACK \
		and (state.ball_special_id != Chars.SUPER_GHOST_BALL or state.tick % 8 < 4)
	_ball.modulate = Color(1.0, 0.55, 0.35) if state.ball_power == 1 else Color.WHITE
	# 転がり回転: simが積むball_spin(横の勢いの累積)からフレームを導出する。
	# 真上のトスはほぼ無回転、前へ強く飛ぶほど速く回る。右へ進めば時計回り。
	# 状態から導出しビューに角度を溜めない(ロールバック安全)
	var frame := 0
	if state.phase != SimState.PHASE_SERVE:
		var radius_px := ViewTransform.to_px(cfg.ball_radius)
		if radius_px > 0.0:
			var angle := ViewTransform.to_px(state.ball_spin) / radius_px
			var step := TAU / float(_ball_roll_frames)
			frame = posmod(roundi(angle / step), _ball_roll_frames)
	_ball.region_rect = Rect2(frame * _ball_frame_w, 0, _ball_frame_w, _ball_frame_w)
	_fx.queue_redraw()  # 壁の波紋とマーカーはsim状態から毎フレーム導出する
	_fxg.queue_redraw()  # 発光レイヤーも同時に再描画

# エフェクト専用の最前面レイヤー。親ノード自身の_drawは子(コート背景)の下に
# 描かれて埋もれるため、必ず最後の子ノードとして重ねる
class FxLayer:
	extends Node2D
	var view

	func _draw() -> void:
		if view != null:
			view.draw_fx(self)

# 加算合成の発光レイヤー。ここに描いたものは重なると白飛びして「光る」。
# 影・マーカー等の暗色/単色UIは加算だと消えるので通常レイヤー(FxLayer)に残す
class FxGlowLayer:
	extends Node2D
	var view

	func _draw() -> void:
		if view != null:
			view.draw_fx_glow(self)

func draw_fx(c: CanvasItem) -> void:
	# 通常合成レイヤー: 影・案内マーカー・サーブ軌跡・渦巻きなど発光しない要素
	if state == null or cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var bx := ViewTransform.to_px(state.ball_x)
	# 画面外(上)に飛んだボールの現在位置を▼で示す(x追従)。強反射やジャンプトスで
	# 天井を突き抜けるのは正しい物理なので、見失わないための案内だけを出す
	var by := ViewTransform.to_px(state.ball_y)
	var view_top := -position.y  # ビューは上へシフトしているため画面上端はローカル正側
	if by < view_top - ViewTransform.to_px(cfg.ball_radius) \
			and state.phase != SimState.PHASE_SERVE:
		var ax := clampf(bx, 8.0, w - 8.0)
		var ay := view_top + 4.0
		var col := Color(1.0, 0.55, 0.35) if state.ball_power == 1 else Color(1.0, 0.9, 0.3)
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(ax - 5.0, ay), Vector2(ax + 5.0, ay), Vector2(ax, ay + 7.0)]), col)
	# サーブ軌跡は自チームのサーブの照準中のみ(相手の狙いはネタバレさせない)
	if state.phase == SimState.PHASE_SERVE and state.serving_team == local_team \
			and state.serve_tossed == 0:
		_draw_serve_preview(c)
	_draw_ball_shadow(c)
	_draw_stun_spirals(c)
	_draw_control_marker(c)
	# 統一パーティクルの不透明の丸/楕円(土煙・火色の塊)。加算だと透けるので通常合成側
	var f := Engine.get_frames_drawn()
	var ground := ViewTransform.to_px(cfg.floor_y)
	_draw_ball_trail(c)  # 残像トレイル: ジャスト(パワーボール)の時だけ出す
	for e in _fx_events:
		if e["k"] == "kiran":
			continue
		FxParticles.draw_opaque(c, e["k"], e["p"], e["d"], e["iner"], e["f0"], f, ground)
	_draw_drive_feedback(c)

func _draw_drive_feedback(c: CanvasItem) -> void:
	# simカウンタだけから導出するため、ロールバック後も同じtickは同じ表示になる。
	var burnout_screen_flash: bool = false
	for p in state.players:
		burnout_screen_flash = burnout_screen_flash \
			or p.burnout_ticks > cfg.burnout_recovery_ticks - 2
	var screen_rect := Rect2(-position, Vector2(640.0, 360.0))
	if burnout_screen_flash:
		c.draw_rect(screen_rect, Color(0.75, 0.08, 0.08, 0.38))
	var font := ThemeDB.fallback_font
	for i in state.players.size():
		var p = state.players[i]
		if p.just_receive_flash <= 0:
			continue
		var pos := ViewTransform.pos_of(p) + _depth_offset(i) + Vector2(-24.0, -42.0)
		var alpha := clampf(float(p.just_receive_flash) / 12.0, 0.35, 1.0)
		c.draw_string(font, pos, "JUST!", HORIZONTAL_ALIGNMENT_CENTER, 48.0, 14,
			Color(0.65, 0.95, 1.0, alpha))

func draw_fx_glow(c: CanvasItem) -> void:
	# 加算合成レイヤー: 発光する要素(火花)。sim状態から導出でロールバック安全
	if state == null or cfg == null:
		return
	var f := Engine.get_frames_drawn()
	var ground := ViewTransform.to_px(cfg.floor_y)
	for e in _fx_events:
		if e["k"] == "kiran":
			_draw_kiran(c, e["p"], float(f - e["f0"]) / (60.0 * FX_LIFE["kiran"]))
		else:
			FxParticles.draw_glow(c, e["k"], e["p"], e["d"], e["iner"], e["f0"], f, ground)

func _draw_kiran(c: CanvasItem, pos: Vector2, t: float) -> void:
	# トス頂点の目印(タイミングUI): 4方向に伸びて縮む十字の輝き(ここで打て!)
	if t < 0.0 or t >= 1.0:
		return
	var a := pow(1.0 - t, 1.4)
	var s4 := 3.0 + 5.0 * sin(t * PI)
	for k in 4:
		var v4 := Vector2.from_angle(float(k) * TAU / 4.0)
		_glow_line(c, pos.round(), (pos + v4 * s4).round(), Color(1.0, 1.0, 0.9), 1.5, 0.9 * a)

func _draw_ball_shadow(c: CanvasItem) -> void:
	# ボールの床影(可読性): 高いほど小さく薄い。空中戦の距離感の基準になる
	if state.phase == SimState.PHASE_SERVE and state.serve_tossed == 0:
		return
	var bx := ViewTransform.to_px(state.ball_x)
	var h := ViewTransform.to_px(cfg.floor_y) - ViewTransform.to_px(state.ball_y)
	if h < 0.0:
		return
	var r := clampf(9.0 - h * 0.02, 3.0, 9.0)
	var a := clampf(0.26 - h * 0.0007, 0.05, 0.26)
	var fy := ViewTransform.to_px(cfg.floor_y) - 1.0
	c.draw_set_transform(Vector2(bx, fy).round(), 0.0, Vector2(1.0, 0.32))
	# 柔らかい楕円影(距離感の基準)。2層で中心を濃く外周をぼかす=素朴で埋もれない
	c.draw_circle(Vector2.ZERO, r, Color(0.04, 0.04, 0.10, a * 0.55))
	c.draw_circle(Vector2.ZERO, r * 0.6, Color(0.03, 0.03, 0.08, a))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ball_trail(c: CanvasItem) -> void:
	# 残像トレイル: 統一パーティクルと同じ「不透明・進行方向に伸びた楕円・後方ほど縮小」で
	# ボールの尾を描く(加算発光ではなく通常合成=土煙と同じ質感)。ジャスト時のみ
	var powered: bool = state.ball_power == 1
	if not powered:
		return  # ジャストスマッシュ(パワーボール)の飛翔中だけ残像を出す
	var col := Color(0.92, 0.86, 0.72)  # ジャスト由来=暖色クリーム
	var n := _ball_hist.size()
	if n < 2:
		return
	var bw := float(FxParticles.BLOB.get_width())
	for k in range(maxi(1, n - 7), n - 1):
		var u := float(k - (n - 7)) / 7.0  # 後方(古い)ほど0=小さく、先頭ほど1=大きく
		# 土煙と同じ揺らぎ: 各残像の丸をサイズ・位置とも毎回散らす(位置で決まる決定論乱数)。
		# 丸の描画自体は不変=均一な尾でなく生きた煙のような尾になる
		var pos := _ball_hist[k]
		var seed := int(pos.x) * 131 + int(pos.y) * 977
		var sz_j := 0.6 + 0.8 * FxParticles.hv(seed, k, 0)   # サイズ0.6〜1.4倍
		var sz := (2.8 + 6.4 * u) * FxParticles.SIZE_SCALE * sz_j
		var off := Vector2(FxParticles.hv(seed, k, 1) - 0.5, FxParticles.hv(seed, k, 2) - 0.5) * 5.0
		c.draw_set_transform(pos + off, 0.0, Vector2(sz, sz) / bw)
		c.draw_texture(FxParticles.BLOB, -FxParticles.BLOB.get_size() * 0.5, col)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# 加算合成レイヤー用の発光プリミティブ。中心ほど白く明るく、外周は彩度の高い色が
# にじむ多層描画=重なって白飛びし「光っている」ように見える(ROUNDS風)。黒縁は使わない。
# ROUNDS実映像の解析結果: コアはほぼ白、その外に彩度の高い色がにじみ、フェードは
# 塊がバラバラの火花に砕けて飛散・縮小して消える。
func _glow_dot(c: CanvasItem, pos: Vector2, r: float, col: Color, a: float) -> void:
	var hot := col.lerp(Color(1, 1, 1), 0.75)
	c.draw_circle(pos, r * 2.4, Color(col, a * 0.10))   # 外周のにじみ
	c.draw_circle(pos, r * 1.4, Color(col, a * 0.22))
	c.draw_circle(pos, r * 0.85, Color(hot, a * 0.70))  # 高温部
	c.draw_circle(pos, r * 0.4, Color(1, 1, 1, a * 0.9))  # 白熱コア

func _glow_line(c: CanvasItem, p1: Vector2, p2: Vector2, col: Color, w: float, a: float) -> void:
	var hot := col.lerp(Color(1, 1, 1), 0.6)
	c.draw_line(p1, p2, Color(col, a * 0.28), w * 2.4)  # 光のにじみ
	c.draw_line(p1, p2, Color(col, a * 0.5), w * 1.3)
	c.draw_line(p1, p2, Color(hot, a * 0.95), maxf(1.0, w * 0.55))  # 明芯

func _glow_arc(c: CanvasItem, ctr: Vector2, r: float, a0: float, a1: float,
		col: Color, w: float, a: float, pts: int = 24) -> void:
	var hot := col.lerp(Color(1, 1, 1), 0.5)
	c.draw_arc(ctr, r, a0, a1, pts, Color(col, a * 0.30), w * 2.6)  # 発光の帯
	c.draw_arc(ctr, r, a0, a1, pts, Color(hot, a * 0.9), w)         # 明るい線

# 飛散する火花(発光): 中心から放射状にcount個が、イーズアウトで外へ飛びつつ
# 重力で少し落ち、縮小しながら消える(ROUNDS風の「抜け」のある爆発の核)。
# 各火花は白熱の頭+色の短い尾=加算で光る。方向はseed(発火フレーム)から決定的に
# 散らす=Math.random不要でロールバック安全
func _glow_shards(c: CanvasItem, pos: Vector2, t: float, col: Color,
		count: int, reach: float, seed: int) -> void:
	var ease := 1.0 - pow(1.0 - t, 2.5)  # イーズアウト(出だし速く、末で減速)
	var a := pow(1.0 - t, 1.5)           # 末に向けて加速度的に消える
	for k in count:
		var h := (seed * 2654435761 + k * 40503) & 0xFFFF
		var ang := float(h) / 65536.0 * TAU
		var dist := reach * (0.6 + 0.4 * float((h >> 3) & 7) / 7.0)
		var off := Vector2.from_angle(ang) * dist * ease
		off.y += ease * ease * 7.0  # 重力で軌道が少し垂れる
		var head := (pos + off).round()
		var tail := (pos + off * 0.72).round()  # 尾は内側へ
		var hr := maxf(0.8, 2.2 - 1.6 * t)  # 序盤は大きく、末で縮んで抜ける
		c.draw_line(tail, head, Color(col, a * 0.6), 2.0)     # 色の尾
		c.draw_circle(head, hr * 1.9, Color(col, a * 0.3))    # にじみ
		c.draw_circle(head, hr, Color(1, 1, 1, a * 0.9))      # 白熱の頭

func _draw_one_shots(c: CanvasItem) -> void:
	# ワンショットFXの描画(加算発光): 膨張→拡散→フェード。tは0..1の寿命進行。
	# ROUNDS実映像解析に基づく: 出だしに白い閃光、そこから彩度の高い光が広がり、
	# 塊は火花に砕けて飛散・縮小して消える。黒縁は使わない(加算で光らせる)
	var f := Engine.get_frames_drawn()
	for e_i in range(_fx_events.size() - 1, -1, -1):
		var e: Dictionary = _fx_events[e_i]
		var life: float = FX_LIFE.get(e["k"], 0.3)
		var t := float(f - e["f0"]) / (60.0 * life)
		if t >= 1.0:
			_fx_events.remove_at(e_i)
			continue
		_draw_fx_shape(c, e["k"], e["p"], t, e.get("d", 0.0), e["f0"])

# 1つのワンショットFXを寿命進行t(0..1)で描く純描画関数。tを外から与えられるので
# プレビュー生成(scripts/gen_fx_preview.gd)が実ゲームと同一のコードで各断面を描ける。
# seedは飛散火花の散り方の種(発火フレーム)
func _draw_fx_shape(c: CanvasItem, kind: String, pos: Vector2, t: float,
		dir: float, seed: int) -> void:
	# フェードは末で加速的に消える(a)。閃光は出だしだけ強い(flash)
	var a := pow(1.0 - t, 1.4)
	var flash := pow(1.0 - t, 3.0)
	# 土煙の色: 淡い青白(加算でふわっと発光する煙)
	var dust := Color(0.55, 0.65, 0.8)
	match kind:
			"jump":
				# 足元の左右にぽわッと土煙(外へ流れながら小さく)
				for s in [-1.0, 1.0]:
					for k in 3:
						var px := pos + Vector2(s * (3.0 + 10.0 * t + k * 2.5),
							-1.0 - k * 1.5 - 4.0 * t)
						var r := (2.6 if k < 2 else 1.6) * (1.0 - 0.4 * t)
						c.draw_circle(px.round(), r, Color(dust, 0.5 * a))
			"land":
				# 着地は横へ平たく広がる
				for s in [-1.0, 1.0]:
					for k in 3:
						var px := pos + Vector2(s * (4.0 + 15.0 * t + k * 3.0),
							-1.0 - 2.0 * t - float(k % 2))
						c.draw_circle(px.round(), 2.0 * (1.0 - 0.4 * t), Color(dust, 0.45 * a))
			"dash", "brake":
				# 走り出し/切り返しの蹴り煙(dirの側へ流れる)。切り返しは少し濃く長い
				var d: float = dir
				var n := 4 if kind == "brake" else 3
				for k in n:
					var px := pos + Vector2(d * (2.0 + 11.0 * t + k * 3.0),
						-1.0 - k * 1.8 - 3.0 * t)
					c.draw_circle(px.round(), 2.2 * (1.0 - 0.4 * t), Color(dust, 0.45 * a))
			"ring":
				# レシーブ/トス: ボール位置に光の輪がふわっと広がる
				_glow_arc(c, pos.round(), 4.0 + 11.0 * t, 0.0, TAU,
					Color(0.6, 0.85, 1.0), 1.5, 0.7 * a, 20)
			"attack":
				# アタック: 斜め4方向の短い白閃光(ボール半径14pxの外側で光る)
				for k in 4:
					var ang := float(k) * TAU / 4.0 + TAU / 8.0
					var v := Vector2.from_angle(ang)
					_glow_line(c, (pos + v * (9.0 + 10.0 * t)).round(),
						(pos + v * (16.0 + 14.0 * t)).round(),
						Color(1.0, 0.95, 0.7), 2.0, 0.9 * a)
			"just":
				# ジャストミート=多層爆発(ROUNDS風の抜けのある弾け):
				# 白い閃光コア+衝撃波リング2枚(白熱→オレンジ)+不規則な飛散火花を多めに。
				# ROUNDSの爆発はカオスで有機的=等間隔スポークではなく火花の乱舞で放射する。
				# 消える時は火花が縮小して抜ける
				_glow_dot(c, pos.round(), 4.0 + 9.0 * flash, Color(1.0, 0.9, 0.6), 0.95 * (0.3 + 0.7 * flash))
				_glow_arc(c, pos.round(), 15.0 + 30.0 * t, 0.0, TAU,
					Color(1.0, 1.0, 0.85), 2.0, 0.8 * a, 28)
				_glow_arc(c, pos.round(), 8.0 + 46.0 * t, 0.0, TAU,
					Color(1.0, 0.6, 0.2), 1.5, 0.5 * a, 28)
				# 2層の火花(速い白熱の外飛び+遅いオレンジの内側)でカオス感を出す
				_glow_shards(c, pos, t, Color(1.0, 0.8, 0.4), 16, 46.0, seed)
				_glow_shards(c, pos, t, Color(1.0, 0.55, 0.2), 10, 26.0, seed * 7 + 13)
			"kiran":
				# トス頂点の目印: 4方向に伸びて縮む十字の輝き(ここで打て!の合図)
				var s4 := 3.0 + 5.0 * sin(t * PI)
				for k in 4:
					var v4 := Vector2.from_angle(float(k) * TAU / 4.0)
					_glow_line(c, pos.round(), (pos + v4 * s4).round(),
						Color(1.0, 1.0, 0.9), 1.5, 0.9 * a)
			"smear":
				# 振り抜きの弧(スミア): 打点の周りを弧が一瞬走る
				var d4: float = dir
				var a0 := -1.9 if d4 > 0.0 else PI + 1.9
				var sweep := 2.4 * (0.3 + 0.7 * t) * d4
				_glow_arc(c, pos.round(), 14.0, a0, a0 + sweep,
					Color(1.0, 1.0, 1.0), 2.0, 0.5 * a, 12)
			"block":
				# ブロック成功: バチンと弾ける白閃光コア+Xの火花+短い衝撃波+少量の火花
				_glow_dot(c, pos.round(), 3.0 + 4.0 * flash, Color(1.0, 1.0, 0.85), 0.95 * (0.3 + 0.7 * flash))
				for k in 4:
					var v5 := Vector2.from_angle(float(k) * TAU / 4.0 + TAU / 8.0)
					_glow_line(c, (pos + v5 * (4.0 + 8.0 * t)).round(),
						(pos + v5 * (12.0 + 12.0 * t)).round(),
						Color(1.0, 0.9, 0.4), 2.5, 0.95 * a)
				_glow_arc(c, pos.round(), 6.0 + 20.0 * t, 0.0, TAU,
					Color(1.0, 0.95, 0.7), 1.5, 0.6 * a, 20)
				_glow_shards(c, pos, t, Color(1.0, 0.85, 0.45), 6, 22.0, seed)
			"score":
				# 得点=金色の多層バースト: 白閃光+二重の衝撃波リング+放射状に飛散する火花。
				# 大きく広がってから火花が縮小して抜ける(得点の余韻)
				_glow_dot(c, pos.round(), 5.0 + 6.0 * flash, Color(1.0, 0.9, 0.5), 0.9 * (0.3 + 0.7 * flash))
				_glow_arc(c, pos.round(), 6.0 + 48.0 * t, 0.0, TAU,
					Color(1.0, 0.8, 0.3), 2.5, 0.8 * a, 32)
				_glow_arc(c, pos.round(), 3.0 + 32.0 * t, 0.0, TAU,
					Color(1.0, 1.0, 0.8), 1.5, 0.5 * a, 24)
				_glow_shards(c, pos, t, Color(1.0, 0.82, 0.35), 14, 42.0, seed)

func _draw_wall_ripple(c: CanvasItem, wall_x: float, dist: float, dir: float) -> void:
	# 透明な壁の「ぶわん」: 衝突点から弾性の波紋が膨らむ。
	# 出だしは勢いよく、後半はゆっくり(イーズアウト)+波打つ半径で弾性感を出す。
	# 衝突点と経過時間はボールの現在位置と速度から逆算する(状態レス)
	var vx := absf(ViewTransform.to_px(state.ball_vx))
	if vx < 0.01:
		return
	var t := dist / vx           # 衝突からの経過tick数
	var dur := 16.0              # 波紋の寿命(tick)
	var u := t / dur
	if u >= 1.0:
		return
	# 直近のヒットが「壁衝突の推定時刻」より後なら、今の速度はヒット由来であり
	# 壁で跳ねていない(サーブ直後などの誤発火を防ぐ)
	var max_cd := 0
	for p in state.players:
		max_cd = maxi(max_cd, p.hit_cooldown)
	if max_cd > 0 and float(cfg.hit_cooldown_ticks - max_cd) <= t:
		return
	var vy := ViewTransform.to_px(state.ball_vy)
	var g := ViewTransform.to_px(cfg.gravity)
	var impact_y := ViewTransform.to_px(state.ball_y) - t * vy + g * t * (t + 1.0) * 0.5
	var center := Vector2(wall_x, impact_y)
	var center_angle := 0.0 if dir > 0.0 else PI
	# 散り方の種は衝突時点の回転量と高さから作る(アニメ中不変=バウンド毎に別の散り方)。
	# ビュー状態レスでロールバック安全
	var spin_imp := ViewTransform.to_px(state.ball_spin) - dir * dist
	var seed := absi(int(roundf(spin_imp)) * 131 + int(roundf(impact_y)) * 31)
	_draw_wall_spark(c, center, center_angle, u, seed)

# 壁反射の発光火花を経過率u(0..1)で描く純描画関数。uを外から与えられるので
# プレビュー生成が実ゲームと同一コードで各断面を描ける
func _draw_wall_spark(c: CanvasItem, center: Vector2, center_angle: float,
		u: float, seed: int) -> void:
	var ease_out := 1.0 - (1.0 - u) * (1.0 - u)   # 出だし速く後半ゆっくり
	# 衝突点の白い閃光コア(加算発光)。出だしだけ強く光り、白熱→オレンジのにじみ。
	# 加算合成なので黒縁は不要=白コアが周囲の色に白飛びして「光る」
	var core_a := pow(1.0 - u, 3.0)  # 閃光は出だしのみ
	if core_a > 0.02:
		_glow_dot(c, center, 5.0 + 5.0 * ease_out, Color(1.0, 0.8, 0.4), core_a)
	# 熱色の発光火花: 衝突点からコート内側へ扇状に飛び散る。炎の物理で色を絞る=
	# 若く速い火花ほど白熱、散り際・古い火花ほどオレンジに冷める。各火花は白熱の頭+
	# 色の尾=加算で光る
	var fade := pow(1.0 - u, 1.4)  # 末で加速的に消える
	for i in 14:
		var h1 := float(posmod(seed + i * 2654435761, 4096)) / 4096.0  # 角度用
		var h2 := float(posmod(seed * 3 + i * 1597334677, 4096)) / 4096.0  # 速さ用
		var h3 := float(posmod(seed * 7 + i * 805459861, 4096)) / 4096.0  # 垂れ用
		var ang := center_angle + (h1 - 0.5) * 2.6
		var spd := 34.0 + 58.0 * h2
		var d := Vector2(cos(ang), sin(ang))
		var dist_now := spd * ease_out
		var droop := 26.0 * u * u * (0.4 + h3)  # 重力で垂れる
		var head := center + d * dist_now + Vector2(0.0, droop)
		var tail := center + d * maxf(dist_now - 8.0 - 6.0 * fade, 0.0) + Vector2(0.0, droop * 0.8)
		# 温度: 速い火花(h2大)ほど白熱、遅い火花はオレンジ。時間が経つほど全体が
		# 冷めてオレンジ→赤へ(炎の物理)。heat=1で白、0で赤オレンジ
		var heat := clampf(h2 * 0.7 * (1.0 - u * 0.7), 0.0, 1.0)
		var spark := Color(1.0, 0.4 + 0.55 * heat, 0.1 + 0.55 * heat)
		c.draw_line(tail, head, Color(spark, fade * 0.35), 3.5)  # 色のにじみ
		c.draw_line(tail, head, Color(spark, fade * 0.85), 1.5)  # 明るい尾
		# 火花の先端は白く光る玉(発光の芯)。縮みながら消える
		var hr := maxf(0.8, 2.0 * fade)
		c.draw_circle(head, hr * 1.8, Color(spark, fade * 0.4))
		c.draw_circle(head, hr, Color(1.0, 1.0, 0.92, fade * 0.95))

func _draw_serve_preview(c: CanvasItem) -> void:
	# サーブトスの軌跡プレビュー(2段階サーブの1段目)。simの_try_serveと同じ式:
	# 左右=着弾距離、上下=高さ%(完全独立)。ここに落ちるボールを自分で打つ
	var aim: int = clampi(state.serve_aim, 0, Simulation.AIM_MAX)
	var net_dir := 1.0 if state.serving_team == 0 else -1.0
	var pow_pct: int = clampi(state.serve_pow, Simulation.POW_MIN, Simulation.POW_MAX)
	# simの_try_serveと同じ整数式で速度を出してからpxへ変換(弾道の完全一致)
	var vy_mag: int = cfg.serve_toss_up * pow_pct / 100
	var flight: int = maxi(2 * vy_mag / cfg.gravity, 1)
	var dx_fp: int = cfg.serve_toss_range * aim / Simulation.AIM_MAX
	var vx := net_dir * ViewTransform.to_px(dx_fp / flight)
	var vy := -ViewTransform.to_px(vy_mag)
	var g := ViewTransform.to_px(cfg.gravity)
	var pos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	var floor_px := ViewTransform.to_px(cfg.floor_y)
	# 高いトス(高さ130%)でも弧の全体が描けるよう滞空上限+αまで積分する
	for i in 160:
		vy += g
		pos += Vector2(vx, vy)
		if pos.y > floor_px:
			break
		if i % 3 == 0:
			var a := clampf(1.1 - float(i) / 100.0, 0.15, 1.0)
			c.draw_circle(pos, 2.0, Color(1.0, 0.95, 0.55, 0.75 * a))

func _draw_stun_spirals(c: CanvasItem) -> void:
	# スタン中のキャラの頭上でヒヨコ(黄色い玉)がクルクル回る古典演出。
	# 角度はtick由来=ロールバック再描画でも一貫(ビュー状態レス)
	for i in state.players.size():
		var p = state.players[i]
		if p.stun_ticks <= 0:
			continue
		var pos := ViewTransform.pos_of(p) + _depth_offset(i)
		var center := pos + Vector2(0.0, -30.0)
		var base := float(state.tick) * 0.22
		for k in 3:
			var ang := base + TAU * float(k) / 3.0
			var orbit := center + Vector2(cos(ang) * 12.0, sin(ang) * 4.0 - 2.0)
			c.draw_circle(orbit, 2.5, Color(1.0, 0.9, 0.2))
			c.draw_circle(orbit, 1.2, Color(1.0, 1.0, 0.75))

func _draw_control_marker(c: CanvasItem) -> void:
	# 操作中キャラの頭上に▽(黄)。自チームの操作スロットから導出(表示専用)。
	# 右チーム操作(ネット対戦のクライアント)はcontrolled_rを見る
	var idx: int = state.controlled_l if local_team == 0 else 2 + state.controlled_r
	var p = state.players[idx]
	var pos := ViewTransform.pos_of(p) + _depth_offset(idx)
	var top := pos + Vector2(0.0, -44.0)
	var pts := PackedVector2Array([
		top + Vector2(-7.0, -8.0), top + Vector2(7.0, -8.0), top + Vector2(0.0, 2.0)])
	c.draw_colored_polygon(pts, Color(1.0, 0.90, 0.20))
	c.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.45, 0.30, 0.0), 1.0)
