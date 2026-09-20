#!/usr/bin/env python3
"""Pratinjau gaya visual PulauToon — "palet Messenger" (CPU, tanpa engine).

Bukti visual sebelum ke HP: membangun adegan diorama yang mengenakan
PERSIS nilai-nilai shader/world.gd setelah restyle (langit turquoise, toon
3-band kontras-rendah + rim hangat, air teal, biome sage/jade, outline
cokelat marun) lalu mengukur eksposur tiap jam (mean luma + klip %).
"""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, math, os

W, H = 960, 540
OUT = os.path.join(os.path.dirname(__file__), "..", "docs", "screenshots")

# ---- nilai persis hasil restyle (singkron dengan file shader/world.gd) ----
SHADOW, MID, B1, B2, SOFT = 0.60, 0.78, 0.36, 0.68, 0.16
RIM = (1.0, 0.90, 0.70)
OUTL = (60, 38, 36)               # ~Color(0.24,0.15,0.14)
PAL = dict(
    sand=(232, 214, 168), sand_d=(210, 188, 146),
    grass=(99, 160, 112), grass_d=(84, 137, 98), sage=(140, 196, 122),
    jade=(84, 168, 130), jade_d=(66, 140, 108), pine=(56, 125, 92),
    orange=(228, 158, 76), orange_d=(196, 130, 62), trunk=(140, 105, 77),
    rock=(140, 143, 153), cream=(240, 227, 194), terra=(153, 74, 51),
    terra_d=(128, 62, 45), teal=(89, 179, 140), ochre=(240, 174, 68),
    shallow=(0, 204, 186), deep=(0, 108, 134), foam=(242, 252, 242),
)
ENV = {  # warna ambience siang/senja/malam persis world.gd
    "day": dict(tint=(1.0, 1.0, 1.0), fade=0.0, key=1.0, nom="day"),
    "dusk": dict(tint=(1.0, 0.80, 0.66), fade=0.10, key=0.72, nom="dusk"),
    "night": dict(tint=(0.44, 0.56, 0.72), fade=0.42, key=0.30, nom="night"),
}

def tint(c, e):
    return tuple(int(min(255, ch * e["tint"][i] * (1 - e["fade"])) + 60 * e["fade"] * e["tint"][i])
                 for i, ch in enumerate(c))

def band_shade(c, f):   # perkalian warna ala band toon
    return tuple(int(min(255, x * f)) for x in c)

def grad_sky(cfg):
    """Gradien ala sky.gdshader + matahari besar lembut + coretan awan."""
    hor, zen, gnd = cfg["h"], cfg["z"], cfg["g"]
    a = np.zeros((H, W, 3), np.float32)
    for y in range(H):
        v = 1 - y / H * 2                      # 1 atas .. -1 bawah
        if v >= 0:
            k = min(v * 1.6, 1.0)
            c = [hor[i] * (1 - k) + zen[i] * k for i in range(3)]
        else:
            k = min(-v * 3.0, 1.0)
            c = [hor[i] * (1 - k) + gnd[i] * k for i in range(3)]
        a[y, :, :] = c
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    dr = ImageDraw.Draw(im, "RGBA")
    dr.ellipse([SUN_POS[0] - 34, SUN_POS[1] - 34, SUN_POS[0] + 34, SUN_POS[1] + 34],
               fill=SUN_F + (250,))
    dr.ellipse([SUN_POS[0] - 60, SUN_POS[1] - 60, SUN_POS[0] + 60, SUN_POS[1] + 60],
               fill=SUN_F + (70,))
    rng = np.random.default_rng(7)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dv = ImageDraw.Draw(ov)
    for i in range(8):
        cx = int(rng.integers(40, W - 220)); cy = int(rng.integers(20, 190))
        ln = int(rng.integers(190, 460)); th = int(rng.integers(7, 20))
        col = (245, 251, 245, 60) if i % 3 else (207, 242, 232, 52)
        pts = [(cx + x, cy + int(math.sin(x * 0.011 + i) * th * 0.4)) for x in range(ln)]
        dv.line(pts, fill=col, width=th, joint="curve")
    im = Image.alpha_composite(im.convert("RGBA"), ov.filter(ImageFilter.GaussianBlur(4)))
    return im

def sketch_ellipse(dr, box, fill, ol_w=3):
    """garis sketchy: 2 offset stroke umber untuk rasa hand-drawn."""
    x0, y0, x1, y1 = box
    dr.ellipse([x0 + 1, y0 + 1, x1 - 1, y1 - 1], fill=fill)
    dr.ellipse(box, outline=OUTL, width=ol_w)
    dr.arc([x0 - 1, y0 + 1, x1 + 1, y1 - 1], 200, 40, fill=OUTL, width=2)

