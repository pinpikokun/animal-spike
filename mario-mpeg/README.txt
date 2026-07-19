■元の動画
https://x.com/yamae_dev/status/2074825862667788311?s=20

■twitterの動画ダウンロード
https://xtwittervid.com/?utm_source=chatgpt.com

■fps確認
ffprobe movie-01.mp4
→最後のほうに「16:9, 60 fps, 60 tbr, 6000k tbn (default)」みたいにfpsが出てくる


■60fps分割
ffmpeg -i movie.mp4 frame_%05d.png


■30fps分割
ffmpeg -i movie.mp4 -vf fps=60 frame_%05d.png



walk.png        歩き
brake.png       歩きの向きを変えた急ブレーキ
jump.png        ジャンプ
spin.png        クルクル回る
hurt.png        ダメージ（尻もちのやられアクション）
dead,png        ゲームオーバー（やられアクションの後の落下モーション）
star.png        スター取得
wall-cling.png 壁へばりつき
hat-throw.png  帽子投げ（本体）
cap.png        飛ぶ帽子



P1_topL.png：クルクル回る
P2_topC_BIG.png：スター取得
P3_topR.png：前半（31まではダメージ）後半（それ以降はゲームオーバー）
P4_midL.pngL：壁へばりつき
P5_center.png：帽子投げ（本体）、飛ぶ帽子
P6_botR.png：ジャンプ
P7_bottom_walk.png：前半は歩き、後半（29以降は急ブレーキ）



P1_topL.png：73から帽子無し
P2_topC_BIG.png：73から帽子無し
P3_topR.png：73から帽子無し
P4_midL.png：73から帽子無し
P6_botR.png：73から帽子無し
P7_bottom_walk.png：73から帽子無し
P5_center.png：これだけ特殊で、64までマリオは棒立ち、65から帽子を投げて、マリオの帽子投げアクションは83でいったんマリオが帽子を投げ終わる、帽子は73でマリオの手を離れて前にいってからマリオ側に戻ってくる、135番でマリオが帽子をキャッチしてかぶるまでのアクションが最後まで続く
