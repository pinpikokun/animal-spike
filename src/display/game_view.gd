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
	position = Vector2((640.0 - ViewTransform.to_px(cfg.court_width)) * 0.5, -12.0)
	Engine.physics_ticks_per_second = cfg.tick_rate
	$Court.setup(cfg)
	$ScoreUI.setup(cfg)
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

func _sync_sprites() -> void:
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
		# スタン中は倒れポーズ(hurt)+薄い赤み。頭上の渦巻きはFxLayerが描く
		if p.stun > 0:
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
	_draw_stun_spirals(c)
	_draw_control_marker(c)

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
	# 衝突点の白い閃光(最初の一瞬だけ)
	var core_a := (1.0 - u) * (1.0 - u) * 0.8
	if core_a > 0.02:
		c.draw_circle(center, 5.0 + 6.0 * ease_out, Color(1.0, 1.0, 1.0, core_a))
	# レインボーの火花: 衝突点からコート内側へ扇状に飛び散る。
	# 散り方はバウンドごとに変える: 種は「衝突時点の回転量と衝突高さ」から作る。
	# どちらもアニメ中は不変で、バウンドごとに異なる値=毎回違う散り方かつ
	# ビュー状態レスでロールバック安全
	var spin_imp := ViewTransform.to_px(state.ball_spin) - dir * dist
	var seed := absi(int(roundf(spin_imp)) * 131 + int(roundf(impact_y)) * 31)
	var fade := 1.0 - u
	for i in 16:
		var h1 := float(posmod(seed + i * 2654435761, 4096)) / 4096.0  # 角度用
		var h2 := float(posmod(seed * 3 + i * 1597334677, 4096)) / 4096.0  # 速さ用
		var h3 := float(posmod(seed * 7 + i * 805459861, 4096)) / 4096.0  # 色/垂れ用
		var ang := center_angle + (h1 - 0.5) * 2.6
		var spd := 30.0 + 52.0 * h2
		var d := Vector2(cos(ang), sin(ang))
		var dist_now := spd * ease_out
		var droop := 26.0 * u * u * (0.4 + h3)  # 重力で垂れる
		var head := center + d * dist_now + Vector2(0.0, droop)
		var tail := center + d * maxf(dist_now - 7.0 - 5.0 * fade, 0.0) + Vector2(0.0, droop * 0.8)
		var hue := fmod(h3 + float(i) / 16.0 + u * 0.25, 1.0)
		c.draw_line(tail, head, Color.from_hsv(hue, 0.85, 1.0, fade * 0.95), 2.0)
		if fade > 0.3:
			c.draw_circle(head, 1.5, Color.from_hsv(hue, 0.55, 1.0, fade))

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
