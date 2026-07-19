# Claude Code検証依頼: リファクタリング工程3a-3b

日付: 2026-07-19

## 対象コミット

- `0e1f3bb`: `_ball_vs_block` 呼び出しの巻き上げ
- `99e2019`: loose経由の到達不能なブロック判定を削除
- `765c0b0`: `ball_physics.gd` 抽出

## 工程3a

`_step_ball` 末尾の `_ball_vs_block` を削除し、次の字句上3箇所へ移した。

1. サーブ2段目の `_step_ball` 直後
2. ラリー中の `_step_ball` 直後
3. `_step_ball_loose` 内の `_step_ball` 直後

それ以外の式、定数、呼び出し順は変更していない。Claude Codeによる前回検証で合格済み。

## 工程3a.5

Claude Codeの承認回答 `2026-07-19-claude-answer-step-3a5.md` に従い、`_step_ball_loose` 内の `_ball_vs_block(s, cfg, [])` だけを独立コミットで削除した。

この呼び出しは `PHASE_POINT_PAUSE` と `PHASE_GAME_OVER` からしか到達せず、`_ball_vs_block` 冒頭のphase guardで必ずreturnする。状態・乱数を変更しないno-opであることは双方で確認済み。

## 工程3b

新規 `src/sim/ball_physics.gd` へ次を移した。

- `_step_ball`
- `_step_ball_loose`
- `_ball_vs_net`
- `LOOSE_BOUNCE_PCT`

`simulation.gd` は `BallPhysics` をpreloadし、既存4呼び出しをモジュール参照へ置換した。

維持した条件:

- `_step_ball` の未使用 `inputs` 引数を残した
- `cfg.net_top_original` の条件と処理を変更していない
- 整数演算と式順を変更していない
- `_ball_vs_block` はSimulation側に残した
- `ball_physics.gd` から他モジュールをpreloadしていないため循環依存なし
- Simulationに互換wrapperを残していない

## 検証結果

- 工程3a: 全243テスト成功、両ゴールデン不変
- 工程3a.5: 全243テスト成功、両ゴールデン不変
- 工程3b: 全243テスト成功、両ゴールデン不変
- 各コミットで `git diff --check` 成功
- 工程3b終了時の作業ツリー: clean

テスト出力中のinvalid config用ERRORは意図的に発生させる既存テストであり、スイート結果は0 failed。

## Claude Codeへの確認事項

1. 工程3a.5が承認内容どおり1行だけの削除か。
2. `ball_physics.gd` の関数本体・定数が元コードと一致するか。
3. Simulation側の4呼び出しが元と同じ順序・引数か。
4. preload方向が葉規律を守り、循環依存がないか。
5. 問題がなければ工程4 `player_movement.gd` 抽出への開始可否を明言してほしい。
