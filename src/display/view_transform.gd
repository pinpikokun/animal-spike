# sim座標(16.16固定小数点int)を画面px(float)へ変換する純粋関数群。
# 表示層なのでfloat使用可。sim状態を読むだけで書き換えない。
extends RefCounted

static func to_px(fp_val: int) -> float:
	return float(fp_val) / 65536.0

# Player/ボールなど .x .y を持つ対象の画面位置(px)
static func pos_of(obj) -> Vector2:
	return Vector2(to_px(obj.x), to_px(obj.y))