def canopy(dr, cx, cy, r, base, lit):
    """kanopi pohon bundar ala low-poly, 3 blob + band gelap bawah."""
    offs = [(-r * 0.55, 0.0), (r * 0.55, 0.05), (0.0, -r * 0.5)]
    cols = [base, lit, base]
    for (ox, oy), col in zip(offs, cols):
        b = [cx + ox - r, cy + oy - r * 0.85, cx + ox + r, cy + oy + r * 0.85]
        dr.ellipse(b, fill=col)
    # bayangan band bawah (kontras rendah ~shadow_tint)
    dr.ellipse([cx - r * 1.5, cy - r * 0.25, cx + r * 1.5, cy + r * 0.8],
               fill=band_shade(base, 0.80))
    dr.line([(cx - r, cy + r * 0.55), (cx, cy + r * 0.8), (cx + r, cy + r * 0.55)],
            fill=OUTL, width=3)
    for (ox, oy) in offs:
        dr.arc([cx + ox - r, cy + oy - r * 0.85, cx + ox + r, cy + oy + r * 0.85],
               start=150, end=340, fill=OUTL, width=3)

def soft_shadow(dr, cx, cy, w, h, e):
    if e["nom"] == "night":
        return
    dr.ellipse([cx + w * 0.6, cy - h * 0.18, cx + w * 1.9, cy + h * 0.25],
               fill=(30, 60, 64, 70))

