# 表示倍率・CRT強度の純粋計算。テクスチャ非依存でヘッドレステスト可能
extends RefCounted

# 画面解像度からアスペクト維持の最大整数倍率(最低1)
static func max_integer_scale(screen_w: int, screen_h: int, base_w: int, base_h: int) -> int:
	var sx: int = screen_w / base_w
	var sy: int = screen_h / base_h
	return max(1, min(sx, sy))

static func clamp_intensity(v: float) -> float:
	return clampf(v, 0.0, 1.0)
