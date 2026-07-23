# int演算のみ。プレイヤーの移動、ジャンプ、硬直中の物理を扱う。
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const Chars := preload("res://src/sim/chars.gd")

const IN_LEFT := SimInput.IN_LEFT
const IN_RIGHT := SimInput.IN_RIGHT
const IN_JUMP := SimInput.IN_JUMP
const IN_ACTION := SimInput.IN_ACTION
const IN_DOWN := SimInput.IN_DOWN
const IN_ABILITY1 := SimInput.IN_ABILITY1

const BRAKE_TICKS := 8  # 急ブレーキ(スキッド)で旧方向へ滑る長さ(tick)
const SKID_MIN_RUN := 12  # この連続走行tick以上でのみ反転スキッドが出る(細かい追尾は滑らない)
const RUN_CAP := 40       # 走行継続カウンタの上限
const RUN_DECAY := 3      # ニュートラル時の走行カウンタ減衰/tick(離して押し直す反転の猶予)
const DASH_TAP_WINDOW := 12  # ダブルタップ受付窓(tick)。1回目の押し始めからこの間に2回目
const DASH_TICKS := 14       # ダッシュ持続tick(CA_DASH固有技)
const DASH_SPD_PCT := 175    # ダッシュ中の移動速度%
const JUMP_RISE_TICKS := 25
const JUMP_FALL_TICKS := 27
const PLAYER_HALF_W_PX := 8    # 体の半幅。ネット面へは体表面で止まる(めり込み防止)
# ノックバック/反動(push): 残りtickに比例した速度で滑り、線形減衰する。
# 量は重さ%で伸縮(重いキャラはどっしり、軽いキャラは飛ばされる)
const PUSH_UNIT_PX := 4      # 反動速度の基準(ジャスト反動で計28px級の後退)
const PUSH_DECAY := 8        # 速度換算の分母
const HIP_HOVER_TICKS := 36  # ヒップアタックの空中静止(回転)時間
const HIP_DROP_PX := 12    # ヒップアタック急降下の速度(px/tick)
const CLING_SLIDE_PX := 1  # 壁張り付きのずるずる降下速度(px/tick)

static func _jump_height_px(rank: int) -> int:
	return Chars.Profile.jump_height_px(rank)

static func _jump_ticks(rising: bool) -> int:
	var base := JUMP_RISE_TICKS if rising else JUMP_FALL_TICKS
	return base

static func _jump_gravity(height_px: int, ticks: int, rising: bool) -> int:
	var den := ticks * (ticks - 1) if rising else ticks * (ticks + 1)
	return FP.from_int(height_px * 2) / den

