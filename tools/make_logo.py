"""Draw PetScout's logo (docs/logo.png): a paw print under a magnifying glass.
Original artwork, no game assets. Run: python tools/make_logo.py"""

from pathlib import Path
from PIL import Image, ImageDraw

SIZE, SCALE = 400, 4            # draw at 4x, then shrink for smooth edges
S = SIZE * SCALE
BG = (28, 36, 30)
GREEN = (171, 212, 115)        # PetScout's chat color (|cffabd473)
GOLD = (232, 190, 92)
GLASS = (60, 78, 66)

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)


def circle(cx, cy, r, fill=None, outline=None, width=0):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=outline, width=width)


def ellipse(cx, cy, rx, ry, fill):
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=fill)


u = S / 400  # one unit at the final size

# Magnifying glass: handle first, then the lens on top.
d.line((262 * u, 262 * u, 352 * u, 352 * u), fill=GOLD, width=int(34 * u))
circle(352 * u, 352 * u, 17 * u, fill=GOLD)
circle(170 * u, 170 * u, 128 * u, fill=GLASS)
circle(170 * u, 170 * u, 128 * u, outline=GOLD, width=int(20 * u))

# Paw print inside the lens: main pad and four toes.
ellipse(170 * u, 208 * u, 50 * u, 40 * u, GREEN)
for cx, cy, rx, ry in ((112, 160, 19, 25), (146, 124, 20, 27), (194, 124, 20, 27), (228, 160, 19, 25)):
    ellipse(cx * u, cy * u, rx * u, ry * u, GREEN)

out = Path(__file__).resolve().parent.parent / "docs" / "logo.png"
img.resize((SIZE, SIZE), Image.LANCZOS).save(out, optimize=True)
print(out)
