# Codexリファクタリング検証依頼: 工程5b

日付: 2026-07-19
対象コミット: `d0e439f` (`refactor: extract hit resolver module`)
次工程: 5c 意図分類の内部純関数化

## 実施内容

`src/sim/hit_resolver.gd`を新設し、工程5bのヒット責務をsimulationから抽出した。

### 移動した6関数

- `_resolve_hit`
- `_apply_hit`
- `_is_active_block`
- `_ball_vs_block`
- `_toss_height_pct`
- `_scatter`

旧コミット`9ae6238`の`simulation.gd`と新`hit_resolver.gd`を関数単位で機械比較し、
6関数すべて本体が逐語一致した。

### 移動した定数

- `NO_HIT` / `HIT_NO_POINT`
- `TOSS_AIM_SHIFT_PX` / `MANGLE_AIM_PCT`
- `PUSH_ATK_TICKS` / `PUSH_BLK_TICKS` / `PUSH_MAX_TICKS` /
  `PUSH_STUN_TICKS`
- `FLINCH_TICKS` / `KNOCKBACK_PX` / `KNOCK_AIR_UP_PX_S`

サーブ所有の`AIM_MAX` / `POW_MIN` / `POW_MAX`はsimulationへ残した。
帽子定数とエンティティ定数もsimulationへ残した。

### 依存方向

`hit_resolver.gd`のpreloadは次の葉4つだけ。

- `fp.gd`
- `sim_input.gd`
- `sim_state.gd`
- `chars.gd`

Simulation、BallPhysics、PlayerMovementへの参照はない。
simulationからHitResolverへの一方向依存だけを追加した。

### 補助関数についての監査事項

6関数本体の逐語性を維持するため、移動先に次の私有委譲補助を置いた。

- `team_of`: `SimState.team_of`へ委譲
- `_server_index`: 旧simulationの同名2行と同じ`serving_team * 2`

`_resolve_hit`が`_server_index`を呼ぶ依存は工程表の列挙から漏れており、最初の
単体コンパイルで検出した。Simulationをpreloadすると循環するため、関数本体を
書き換えず同じ私有補助を置いた。simulation側の`_server_index`はサーブ進行でも
使用するため残している。この重複を工程5bで許容できるか、特に確認してほしい。

### 呼び出し元とテスト参照

- simulationの`_resolve_hit` 1箇所と`_ball_vs_block` 2箇所をHitResolverへ更新
- `test_rally.gd`: `_resolve_hit` 3箇所
- `test_char_stats.gd`: `_scatter` 4箇所
- `test_refactor_characterization.gd`: `_apply_hit` 3箇所、`_scatter` 1箇所、
  `_ball_vs_block` 1箇所
- `test_hit_boundary.gd`: 三状態定数と`_resolve_hit` / `_apply_hit`参照

旧`Simulation._resolve_hit`等と`Sim._scatter`の取り残し参照はゼロ。
simulationにヒット関数・ヒット定数の互換ラッパーは残していない。
表示層用の`Simulation.team_of`だけは工程5aの方針どおり維持している。

## 検証結果

- `hit_resolver.gd`単体コンパイル: 成功
- 全248テスト: 0 failed
- `test_sync.gd.test_golden_hash_regression`: 通過、値変更なし
- `test_refactor_characterization.gd.test_hit_chain_second_golden`: 通過、値変更なし
- 6関数の旧新機械比較: すべて一致
- `git diff --check`: 問題なし
- コミット後フックでも全248テスト、0 failed

## Claude Codeへの確認依頼

1. 6関数が旧実装と逐語一致しているか独立に機械比較してほしい
2. 移動定数とsimulation残留定数の責務境界が正しいか
3. 追加されたテスト直接参照を含め、取り残しがないか
4. preload方向に循環や逆流がないか
5. `team_of`委譲補助と`_server_index`2行重複を工程5bで許容できるか
6. 問題がなければ工程5c開始可否を明言してほしい
