#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "StartPatcheddLive.iconset"
BASE_PNG = ASSETS / "StartPatcheddLive-1024.png"


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1, c2, t: float):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def draw_vertical_gradient(size: int, top, bottom):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        row = mix(top, bottom, t)
        for x in range(size):
            px[x, y] = (*row, 255)
    return img


def build_icon(size: int = 1024) -> Image.Image:
    bg = draw_vertical_gradient(size, (252, 252, 251), (239, 239, 237))

    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=int(size * 0.22),
        fill=255,
    )

    art = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(art)
    frame = [int(size * 0.09), int(size * 0.10), int(size * 0.91), int(size * 0.90)]
    frame_w = int(size * 0.04)
    draw.rounded_rectangle(
        frame,
        radius=int(size * 0.13),
        outline=(92, 92, 96, 255),
        width=frame_w,
    )

    arrow_color = (202, 205, 211, 255)
    dark = (92, 92, 96, 255)
    arrow_y = int(size * 0.36)
    line_w = int(size * 0.028)
    head = int(size * 0.045)

    def draw_arrow(start_x: int, end_x: int):
        draw.line((start_x, arrow_y, end_x, arrow_y), fill=arrow_color, width=line_w)
        if end_x > start_x:
            draw.line((end_x - head, arrow_y - head, end_x, arrow_y), fill=arrow_color, width=line_w)
            draw.line((end_x - head, arrow_y + head, end_x, arrow_y), fill=arrow_color, width=line_w)
        else:
            draw.line((end_x + head, arrow_y - head, end_x, arrow_y), fill=arrow_color, width=line_w)
            draw.line((end_x + head, arrow_y + head, end_x, arrow_y), fill=arrow_color, width=line_w)

    draw_arrow(int(size * 0.37), int(size * 0.29))
    draw_arrow(int(size * 0.55), int(size * 0.72))

    fader_top = int(size * 0.52)
    fader_bottom = int(size * 0.75)
    x_positions = [int(size * 0.36), int(size * 0.45), int(size * 0.55), int(size * 0.64)]
    knob_ys = [int(size * 0.64), int(size * 0.57), int(size * 0.69), int(size * 0.645)]
    track_w = int(size * 0.02)
    knob_r = int(size * 0.035)

    for x, knob_y in zip(x_positions, knob_ys):
        draw.rounded_rectangle(
            [x - track_w // 2, fader_top, x + track_w // 2, fader_bottom],
            radius=track_w // 2,
            fill=dark,
        )
        draw.ellipse(
            [x - knob_r, knob_y - knob_r, x + knob_r, knob_y + knob_r],
            fill=(248, 248, 246, 255),
            outline=dark,
            width=max(2, int(size * 0.012)),
        )

    final = Image.alpha_composite(bg, art)
    final.putalpha(mask)
    return final


def write_iconset(image: Image.Image):
    ASSETS.mkdir(exist_ok=True)
    ICONSET.mkdir(exist_ok=True)
    BASE_PNG.parent.mkdir(parents=True, exist_ok=True)

    image.save(BASE_PNG)
    sizes = [16, 32, 128, 256, 512]
    for px in sizes:
        image.resize((px, px), Image.Resampling.LANCZOS).save(ICONSET / f"icon_{px}x{px}.png")
        image.resize((px * 2, px * 2), Image.Resampling.LANCZOS).save(ICONSET / f"icon_{px}x{px}@2x.png")


if __name__ == "__main__":
    icon = build_icon()
    write_iconset(icon)
    print(BASE_PNG)
