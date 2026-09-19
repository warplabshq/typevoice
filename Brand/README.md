# Brand assets

Rendered from the app icon and the site's serif by `swift Tools/brand.swift build/AppIcon.iconset Brand Brand/out`
(run `make icon` first to produce the iconset). Everything in `out/` is a PNG at full resolution.

| File | Use |
|---|---|
| `icon-1024.png`, `-512`, `-256`, `-128` | Product image / logo fields (Dodo, directories, press). Square, no padding. |
| `product-tile-1200.png` | Square listing tile: icon, name, tagline on the dark field. |
| `lockup-dark.png`, `lockup-light.png` | Icon + wordmark on a background, 2400×800. |
| `lockup-transparent-for-dark.png`, `-for-light.png` | Same, transparent, for placing on your own background. |
| `wordmark-white.png`, `wordmark-black.png` | The name alone, transparent. |
| `banner-2400x1000.png` | Wide hero for storefronts and announcements. |

The waveform's numbers live in `Sources/TypeVoice/UI/BrandWave.swift`; the font is
Instrument Serif (SIL OFL, `OFL.txt`). The name and icon are trademarks — see `TRADEMARKS.md`.
