# リファクタリング確定工程表へのCodex最終依存監査

日付: 2026-07-19
状態: 1件の参照更新追記待ち。実装開始は未承認

対象: `2026-07-19-refactor-final-plan.md` 第3訂

## 結論

第3訂は三状態API、得点からサーブ遷移の順序、`max_touches=0` の特性テスト、
hit resolver抽出時の直接参照更新を正しく反映している。工程5の依存ブロッカーは
解消されたと判断する。

ただし最終工程表全体を再検索した結果、工程4にテストの直接参照更新が1群だけ
抜けている。修正要求はこれだけである。

## 最終修正要求: test_dash.gdのDASH定数参照

工程4は `DASH_TAP_WINDOW`、`DASH_TICKS`、`DASH_SPD_PCT` を
`player_movement.gd` へ逐語移動する。一方、`tests/unit/test_dash.gd` は現在、
次の4箇所でsimulation側の定数を直接参照している。

- 33行: `Sim.DASH_SPD_PCT`
- 37行: `Sim.DASH_TAP_WINDOW`
- 59行: `Sim.DASH_SPD_PCT`
- 64行: `Sim.DASH_TICKS`

定数を移動してsimulation側から削除すれば、このテストはパースまたは実行時に
失敗する。不要な互換定数をsimulationへ残す理由はないため、工程4と同じコミットで
4参照を `PlayerMovement` へ更新する。`test_dash.gd` に
`player_movement.gd` のpreloadを追加する。

工程4の記述と合格条件へ、この4箇所の参照更新を明記すること。

## 全外部参照の監査結果

`Sim.` / `Simulation.` の外部参照を全件検索した。

- 工程3で移すball physicsの非公開関数・定数: 外部直接参照なし。
- 工程4のジャンプ補助関数: `test_char_stats.gd` の2参照は工程表に記載済み。
- 工程4の移動定数: 上記DASH定数4参照だけが未記載。
- 工程5の `_resolve_hit`: `test_rally.gd` の3参照は記載済み。
- 工程5の `_scatter`: `test_char_stats.gd` の4参照は記載済み。
- `team_of`: 表示層3参照に委譲ラッパーを残す方針が記載済み。
- 帽子・エンティティ・サーブ照準・入力定数は今回の抽出対象外であり、
  simulation上の既存参照を維持する。

## 最終判定条件

Claude Codeが `2026-07-19-refactor-final-plan.md` の工程4へDASH定数4参照の更新を
追記した後、内容に別の変更がなければCodexは確定工程表へ技術的に合意する。

合意後も自動では開始しない。確定工程表をユーザーへ提示し、ユーザーの明確な
開始承認を得た後にのみ工程1を開始する。工程1の監査で削除候補が出た場合は、
実際の削除前に別途ユーザー承認を得る。
