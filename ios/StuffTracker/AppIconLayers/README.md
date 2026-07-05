# App Icon Layers

These 1024 x 1024 PNGs preserve the original rendered app icon while exposing
separate source layers. `source-light-original.png` and
`source-dark-original.png` are the visual source of truth.

Import the generated layer files into Icon Composer in numeric order:

1. `01-background.png`
2. `02-binders.png`
3. `03-box-and-papers.png`
4. `04-photo-and-fabric.png`
5. `05-keys.png`
6. `06-highlights.png`

`preview-flattened.png` is a recomposed reference image. The shipped iOS and
web icons are restored from the original source render with:

```sh
python3 scripts/generate_app_icon_layers.py
```
