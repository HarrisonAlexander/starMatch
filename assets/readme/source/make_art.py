"""
make_art.py - builds every TrueHire brand image.

    python assets/readme/source/make_art.py

The scene art is AI-generated once through the Higgsfield API and kept in this
folder; this script only crops it and draws the exact TrueHire typography on
top, so text is always crisp and correctly spelled.

    hero-scene.jpg  Seedream 5.0 Pro, 16:9 2k  (prompt: hero-scene-prompt.txt)
    hero-anim.mp4   Seedance 2.5 image-to-video from hero-scene.jpg, 5 s 720p
                    (prompt: hero-anim-prompt.txt)

Outputs (paths relative to the repo root):
    images/logo.png              512x512 app logo (drawn in code)
    icon.ico                     16..256 multi-size window/taskbar icon
    images/banner.png            2172x393 in-app header (wordmark baked in)
    assets/readme/hero.png       1600x800 README hero
    assets/readme/hero.gif       960x480 animated README hero
    assets/readme/social-preview.png  1280x640 GitHub social card
    assets/readme/app-on-laptop.jpg   dashboard screenshot on the laptop mockup
                                      (run tools/Capture-Screenshots.ps1 first)

Needs Pillow, numpy, ffmpeg and Montserrat Regular/Bold from the Windows fonts folder.
"""
import math
import os
import shutil
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
FONT_DIR = r'C:\Windows\Fonts'
BOLD = os.path.join(FONT_DIR, 'Montserrat-Bold.ttf')
REG = os.path.join(FONT_DIR, 'Montserrat-Regular.ttf')
SCENE = os.path.join(HERE, 'hero-scene.jpg')
ANIM = os.path.join(HERE, 'hero-anim.mp4')

GOLD = (245, 166, 35)
GOLD_HI = (255, 214, 102)
CREAM = (255, 248, 234)
MIST = (216, 220, 240)

EYEBROW = 'BEHAVIORAL INTERVIEW ANALYTICS  ·  WINDOWS DESKTOP'
TAGLINE = 'Structured interviews, ranked by evidence.'

# ---------------------------------------------------------------- helpers
def lerp(a, b, t):
    return a + (b - a) * t


def gradient(w, h, stops):
    """Vertical gradient; stops = [(pos 0..1, (r,g,b)), ...]."""
    ys = np.linspace(0, 1, h)
    out = np.zeros((h, 3))
    for c in range(3):
        out[:, c] = np.interp(ys, [s[0] for s in stops], [s[1][c] for s in stops])
    arr = np.repeat(out[:, None, :], w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), 'RGB')


