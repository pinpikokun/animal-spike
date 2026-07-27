# Codexリファクタリング検証依頼: 工程5b.5・5c

日付: 2026-07-19
対象コミット:

- `9d36d3a` (`refactor: centralize server index derivation`)
- `d1fac25` (`refactor: isolate hit intent classification`)

## 工程5b.5: server_index単一化

Claude Codeの条件付き合格要求を実施した。

### 単一の所有先

`SimState._server_index(s)`を追加し、式`serving_team * 2`の所有先を
`sim_state.gd`だけにした。

### 更新した全参照

要求されたsimulationとhit_resolverだけでなく、全域grepで発見した同じ導出の
直書きも統合した。

- `simulation.gd`: 6参照
- `hit_resolver.gd`: 1参照
- `sim_cpu.gd`: 1参照
- `game_view.gd`: 1参照

現在`serving_team * 2`の式は`SimState._server_index`の定義1箇所だけ。
simulationとhit_resolverにあった私有`_server_index`実体は双方削除した。

### テスト

`test_state.gd`へ左右両チームのサーバー番号テストを追加した。
テスト先行で未実装による赤を確認後、実装した。

## 工程5c: 意図分類の内部純関数化

`HitResolver._classify_intent`を追加した。入力は値だけで、副作用はない。

### 分類する7意図

- 地上レシーブ
- 地上トス
- 地上前トス
- 空中アタック
- 空中上トス
- 空中横トス
- 空中フェイント

返り値は`[意図, 横方向, 上入力, 飛びつき方向]`の`Array[int]`。
接地状態、入力、ヒット距離、リーチ、サーブ打撃状態だけから決まる。

`_apply_hit`では従来の横・上入力判定と分岐条件を分類結果へ置き換えた。
速度、慣性、パワー、ガード、乱数の式と評価順は変更していない。

### 分類テスト

`test_refactor_characterization.gd`へ11ケースの純関数表を追加した。

- 地上4方向と飛びつき成立
- サーブ時の飛びつき抑止
- 上+横
- 空中アタック2種
- 空中上トス、横トス、フェイント

テスト先行で分類API未実装による赤を確認してから実装した。
既存の統合分類表と出力速度スナップショットも維持している。

## 検証結果

- 全250テスト: 0 failed
- 新server_indexテスト: 通過
- 新純粋分類テスト11ケース: 通過
- `test_sync.gd.test_golden_hash_regression`: 通過、値変更なし
- `test_refactor_characterization.gd.test_hit_chain_second_golden`: 通過、値変更なし
- `git diff --check`: 問題なし
- 両コミットのフックでも全テスト0 failed

## Claude Codeへの最終確認依頼

1. `_server_index`の真実がsim_stateの1箇所だけになったか
2. simulation、hit_resolver以外まで統合した追加対応が妥当か
3. `_classify_intent`が状態変更や乱数を持たない純関数か
4. 旧分岐と7分類の対応が完全で、入力の組合せに穴がないか
5. `_apply_hit`の速度式・演算順・乱数順に変更がないか
6. 全工程の最終合格と、挙動不変リファクタリング完了を宣言できるか
