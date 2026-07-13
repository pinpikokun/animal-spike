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
var _fx: Node2D  # エフェクト最前面レイヤー(FxLayer)
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
var _prev_stun: Array[int] = [0, 0, 0, 0]
var _prev_power := 0
var _prev_bvy := 0
var _prev_score := Vector2i.ZERO
var _last_dust_frame: Array[int] = [-99, -99, -99, -99]
var _flash: Array[int] = [0, 0, 0, 0]  # 被弾白フラッシュの残りフレーム
var _ball_hist: Array[Vector2] = []    # 残像トレイル用のボール位置履歴
var _sfx: Dictionary = {}              # 仮SE(自前合成WAV)。無ければ黙って鳴らさない
const FX_LIFE := {"jump": 0.28, "land": 0.30, "dash": 0.25, "brake": 0.32,
	"ring": 0.25, "attack": 0.22, "just": 0.50, "kiran": 0.30, "smear": 0.16,
	"block": 0.36, "score": 0.62}
const KIRAN_MIN_H_FP := 120 << 16  # 頂点キランを出す最低高度(床から120px、fp)
# ローカルプレイヤーのチーム(0=左,1=右)。▽マーカーとサーブ軌跡は自チームのみ
# 表示する(相手のサーブ予測軌跡が見えると駆け引きが死ぬ)。ネット対戦では
# net_match.gdがホスト=0/クライアント=1を設定する
var local_team := 0

func attach_external(cfg_in, state_ref) -> void:
	# instantiate直後・add_child前に呼ぶこと(_readyがcfg/stateを自前生成しないため)
	external_sim = true
	cfg = cfg_in
	state = state_ref

func _ready() -> void:
	if not external_sim:
		cfg = SimConfig.new()
		if not cfg.valid:
			push_error("rules.jsonの読み込みに失敗したため起動を中止する")
			return
		state = SimState.new()
		Simulation.reset_match(state, cfg, 0)
	# 表示のみの一括シフト(ScoreUIはCanvasLayerで不動):
	# コートが画面より狭いぶん中央寄せ。縦は上へ寄せて下端の顔HUD帯(y=332..356)と
	# コート床(floor_y=320)・キャラの足元が重ならないようにする
	_base_pos = Vector2((640.0 - ViewTransform.to_px(cfg.court_width)) * 0.5, -12.0)
	position = _base_pos
	Engine.physics_ticks_per_second = cfg.tick_rate
	$Court.setup(cfg)
	$ScoreUI.setup(cfg)
	_setup_sfx()
	var fox := SpriteFactory.build_fox()
	var frog := SpriteFactory.build_frog()
	for i in 4:
		var s := AnimatedSprite2D.new()
		# チーム0(左, index0,1)=キツネ、チーム1(右)=カエル
		s.sprite_frames = fox if Simulation.team_of(i) == 0 else frog
		# 奇数幅(33px)のセンター配置は常に半ピクセルずれてぼやける。
		# 非センター+整数オフセットで足元原点・整数ピクセル描画にする
		s.centered = false
		s.offset = Vector2(-16, -32)
		# 手前レーン(偶数slot)を前面に描く(奥のキャラと重なった時に自然な前後関係)
		s.z_index = 1 if i % 2 == 0 else 0
		s.play("idle")
		$Players.add_child(s)
		_sprites.append(s)
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
	# エフェクトレイヤーは最後に追加し、z_indexでも最前面を保証する
	_fx = FxLayer.new()
	_fx.view = self
	_fx.z_index = 10
	add_child(_fx)

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
	for sfx_name in ["hit", "just", "block", "score"]:
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

func _spawn_fx(kind: String, pos: Vector2, dir: float = 0.0) -> void:
	if _fx_events.size() >= 32:
		_fx_events.pop_front()
	_fx_events.append({"k": kind, "p": pos, "f0": Engine.get_frames_drawn(), "d": dir})

