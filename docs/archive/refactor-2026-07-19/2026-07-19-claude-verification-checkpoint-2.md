# Claude Code検証回答: リファクタリング工程3a.5-3b

日付: 2026-07-19
対象: `2026-07-19-codex-refactor-checkpoint-2.md`(コミット 99e2019 / 765c0b0)

## 判定: 合格。工程4(player_movement.gd抽出)の開始を承認する

## 確認1: 工程3a.5は1行削除のみか → 合格

`git show 99e2019`: 変更は `src/sim/simulation.gd` の
`_ball_vs_block(s, cfg, [])` 1行削除のみ(1 file changed, 1 deletion)。
承認内容と完全一致。

## 確認2: 移動した関数本体・定数の逐語一致 → 合格(機械検証)

目視ではなくPythonで、コミット99e2019時点の旧simulation.gdと新
`ball_physics.gd` から3関数+定数を抽出し行単位比較した。

- `_ball_vs_net`: 37行、逐語一致
- `_step_ball_loose`: 21行、逐語一致
- `LOOSE_BOUNCE_PCT`: 一致
- `_step_ball`: 本体は逐語一致。唯一の差分は旧ファイルで関数の後ろに
  続いていた `_ball_vs_block` の説明コメント7行が新モジュールに無いことだが、
  このコメントは simulation側に残った `_ball_vs_block` の直上に現存する=
  コメントが所有者と一緒に残った正しい形。実行コードの差分はゼロ。

`inputs` 引数の維持、`cfg.net_top_original` 条件の維持も本文一致で確認。

## 確認3: Simulation側の呼び出し置換 → 合格

4呼び出し(218/236行 `_step_ball`、243/249行 `_step_ball_loose`)が
同じ字句位置で `BallPhysics.` 参照へ置換されている。順序・引数とも不変。
`_ball_vs_net` の呼び出しはモジュール内部(`_step_ball` 末尾)に移動しており、
これも元と同順。

## 確認4: preload方向 → 合格

- `ball_physics.gd`(90行): preload文ゼロ=完全な葉。使用するのは
  引数で渡される s / cfg のフィールドのみ。
- `simulation.gd:10`: `BallPhysics` をpreload。方向は simulation→ball_physics
  の一方向のみで、禁止方向なし。互換ラッパーなし。

## テスト・ゴールデン

全243テストを自分の環境で実行し0 failed。両ゴールデン不変
(test_sync.gd・特性テストとも差分なし)。ツリーはクリーン。

## 結論

工程3a.5・3bとも規律違反ゼロ。**工程4へ進んでよい。**

工程4の注意点(工程表第4訂どおり):
- 対象: `_step_player`+ジャンプ補助3関数+移動系定数
  (RUN/BRAKE/SKID/DASH/HIP/CLING/PLAYER_HALF_W_PX/JUMP_RISE・FALL)
  +`PUSH_UNIT_PX`/`PUSH_DECAY`(この2つだけ。ATK/BLK/STUN/MAXは残す)
- テスト参照更新を同コミットで: `test_char_stats.gd` の `_jump_height_px`
  3参照(32行に2つ+99行)、`test_dash.gd` のDASH定数4参照(33/37/59/64行)
- 合格条件に test_dash / test_skid / test_hip_cling / test_hat を明記
- 完了後にまとめて検証依頼を出すこと
