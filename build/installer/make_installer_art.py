"""
make_installer_art.py - builds the branded bitmaps for the MSI's setup dialogs.

    python build/installer/make_installer_art.py

    dialog.bmp  493x312  welcome / finish screens; the art fills the left
                         164 px, the dialog draws its text on the white right side
    banner.bmp  493x58   top strip of the inner screens; the dialog draws its
                         title on the white left side, the logo sits at the right

Reuses the hero scene and logo helpers from assets/readme/source/make_art.py.
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'assets', 'readme', 'source'))
import make_art  # noqa: E402

PANEL_W = 164
LOGO = os.path.join(ROOT, 'images', 'logo.png')


def make_dialog(out):
    W, H = 493, 312
    img = Image.new('RGB', (W, H), 'white')
    scene = Image.open(make_art.SCENE).convert('RGB')
    sw, sh = scene.size
    # Tall slice around the figure reaching for the star (right of centre).
    ch = sh
    cw = int(ch * PANEL_W / H)
    cx = int(sw * 0.66)
    panel = scene.crop((cx - cw // 2, 0, cx + cw // 2, ch)).resize((PANEL_W, H), Image.LANCZOS)
    img.paste(panel, (0, 0))
    logo = Image.open(LOGO).convert('RGBA').resize((64, 64), Image.LANCZOS)
    img.paste(logo, ((PANEL_W - 64) // 2, 18), logo)
    ImageDraw.Draw(img).line([(PANEL_W, 0), (PANEL_W, H)], fill=(220, 224, 232))
    img.save(out)


def make_banner(out):
    W, H = 493, 58
    img = Image.new('RGB', (W, H), 'white')
    logo = Image.open(LOGO).convert('RGBA').resize((44, 44), Image.LANCZOS)
    img.paste(logo, (W - 44 - 10, (H - 44) // 2), logo)
    ImageDraw.Draw(img).line([(0, H - 1), (W, H - 1)], fill=(220, 224, 232))
    img.save(out)


if __name__ == '__main__':
    make_dialog(os.path.join(HERE, 'dialog.bmp'))
    make_banner(os.path.join(HERE, 'banner.bmp'))
    print('wrote dialog.bmp, banner.bmp')
