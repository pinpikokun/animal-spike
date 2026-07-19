# 不要ファイル監査

日付: 2026-07-19

## 判定基準

- Git管理状況
- `src`、`tests`、`data`、`project.godot`からの参照
- 生成スクリプトとの関係
- 今後予定している原作キャラクター追加での資料価値

削除はこの文書に対するユーザーの明示承認後に、独立コミットで行う。

## remove: 削除推奨

### Git管理中の生成プレビュー

以下はゲーム実行時の直接参照がなく、現在の正式アセットは `assets` 以下にある。いずれも生成・比較・方向性確認の出力物である。

- `bloom_compare.png`
- `fakebloom.png`
- `fx_anim.mp4`
- `fx_bursts_variety.png`
- `fx_dust_crisp.png`
- `fx_dust_shrink.png`
- `fx_ingame_model.mp4`
- `fx_jump_attack.png`
- `fx_jump_inertia.png`
- `fx_land_cream.png`
- `fx_preview.png`
- `fx_scenarios.png`

`fx_preview.png` は `scripts/gen_fx_preview.gd` の既定出力先だが、入力ではない。必要なら再生成できる。

### バックアップ

- `scripts/gen_fx_anim.gd.bak`

現行の `scripts/gen_fx_anim.gd` があり、バックアップ側だけを参照するコードはない。

### Git管理外のGodot生成メタデータ

- リポジトリ直下の `*.import` 54ファイル

すべてGit管理外である。現存しない一時画像を指すものを多数含み、必要なインポート情報はGodotが `.godot/imported` に再生成できる。

## confirm: 今回は削除しない

- `rounds_ref_purple.png`: 実行時参照はないが、原作表現を照合する単独資料。原作キャラクター追加と表示調整が残っているため保持する。
- `mario-mpeg/`: 約178MB。実行時参照はないが、マリオの原動画、抽出フレーム、採用素材の由来を含む。固有技・アニメーションの再調整に必要となる可能性が高いため保持する。
- `court_preview.png`: Git管理外だが、コート表示の比較資料として保持する。
- `istockphoto-1621604084-1024x1024.jpg`: Git管理外。背景素材の由来確認が済んでいないため保持する。
- `scripts/probe_airknock.gd`
- `scripts/probe_knock2.gd`
- `scripts/probe_toss.gd`

3本のプローブは通常テストから呼ばれないが、現在の物理挙動を実測する診断ツールである。今回の物理処理抽出が終わるまでは保持し、リファクタリング完了後に再監査する。

## keep: 保持

- `.gitattributes`、`.gitignore`
- `AGENTS.md`、`CLAUDE.md`
- `README.md`、`AnimalSpike_GDD_ClaudeCode_v0.1.md`
- `project.godot`、`run_tests.ps1`、`ゲーム起動.bat`
- `assets/reference/vb2211/`: 今後予定している原作キャラクター追加の一次資料
- `scripts` 内の現行生成・検証スクリプト。ただし上記の `.bak` を除く

## 承認対象

今回削除するのは `remove` に列挙したものだけとする。`confirm` と `keep` は削除しない。
