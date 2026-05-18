# Lumen Mosaic — Palette Library (design artifacts)

The 18 palettes that Lumen Mosaic samples from at LM.4.7 onward. Authored 2026-05-17 in the palette exploration conversation; decisions filed at D-LM-palette-library + D-LM-cream-rescission (2026-05-18). Per-song selection per D-LM-palette-library amendment (2026-05-18).

These HTML files are the **authoritative design intent** for the palette library — named hex anchors, role groupings (ground / light / anchor), panel-preview character. The Swift implementation in `PhospheneEngine/Sources/Presets/LumenMosaicPaletteLibrary.swift` (lands at LM.4.7) is the source of truth for the colour values that ship; if the Swift and the HTML disagree on a hex value, the implementer should reconcile against this directory before merging.

## Plate index

| Plate | Name | File | Character |
|---|---|---|---|
| 01 | Autumnal | `lumen_mosaic_palettes.html` | Burning maple / oxblood / mossy bottle-green / copper. Saturated harvest. |
| 02 | Refn Glow | `lumen_mosaic_palettes.html` | Sodium-vapour neon over hard noir. *Drive* / *Neon Demon* / *Only God Forgives*. |
| 03 | Glacier | `lumen_mosaic_palettes.html` | Saturated ice. Crevasse blues, aurora green and magenta veils, sodium-lamp accent. |
| 04 | Art Deco | `lumen_mosaic_palettes.html` | Chrysler Building / Gatsby smoking room. Brass and onyx anchor; emerald, sapphire, ruby, jade. |
| 05 | Abyssal Bioluminescence | `lumen_mosaic_palettes.html` | Mariana-trench dark base with electric jewel glows. Two near-black anchors. |
| 06 | Kintsugi | `lumen_mosaic_palettes.html` | Japanese pottery repaired with gold. Sumi-ink + indigo base, gold seam + saffron accents. |
| 07 | Carnival | `lumen_mosaic_palettes.html` | Día de Muertos altar / papel picado / Caribbean folk-art. Maximum saturation, zero apology. |
| 08 | Holi | `lumen_mosaic_palettes_vol2.html` | Indian spring festival gulal pigments. Pink–turmeric–vermilion–Krishna-blue. |
| 09 | Geode | `lumen_mosaic_palettes_vol2.html` | Gemstone cross-sections. Citrine, amethyst, peridot, malachite. |
| 10 | Rothko Chapel | `lumen_mosaic_palettes_vol2.html` | Late Rothko, Houston 1971. Oxblood, plum, aubergine, burnt sienna. Low-value high-chroma. |
| 11 | Tropical Aviary | `lumen_mosaic_palettes_vol2.html` | Scarlet macaw / toucan / quetzal / Morpho butterfly. Biological-extreme primaries. |
| 12 | Persian Miniature | `lumen_mosaic_palettes_vol2.html` | Safavid manuscript painting. Lapis ground, malachite, vermilion, saffron, gold leaf. |
| 13 | Ukiyo-e | `lumen_mosaic_palettes_vol2.html` | Edo woodblock. Prussian blue, willow green, susuki gold, sakura cerise. |
| 14 | Cathedral Lights | `cathedral_lights.html` | Chartres / Sainte-Chapelle / Saint-Denis. Jewel-tone ground with cream/honey/ivory highlights. **Cream-rescission proof point.** |
| 15 | Cycladic | `cream_and_charcoal.html` | Greek island whitewash. Limewash + Crete sand + Aegean foam ground; cobalt + bougainvillea. |
| 16 | Ming Porcelain | `cream_and_charcoal.html` | Jingdezhen kilns 14th–18th c. Porcelain + pale celadon ground; underglaze cobalt + sang-de-boeuf. |
| 17 | Tenebrism | `cream_and_charcoal.html` | Caravaggio late 1590s. Black ground + dramatic warm light. Candle flame gold, vermilion robe, lapis drapery. |
| 18 | Obsidian | `cream_and_charcoal.html` | Volcanic geology. Obsidian glass + basalt + ash anchors; magma orange + sulfur yellow + cinder red. |

## Mood-anchor authoring notes

Each palette declares a `moodAnchor: SIMD2<Float>` in normalised mood space `(valence, arousal) ∈ [-1, +1]`. The 18 anchors are the implementer's call to set at LM.4.7 time; the descriptive characters above are the input. Indicative anchors:

- **High-valence high-arousal:** Carnival, Holi, Tropical Aviary, Refn Glow
- **High-valence low-arousal:** Cycladic, Ming Porcelain, Persian Miniature, Ukiyo-e
- **Low-valence high-arousal:** Abyssal Bioluminescence, Obsidian, Glacier (cold-bright), Geode
- **Low-valence low-arousal:** Rothko Chapel, Tenebrism, Cathedral Lights, Kintsugi
- **Mid-mid (neutral):** Autumnal, Art Deco

These are starting points, not commitments. Matt's M7 review on real music is the load-bearing tuning surface.

## Pale-tone-share audit (per D-LM-cream-rescission)

Each palette must pass the LM.9 pale-tone-share gate (≤ 0.30 of cells; pale = linear RGB `min(R, G, B) > 0.65`). At authoring time, the per-palette pale-share is the count of palette entries satisfying the pale predicate, divided by 12. Computed counts under the rule's exact definition:

| Palette | Pale entries | Palette pale-share |
|---|---|---|
| Cathedral Lights | `F2DEAC`, `EDE4D1` | 2 / 12 ≈ 16.7 % |
| Cycladic | `F8F4EB`, `E0F2EE` | 2 / 12 ≈ 16.7 % |
| Ming Porcelain | `F5EFE0`, `D7E4D0` | 2 / 12 ≈ 16.7 % |
| Obsidian | `C7DCE2` (Snowmelt) | 1 / 12 ≈ 8.3 % |
| All other 14 palettes | — | 0 / 12 = 0 % |

Note: Cycladic's Crete sand `E8D3A3` has `min(R, G, B) = 0.639`, just under the 0.65 threshold, and does NOT count as pale by the rule's mechanical definition (even though the design narrative groups it with the cream register). Same for Cathedral Lights's beeswax honey `E8B95B` and sky pane `87B4D9`.

No palette in the library is at the 30 % ceiling; the gate has comfortable margin (≥ 13 percentage points on Cathedral Lights, the highest-pale member). A future palette addition that approaches 30 % needs explicit M7 sign-off.

## Provenance

- 2026-05-17 — Matt + Claude design conversation produced all 18 palettes in four HTML artifacts.
- 2026-05-18 — D-LM-palette-library + D-LM-cream-rescission filed; HTML files committed to this directory as design artifacts.
- LM.4.7 (planned) — implementation ships `LumenMosaicPaletteLibrary.swift` with these 18 palettes.
