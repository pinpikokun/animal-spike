# int演算のみ。プレイヤーの移動、ジャンプ、硬直中の物理を扱う。
extends RefCounted

const FP := preload("res://src/sim/fp.gd")
const SimInput := preload("res://src/sim/sim_input.gd")
const Chars := preload("res://src/sim/chars.gd")
const JumpArc := preload("res://src/sim/jump_arc.gd")
const CombatResources := preload("res://src/sim/combat_resources.gd")
const SimStateScript := preload("res://src/sim/sim_state.gd")
const PlayerStatus := preload("res://src/sim/player_status.gd")

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
const PLAYER_HALF_W_PX := 8    # 体の半幅。ネット面へは体表面で止まる(めり込み防止)
# ノックバック/反動(push): 残りtickに比例した速度で滑り、線形減衰する。
# 量は重さ%で伸縮(重いキャラはどっしり、軽いキャラは飛ばされる)
const PUSH_UNIT_PX := 4      # 反動速度の基準(ジャスト反動で計28px級の後退)
const PUSH_DECAY := 8        # 速度換算の分母
const HIP_HOVER_TICKS := 36  # ヒップアタックの空中静止(回転)時間
const HIP_DROP_PX := 12    # ヒップアタック急降下の速度(px/tick)
const CLING_SLIDE_PX := 1  # 壁張り付きのずるずる降下速度(px/tick)

static func _step_player(p, input: int, cfg, team: int,
		state_tick: int = 0, actor: int = 0, rng: int = 0) -> void:
	var status_locked: bool = \
		(p.stun_ticks | p.bubble_ticks | p.shock_ticks | p.burn) != 0
	if status_locked:
		if PlayerStatus.step(p, cfg, team, state_tick, actor, rng):
			return
		# 最終tick中にタイマーが0になっても、生入力は次tickまで通さない。
		input = 0
	_step_player_unlocked(p, input, cfg, team)

static func _step_player_unlocked(p, input: int, cfg, team: int) -> void:
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
	if p.dive_recovery_ticks > 0:
		p.dive_recovery_ticks -= 1
		p.vx = 0
		if p.dive_recovery_ticks == 0:
			p.dive_resource_mode = SimStateScript.DIVE_NONE
		return
	var stance_lock: bool = p.stance_active != 0 \
		or p.stance_exit_recovery_ticks > 0
	if stance_lock:
		input &= ~(IN_LEFT | IN_RIGHT | IN_JUMP | IN_ABILITY1)
		p.vx = 0
		p.brake = 0
		p.run = 0
		p.dash = 0
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w - FP.from_int(PLAYER_HALF_W_PX)
	else:
		min_x = cfg.net_x + cfg.net_half_w + FP.from_int(PLAYER_HALF_W_PX)
	if p.dive != 0:
		p.dive_age_ticks += 1
		var dive_speed: int = cfg.dive_receive_speed
		if p.dive_resource_mode == SimStateScript.DIVE_WEAK:
			dive_speed = dive_speed * cfg.dive_burnout_distance_pct / 100
		p.vx = p.dive * dive_speed if p.dive_contact_ticks > 0 else 0
		p.vy += cfg.gravity
		p.x = clampi(p.x + p.vx, min_x, max_x)
		p.y += p.vy
		if p.hit_cooldown > 0:
			p.hit_cooldown -= 1
		if p.y >= cfg.floor_y:
			if p.dive_resource_mode == SimStateScript.DIVE_WEAK:
				p.dive_recovery_ticks = p.dive_age_ticks \
					* (cfg.dive_burnout_recovery_pct - 100) / 100
			p.y = cfg.floor_y
			p.vy = 0
			p.on_ground = 1
			p.dive = 0
			p.dive_contact_ticks = 0
			p.dive_age_ticks = 0
			if p.dive_recovery_ticks == 0:
				p.dive_resource_mode = SimStateScript.DIVE_NONE
		return
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
		p.vy = JumpArc.launch_velocity(Chars.jump_height_px(p.char_id))
		p.on_ground = 0
	if p.on_ground == 0:
		# 可変ジャンプ: 上昇中に上キーを離すとその場で失速して落下に転じる
		# (毎tick半減の減衰。intの/2はゼロ方向切り捨てで決定論)
		p.vy = JumpArc.advance_velocity(p.vy, (input & IN_JUMP) != 0)
	if p.hit_cooldown > 0:
		p.hit_cooldown -= 1
	# ヒップアタック(固有技CA_HIP): 空中で下+Dの明示入力により発動。
	# その後まっすぐ急降下。帽子所持への相乗りは廃止(技として独立)
	var want_hip: bool = p.on_ground == 0 and (input & IN_DOWN) != 0 \
			and (input & IN_ABILITY1) != 0 \
			and Chars.has_ability(p.char_id, Chars.CA_HIP) \
			and CombatResources.can_pay(p, CombatResources.special_drive_cost(cfg))
	if p.hip == 0 and want_hip:
		CombatResources.spend_committed(
			p, CombatResources.special_drive_cost(cfg), cfg)
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


# CPUが「この入力を出した同tickの接触位置」を読むための決定論的な予測窓口。
# 通常の行動可能な空中選手を対象にし、_step_player_unlockedの入力移動、可変ジャンプ、
# push、hip、cling、コート境界を同じ順序で反映する。状態自体は変更しない。
static func predict_air_contact_positions(
		p, inputs: Array[int], cfg, team: int) -> Array[Vector2i]:
	var dash_after: int = maxi(p.dash - 1, 0)
	var speed: int = cfg.move_speed * Chars.stat(p.char_id, "speed") / 100
	if dash_after > 0:
		speed = speed * DASH_SPD_PCT / 100
	var min_x: int = 0
	var max_x: int = cfg.court_width
	if team == 0:
		max_x = cfg.net_x - cfg.net_half_w - FP.from_int(PLAYER_HALF_W_PX)
	else:
		min_x = cfg.net_x + cfg.net_half_w + FP.from_int(PLAYER_HALF_W_PX)
	var push_vx: int = 0
	if p.push != 0:
		push_vx = signi(p.push) * FP.from_int(PUSH_UNIT_PX) \
			* absi(p.push) / PUSH_DECAY
	var can_cling: bool = Chars.has_ability(p.char_id, Chars.CA_CLING)
	var result: Array[Vector2i] = []
	for input in inputs:
		var in_dir: int = 0
		if input & IN_LEFT:
			in_dir -= 1
		if input & IN_RIGHT:
			in_dir += 1
		var vx: int = in_dir * speed + push_vx
		var vy: int = JumpArc.advance_velocity(p.vy, (input & IN_JUMP) != 0)
		var hip_after: int = p.hip
		if hip_after > 0:
			vx = 0
			vy = 0
			hip_after -= 1
		elif hip_after == -1:
			vx = 0
			vy = FP.from_int(HIP_DROP_PX)
		if hip_after == 0 and can_cling:
			var at_left: bool = team == 0 \
				and (input & IN_LEFT) != 0 and p.x <= min_x
			var at_right: bool = team == 1 \
				and (input & IN_RIGHT) != 0 and p.x >= max_x
			if at_left or at_right:
				vx = 0
				vy = FP.from_int(CLING_SLIDE_PX)
		var next_x: int = clampi(p.x + vx, min_x, max_x)
		var next_y: int = p.y + vy
		if next_y >= cfg.floor_y:
			next_y = cfg.floor_y
		result.append(Vector2i(next_x, next_y))
	return result


static func predict_air_contact_position(p, input: int, cfg, team: int) -> Vector2i:
	return predict_air_contact_positions(p, [input], cfg, team)[0]
