# -*- coding: utf-8 -*-
# 1.jpeg -> 320x240 12bit(4:4:4) ROM 用 image.mif を生成
# ・アスペクト保持で320x240にレターボックス(上下黒帯)して焼き込む
# ・VHDL側は単純2倍スケールで640x480に拡大する前提
# ・各ch 8bit -> 4bit(round)、data = R4<<8 | G4<<4 | B4
# ・確認用の expected_preview.png(640x480相当)も出力
from PIL import Image

SRC = r"C:\Users\kaga\.claude\image-cache\84ae2ee8-f40a-4bb7-9f19-8d701259c550\1.jpeg"
W, H = 320, 240          # ストア解像度
OUT_MIF = "image.mif"
OUT_PREVIEW = "expected_preview.png"

src = Image.open(SRC).convert("RGB")
sw, sh = src.size
# 320x240に収まる最大サイズ(アスペクト保持)
scale = min(W / sw, H / sh)
nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
resized = src.resize((nw, nh), Image.LANCZOS)
canvas = Image.new("RGB", (W, H), (0, 0, 0))   # 黒キャンバス
ox, oy = (W - nw) // 2, (H - nh) // 2
canvas.paste(resized, (ox, oy))
print(f"src={sw}x{sh} -> fit={nw}x{nh} @offset({ox},{oy}) on {W}x{H}")

px = canvas.load()

def q4(v):  # 8bit -> 4bit(round, clamp)
    return min(15, max(0, round(v / 255 * 15)))

# MIF出力
with open(OUT_MIF, "w", encoding="ascii") as f:
    f.write(f"-- {W}x{H} 12bit(4:4:4) image ROM, addr = y*{W}+x\n")
    f.write(f"DEPTH = {W*H};\n")
    f.write("WIDTH = 12;\n")
    f.write("ADDRESS_RADIX = DEC;\n")
    f.write("DATA_RADIX = HEX;\n\n")
    f.write("CONTENT\nBEGIN\n")
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            data = (q4(r) << 8) | (q4(g) << 4) | q4(b)
            f.write(f"    {y*W + x} : {data:03X};\n")
    f.write("END;\n")
print(f"wrote {OUT_MIF}  ({W*H} words)")

# 確認用プレビュー: 4bit量子化を反映し640x480へ最近傍2倍拡大
prev = Image.new("RGB", (W, H))
pp = prev.load()
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        pp[x, y] = (q4(r) * 17, q4(g) * 17, q4(b) * 17)  # 4bit->8bit表示(×17=255/15)
prev.resize((640, 480), Image.NEAREST).save(OUT_PREVIEW)
print(f"wrote {OUT_PREVIEW}")
