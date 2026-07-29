# #91 ラリー状態初期化とネット設定検査 実装計画

**Goal:** 前ラリーの移動補助状態を消し、ネット対戦が無効な設定から開始しないようにする。

**Design:** `reset_rally` の既存クリア列へ四状態を加える。`SimRoot.setup` は設定検査結果を bool で返し、`NetMatch` は失敗時に同期前停止する。HUD生成前の停止では process 自体を止める。

**Approved design:** `docs/superpowers/specs/2026-07-29-91-rally-reset-config-validation-design.md` 162行、SHA-256 `5f27a1cb2681020e24efe13f0d27a9e007fd110f0c9ca9841d768eb651a9df67`

## Task 1: 設計契約を記録する

**Files:**
- Add: `docs/superpowers/specs/2026-07-29-91-rally-reset-config-validation-design.md`
- Add: `docs/superpowers/plans/2026-07-29-91-rally-reset-config-validation.md`

1. 行数と SHA-256 を承認値と照合する。
2. 設計書と本計画だけをコミットする。

## Task 2: ラリー状態漏れをTDDで直す

**Files:**
- Modify: `tests/unit/test_rally.gd`
- Modify: `src/sim/simulation.gd`

1. 四選手へ非ゼロの `tap_dir`、`tap_tick`、`dash`、`push` を設定する回帰テストを追加する。
2. `run_tests.ps1` を実行し、四状態の検査だけが失敗することを確認する。
3. `reset_rally` の既存選手クリア列で四状態を 0 にする。
4. `run_tests.ps1` を再実行し、固定 hash を含む全件が通ることを確認する。
5. 状態漏れ修正をコミットする。

## Task 3: SimRootの設定検査をTDDで直す

**Files:**
- Modify: `tests/unit/test_sim_root.gd`
- Modify: `src/net/sim_root.gd`
- Modify: `src/net/net_match.gd`

1. 正常設定の `setup()` が true、不正fixtureが false、invalid cfg、null stateになるテストを追加する。
2. `run_tests.ps1` を実行し、setup APIと拒否検査が失敗することを確認する。
3. `SimRoot.setup` へ既定の `rules_path` と bool 戻り値を追加し、validを検査する。
4. `SimRoot._ready` で自動setup失敗時にグループ追加せずreturnする。
5. `NetMatch._ready` でsetup失敗を `stop_handshake` へ渡し、SimRootを同期解放してreturnする。
6. `stop_handshake` で `set_process(false)` を行う。
7. `run_tests.ps1` を再実行し、全件と固定値が通ることを確認する。
8. 設定検査修正をコミットする。

## Task 4: 最終検証とレビュー

**Files:**
- Modify: `docs/tasks/91.md`
- Modify: `docs/remaining-tasks.md`

1. `rg` で四状態の初期化、`cfg.valid`、setup戻り値の全呼び出しを静的確認する。
2. `run_tests.ps1` を新たに実行し、終了コード、件数、failed、SCRIPT ERRORを記録する。
3. `git diff --check` と `git status --short` を確認する。
4. Claude Codeへ設計適合性、回帰、停止経路、テストの穴を最終レビュー依頼する。
5. 指摘があれば証拠を確認して修正し、再検証する。
6. #91の実測結果を課題文書へ記録し、残件一覧から完了項目を除く。
7. 文書更新をコミットし、作業ツリーがcleanであることを確認する。