func _detect_fx() -> void:
	# sim状態の1フレーム差分からエフェクト発火点を検知する。
	# 入力は見ない(観測できるのは物理状態だけ=ネット対戦でも同じ絵になる)
	var f := Engine.get_frames_drawn()
	var bpos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	var just_fired: bool = _prev_power == 0 and state.ball_power == 1
	for i in state.players.size():
		var p = state.players[i]
		var foot := ViewTransform.pos_of(p) + _depth_offset(i)
		if _prev_ground[i] == 1 and p.on_ground == 0:
			_spawn_fx("jump", foot)
		elif _prev_ground[i] == 0 and p.on_ground == 1:
			_spawn_fx("land", foot)
		elif p.on_ground == 1 and f - _last_dust_frame[i] > 12:
			# 走り出し=静止からの発進(煙は進行の逆側へ)、切り返し=速度の符号反転
			if _prev_vx[i] == 0 and p.vx != 0:
				_spawn_fx("dash", foot, -signf(float(p.vx)))
				_last_dust_frame[i] = f
			elif _prev_vx[i] != 0 and p.vx != 0 and signi(p.vx) != signi(_prev_vx[i]):
				_spawn_fx("brake", foot, signf(float(_prev_vx[i])))
				_last_dust_frame[i] = f
		if _prev_cd[i] < cfg.hit_cooldown_ticks and p.hit_cooldown == cfg.hit_cooldown_ticks:
			# ヒットの瞬間。ジャスト=炸裂、ブロック(タッチ数0)=火花、
			# 地上=リング、空中=衝撃閃光。空中打ちは腕の振り抜きスミアも重ねる
			var team_dir := 1.0 if Simulation.team_of(i) == 0 else -1.0
			if just_fired:
				_spawn_fx("just", bpos)
				_spawn_fx("smear", foot + Vector2(0, -14.0), team_dir)
				_play_sfx("just")
			elif p.on_ground == 0 and state.touches == 0:
				_spawn_fx("block", bpos)
				_play_sfx("block")
			elif p.on_ground == 1:
				_spawn_fx("ring", bpos)
				_play_sfx("hit")
			else:
				_spawn_fx("attack", bpos)
				_spawn_fx("smear", foot + Vector2(0, -14.0), team_dir)
				_play_sfx("hit")
		# 被弾フラッシュ: よろけ/気絶の開始フレームで白く点滅させる
		if _prev_stun[i] == 0 and p.stun > 0:
			_flash[i] = 14 if p.stun > cfg.stagger_ticks else 8
		_prev_ground[i] = p.on_ground
		_prev_vx[i] = p.vx
		_prev_cd[i] = p.hit_cooldown
		_prev_stun[i] = p.stun
	# トスの頂点キラン: 上昇から落下に転じた瞬間、高い球にだけ光る
	# (=ジャストミートを狙う目印。演出でタイミングを教える)
	if _prev_bvy < 0 and state.ball_vy >= 0 and state.phase == SimState.PHASE_RALLY \
			and state.ball_y < cfg.floor_y - KIRAN_MIN_H_FP:
		_spawn_fx("kiran", bpos)
	_prev_bvy = state.ball_vy
	_prev_power = state.ball_power
	# 得点の瞬間: 落下点に金色のバースト
	var score_now := Vector2i(state.score_l, state.score_r)
	if score_now != _prev_score:
		if _prev_score != Vector2i.ZERO or score_now.x + score_now.y == 1:
			_spawn_fx("score", bpos)
			_play_sfx("score")
		_prev_score = score_now
	# 残像トレイル: ボール位置の履歴(描画側が速度に応じて使う)
	_ball_hist.append(bpos)
	if _ball_hist.size() > 10:
		_ball_hist.pop_front()

