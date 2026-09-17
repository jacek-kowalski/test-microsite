"""
Generate icon.png for the Tizen app package.

icon.png is committed, so you only need this if you want to regenerate it.

    python make_icon.py
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 512
BG = (11, 14, 20)          # #0b0e14, same as the probe page background
ACCENT = (127, 209, 255)   # #7fd1ff
GREEN = (108, 243, 165)
AMBER = (255, 192, 120)
GREY = (154, 163, 181)


def load_font(size, bold=False):
    """Best-effort TrueType lookup; falls back to PIL's bitmap font."""
    candidates = [
        'arialbd.ttf' if bold else 'arial.ttf',
        'C:/Windows/Fonts/arialbd.ttf' if bold else 'C:/Windows/Fonts/arial.ttf',
        'DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf',
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def centered(draw, text, font, cx, y, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text((cx - (right - left) / 2 - left, y - top), text, font=font, fill=fill)


img = Image.new('RGB', (SIZE, SIZE), BG)
draw = ImageDraw.Draw(img)

# Rounded accent border
draw.rounded_rectangle([14, 14, SIZE - 15, SIZE - 15], radius=56,
                       outline=ACCENT, width=8)

# Title
centered(draw, 'API', load_font(150, bold=True), SIZE / 2, 96, (255, 255, 255))
centered(draw, 'PROBE', load_font(72, bold=True), SIZE / 2, 262, ACCENT)

# Three status pips standing in for OK / BLOCKED / MISSING
pip_y = 392
pip_r = 24
gap = 96
for index, colour in enumerate((GREEN, AMBER, GREY)):
    cx = SIZE / 2 + (index - 1) * gap
    draw.ellipse([cx - pip_r, pip_y - pip_r, cx + pip_r, pip_y + pip_r], fill=colour)

centered(draw, 'SSO / ADINFO', load_font(34), SIZE / 2, 444, GREY)

img.save('icon.png')
print('Wrote icon.png ({}x{})'.format(SIZE, SIZE))
