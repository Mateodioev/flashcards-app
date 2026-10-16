#!/usr/bin/env python3
"""Regenerates the Android launcher icon and splash assets (T10.4).

The drawing lives in this script so the assets are reproducible: run
`python3 tool/generate_launcher_assets.py` from the repository root and every
PNG plus the adaptive-icon XML is rewritten deterministically.

Design: the app's indigo seed (lib/core/theme.dart `_seed`) as the background,
a slightly tilted white flashcard on top, and an indigo fraction on the card —
the LaTeX-heavy content this app exists for. The glyph is shared between the
adaptive-icon foreground and the splash logo so splash --> icon hand-off does
not jump.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

BRAND = (63, 81, 181, 255)  # #3F51B5, must match _seed in lib/core/theme.dart
WHITE = (250, 250, 255, 255)

# Android density buckets, with legacy launcher / adaptive-canvas sizes in px.
LAUNCHER_PX = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_PX = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
SPLASH_PX = {"mdpi": 192, "hdpi": 288, "xhdpi": 384, "xxhdpi": 576, "xxxhdpi": 768}

# The adaptive spec keeps icon content inside the central 72dp of the 108dp
# canvas (2/3); we use 0.62 so the tilted card survives round mask corners.
FOREGROUND_SCALE = 0.62
CARD_SCALE = 0.78  # card size relative to the glyph canvas


def _draw_glyph(size: int) -> Image.Image:
    """The card-plus-fraction glyph alone, transparent background."""
    ss = 4  # supersample, then downscale for antialiasing
    canvas = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    s = size * ss

    card = int(s * CARD_SCALE)
    card_img = Image.new("RGBA", (card + 4, card + 4), (0, 0, 0, 0))
    cd = ImageDraw.Draw(card_img)
    radius = int(card * 0.14)
    cd.rounded_rectangle([2, 2, card + 1, card + 1], radius=radius, fill=WHITE)

    # Fraction: numerator bar, ruled line, denominator bar. The numerator and
    # denominator are drawn clearly wider than the vinculum, otherwise the
    # three strokes read as "identical to" (≡) at launcher sizes.
    fg = int(card * 0.46)
    bar_w = int(fg * 0.42)
    cx = card // 2 + 2
    d_frac = ImageDraw.Draw(card_img)
    bar_r = bar_w // 2

    def bar(center_y: int, height: int) -> None:
        x0, x1 = cx - bar_w, cx + bar_w
        y0, y1 = center_y - height // 2, center_y + height // 2
        d_frac.rounded_rectangle([x0 - bar_r, y0, x1 + bar_r, y1],
                                 radius=height // 2, fill=BRAND)

    top_y = int(card * 0.28)
    rule_y = card // 2 + 2
    bot_y = int(card * 0.74)
    bar_h = max(int(card * 0.10), ss)
    bar(top_y, bar_h)
    bar(bot_y, bar_h)
    rule_h = max(int(card * 0.05), ss)
    rule_half = int(fg * 0.30)
    d_frac.rounded_rectangle(
        [cx - rule_half, rule_y - rule_h // 2, cx + rule_half, rule_y + rule_h // 2],
        radius=rule_h // 2,
        fill=BRAND,
    )

    rotated = card_img.rotate(8, resample=Image.BICUBIC, center=(card // 2 + 2, card // 2 + 2))
    ox = (canvas.width - rotated.width) // 2
    oy = (canvas.height - rotated.height) // 2
    canvas.alpha_composite(rotated, (ox, oy))
    return canvas.resize((size, size), Image.LANCZOS)


def _legacy_icon(size: int) -> Image.Image:
    """Full-bleed square icon (pre-API 26 fallback)."""
    img = Image.new("RGBA", (size, size), BRAND)
    glyph = _draw_glyph(size)
    img.alpha_composite(glyph, ((size - glyph.width) // 2, (size - glyph.height) // 2))
    return img


def _foreground(size: int) -> Image.Image:
    """Adaptive-icon foreground layer: glyph inside the safe zone."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glyph = _draw_glyph(int(size * FOREGROUND_SCALE))
    img.alpha_composite(glyph, ((size - glyph.width) // 2, (size - glyph.height) // 2))
    return img


def main() -> None:
    for density, px in LAUNCHER_PX.items():
        out = RES / f"mipmap-{density}" / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        icon = _legacy_icon(px)
        assert icon.size == (px, px)
        icon.save(out)

    for density, px in ADAPTIVE_PX.items():
        out = RES / f"mipmap-{density}" / "ic_launcher_foreground.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        layer = _foreground(px)
        assert layer.size == (px, px)
        layer.save(out)

        splash_out = RES / f"drawable-{density}" / "splash_logo.png"
        splash_out.parent.mkdir(parents=True, exist_ok=True)
        logo = _draw_glyph(int(SPLASH_PX[density] * 0.9))
        canvas = Image.new("RGBA", (SPLASH_PX[density], SPLASH_PX[density]), (0, 0, 0, 0))
        canvas.alpha_composite(
            logo,
            ((SPLASH_PX[density] - logo.width) // 2, (SPLASH_PX[density] - logo.height) // 2),
        )
        canvas.save(splash_out)

    adaptive = RES / "mipmap-anydpi-v26"
    adaptive.mkdir(parents=True, exist_ok=True)
    (adaptive / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )

    colors = RES / "values" / "colors.xml"
    colors.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <!-- Brand indigo; keep in sync with _seed in lib/core/theme.dart. -->\n'
        '    <color name="ic_launcher_background">#3F51B5</color>\n'
        '    <color name="splash_background">#3F51B5</color>\n'
        '</resources>\n'
    )

    # Sabotage gate: every declared density must now hold all three PNGs, with
    # the exact pixel sizes Android expects.
    for density in LAUNCHER_PX:
        for name, size in (
            ("ic_launcher.png", LAUNCHER_PX[density]),
            ("ic_launcher_foreground.png", ADAPTIVE_PX[density]),
        ):
            path = RES / f"mipmap-{density}" / name
            with Image.open(path) as check:
                assert check.size == (size, size), f"{path}: {check.size} != {size}"
    print("launcher assets regenerated")


if __name__ == "__main__":
    main()