func _sync_sprites() -> void:
	_detect_fx()
	# 画面揺れ: ヒットストップ中とパワーボール直後は基準位置から細かくブレる。
	# 表示層のみ(floatも描画フレーム由来の乱れも許される)
	# 揺れるのは大物だけ: 気絶級の長い瞬止(>=5)かパワーボールの瞬止。
	# 通常アタックの軽い瞬止(2tick)は止まるだけで揺らさない(ユーザー指定)
	var shake := 0.0
	if state.hit_freeze >= 5 or (state.hit_freeze > 0 and state.ball_power == 1):
		shake = 2.5
	elif state.ball_power == 1 and state.tick - state.last_hit_tick < 10:
		shake = 1.2
	if shake > 0.0:
		var f := Engine.get_frames_drawn()
		position = _base_pos + Vector2(
			(float(f % 2) * 2.0 - 1.0) * shake, (float((f / 2) % 2) * 2.0 - 1.0) * shake * 0.6)
	else:
		position = _base_pos
	for i in _sprites.size():
		var p = state.players[i]
		var spr: AnimatedSprite2D = _sprites[i]
		var pos := ViewTransform.pos_of(p) + _depth_offset(i)
		# レシーブの小ホップ: 接地ヒット中はhit_cooldownから上下オフセットを導出。
		# 打った瞬間(cooldown最大)に最も持ち上がり、硬直が抜けるにつれ着地する。
		# 状態から導出するのでロールバック再描画でも一貫する
		if p.on_ground == 1 and p.hit_cooldown > 0:
			var t := float(p.hit_cooldown) / float(cfg.hit_cooldown_ticks)
			pos.y -= RECEIVE_HOP_PX * t
		spr.flip_h = AnimSelect.flip_for_team(Simulation.team_of(i))
		var anim := AnimSelect.anim_for(p)
		if spr.animation != anim:
			spr.play(anim)
		# カエル素材はidle系の足元に5pxの透明余白があり浮いて見える。
		# キツネの接地軸に合わせる表示補正(jump素材は余白なしなので補正しない)
		if Simulation.team_of(i) == 1 and anim != "jump":
			pos.y += 5.0
		# ジャンピングトス(リーチ縁の救済)は体を倒して飛びつく。sim状態の
		# dive(符号=方向、絶対値=残tick)から毎フレーム導出(ロールバック安全)。
		# 回転軸は足元原点。出だしが最大で起き上がりながら戻る
		if p.dive != 0:
			var lean := float(p.dive) / float(cfg.hit_cooldown_ticks)
			spr.rotation = lean * 0.9
		else:
			spr.rotation = 0.0
		# 被弾直後は白/赤の高速点滅(ダメージフラッシュ)。その後スタン中は薄い赤み。
		# 頭上の渦巻きはFxLayerが描く
		if _flash[i] > 0:
			_flash[i] -= 1
			spr.modulate = Color.WHITE if (_flash[i] / 2) % 2 == 0 \
				else Color(1.0, 0.3, 0.3)
		elif p.stun > 0:
			spr.modulate = Color(1.0, 0.75, 0.75)
		else:
			spr.modulate = Color.WHITE
		# 整数ピクセルにスナップ(小数座標のままだとドットが滲む)
		spr.position = pos.round()
	var ball_pos := Vector2(ViewTransform.to_px(state.ball_x), ViewTransform.to_px(state.ball_y))
	if state.phase == SimState.PHASE_SERVE and state.serve_tossed == 0:
		# 保持中はサーバーの奥行きオフセットに合わせる(頭上からずれないように)
		ball_pos += _depth_offset(state.serving_team * 2)
	_ball.position = ball_pos.round()
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
	# パワーボール(ジャストミートのスパイク)は熱を帯びた色で警告する
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

# エフェクト専用の最前面レイヤー。親ノード自身の_drawは子(コート背景)の下に
# 描かれて埋もれるため、必ず最後の子ノードとして重ねる
class FxLayer:
	extends Node2D
	var view

	func _draw() -> void:
		if view != null:
			view.draw_fx(self)

