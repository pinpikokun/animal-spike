# 確定フォーマットで全キャラ+ボールを透過PNG化
# 1スプライト=640B=[B,R,G,E各128B]+マスク128B(1=透過)、32x32、24体/DAT
from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path(r"C:\work\PC98\vb2211")
OUT = Path(r"C:\Users\Hiroki\AppData\Local\Temp\claude\C--work-git-Animal-Spike\3461fd49-142b-4d31-adfc-f9bca1b83925\scratchpad\vb_sprites")
OUT.mkdir(parents=True, exist_ok=True)

PAL = [
    (0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
    (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255),
    (64, 64, 64), (0, 0, 160), (160, 0, 0), (160, 0, 160),
    (0, 160, 0), (0, 160, 160), (160, 160, 0), (200, 200, 200),
]
CELL = 128

def decode_char(data):
    n = len(data) // 640
    frames = []
    for s in range(n):
        base = s * 640
        img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        px = img.load()
        for y in range(32):
            for xb in range(4):
                off = y * 4 + xb
                bs = [data[base + p * CELL + off] for p in range(5)]
                for bit in range(8):
                    v = 0
                    for ci in range(4):
                        v |= ((bs[ci] >> (7 - bit)) & 1) << ci
                    m = (bs[4] >> (7 - bit)) & 1
                    if m == 0:  # マスク=0が不透過(inv=1相当)
                        px[xb * 8 + bit, y] = (*PAL[v], 255)
        frames.append(img)
    return frames

NAMES = ["TOME", "HITO", "PIYO", "UME", "CARBY", "DUO", "SEC1", "SEC2", "BALL"]
all_sheets = []
for name in NAMES:
    frames = decode_char((SRC / f"{name}.DAT").read_bytes())
    cols = 12
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * 32, rows * 32), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % cols) * 32, (i // cols) * 32), f)
    sheet.save(OUT / f"{name.lower()}_sheet.png")
    all_sheets.append((name, sheet))

# 全キャラ確認用の1枚絵(x3拡大、暗背景+ラベル)
pad_top = 14
w = max(s.width for _, s in all_sheets) * 3
h = sum(s.height * 3 + pad_top for _, s in all_sheets)
combo = Image.new("RGB", (w, h), (35, 35, 45))
d = ImageDraw.Draw(combo)
y = 0
for name, sheet in all_sheets:
    d.text((2, y + 1), name, fill=(255, 255, 0))
    big = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    combo.paste(big, (0, y + pad_top), big)
    y += sheet.height * 3 + pad_top
combo.save(OUT / "ALL_preview.png")
print("done ->", OUT)
