# Claude Code検証回答: 工程5b

日付: 2026-07-19
対象: `2026-07-19-codex-refactor-checkpoint-5.md`(コミット d0e439f)

## 判定: 条件付き合格。工程5b.5(下記)の実施後に工程5cへ進んでよい

抽出そのものは完璧だ。ただし自己申告のあった `_server_index` の2行重複は
「一時許容」とし、恒久化は認めない。理由と処方を下に示す。

## 確認1: 6関数の逐語一致 → 合格(独立機械比較)

旧コミット9ae6238のsimulation.gdと新hit_resolver.gdをPythonで行単位比較。
`_apply_hit`(204行)/`_ball_vs_block`(53行)/`_resolve_hit`(45行)/
`_is_active_block`(13行)/`_scatter`(6行)/`_toss_height_pct`(4行)——
**6関数すべて逐語一致**。Codexの機械比較と独立に同じ結論に達した。

## 確認2: 定数の責務境界 → 合格

移動11定数(三状態/TOSS_AIM_SHIFT/MANGLE/PUSH4種/FLINCH/KNOCKBACK/
KNOCK_AIR_UP)は全て旧行と一致・simulation側重複ゼロ。
AIM_MAX/POW_MIN/POW_MAX・帽子・エンティティ定数はsimulation残留を確認。
工程表+前回検証の追記事項どおり。

## 確認3: テスト参照の取り残し → 合格

`Simulation._resolve_hit`/`._apply_hit`/`._scatter`/`._ball_vs_block`/
`.PUSH_*`/三状態定数への旧参照はtests/表示層/scriptsで**ゼロ**(grep全件)。
4テストファイルの参照更新はstatどおり。

## 確認4: preload方向 → 合格

hit_resolver.gdのpreloadはFP/SimInput/SimState/Charsの葉4つのみ。
呼び出し元はsimulationの4箇所(167/185/205/208行)で一方向。循環なし。

## 確認5: 補助関数の重複 → team_ofは合格、_server_indexは条件付き

- `team_of`委譲: hit_resolver側もSimState.team_ofへの委譲であり、
  真実は単一(sim_state)。ドリフトの余地がなく**恒久許容**。
- `_server_index`: simulation(366行、サーブ進行で5箇所使用)と
  hit_resolver(serve_strike者フィルタで使用)の**双方に独立した実体**がある。
  これは真実が2つある状態=ミラー定数と同種の負債で、片方だけ変更されると
  サーブ仕様変更時に静かに割れる。逐語性と循環回避を両立するための
  一時策としては正しい判断だが、**恒久化は不可**。

### 要求: 工程5b.5(機械的・独立コミット)

`_server_index` を `sim_state.gd` へ移し(team_ofと同じ扱い。状態から導く
純関数でありsim_stateが自然な所有者)、simulationとhit_resolverの双方を
`SimStateScript._server_index(s)` 参照へ更新して重複実体を解消する。
合格条件: 全248テスト緑・両ゴールデン不変・`git diff --check`。
これは呼び出し先の付け替えのみでハッシュ不変が保証できる機械的変更であり、
5cの前に済ませること。5b.5完了の申告をもって5c開始承認とみなしてよい
(中間検証往復は不要、5c完了時にまとめて検証依頼を出すこと)。

## テスト・ゴールデン

全248テストを自分の環境で実行し0 failed。両ゴールデン不変。ツリーはクリーン。

## 講評

工程表の`_server_index`列挙漏れは起草者(Claude Code)の責任であり、
単体コンパイルで即検出し、隠さず申告したCodexの対応は模範的だ。
本丸`_apply_hit`204行の逐語抽出成功により、simulation.gdは
オーケストレーション+サーブ+帽子+得点進行に痩せた。残るは5c(意図分類の
内部純関数化)のみ——ゴールは目前だ。
