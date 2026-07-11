# ボール素材 (自作SVG + ゲーム実寸焼き込みPNG)

クラシックな18枚パネル(9本シーム)構造のバレーボール。全て自作(CC0相当、権利問題なし)。
生成は scripts/gen_ball.gd (SVG原版とPNGを一括生成):

```
tools\godot\Godot_v4.6-stable_win64.exe --headless --path . -s res://scripts/gen_ball.gd
```

## 2種類の出力

- `volleyball*.svg` : 128px viewBoxの原版。プレビューや将来の大型表示用
- `volleyball*_game.png` : ゲーム内実寸(rules.jsonのball_radius_px*2)へ直接ラスタした
  焼き込み版。**ゲームはこちらを使う**。128px素材の実行時縮小はぼやけ/ムラが出るため
  (実測比較済み)。小サイズで輪郭が消えないよう焼き込み版のみ輪郭を約1px相当へ補強。
  **ball_radius_pxや配色を変えたらジェネレーター再実行**(game_view.gdが不一致を警告する)

## 構造 (全色共通・ユーザー承認済み)

- 中心からのシーム3本(Y字) + 各セクターに平行パネル線2本 = 計9本
- 立体感: 右下に三日月影2枚(広く薄い+狭く濃い)、左上にハイライト楕円
- パネル塗り: 隣の腕カーブをDe Casteljau分割(t=0.6, 0.8)した閉パスで
  正確に塗り分け。境界は全てシームのストローク(2.6px)の下に隠れる

## ファイル

| ファイル(svg/_game.png各1) | パネル色 | 用途 |
|---|---|---|
| volleyball | 白 | 標準(ゲーム内で使用中) |
| volleyball_blue | 白+青+黄 | ステージ別バリエーション |
| volleyball_green | 白+緑+赤 | 同上 |
| volleyball_teal | クリーム+ティール+橙 | 同上 |

色バリエーションはパネルのfill色のみ差し替え(シーム構造・影は共通)。
新色は scripts/gen_ball.gd の PALETTES に5色([A,B,C,シーム,輪郭])を足して再実行。
