# #83 シミュレーション性能ゲート 実装計画

**Goal:** 正規テスト入口で、ロールバック再計算と3候補空中仮想打球の大幅な性能退行を止める。

**Design:** 通常ユニットテスト1件で、SimRoot担当範囲のstep、復元、16コマ下限見積り、
政策3の3候補ホットパスを反復計測する。5サンプルの最小値で合否を決め、中央値も1行出力する。

**Approved design:** `docs/superpowers/specs/2026-07-29-83-performance-gate-design.md`
309行、SHA-256 `1697da8335387a704ba741bacfae04127bc6b3001e4ea414f6d41c52befee1af`

## Task 1: 設計契約と残リスクを記録する

**Files:**
- Add: `docs/superpowers/specs/2026-07-29-83-performance-gate-design.md`
- Add: `docs/superpowers/plans/2026-07-29-83-performance-gate.md`
- Add: `docs/tasks/111.md`
- Modify: `docs/remaining-tasks.md`

1. 設計書の行数とSHA-256を承認値と照合する。
2. 低速PCの巻き戻し上限とsnapshot最適化を#111としてP1へ登録する。
3. 設計、計画、追跡課題だけをコミットする。

## Task 2: 性能ゲートをTDDで追加する

**Files:**
- Add: `tests/unit/test_zz_performance.gd`

1. `test_` 関数が正確に1個の性能テストを作る。
2. 決定的な保存済み入力、全選手最強CPU、実ロスターでstepを5サンプル測る。
3. step上限を一時的に1nsとして全件が赤になることを確認する。
4. 承認上限230,000nsへ戻し、全件が494件で緑になることを確認する。
5. 1 nominal stepでtickとsnapshot保存を2回行い、stepが赤になることを確認して戻す。
6. policy 2、3候補非空、期待入力一致を検査し、空中仮想打球を5サンプル測る。
7. air上限1nsで赤、20%追加呼出しで緑、2倍呼出しで赤を確認して戻す。
8. `PERF_GATE` が成否にかかわらず正確に1行で、失敗文へ混入しないことを確認する。
9. 正式差分をコミットする。

## Task 3: 再現性と順序独立性を検証する

**Files:**
- Temporarily modify and restore: `tests/unit/test_zz_performance.gd`

1. 正式実装で `run_tests.ps1` を独立5回実行し、全結果と性能値を記録する。
2. 性能テストを先頭へ一時移動して全件を1回実行し、固定値と合否が不変と確認して戻す。
3. `git diff --check`、test関数数、`PERF_GATE` 行数、production差分0を確認する。

## Task 4: 最終レビューと完了記録

**Files:**
- Modify: `docs/tasks/83.md`
- Modify: `docs/remaining-tasks.md`

1. Claude Codeへ計測区間、fixture、mutation、ノイズ再現性、production差分をレビュー依頼する。
2. 指摘を証拠で判定し、必要なら修正後に全検証をやり直す。
3. #83へ承認設計の同一性、全実測、mutation、レビュー結果を記録する。
4. #83を残件一覧から除き、文書更新をコミットする。
5. 作業ツリーがcleanであることを確認する。
