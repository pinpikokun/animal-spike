# プレイヤーのsim状態(int)からアニメ名・向きを選ぶ純粋関数。
# 状態を読むだけ(副作用なし)。表示層だがテクスチャ非依存なのでヘッドレステスト可能。
extends RefCounted

# 優先順位: スタン=hurt > 空中で打撃=attack > 空中=jump > 接地ヒット硬直=crouch
#         > 移動=run > 静止=idle
static func anim_for(p) -> String:
	if p.stun > 0:
		return "hurt"
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
		# 地上ヒット: 前トス(横のみ=hit_kind2)以外の上げ系はすべてトス扱い。
		# ニュートラル受けも球は上へ上がる=見た目はトスなのでtossに寄せる
		if p.hit_kind == 2:
			return "toss_fwd"
		return "toss"
	if p.vx != 0:
		return "run"
	return "idle"

# チーム0(左)は右向き=反転なし、チーム1(右)は左向き=反転
static func flip_for_team(team: int) -> bool:
	return team == 1
