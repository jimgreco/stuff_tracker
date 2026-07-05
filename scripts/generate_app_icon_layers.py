#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
LAYER_DIR = ROOT / "ios/StuffTracker/AppIconLayers"
APPICON_DIR = ROOT / "ios/StuffTracker/Assets.xcassets/AppIcon.appiconset"
WEB_ICON = ROOT / "web/assets/app-icon.png"
LIGHT_SOURCE = LAYER_DIR / "source-light-original.png"
DARK_SOURCE = LAYER_DIR / "source-dark-original.png"
SIZE = 1024


def rounded(mask, xy, radius):
    ImageDraw.Draw(mask).rounded_rectangle(xy, radius=radius, fill=255)


def ellipse(mask, xy):
    ImageDraw.Draw(mask).ellipse(xy, fill=255)


def polygon(mask, points):
    ImageDraw.Draw(mask).polygon(points, fill=255)


def layer_from_mask(source, mask):
    layer = Image.new("RGBA", source.size, (0, 0, 0, 0))
    layer.alpha_composite(source.convert("RGBA"))
    layer.putalpha(mask)
    return layer


def build_masks():
    binders = Image.new("L", (SIZE, SIZE), 0)
    rounded(binders, (130, 185, 324, 835), 42)
    rounded(binders, (280, 185, 470, 835), 40)

    box = Image.new("L", (SIZE, SIZE), 0)
    rounded(box, (430, 130, 910, 635), 46)
    rounded(box, (445, 300, 875, 615), 34)
    polygon(box, [(525, 105), (835, 115), (860, 310), (500, 315)])
    rounded(box, (430, 520, 930, 650), 26)

    photo_fabric = Image.new("L", (SIZE, SIZE), 0)
    polygon(photo_fabric, [(410, 515), (735, 480), (765, 775), (390, 815)])
    rounded(photo_fabric, (420, 625, 875, 865), 42)

    keys = Image.new("L", (SIZE, SIZE), 0)
    ellipse(keys, (700, 555, 890, 745))
    ellipse(keys, (845, 620, 940, 720))
    polygon(keys, [(710, 650), (825, 720), (690, 890), (610, 835)])
    rounded(keys, (630, 760, 765, 890), 18)

    highlights = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(highlights)
    draw.arc((10, 6, 1012, 1018), 203, 337, fill=255, width=20)
    draw.arc((55, 55, 968, 970), 203, 337, fill=255, width=12)

    object_union = Image.new("L", (SIZE, SIZE), 0)
    for mask in [binders, box, photo_fabric, keys, highlights]:
        object_union = ImageChops.lighter(object_union, mask)

    background = ImageChops.invert(object_union)
    return [
        ("01-background.png", background),
        ("02-binders.png", binders),
        ("03-box-and-papers.png", box),
        ("04-photo-and-fabric.png", photo_fabric),
        ("05-keys.png", keys),
        ("06-highlights.png", highlights),
    ]


def main():
    LAYER_DIR.mkdir(parents=True, exist_ok=True)
    source = Image.open(LIGHT_SOURCE).convert("RGBA")
    dark_source = Image.open(DARK_SOURCE).convert("RGB")

    masks = build_masks()
    for stale in LAYER_DIR.glob("0[1-9]-*.png"):
        stale.unlink()
    preview_path = LAYER_DIR / "preview-flattened.png"
    if preview_path.exists():
        preview_path.unlink()

    layers = []
    for filename, mask in masks:
        layer = layer_from_mask(source, mask)
        layer.save(LAYER_DIR / filename, optimize=True)
        layers.append(layer)

    preview = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for layer in layers:
        preview.alpha_composite(layer)
    preview = preview.convert("RGB")

    source.convert("RGB").save(APPICON_DIR / "icon-1024.png", optimize=True)
    dark_source.save(APPICON_DIR / "icon-1024-dark.png", optimize=True)
    source.convert("RGB").save(WEB_ICON, optimize=True)
    preview.save(LAYER_DIR / "preview-flattened.png", optimize=True)

    for path in sorted(LAYER_DIR.glob("*.png")) + [
        APPICON_DIR / "icon-1024.png",
        APPICON_DIR / "icon-1024-dark.png",
        WEB_ICON,
    ]:
        with Image.open(path) as image:
            print(f"{path.relative_to(ROOT)}: {image.mode} {image.size}")


if __name__ == "__main__":
    main()
