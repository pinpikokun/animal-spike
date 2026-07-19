# Codexリファクタリング検証依頼: 工程5a

日付: 2026-07-19
対象コミット: `c8dc1e2` (`refactor: prepare three-state hit boundary`)
次工程: 5b `hit_resolver.gd`逐語抽出

## 実施内容

工程5aだけを独立コミットで実施した。工程5bの関数・定数抽出はまだ行っていない。

### 1. 三状態API

`simulation.gd`へ次を追加した。

- `NO_HIT = -2`: ヒット不成立
- `HIT_NO_POINT = -1`: ヒット成立、得点なし
- `0`または`1`: 得点チーム

`_resolve_hit`は全経路で上記いずれかを返す。ヒット成立時は`_apply_hit`後の
`touches > cfg.max_touches`を見て得点チームまたは`HIT_NO_POINT`を返す。

### 2. 得点授与とサーブ遷移の順序

`_step_players_and_hits`はリゾルバー呼び出し前に`was_serve_strike`を記録する。
戻り後の順序は次のとおり。

1. 結果が0または1なら`_award_point`
2. `was_serve_strike`かつ`NO_HIT`以外なら`PHASE_RALLY`、`serve_tossed=0`、
   `serve_flight=1`

これにより`max_touches=0`でも旧実装の「得点授与、その後サーブ遷移」を保存した。
`_apply_hit`から直接の`_award_point`呼び出しは削除した。

### 3. チーム判定の所有移動

- `team_of`と`_dir_of_team`を`sim_state.gd`へ移動
- 表示層互換の`Simulation.team_of`は`SimState.team_of`への委譲ラッパーとして維持
- simulation内部の方向判定は`SimState._dir_of_team`を参照

### 4. 特性テスト

`tests/unit/test_hit_boundary.gd`を追加した。確定仕様4ケースと定数契約を検証する。

1. 通常サーブ打撃は`HIT_NO_POINT`を返し、ラリーへ移行
2. `max_touches=0`のサーブ打撃は相手得点を返し、得点授与後にサーブ遷移
3. 届かないサーブ打撃は`NO_HIT`を返し、全state不変
4. ラリー中タッチ超過は得点チームを返し、同tickで授与
5. 三状態定数が`-2`と`-1`

成立3ケースは旧境界の期待処理を別stateに再現し、`to_int_array()`同士を比較する。
したがって一部フィールドやハッシュだけでなく、全stateフィールドを比較している。
`max_touches=0`は実際の`_step_players_and_hits`経路も通して最終score/phase/serve
フラグを検証した。

## TDD記録

- 定数テストを先に追加し、未実装による1失敗を確認
- 定数の最小実装後、4特性テストを追加し4失敗を確認
- プロダクション境界変更後、全テストを緑にした

## 検証結果

- 全248テスト: 0 failed
- `test_hit_boundary.gd`: 5件すべて通過
- `test_sync.gd.test_golden_hash_regression`: 通過、値変更なし
- `test_refactor_characterization.gd.test_hit_chain_second_golden`: 通過、値変更なし
- `git diff --check`: 問題なし
- コミット後フックでも全248テスト、0 failed

## Claude Codeへの確認依頼

1. 三状態の全return経路が仕様どおりか
2. `max_touches=0`を含め、得点授与からサーブ遷移の順序が旧実装と一致するか
3. `_apply_hit`から得点責務が完全に除かれたか
4. `team_of`/`_dir_of_team`の所有移動と表示層互換ラッパーが適切か
5. 4特性テストが全state比較を含み、境界変更を十分固定しているか
6. 問題がなければ工程5bの逐語抽出開始可否を明言してほしい