def glow(size, center, radius, color, strength):
    """Additive radial glow layer as RGBA."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    a = np.clip(np.exp(-d * d * 2.2) * strength, 0, 1)
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = color
    arr[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr, 'RGBA')


def star_polygon(cx, cy, r, inner=0.45, rot=-math.pi / 2):
    pts = []
    for k in range(10):
        rr = r if k % 2 == 0 else r * inner
        a = rot + k * math.pi / 5
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def text_spaced(draw, xy, text, font, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + spacing
    return x


def spaced_width(draw, text, font, spacing):
    return sum(draw.textlength(ch, font=font) for ch in text) + spacing * (len(text) - 1)



# ---------------------------------------------------------------- typography
def text_overlay(w, h, cx, top, size, eyebrow=True, tagline=True, vignette=0.42):
    """Transparent RGBA layer with the TrueHire wordmark (+ eyebrow/tagline)."""
    lay = Image.new('RGBA', (w, h))
    if vignette:
        lay.alpha_composite(glow((w, h), (cx, top + size * 0.9), size * 4.2, (8, 16, 38), vignette))
    fb, fr = ImageFont.truetype(BOLD, size), ImageFont.truetype(REG, round(size * 0.27))
    fe = ImageFont.truetype(BOLD, round(size * 0.12))
    d = ImageDraw.Draw(lay)
    y = top
    if eyebrow:
        sp = size * 0.03
        text_spaced(d, (cx - spaced_width(d, EYEBROW, fe, sp) / 2, y), EYEBROW, fe, GOLD, sp)
        y += size * 0.36
    wt = d.textlength('True', font=fb)
    x = cx - (wt + d.textlength('Hire', font=fb)) / 2
    gl = Image.new('RGBA', (w, h))
    gd = ImageDraw.Draw(gl)
    gd.text((x, y), 'True', font=fb, fill=(255, 230, 170, 150))
    gd.text((x + wt, y), 'Hire', font=fb, fill=(255, 190, 80, 170))
    lay.alpha_composite(gl.filter(ImageFilter.GaussianBlur(size * 0.09)))
    d = ImageDraw.Draw(lay)
    d.text((x, y), 'True', font=fb, fill=CREAM)
    d.text((x + wt, y), 'Hire', font=fb, fill=GOLD_HI)
    if tagline:
        y += size * 1.22
        d.text((cx - d.textlength(TAGLINE, font=fr) / 2, y), TAGLINE, font=fr, fill=MIST)
    return lay


def crop_rel(img, aspect, y_center):
    """Full-width crop to the given aspect, centred at y_center (0..1 of height)."""
    w, h = img.size
    ch = round(w / aspect)
    y0 = min(max(0, round(h * y_center - ch / 2)), h - ch)
    return img.crop((0, y0, w, y0 + ch))


HERO_Y = 0.555      # keeps the star, figure and peak; trims empty sky
BANNER_Y = 0.60     # band holding the star and figure for the 5.5:1 header


def make_wide(out, w, h):
    img = crop_rel(Image.open(SCENE).convert('RGB'), w / h, HERO_Y).resize((w, h), Image.LANCZOS).convert('RGBA')
    img.alpha_composite(text_overlay(w, h, w * 0.33, h * 0.24, round(h * 0.19)))
    img.convert('RGB').save(out)


def make_banner(out, w=2172, h=393):
    """The app shows this UniformToFill in a 216 px row, so wide windows crop
    top and bottom: keep the wordmark vertically centred."""
    img = crop_rel(Image.open(SCENE).convert('RGB'), w / h, BANNER_Y).resize((w, h), Image.LANCZOS).convert('RGBA')
    img.alpha_composite(text_overlay(w, h, w * 0.40, h * 0.25, round(h * 0.42), eyebrow=False, tagline=False, vignette=0.5))
    img.convert('RGB').save(out)


def make_gif(out, w=960, h=480, fps=10):
    tmp = tempfile.mkdtemp()
    try:
        # hqdn3d strips the art's film grain, which otherwise defeats GIF compression
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', ANIM, '-vf', f'fps={fps},hqdn3d=6:4:8:6',
                        os.path.join(tmp, 'f%03d.png')], check=True)
        overlay = text_overlay(w, h, w * 0.33, h * 0.24, round(h * 0.19))
        for name in sorted(os.listdir(tmp)):
            p = os.path.join(tmp, name)
            fr = crop_rel(Image.open(p).convert('RGB'), w / h, HERO_Y).resize((w, h), Image.LANCZOS).convert('RGBA')
            fr.alpha_composite(overlay)
            fr.convert('RGB').save(p)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', str(fps), '-i', os.path.join(tmp, 'f%03d.png'),
                        '-vf', 'split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle',
                        '-loop', '0', out], check=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- logo
def make_logo(path_png, path_ico):
    S = 1024
    img = Image.new('RGBA', (S, S))
    tile = gradient(S, S, [(0, (20, 58, 92)), (1, (8, 30, 52))]).convert('RGBA')
    mask = Image.new('L', (S, S))
    ImageDraw.Draw(mask).rounded_rectangle([24, 24, S - 24, S - 24], radius=210, fill=255)
    img.paste(tile, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([24, 24, S - 24, S - 24], radius=210, outline=(60, 100, 140, 255), width=6)
    # gold check, long arm reaching up to a star
    pts = [(250, 545), (420, 715), (700, 410)]
    glow_l = Image.new('RGBA', (S, S))
    ImageDraw.Draw(glow_l).line(pts, fill=(255, 190, 80, 200), width=150, joint='curve')
    img.alpha_composite(glow_l.filter(ImageFilter.GaussianBlur(40)))
    chk = Image.new('RGBA', (S, S))
    cd = ImageDraw.Draw(chk)
    cd.line(pts, fill=GOLD + (255,), width=118, joint='curve')
    for p in (pts[0], pts[-1]):
        cd.ellipse([p[0] - 59, p[1] - 59, p[0] + 59, p[1] + 59], fill=GOLD + (255,))
    shade = gradient(S, S, [(0, GOLD_HI), (1, (226, 138, 18))]).convert('RGBA')
    shade.putalpha(chk.getchannel('A'))
    img.alpha_composite(shade)
    sx, sy, sr = 790, 270, 130
    img.alpha_composite(glow((S, S), (sx, sy), 230, (255, 220, 140), 0.55))
    st = Image.new('RGBA', (S, S))
    sd = ImageDraw.Draw(st)
    sd.polygon(star_polygon(sx, sy, sr, inner=0.47), fill=CREAM + (255,))
    img.alpha_composite(st)
    img.resize((512, 512), Image.LANCZOS).save(path_png)
    sizes = [16, 24, 32, 48, 64, 128, 256]
    img.resize((256, 256), Image.LANCZOS).save(path_ico, sizes=[(s, s) for s in sizes])


# ---------------------------------------------------------------- laptop
def make_laptop(shot_path, out):
    """Key the dashboard screenshot into the green screen of laptop-greenscreen.png."""
    lap = np.asarray(Image.open(os.path.join(HERE, 'laptop-greenscreen.png')).convert('RGB')).astype(np.int32)
    r, g, b = lap[..., 0], lap[..., 1], lap[..., 2]
    key = (g > 150) & (g > r + 60) & (g > b + 60)
    ys, xs = np.where(key)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    lim = np.maximum(r, b)
    lap[..., 1] = np.where(g > lim + 6, lim + 6, g)          # despill the bezel
    shot = Image.open(shot_path).convert('RGB').resize((x1 - x0 + 1, y1 - y0 + 1), Image.LANCZOS)
    m = Image.fromarray((key[y0:y1 + 1, x0:x1 + 1] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))
    m = np.asarray(m).astype(float)[..., None] / 255
    lap[y0:y1 + 1, x0:x1 + 1] = np.asarray(shot) * m + lap[y0:y1 + 1, x0:x1 + 1] * (1 - m)
    img = Image.fromarray(np.clip(lap, 0, 255).astype(np.uint8))
    img.resize((1600, round(img.height * 1600 / img.width)), Image.LANCZOS).save(out, quality=88)



# ---------------------------------------------------------------- main
if __name__ == '__main__':
    img_dir, readme = os.path.join(ROOT, 'images'), os.path.join(ROOT, 'assets', 'readme')
    make_logo(os.path.join(img_dir, 'logo.png'), os.path.join(ROOT, 'icon.ico'))
    make_banner(os.path.join(img_dir, 'banner.png'))
    make_wide(os.path.join(readme, 'hero.png'), 1600, 800)
    make_wide(os.path.join(readme, 'social-preview.png'), 1280, 640)
    make_gif(os.path.join(readme, 'hero.gif'))
    shot = os.path.join(ROOT, 'docs', 'screenshots', '01-TabDashboard.png')
    if os.path.exists(shot):
        make_laptop(shot, os.path.join(readme, 'app-on-laptop.jpg'))
    print('done')
