# -*- coding: utf-8 -*-
"""生成 Komari Agent 应用图标（圆角矩形风格，纯 Pillow，无其他依赖）

产出：
  komari-agent/ICON.PNG                 64x64   包图标
  komari-agent/ICON_256.PNG            256x256 包图标
  komari-agent/app/ui/images/icon_64.png   64x64   入口图标
  komari-agent/app/ui/images/icon_256.png  256x256 入口图标
"""
import os
import math
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "komari-agent")


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_icon(size):
    """深蓝渐变圆角背景 + 白色监控波形（折线 + 端点圆点）"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    top = (15, 45, 105)
    bottom = (8, 26, 64)
    radius = max(6, int(size * 0.18))

    # 垂直渐变背景（先画到临时图层再裁圆角）
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / (size - 1)
        bd.line([(0, y), (size, y)], fill=lerp_color(top, bottom, t))

    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.paste(bg, (0, 0), mask)

    # 波形（白色折线）：在圆角内留白的安全区内绘制
    pad = size * 0.22
    x0, x1 = pad, size - pad
    y_mid = size * 0.5
    amp = size * 0.22
    points = [
        (x0, y_mid + amp * 0.6),
        (x0 + (x1 - x0) * 0.22, y_mid - amp * 0.35),
        (x0 + (x1 - x0) * 0.42, y_mid + amp * 0.45),
        (x0 + (x1 - x0) * 0.62, y_mid - amp * 0.6),
        (x0 + (x1 - x0) * 0.82, y_mid + amp * 0.1),
        (x1, y_mid - amp * 0.45),
    ]
    line_w = max(3, int(size * 0.045))
    draw.line(points, fill=(255, 255, 255, 235), width=line_w, joint="curve")
    # 端点圆点
    dot_r = max(2.5, size * 0.045)
    for p in (points[0], points[-1]):
        draw.ellipse(
            [p[0] - dot_r, p[1] - dot_r, p[0] + dot_r, p[1] + dot_r],
            fill=(255, 255, 255, 255),
        )
    return img


def main():
    for d in (PACK, os.path.join(PACK, "app", "ui", "images")):
        os.makedirs(d, exist_ok=True)

    img256 = draw_icon(256)
    img64 = img256.resize((64, 64), Image.LANCZOS)

    img256.convert("RGB").save(os.path.join(PACK, "ICON_256.PNG"), "PNG")
    img64.convert("RGB").save(os.path.join(PACK, "ICON.PNG"), "PNG")
    img256.convert("RGB").save(os.path.join(PACK, "app", "ui", "images", "icon_256.png"), "PNG")
    img64.convert("RGB").save(os.path.join(PACK, "app", "ui", "images", "icon_64.png"), "PNG")

    for name in ("ICON.PNG", "ICON_256.PNG",
                 "app/ui/images/icon_64.png", "app/ui/images/icon_256.png"):
        p = os.path.join(PACK, name)
        print(f"generated {p} ({os.path.getsize(p)} bytes)")


if __name__ == "__main__":
    main()
