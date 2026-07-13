extends SceneTree

# 仮SEジェネレーター(表示層ツール。float可)。レトロ調の効果音を合成する。
# 使い方: tools\godot\Godot_v4.6-stable_win64_console.exe --headless --path . -s res://scripts/gen_sfx.gd
# 出力: assets/sfx/{hit,just,block,score}.wav
# 本番SEに差し替えるまでのつなぎ。音を変えたら再実行してWAVをコミットすること。

const RATE := 22050

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/sfx")
	_save("hit", _gen_hit())
	_save("just", _gen_just())
	_save("block", _gen_block())
	_save("score", _gen_score())
	print("sfx generated")
	quit()

func _save(name: String, samples: PackedFloat32Array) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, clampi(int(samples[i] * 32767.0), -32768, 32767))
	wav.data = b
	wav.save_to_wav("res://assets/sfx/%s.wav" % name)

func _gen_hit() -> PackedFloat32Array:
	# パン!と乾いた打撃: ノイズバースト+低い実音、指数減衰
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	var rng := 12345
	for i in n:
		rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(rng % 2000) / 1000.0 - 1.0
		var t := float(i) / RATE
		var env := exp(-t * 60.0)
		var tone := sin(TAU * 180.0 * t)
		out.append((noise * 0.55 + tone * 0.45) * env * 0.8)
	return out

func _gen_just() -> PackedFloat32Array:
	# キュイン!と抜ける快音: 上昇する矩形波+倍音
	var n := int(RATE * 0.14)
	var out := PackedFloat32Array()
	for i in n:
		var t := float(i) / RATE
		var freq := 500.0 + 1800.0 * (t / 0.14)
		var sq := 1.0 if sin(TAU * freq * t) > 0.0 else -1.0
		var hi := sin(TAU * freq * 2.0 * t)
		var env := exp(-t * 18.0) * minf(t * 200.0, 1.0)
		out.append((sq * 0.5 + hi * 0.3) * env * 0.8)
	return out

func _gen_block() -> PackedFloat32Array:
	# ドッ!と重い壁音: 低い矩形波の短打+クリック
	var n := int(RATE * 0.08)
	var out := PackedFloat32Array()
	for i in n:
		var t := float(i) / RATE
		var sq := 1.0 if sin(TAU * 110.0 * t) > 0.0 else -1.0
		var env := exp(-t * 45.0)
		out.append(sq * env * 0.85)
	return out

func _gen_score() -> PackedFloat32Array:
	# ピンポン!の二音チャイム(得点)
	var n := int(RATE * 0.30)
	var out := PackedFloat32Array()
	for i in n:
		var t := float(i) / RATE
		var freq := 880.0 if t < 0.13 else 1174.0
		var t0 := t if t < 0.13 else t - 0.13
		var env := exp(-t0 * 16.0) * minf(t0 * 300.0, 1.0)
		out.append(sin(TAU * freq * t) * env * 0.6)
	return out
