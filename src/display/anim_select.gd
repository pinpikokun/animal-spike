# プレイヤーのsim状態(int)からアニメ名・向きを選ぶ純粋関数。
# 状態を読むだけ(副作用なし)。表示層だがテクスチャ非依存なのでヘッドレステスト可能。
extends RefCounted

# 優先順位: 被弾 > 横っ飛び > 固有動作 > 空中打撃 > 空中 > 接地実打
#         > レシーブ構え > 移動 > 静止
static func anim_for(p) -> String:
	if p.stun > 0:
		return "stun"
	if p.flinch > 0:
		return "hurt"
	if p.dive != 0:
		return "dive"
	if p.hip != 0:
		return "hipdrop"
	if p.cling != 0:
		return "wallcling"
	if p.on_ground == 0:
		if p.hit_cooldown > 0:
			return "attack"
		return "jump"
	if p.brake != 0:
		return "brake"
	if p.hit_cooldown > 0:
		# 地上のトス/レシーブ実打は原作セル8,9。前トスだけ専用姿勢を残す。
		if p.hit_kind == 2:
			return "toss_fwd"
		return "ground_swing"
	if p.on_ground == 1 and p.receive_stance != 0:
		return "receive_stance"
	if p.vx != 0:
		return "run"
	return "idle"

# 原作セル11,10,7,0の4コマをsim経過から固定選択する。
static func dive_frame_for(p) -> int:
	return clampi(int(p.dive_age_ticks / 2), 0, 3)

static func dive_rotation_for(p) -> float:
	return float(signi(p.dive)) * 0.9

# チーム0(左)は右向き=反転なし、チーム1(右)は左向き=反転
static func flip_for_team(team: int) -> bool:
	return team == 1
