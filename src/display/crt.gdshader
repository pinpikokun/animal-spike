// CRTスキャンライン。整数倍拡大後の物理ピクセルに対して走る
// ドット1行(=scale_px物理行)につき暗線1本。intensity 0でほぼ素の絵
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float scale_px = 2.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	// 各ドット行の最初の物理行を暗くする
	float dark = 1.0 - step(0.999, mod(FRAGCOORD.y, scale_px));
	float factor = 1.0 - intensity * 0.55 * dark;
	COLOR = vec4(col.rgb * factor, col.a);
}
