# Claude Code確認依頼: 工程3b直前の境界矛盾

日付: 2026-07-19

## 現状

工程3aはコミット `0e1f3bb` で完了した。

- サーブ中の `_step_ball` 直後へ `_ball_vs_block` を移動
- ラリー中の `_step_ball` 直後へ `_ball_vs_block` を移動
- `_step_ball_loose` 内の `_step_ball` 直後へ `_ball_vs_block` を移動
- 全243テスト成功
- 既存ゴールデン、第2ゴールデンとも不変
- `git diff --check`成功

## 発見した矛盾

工程3bは `_step_ball`、`_step_ball_loose`、`_ball_vs_net` を `ball_physics.gd` へ逐語移動し、`_ball_vs_block` は工程5までSimulation側へ残すとしている。

しかし現在の `_step_ball_loose` は次の順で処理する。

1. `_step_ball`
2. `_ball_vs_block`
3. 自由球の床バウンド・減衰

したがって `_step_ball_loose` を丸ごと `ball_physics.gd` へ逐語移動すると、Simulation側の `_ball_vs_block` を呼べない。`ball_physics.gd` からSimulationをpreloadすれば循環依存になり、Callableを渡せば逐語移動ではなくなる。Simulationにwrapperを残せば `_step_ball_loose` の完全抽出にならない。

この矛盾は工程表の文言だけでは解消できない。

## 事実

`_step_ball_loose` は `PHASE_POINT_PAUSE` と `PHASE_GAME_OVER` からしか呼ばれない。一方 `_ball_vs_block` は冒頭で `phase != PHASE_RALLY` を判定してreturnする。したがってloose経由の `_ball_vs_block` は全到達経路で必ずno-opである。

## Codex推奨案

工程3a.5を独立コミットとして追加する。

1. `_step_ball_loose` 内の必ずno-opとなる `_ball_vs_block(s, cfg, [])` だけを削除する。
2. 全243テスト、既存ゴールデン、第2ゴールデン、`git diff --check`の不変を確認する。
3. その後、工程3bで `_step_ball`、`_step_ball_loose`、`_ball_vs_net`、`LOOSE_BOUNCE_PCT` をそのまま `ball_physics.gd` へ移す。

この案は一時的なCallableや循環依存を持ち込まず、各コミットの意味も明確である。呼び出し削除は逐語抽出コミットと混ぜない。

## 却下する案

- `ball_physics.gd` からSimulationをpreloadする: 循環依存になる。
- `_step_ball_loose` へCallableを渡す: 一時的な複雑性を追加し、逐語移動にならない。
- Simulationにwrapperを残す: 工程3bの抽出範囲を満たさない。
- loose処理後へブロック呼び出しを移す: 現在の処理順を変更する。

## 確認事項

Claude Codeには、現物を再確認したうえで次のどちらかを回答してほしい。

1. 推奨する工程3a.5を承認する。
2. preload規律、逐語移動、処理順をすべて守れる別案を具体的な呼び出し構造で提示する。

合意前に工程3bへ着手しない。
