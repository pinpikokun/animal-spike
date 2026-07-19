# Jump Weight Physics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 足元基準のジャンプ高度、ウェイト別の上昇・下降時間、キャラクター選択画面の全プレイヤー向け能力表示を実装する。

**Architecture:** `chars.gd` が10段階能力と表示用レベルを提供し、`simulation.gd` が目標高度と時間から整数物理を計算する。`char_select.gd` は能力値を読むだけの表示層に保つ。

**Tech Stack:** Godot 4.6、GDScript、整数固定小数点シミュレーション、既存の独自テストランナー

## Global Constraints

- ジャンプ高度は足元基準でレベル1=108px、レベル5=132px、レベル10=162px。
- ウェイトは高度を変えず、上昇・下降時間だけを変える。
- プレイヤー向け能力だけを選択画面へ表示し、内部倍率は表示しない。
- 既存の小ジャンプ、吹っ飛ばされにくさ、決定論を維持する。

---

### Task 1: 能力レベルAPI

**Files:**
- Modify: `src/sim/chars.gd`
- Test: `tests/unit/test_chars.gd`

**Interfaces:**
- Produces: `Chars.display_level(char_id: int, key: String) -> int`

- [ ] プレイヤー向け全能力が1から10で取得でき、ばらつき値が安定性へ反転される失敗テストを書く。
- [ ] `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1 test_chars.gd` で期待どおり失敗することを確認する。
- [ ] `display_level` と能力キー一覧を最小実装する。
- [ ] 同じテストを再実行して通過を確認する。

### Task 2: 高度とウェイト時間

**Files:**
- Modify: `src/sim/simulation.gd`
- Test: `tests/unit/test_char_stats.gd`

**Interfaces:**
- Produces: 足元基準のフルジャンプ挙動

- [ ] ジャンプレベル1、5、10の最高点と、同じ高さにおけるウェイト別の上昇・下降順を測る失敗テストを書く。
- [ ] `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1 test_char_stats.gd` で期待どおり失敗することを確認する。
- [ ] 目標高度の区分線形補間と、ウェイト別の上昇・下降加速度を整数演算で実装する。
- [ ] 小ジャンプと着地を含む対象テストを再実行して通過を確認する。

### Task 3: 全能力表示

**Files:**
- Modify: `src/display/char_select.gd`
- Create: `tests/unit/test_char_select.gd`

**Interfaces:**
- Consumes: `Chars.display_level`
- Produces: `CharSelect.stats_text(char_id: int) -> String`

- [ ] 全能力名と固有技が文字列へ含まれる失敗テストを書く。
- [ ] `powershell -ExecutionPolicy Bypass -File .\run_tests.ps1 test_char_select.gd` で期待どおり失敗することを確認する。
- [ ] 複数列の数値一覧を返す純粋関数と画面レイアウトを実装する。
- [ ] 対象テストを通し、640x360画面で文字が重ならないことをスクリーンショットで確認する。

### Task 4: 回帰検証

**Files:**
- Modify: `tests/unit/test_sync.gd`（意図した物理変更でゴールデン値だけが変わる場合）

- [ ] 全テストを実行し、物理変更に由来する失敗と既存失敗を切り分ける。
- [ ] 同期ゴールデン値を新しい決定論的結果へ更新する。
- [ ] 全テストを再実行し、成功件数と残存失敗を記録する。
- [ ] ゲームを起動し、パンダとカエルの最高点、滞空時間、選択画面を目視確認する。
