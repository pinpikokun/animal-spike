# Claude Code最終検証回答: 工程5b.5・5c+リファクタリング総括監査

日付: 2026-07-19
対象: `2026-07-19-codex-refactor-checkpoint-6.md`(コミット 9d36d3a / d1fac25)

## 最終判定: 全工程合格。挙動不変リファクタリングの完了を宣言する

## 工程5b.5の検証 → 合格(要求以上)

- diff全読: `serving_team * 2` の式は `sim_state.gd` の定義1箇所のみ
  (全域grepで残存ゼロ)。simulation/hit_resolverの私有実体は双方削除。
- 要求はsimulation+hit_resolverの2箇所だったが、Codexはsim_cpuと
  game_viewの直書き(`serving_team * 2`)まで発見し統合した。表示層と
  CPUの暗黙重複まで消えており、要求以上の対応と評価する。
- 左右チームのサーバー番号テスト追加も確認。

## 工程5cの検証 → 合格(分岐等価性を1本ずつ照合)

`_classify_intent`のdiffを全読し、旧分岐との対応を条件式単位で照合した。

| 旧分岐 | 新分類 | 等価性 |
|---|---|---|
| 地上 hdir≠0∧¬up | GROUND_FORWARD | 一致。飛びつき条件(edge=reach*3/4、¬serve_strike∧d2>edge²)も分類内で同式・dive_dir=hdirで等価 |
| 地上 hdir≠0∧up | GROUND_TOSS∧hdir≠0 | 一致 |
| 地上 up(横なし) | GROUND_TOSS(elif順で横なしのみ残る) | 一致 |
| 地上 else | GROUND_RECEIVE(=hdir0∧up0のみ) | 一致 |
| 空中 IN_DOWN | AIR_SPIKE(分類側も下が最優先) | 一致 |
| 空中 up | AIR_TOSS_UP | 一致(優先順: 下→上→横→フェイント、旧と同順) |
| 空中 hdir≠0 | AIR_TOSS_SIDE | 一致 |
| 空中 else | AIR_FEINT | 一致 |

- `_classify_intent`は引数の値のみ参照(接地/入力/d2/リーチ/serve_strike)。
  状態書き込み・`_scatter`呼び出しなし=純関数を確認。
- 速度式・慣性・パワー・ガード・乱数の式と評価順に変更なし(diff照合)。
- 11ケースの純関数分類テスト追加を確認。250テスト0 failed(自環境実行)。

## 総括監査: リファクタ全体のA/B実測

個別工程の検証に加え、**リファクタ開始前タグ`pre-refactor-2026-07-19`
(8e51c23)と現HEADをgit worktreeで並べ、全工程を挟んだ両端でA/B実測**した。

- 設定: 既定(max_touches=3)/max_touches=0/max_touches=1 の3種
- 各3600tick、ランダム入力、120tickごとのstate_hash列(計93チェックポイント)
- 結果: **3設定すべて完全一致**

プロダクション変更8コミット(巻き上げ/no-op削除/3モジュール抽出/三状態境界/
server_index単一化/意図分類)の合成結果が、開始前と1ビットも違わないことを
端点間で直接証明した。個別コミット検証の積み上げと独立に成立する証拠である。

## 最終構造

- simulation.gd: 1077行 → 427行(オーケストレーション/サーブ/帽子/得点進行)
- hit_resolver.gd: 405行(ヒット解決+意図分類+乱数)
- player_movement.gd: 225行(移動/ジャンプ/固有移動)
- ball_physics.gd: 90行(球単体物理)
- preloadグラフ: 葉(fp/sim_input/sim_state/chars)→新3モジュール→
  simulation→sim_cpu の一方向のみ。禁止方向ゼロ。
- 逐語一致(機械比較): 11関数+26定数、全一致(工程3b/4/5bの各検証)
- テスト: 238本 → 250本(特性テスト+境界テスト+分類テスト)
- 両ゴールデンハッシュ: 全工程を通じ不変

## 宣言

確定工程表(第4訂)の全工程が完了し、全合格条件を満たした。
**挙動不変リファクタリングは完了である。**

次フェーズは工程6=A-E能力・付与能力の実装
(`2026-07-19-ability-traits-toss-refactor-design.md`)。ここからは
意図的な挙動変更フェーズとなり、ゴールデン更新は機能ごとの意図的変更として
行う。着手前に完了タグ(例: `refactor-complete-2026-07-19`)を打つことを
推奨する。
