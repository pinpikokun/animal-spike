# int演算のみ。球単体の移動、壁、ネット、自由球減衰を扱う。
extends RefCounted

const LOOSE_BOUNCE_PCT := 50   # ポーズ中の床バウンド反発%(勢い半分で早く落ち着く)

static func wall_reflect_vx(vx: int, cfg) -> int:
	return -vx * cfg.wall_bounce_num / cfg.ball_bounce_den

static func _step_ball(s, cfg, inputs: Array[int] = []) -> void:
	var prev_x: int = s.ball_x
	s.ball_vy += cfg.gravity
	s.ball_x += s.ball_vx
	s.ball_y += s.ball_vy
	# 回転は横の勢いに比例して累積する(真上のトスはほぼ無回転、前へ飛ぶほど回る)
	s.ball_spin += s.ball_vx
	var left: int = cfg.ball_radius
	var right: int = cfg.court_width - cfg.ball_radius
	var hit_wall := false
	if s.ball_x < left:
		s.ball_x = left + (left - s.ball_x)
		s.ball_vx = wall_reflect_vx(s.ball_vx, cfg)
		hit_wall = true
	elif s.ball_x > right:
		s.ball_x = right - (s.ball_x - right)
		s.ball_vx = wall_reflect_vx(s.ball_vx, cfg)
		hit_wall = true
	if hit_wall and s.ball_power == 1:
		s.ball_vy = s.ball_vy * cfg.wall_bounce_num / cfg.ball_bounce_den
		s.ball_power = 0
	# 床の反射はしない。RALLY中の床接触は_check_floor_pointが得点として処理する。
	# 天井の反射もしない(原作準拠): ボールは画面上端を突き抜けて出てよい。重力で必ず
	# 戻るため見失わない。跳ね返るのは左右の壁だけ。
	_ball_vs_net(s, cfg, prev_x)

static func _step_ball_loose(s, cfg) -> void:
	# ポーズ中・勝敗確定後のボール。得点処理はせず、床で減衰バウンドして転がる
	_step_ball(s, cfg)
	var floor_limit: int = cfg.floor_y - cfg.ball_radius
	if s.ball_y > floor_limit:
		s.ball_y = floor_limit - (s.ball_y - floor_limit)
		if s.ball_vy > 0:
			# 床バウンドは勢い半分(原作の「着地したら死ぬ球」の感触に寄せた減衰)
			s.ball_vy = -s.ball_vy * LOOSE_BOUNCE_PCT / 100
			# 乗算減衰だけだと閾値近傍で微小バウンドが長く続く速度帯がある(共振、
			# レビュー指摘: 特定入射で数千tick跳ね続けた)。反発のたびに固定量も
			# 減衰させ、有限バウンド回数で必ず閾値を割らせる
			s.ball_vy = mini(s.ball_vy + cfg.ball_rest_speed / 4, 0)
		# 床接触のたびに横速度も減衰(転がって自然に止まる)
		s.ball_vx = s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
		# 微小な跳ね/転がりは静止させ床にスナップ(小刻みな跳ねの継続を断つ)
		if absi(s.ball_vy) < cfg.ball_rest_speed:
			s.ball_vy = 0
			s.ball_y = floor_limit
		if absi(s.ball_vx) < cfg.ball_rest_speed:
			s.ball_vx = 0

static func _ball_vs_net(s, cfg, prev_x: int) -> void:
	var net_left: int = cfg.net_x - cfg.net_half_w - cfg.ball_radius
	var net_right: int = cfg.net_x + cfg.net_half_w + cfg.ball_radius
	var below_top: bool = s.ball_y > cfg.net_top_y
	var was_left: bool = prev_x < cfg.net_x
	var is_left: bool = s.ball_x < cfg.net_x
	if below_top:
		# ネット下部は壁。来た側へ押し返す
		if s.ball_x >= net_left and s.ball_x <= net_right:
			# 減衰反射しつつ最低反発速度を保証(ネットに当たったら必ず少し跳ね返る)
			if was_left:
				s.ball_x = net_left - (s.ball_x - net_left)
				if s.ball_vx > 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
				s.ball_vx = mini(s.ball_vx, -cfg.net_repel)
			else:
				s.ball_x = net_right + (net_right - s.ball_x)
				if s.ball_vx < 0:
					s.ball_vx = -s.ball_vx * cfg.ball_bounce_num / cfg.ball_bounce_den
				s.ball_vx = maxi(s.ball_vx, cfg.net_repel)
	elif s.ball_vy > 0 \
			and s.ball_x >= net_left and s.ball_x <= net_right \
			and s.ball_y >= cfg.net_top_y - cfg.ball_radius:
		# 原作式ネットイン: 上端(白帯)に当たると縦の勢いが半減して跳ね、
		# ネットから離れる向きへ押し出される=ポトリと落ちる緊張感
		s.ball_y = cfg.net_top_y - cfg.ball_radius
		s.ball_vy = -s.ball_vy / 2
		var out_dir: int = -1 if is_left else 1
		if s.ball_vx * out_dir < cfg.net_repel / 2:
			s.ball_vx = out_dir * cfg.net_repel / 2
		if was_left != is_left:
			s.touches = 0
			s.serve_flight = 0
			_clear_ghost_on_opponent_entry(s, is_left)
	elif was_left != is_left:
		# ネット上空を越えた: 攻守交代なのでタッチ数リセット。サーブ打球も渡り切り
		s.touches = 0
		s.serve_flight = 0
		_clear_ghost_on_opponent_entry(s, is_left)

static func _clear_ghost_on_opponent_entry(s, is_left: bool) -> void:
	var entered_team: int = 0 if is_left else 1
	if s.ball_ghost == 1 and s.last_touch_team >= 0 and entered_team != s.last_touch_team:
		s.ball_ghost = 0