func draw_fx(c: CanvasItem) -> void:
	# 透明な壁(コート端)の「ブイン」: 壁で跳ね返った直後=壁の近くで壁から離れる向きに
	# 飛んでいる時だけ描く。強さは壁からの距離で減衰。
	# 全てsim状態からの導出でビュー側に状態を持たない(ロールバック安全)
	if state == null or cfg == null:
		return
	var w := ViewTransform.to_px(cfg.court_width)
	var bx := ViewTransform.to_px(state.ball_x)
	var vx := ViewTransform.to_px(state.ball_vx)
	# 壁から離れる向きに飛んでいる=直前に跳ねた可能性。寿命判定は波紋側(u>=1で消灯)
	if vx > 0.01:
		_draw_wall_ripple(c, 0.0, bx, 1.0)
	elif vx < -0.01:
		_draw_wall_ripple(c, w, w - bx, -1.0)
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
	_draw_ball_trail(c)
	_draw_one_shots(c)
	_draw_stun_spirals(c)
	_draw_control_marker(c)

func _draw_ball_shadow(c: CanvasItem) -> void:
	# ボールの床影(可読性): 高いほど小さく薄い。空中戦の距離感の基準になる
	if state.phase == SimState.PHASE_SERVE and state.serve_tossed == 0:
		return
	var bx := ViewTransform.to_px(state.ball_x)
	var h := ViewTransform.to_px(cfg.floor_y) - ViewTransform.to_px(state.ball_y)
	if h < 0.0:
		return
	var r := clampf(9.0 - h * 0.02, 3.0, 9.0)
	var a := clampf(0.30 - h * 0.0007, 0.06, 0.30)
	var fy := ViewTransform.to_px(cfg.floor_y) - 1.0
	c.draw_set_transform(Vector2(bx, fy).round(), 0.0, Vector2(1.0, 0.35))
	# 暗い芯(明背景で効く)+細い明色リング(暗背景で効く)=床面の明暗を問わず見える
	c.draw_circle(Vector2.ZERO, r, Color(0.05, 0.05, 0.12, a))
	c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, a * 0.35), 1.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ball_trail(c: CanvasItem) -> void:
	# 残像トレイル: スパイク級の速度で尾を引く。パワーボールは熱色で強く
	var spd := Vector2(ViewTransform.to_px(state.ball_vx),
		ViewTransform.to_px(state.ball_vy)).length()
	var powered: bool = state.ball_power == 1
	if not powered and spd < 9.0:
		return
	# 芯色は熱色/白。暗い縁を1px重ねて明るい背景でも尾が消えないようにする
	var core := Color(1.0, 0.55, 0.3) if powered else Color(1.0, 1.0, 1.0)
	var n := _ball_hist.size()
	for k in range(maxi(0, n - 8), n - 1):
		var u := float(k - (n - 8)) / 8.0  # 古いほど0
		var alpha := (0.35 if powered else 0.20) * u
		var r := 2.0 + 3.0 * u
		var p := _ball_hist[k].round()
		c.draw_circle(p, r + 1.0, Color(FX_OUTLINE, alpha * 0.8))
		c.draw_circle(p, r, Color(core, alpha))

# エフェクトの縁取り色。ほぼ黒だが完全な黒ではない暗色=どんな背景(雪原/砂浜/
# 白い体育館でも紺コートでも)でも芯の明色が沈まず浮き上がる。背景非依存の要。
const FX_OUTLINE := Color(0.10, 0.08, 0.13)

# 縁取り付きプリミティブ: 先に暗色で1回り大きく描いてから明色の芯を重ねる。
# 明るい背景でも輪郭が背景と芯を分離するので視認性が保たれる
func _fx_line(c: CanvasItem, p1: Vector2, p2: Vector2, col: Color, w: float, a: float) -> void:
	c.draw_line(p1, p2, Color(FX_OUTLINE, a), w + 2.0)
	c.draw_line(p1, p2, Color(col, a), w)

