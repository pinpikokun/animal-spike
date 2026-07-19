# Claude Code検証依頼: リファクタリング工程4

日付: 2026-07-19

## 対象コミット

- `12be781`: `player_movement.gd` 抽出

## 抽出内容

新規 `src/sim/player_movement.gd` へ次を移した。

- `_step_player`
- `_jump_height_px`
- `_weight_time_pct`
- `_jump_ticks`
- `_jump_gravity`
- 移動定数: `BRAKE_TICKS`、`SKID_MIN_RUN`、`RUN_CAP`、`RUN_DECAY`
- ダッシュ定数: `DASH_TAP_WINDOW`、`DASH_TICKS`、`DASH_SPD_PCT`
- ジャンプ・当たり幅定数: `JUMP_RISE_TICKS`、`JUMP_FALL_TICKS`、`PLAYER_HALF_W_PX`
- 固有移動定数: `HIP_HOVER_TICKS`、`HIP_DROP_PX`、`CLING_SLIDE_PX`
- push定数: `PUSH_UNIT_PX`、`PUSH_DECAY` の2つだけ

`PUSH_ATK_TICKS`、`PUSH_BLK_TICKS`、`PUSH_MAX_TICKS`、`PUSH_STUN_TICKS` はヒット側の所有としてSimulationへ残した。

## 依存方向

`player_movement.gd` のpreloadは次の3つだけ。

- `fp.gd`
- `sim_input.gd`
- `chars.gd`

SimulationやBallPhysicsを参照せず、SimulationからPlayerMovementへの一方向である。

## Simulation側

`_step_players_and_hits` 内の呼び出しを、同じ位置・引数のまま次へ置換した。

`PlayerMovement._step_player(state.players[i], input, cfg, team_of(i))`

旧関数・旧補助関数・移動済み定数・互換wrapperはSimulationに残していない。

## テスト参照更新

同一コミットで次を更新した。

- `test_char_stats.gd`: `_jump_height_px` 3参照を `PlayerMovement` へ
- `test_dash.gd`: DASH定数4参照を `PlayerMovement` へ

Simulationに互換定数は残していない。

## 逐語確認

抽出前コミット `53289fb` の `simulation.gd` から `_step_player` を抽出し、新しい `player_movement.gd` の同関数と行単位で機械比較した。末尾空行を除いて完全一致した。

作業途中に行末コメント4つの欠落を機械比較で検出したため、コミット前にすべて復元して再比較した。実行コードだけでなく関数内コメントも一致している。

## 検証結果

- 全243テスト: 0 failed
- `test_dash`: 全6テスト成功
- `test_skid`: 全3テスト成功
- `test_hip_cling`: 全5テスト成功
- `test_hat`: 全5テスト成功
- 既存ゴールデン: 不変
- 第2ゴールデン: 不変
- `git diff --check`: 成功
- 作業ツリー: clean

テスト出力中のinvalid config用ERRORは意図的に発生させる既存テストであり、スイート結果は0 failed。

## Claude Codeへの確認事項

1. `_step_player` と4補助関数が旧版と逐語一致するか。
2. 移動定数の範囲が工程表どおりで、PUSH定数が2つだけか。
3. テスト参照7箇所が漏れなく更新されているか。
4. preload方向が葉規律を守り、互換wrapper・重複定数がないか。
5. 問題がなければ工程5aの三状態ヒット境界準備への開始可否を明言してほしい。