static func _step_player(p, input: int, cfg, team: int) -> void:
	var action_down: int = 1 if (input & IN_ACTION) != 0 else 0
	if p.burn > 0:
		p.burn -= 1
	if p.quake_stun > 0:
		p.quake_stun -= 1
		p.vx = 0
		return
	# 帽子投げの溜め中: 入力を一切受け付けず、その場で凍結(空中なら浮いたまま)。
	# 投げは強いがリスク=硬直を負う。溜め終了で_update_hatが帽子を発射する
	if p.throw > 0:
		p.vx = 0
		if p.on_ground == 0:
			p.vy = 0
		return
	# しりもち(butt-drop)中: 入力無効。ノックバックのvxを摩擦で減衰させ後ろへ滑る。
	# 空中なら落下し着地する。スタンより短い被弾リアクション
	if p.flinch > 0:
		p.flinch -= 1
		# 減衰: 地上は摩擦で早く止まる(3/4)、空中は抵抗が薄く吹っ飛び続ける(15/16)
		p.vx = p.vx * 3 / 4 if p.on_ground == 1 else p.vx * 15 / 16
		if p.on_ground == 0:
			if p.vy < 0:
				p.vy = p.vy / 2
			p.vy += cfg.gravity
		var fmin: int = 0
		var fmax: int = cfg.court_width
		if team == 0:
			fmax = cfg.net_x - cfg.net_half_w - FP.from_int(PLAYER_HALF_W_PX)
		else:
			fmin = cfg.net_x + cfg.net_half_w + FP.from_int(PLAYER_HALF_W_PX)
		p.x = clampi(p.x + p.vx, fmin, fmax)
		p.y += p.vy
		if p.y >= cfg.floor_y:
			p.y = cfg.floor_y
			p.vy = 0
			p.on_ground = 1
		if p.hit_cooldown > 0:
			p.hit_cooldown -= 1
		return
	# スタン中は入力無効(移動もジャンプも不可)。物理(重力・着地)は生きる
	if p.stun > 0:
		p.stun -= 1
		if action_down == 1 and p.stun_action_held == 0:
			p.stun = maxi(p.stun - cfg.stun_mash_bonus, 0)
			p.stun_mash_event += 1
		p.stun_action_held = action_down
		input = 0
	else:
		p.stun_action_held = action_down
	var in_dir: int = 0
	if input & IN_LEFT:
		in_dir -= 1
	if input & IN_RIGHT:
		in_dir += 1
	# 急ブレーキ(スキッド): 一定時間"走り続けた"後に逆方向を入れたときだけ、すぐ反転せず
	# 数tick旧方向へ滑って減速してから向きが変わる(マリオの"キキーッ"の間)。
	# 追尾の細かい左右振り(オシレーション)ではrunが溜まらず発動しない=制御を壊さない。
	# p.brake: 符号=滑る方向, 絶対値=残りtick(diveと同じ「表示層も読むヒント」方式)
	# 走行方向と継続を符号付きp.runで管理(符号=方向, 絶対値=継続tick)。
	# ニュートラルでは即0にせず徐々に減衰させる=「離して押し直す」反転も拾う猶予。
	var prev_run: int = p.run
	if p.on_ground == 0:
		p.run = 0
	elif in_dir == 0:
		p.run = signi(prev_run) * maxi(absi(prev_run) - RUN_DECAY, 0)
	elif signi(prev_run) == in_dir:
		p.run = in_dir * mini(absi(prev_run) + 1, RUN_CAP)
	elif p.brake == 0 and absi(prev_run) >= SKID_MIN_RUN:
		# 十分走った後の逆方向入力 → 急ブレーキ(旧方向へ滑ってから反転)
		p.brake = BRAKE_TICKS * signi(prev_run)
		p.run = 0
	else:
		p.run = in_dir  # 走り始め
	# ダブルタップダッシュ(固有技CA_DASH): 同方向の押し始めを窓内に2回で発動。
	# tap_dir=前tickの方向(エッジ検出)、tap_tick=窓の残り(符号=1回目の方向)。
	# ダッシュ中にジャンプすれば空中もダッシュ速度が乗る(ダッシュジャンプ)
	if p.dash > 0:
		p.dash -= 1
	var tap_edge: bool = in_dir != 0 and p.tap_dir == 0
	if tap_edge:
		if signi(p.tap_tick) == in_dir and Chars.has_ability(p.char_id, Chars.CA_DASH) \
				and p.on_ground == 1:
			p.dash = DASH_TICKS
			p.tap_tick = 0
		else:
			p.tap_tick = in_dir * DASH_TAP_WINDOW
	elif p.tap_tick != 0:
		p.tap_tick -= signi(p.tap_tick)
	p.tap_dir = in_dir
	# キャラ性能シート(全員100=標準なら従来と完全一致)
	var spd: int = cfg.move_speed * Chars.stat(p.char_id, "speed") / 100
	if p.dash > 0:
		spd = spd * DASH_SPD_PCT / 100
	if p.brake != 0 and p.on_ground == 1:
		var sdir: int = signi(p.brake)
		var rem: int = absi(p.brake)
		# 滑走距離%: 滑り速度に掛かる(距離=速度の積分なので距離も%で伸縮する)
		p.vx = sdir * spd * rem * Chars.stat(p.char_id, "slide") / (BRAKE_TICKS * 100)
		rem -= 1
		p.brake = sdir * rem  # 残りゼロで自動的にbrake=0=反転解禁
	else:
		p.brake = 0  # 空中やニュートラルではスキッド解除
		p.vx = in_dir * spd
	# 向き(face)をvxから更新。動いていない間は直前の向きを保持
	if p.vx > 0:
		p.face = 1
	elif p.vx < 0:
		p.face = -1
	# ノックバック/反動(push): 入力とは独立に体が押される。毎tick弱まる。
	# 地上でも空中でも効く(空中のジャスト反動もここで滑る)。
	# faceの後に足すので、押されても向きは変わらない(反動でのけぞる見た目は表示層)
	if p.push != 0:
		p.vx += signi(p.push) * FP.from_int(PUSH_UNIT_PX) * absi(p.push) / PUSH_DECAY
		p.push -= signi(p.push)
	if (input & IN_JUMP) and p.on_ground == 1 and not (input & IN_ABILITY1):
		# 上はジャンプ専用。Dは必殺技の方向モディファイアなので、
		# 上+Dだけは地上技判定まで接地を維持する。
		var height_px := _jump_height_px(Chars.rank(p.char_id, Chars.Profile.ABILITY_JUMP))
		var rise_ticks := _jump_ticks(true)
		p.vy = -_jump_gravity(height_px, rise_ticks, true) * rise_ticks
		p.on_ground = 0
	if p.on_ground == 0:
		# 可変ジャンプ: 上昇中に上キーを離すとその場で失速して落下に転じる
		# (毎tick半減の減衰。intの/2はゼロ方向切り捨てで決定論)
		if p.vy < 0 and not (input & IN_JUMP):
			p.vy = p.vy / 2
		var jump_height := _jump_height_px(Chars.rank(p.char_id, Chars.Profile.ABILITY_JUMP))
		if p.vy < 0:
			var up_ticks := _jump_ticks(true)
			p.vy += _jump_gravity(jump_height, up_ticks, true)
		else:
			var down_ticks := _jump_ticks(false)
			p.vy += _jump_gravity(jump_height, down_ticks, false)
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1
	# ジャンピングトス演出の残時間(符号=方向)。ゼロへ向かって減る
	if p.dive > 0:
		p.dive -= 1
	elif p.dive < 0:
		p.dive += 1
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w - FP.from_int(PLAYER_HALF_W_PX)
	else:
		min_x = cfg.net_x + cfg.net_half_w + FP.from_int(PLAYER_HALF_W_PX)
	# ヒップアタック(固有技CA_HIP): 空中で下+Dの明示入力により発動。
	# その後まっすぐ急降下。帽子所持への相乗りは廃止(技として独立)
	var want_hip: bool = p.on_ground == 0 and (input & IN_DOWN) != 0 \
			and (input & IN_ABILITY1) != 0 \
			and Chars.has_ability(p.char_id, Chars.CA_HIP) \
			and p.burnout_ticks == 0 \
			and p.drive_gauge >= cfg.drive_gauge_stock * 2
	if p.hip == 0 and want_hip:
		p.drive_gauge -= cfg.drive_gauge_stock * 2
		if p.drive_gauge == 0:
			p.burnout_ticks = cfg.burnout_recovery_ticks
			p.drive_recovery_progress = 0
		p.hip = HIP_HOVER_TICKS
	if p.hip > 0:
		p.vx = 0
		p.vy = 0
		p.hip -= 1
		if p.hip == 0:
			p.hip = -1  # 静止終了→急降下へ
	elif p.hip == -1:
		p.vx = 0
		p.vy = FP.from_int(HIP_DROP_PX)
	# 壁張り付き(固有技CA_CLING): 空中で外壁側へ押し付けると、壁を背にずるずる低速降下
	p.cling = 0
	if p.hip == 0 and p.on_ground == 0 \
			and Chars.has_ability(p.char_id, Chars.CA_CLING):
		var at_left: bool = team == 0 and (input & IN_LEFT) != 0 and p.x <= min_x
		var at_right: bool = team == 1 and (input & IN_RIGHT) != 0 and p.x >= max_x
		if at_left or at_right:
			p.vx = 0
			p.vy = FP.from_int(CLING_SLIDE_PX)
			p.cling = 1 if at_left else -1
	p.x = clampi(p.x + p.vx, min_x, max_x)
	p.y += p.vy
	if p.y >= cfg.floor_y:
		p.y = cfg.floor_y
		p.vy = 0
		p.on_ground = 1
		p.hip = 0
		p.cling = 0