func _fx_arc(c: CanvasItem, ctr: Vector2, r: float, a0: float, a1: float,
		col: Color, w: float, a: float, pts: int = 24) -> void:
	c.draw_arc(ctr, r, a0, a1, pts, Color(FX_OUTLINE, a), w + 2.0)
	c.draw_arc(ctr, r, a0, a1, pts, Color(col, a), w)

func _fx_dot(c: CanvasItem, pos: Vector2, r: float, col: Color, a: float) -> void:
	c.draw_circle(pos, r + 1.0, Color(FX_OUTLINE, a))
	c.draw_circle(pos, r, Color(col, a))

func _fx_rect(c: CanvasItem, pos: Vector2, sz: Vector2, col: Color, a: float) -> void:
	c.draw_rect(Rect2(pos - Vector2.ONE, sz + Vector2(2, 2)), Color(FX_OUTLINE, a))
	c.draw_rect(Rect2(pos, sz), Color(col, a))

# 飛散する破片: 中心から放射状にcount個の小片が、イーズアウトで外へ飛びつつ
# 重力で少し落ち、縮小しながら消える(ROUNDS風の「抜け」のある爆発の核)。
# 方向はseed(発火フレーム)から決定的に散らす=Math.random不要でロールバック安全
func _fx_shards(c: CanvasItem, pos: Vector2, t: float, col: Color,
		count: int, reach: float, seed: int) -> void:
	var ease := 1.0 - pow(1.0 - t, 2.5)  # イーズアウト(出だし速く、末で減速)
	var a := pow(1.0 - t, 1.5)           # 末に向けて加速度的に消える
	for k in count:
		var h := (seed * 2654435761 + k * 40503) & 0xFFFF
		var ang := float(h) / 65536.0 * TAU
		var dist := reach * (0.6 + 0.4 * float((h >> 3) & 7) / 7.0)
		var off := Vector2.from_angle(ang) * dist * ease
		off.y += ease * ease * 6.0  # 重力で軌道が少し垂れる
		var sz := maxf(1.0, 3.5 - 2.5 * t)  # 序盤は大きく、末で1pxまで縮んで抜ける
		_fx_rect(c, (pos + off).round(), Vector2(sz, sz), col, 0.9 * a)