def scene(name, e):
    global SUN_POS, SUN_F
    SUN_POS = {"day": (470, 66), "dusk": (150, 300), "night": (760, 90)}[e["nom"]]
    SUN_F = {"day": (255, 243, 209), "dusk": (255, 214, 160), "night": (220, 230, 250)}[e["nom"]]
    hor = {"day": (219, 242, 219), "dusk": (242, 204, 158), "night": (26, 38, 56)}[e["nom"]]
    zen = {"day": (77, 189, 176), "dusk": (41, 87, 112), "night": (13, 23, 41)}[e["nom"]]
    gnd = (92, 112, 112) if e["nom"] != "night" else (26, 38, 56)
    im = grad_sky({"h": hor, "z": zen, "g": gnd})
    dr = ImageDraw.Draw(im, "RGBA")

    T = lambda c: tint(c, e)                      # palet diekspos sesuai jam
    TB = lambda c, f: band_shade(tint(c, e), f)

    # --- laut: dalam -> dangkal mengelilingi pulau
    dr.rectangle([0, 250, W, H], fill=T(PAL["shallow"]))
    dr.ellipse([-90, 300, W + 90, 640], fill=TB(PAL["deep"], 1.0))
    dr.ellipse([60, 320, 900, 600], fill=T(PAL["deep"]))
    dr.ellipse([150, 340, 810, 585], fill=T(PAL["shallow"]))
    for i in range(26):                            # rimbaan ombak kecil
        x = 70 + i * 35; y = 505 + (i % 2) * 9
        dr.arc([x, y, x + 26, y + 10], 200, 340, fill=(255, 255, 255, 110), width=2)

    # --- pulau: pasir krim + garis foam
    sketch_ellipse(dr, [170, 350, 790, 600], T(PAL["sand"]))
    dr.ellipse([180, 357, 780, 593], fill=T(PAL["sand"]))
    dr.ellipse([170, 350, 790, 600], outline=T(PAL["foam"]), width=7)
    dr.ellipse([195, 366, 765, 585], outline=TB(PAL["sand_d"], 1.0), width=2)

    # --- bukit rumput jade + batuan (band shading kontras rendah di tepi bawah)
    dr.ellipse([250, 340, 640, 520], fill=T(PAL["grass"]))
    dr.pieslice([250, 340, 640, 520], 20, 160, fill=T(band_shade(PAL["grass"], 0.82)))
    dr.ellipse([250, 340, 640, 520], outline=OUTL, width=3)
    dr.ellipse([430, 320, 720, 470], fill=T(PAL["grass_d"]))
    dr.pieslice([430, 320, 720, 470], 20, 160, fill=T(band_shade(PAL["grass_d"], 0.82)))
    dr.ellipse([430, 320, 720, 470], outline=OUTL, width=3)
    dr.ellipse([120, 470, 200, 520], fill=T(PAL["rock"])); dr.ellipse([120, 470, 200, 520], outline=OUTL, width=3)
    dr.ellipse([150, 452, 300, 512], fill=T(PAL["sage"])); dr.ellipse([150, 452, 300, 512], outline=OUTL, width=3)

    # Bayangan lembut objek (arah matahari kiri-atas)
    soft_shadow(dr, 320, 480, 60, 14, e)
    soft_shadow(dr, 700, 380, 90, 18, e)

    # --- pohon-pohon: jade + pinus + satu aksen oranye
    def tree(x, y, r, c1, c2):
        dr.rectangle([x - 4, y - 4, x + 4, y + r * 0.6], fill=T(PAL["trunk"]))
        dr.line([x - 6, y + r * 0.6, x + 6, y + r * 0.6], fill=OUTL, width=3)
        canopy(dr, x, y - r * 0.8, r * 0.55, TB(c1, 1.0), TB(c2, 1.02))
    tree(320, 470, 44, PAL["jade"], PAL["sage"])
    tree(430, 425, 52, PAL["jade_d"], PAL["jade"])
    tree(560, 445, 46, PAL["jade"], PAL["sage"])
    tree(700, 455, 44, PAL["orange"], PAL["ochre"])      # aksen oranye khas
    tree(225, 420, 40, PAL["pine"], PAL["jade_d"])

    # --- rumah krim + atap terracotta + pintu teal
    dr.rectangle([690, 330, 800, 405], fill=T(PAL["cream"]))
    dr.rectangle([690, 330, 800, 405], outline=OUTL, width=3)
    dr.polygon([(680, 332), (810, 332), (745, 285)], fill=T(PAL["terra"]), outline=OUTL)
    dr.line([(690, 336), (810, 336)], fill=TB(PAL["terra_d"], 1.0), width=2)
    dr.rectangle([735, 362, 757, 405], fill=T(PAL["teal"]), outline=OUTL, width=2)
    win_col = (255, 210, 120) if e["nom"] == "night" else band_shade(T(PAL["cream"]), 0.86)
    dr.rectangle([704, 348, 722, 372], fill=win_col, outline=OUTL, width=2)
    dr.rectangle([772, 348, 790, 372], fill=win_col, outline=OUTL, width=2)
    dr.line([(745, 285), (745, 275)], fill=OUTL, width=4)
    dr.ellipse([740, 268, 750, 278], fill=T(PAL["ochre"]), outline=OUTL)

    # --- kereta kantor pos mini + payung pantai + tanda
    dr.rectangle([196, 492, 226, 520], fill=T(PAL["ochre"]), outline=OUTL, width=2)
    dr.ellipse([186, 500, 206, 524], fill=band_shade(T(PAL["terra"]), 1.0), outline=OUTL, width=2)
    dr.line([226, 500, 244, 492], fill=OUTL, width=3)
    px_, py = 350, 525
    dr.line([px_, py - 60, px_, py], fill=T(PAL["trunk"]), width=4)
    dr.polygon([(px_ - 52, py - 48), (px_ + 52, py - 48), (px_, py - 86)],
               fill=T(PAL["terra"]))
    dr.pieslice([px_ - 52, py - 92, px_ + 52, py - 40], 180, 360, fill=T(PAL["terra"]))
    dr.polygon([(px_ - 16, py - 86), (px_ + 16, py - 86), (px_, py - 48 * 0 - 48)],
               fill=T(PAL["cream"]))
    dr.arc([px_ - 52, py - 92, px_ + 52, py - 40], 180, 360, fill=OUTL, width=3)
    dr.line([px_ - 52, py - 48, px_ + 52, py - 48], fill=OUTL, width=3)

    # --- surat kirim di-ground (ikon kecil) + lampu taman
    dr.polygon([(610, 500), (632, 500), (632, 512), (610, 512)], fill=T(PAL["cream"]), outline=OUTL)
    dr.line([610, 500, 621, 507, 632, 500], fill=T(PAL["terra"]))
    dr.line([830, 350, 830, 420], fill=T(PAL["teal"]), width=4)
    dr.ellipse([822, 336, 838, 356], fill=SUN_F, outline=OUTL, width=2)

    return im.convert("RGB")

def metrics(np_img, name):
    lum = (np_img.astype(np.float32) / 255.0) @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    m, over, und = lum.mean(), (lum > 0.97).mean() * 100, (lum < 0.02).mean() * 100
    ok = (over < 2.0 and und < 2.0 and (m > 0.4 if name == "day" else m > 0.12))
    print(f"[{name}] mean_luma={m:.3f} over={over:.2f}% under={und:.2f}%  " + ("OK" if ok else "SESUAIKAN"))

def main():
    os.makedirs(OUT, exist_ok=True)
    for name, e in ENV.items():
        im = scene(name, e)
        im.save(os.path.join(OUT, f"style_{name}.png"))
        metrics(np.asarray(im), name)
        print("saved style_%s.png" % name)

if __name__ == "__main__":
    main()