func _draw_one_shots(c: CanvasItem) -> void:
	# ワンショットFXの描画: 膨張→拡散→フェード。円でなくピクセルにスナップした
	# 小矩形で描く(ドット絵の質感を守る)。tは0..1の寿命進行。
	# 色は全て「暗い縁取り+明るい芯」で背景非依存(FX_OUTLINE参照)
	var f := Engine.get_frames_drawn()
	for e_i in range(_fx_events.size() - 1, -1, -1):
		var e: Dictionary = _fx_events[e_i]
		var life: float = FX_LIFE.get(e["k"], 0.3)
		var t := float(f - e["f0"]) / (60.0 * life)
		if t >= 1.0:
			_fx_events.remove_at(e_i)
			continue
		var a := 1.0 - t
		var pos: Vector2 = e["p"]
		# 土煙の芯色: 明るいオフホワイト(縁取りが背景から分離するので明背景でも可)
		var dust := Color(0.95, 0.93, 0.86)
		match e["k"]:
			"jump":
				# 足元の左右にぽわッと土煙(外へ流れながら小さく)
				for s in [-1.0, 1.0]:
					for k in 3:
						var px := pos + Vector2(s * (3.0 + 10.0 * t + k * 2.5),
							-1.0 - k * 1.5 - 4.0 * t)
						var sz := 2.0 if k < 2 and t < 0.6 else 1.0
						_fx_rect(c, px.round(), Vector2(sz, sz), dust, 0.85 * a)
			"land":
				# 着地は横へ平たく広がる
				for s in [-1.0, 1.0]:
					for k in 3:
						var px := pos + Vector2(s * (4.0 + 15.0 * t + k * 3.0),
							-1.0 - 2.0 * t - float(k % 2))
						_fx_rect(c, px.round(), Vector2(2, 1), dust, 0.85 * a)
			"dash", "brake":
				# 走り出し/切り返しの蹴り煙(dirの側へ流れる)。切り返しは少し濃く長い
				var d: float = e["d"]
				var n := 4 if e["k"] == "brake" else 3
				for k in n:
					var px := pos + Vector2(d * (2.0 + 11.0 * t + k * 3.0),
						-1.0 - k * 1.8 - 3.0 * t)
					var sz2 := 2.0 if t < 0.5 else 1.0
					_fx_rect(c, px.round(), Vector2(sz2, sz2), dust, 0.85 * a)
			"ring":
				# レシーブ/トス: ボール位置に輪がふわっと広がる
				_fx_arc(c, pos.round(), 4.0 + 11.0 * t, 0.0, TAU,
					Color(1.0, 1.0, 1.0), 1.0, 0.7 * a, 20)
			"attack":
				# アタック: 斜め4方向の短い閃光(ボール半径14pxの外側で光る)
				for k in 4:
					var ang := float(k) * TAU / 4.0 + TAU / 8.0
					var v := Vector2.from_angle(ang)
					_fx_line(c, (pos + v * (9.0 + 10.0 * t)).round(),
						(pos + v * (16.0 + 14.0 * t)).round(),
						Color(1.0, 1.0, 0.85), 1.0, 0.9 * a)
			"just":
				# ジャストミート=多層爆発(ROUNDS風の抜けのある弾け):
				# 中心の白い閃光コア+衝撃波リング2枚+8方向の放射光+飛散破片。
				# 消える時は破片が縮小して抜ける。ボール半径14pxの外から放射する
				if t < 0.35:
					_fx_dot(c, pos.round(), 10.0 * (1.0 - t / 0.35),
						Color(1.0, 1.0, 0.92), 0.95)
				for k in 8:
					var ang2 := float(k) * TAU / 8.0
					var v2 := Vector2.from_angle(ang2)
					_fx_line(c, (pos + v2 * (12.0 + 22.0 * t)).round(),
						(pos + v2 * (22.0 + 30.0 * t)).round(),
						Color(1.0, 0.8, 0.25), 2.0, 0.95 * a)
				_fx_arc(c, pos.round(), 15.0 + 30.0 * t, 0.0, TAU,
					Color(1.0, 1.0, 0.9), 2.0, 0.85 * a, 28)
				_fx_arc(c, pos.round(), 8.0 + 44.0 * t, 0.0, TAU,
					Color(1.0, 0.7, 0.2), 1.0, 0.6 * a, 28)
				_fx_shards(c, pos, t, Color(1.0, 0.85, 0.4), 10, 34.0, e["f0"])
			"kiran":
				# トス頂点の目印: 4方向に伸びて縮む十字の輝き(ここで打て!の合図)
				var s4 := 3.0 + 5.0 * sin(t * PI)
				for k in 4:
					var v4 := Vector2.from_angle(float(k) * TAU / 4.0)
					_fx_line(c, pos.round(), (pos + v4 * s4).round(),
						Color(1.0, 1.0, 1.0), 1.0, 0.9 * a)
			"smear":
				# 振り抜きの弧(スミア): 打点の周りを弧が一瞬走る
				var d4: float = e["d"]
				var a0 := -1.9 if d4 > 0.0 else PI + 1.9
				var sweep := 2.4 * (0.3 + 0.7 * t) * d4
				_fx_arc(c, pos.round(), 14.0, a0, a0 + sweep,
					Color(1.0, 1.0, 1.0), 2.0, 0.55 * a, 12)
			"block":
				# ブロック成功: バチンと弾けるXの火花+短い衝撃波+少量の破片
				if t < 0.3:
					_fx_dot(c, pos.round(), 5.0 * (1.0 - t / 0.3),
						Color(1.0, 1.0, 1.0), 0.95)
				for k in 4:
					var v5 := Vector2.from_angle(float(k) * TAU / 4.0 + TAU / 8.0)
					_fx_line(c, (pos + v5 * (4.0 + 8.0 * t)).round(),
						(pos + v5 * (12.0 + 12.0 * t)).round(),
						Color(1.0, 0.9, 0.4), 2.0, 0.95 * a)
				_fx_arc(c, pos.round(), 6.0 + 20.0 * t, 0.0, TAU,
					Color(1.0, 0.95, 0.7), 1.0, 0.6 * a, 20)
				_fx_shards(c, pos, t, Color(1.0, 0.9, 0.5), 5, 20.0, e["f0"])
			"score":
				# 得点=金色の多層バースト: 二重の衝撃波リング+放射状に飛散する破片。
				# 大きく広がってから破片が縮小して抜ける(得点の余韻)
				_fx_arc(c, pos.round(), 6.0 + 48.0 * t, 0.0, TAU,
					Color(1.0, 0.85, 0.3), 2.0, 0.8 * a, 32)
				_fx_arc(c, pos.round(), 3.0 + 32.0 * t, 0.0, TAU,
					Color(1.0, 1.0, 0.85), 1.0, 0.5 * a, 24)
				_fx_shards(c, pos, t, Color(1.0, 0.88, 0.4), 12, 40.0, e["f0"])

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
	var ease_out := 1.0 - (1.0 - u) * (1.0 - u)   # 出だし速く後半ゆっくり
	var center := Vector2(wall_x, impact_y)
	var center_angle := 0.0 if dir > 0.0 else PI
	# 衝突点の白い閃光コア+熱色のハロー(局所疑似発光=ROUNDS風の「光ってる」感)。
	# 最初の一瞬だけ強く光り、周りにオレンジのにじみを重ねる
	# コアは素早く消す(pow3): 薄い層は紺背景でくすんで「紫のシミ」になるので使わず、
	# 不透明に近い黄コア+白コアの2層だけで明るく光らせる(発光感は火花先端が担う)
	# 閾値0.25で早期に消す(薄い暖色は紺背景でくすんで紫のシミになるため)。
	# コアが生きている間は暗縁+黄+白の三層で紫化を防ぎつつ明るく光らせる
	var core_a := pow(1.0 - u, 3.0)
	if core_a > 0.25:
		c.draw_circle(center, 7.0 + 6.0 * ease_out, Color(FX_OUTLINE, core_a * 0.6))
		c.draw_circle(center, 6.0 + 6.0 * ease_out, Color(1.0, 0.85, 0.45, core_a))
		c.draw_circle(center, 3.0 + 4.0 * ease_out, Color(1.0, 1.0, 0.95, core_a))
	# 熱色の発光火花: 衝突点からコート内側へ扇状に飛び散る。虹色はやめ、炎の物理で
	# 色を絞る=若く速い火花ほど白熱、散り際・古い火花ほどオレンジに冷める。
	# 各火花は「暗縁+明芯」で背景非依存。散り方の種は衝突時点の回転量と高さから作り
	# (アニメ中不変=バウンド毎に別の散り方)、ビュー状態レスでロールバック安全
	var spin_imp := ViewTransform.to_px(state.ball_spin) - dir * dist
	var seed := absi(int(roundf(spin_imp)) * 131 + int(roundf(impact_y)) * 31)
	var fade := 1.0 - u
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
		c.draw_line(tail, head, Color(FX_OUTLINE, fade * 0.8), 4.0)  # 暗縁
		c.draw_line(tail, head, Color(spark, fade * 0.95), 2.0)      # 明芯
		# 火花の先端は白く光る玉(発光の芯)
		if fade > 0.3:
			c.draw_circle(head, 2.5, Color(1.0, 0.85, 0.6, fade * 0.5))
			c.draw_circle(head, 1.3, Color(1.0, 1.0, 0.9, fade * 0.95))

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
		if p.stun <= 0:
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
