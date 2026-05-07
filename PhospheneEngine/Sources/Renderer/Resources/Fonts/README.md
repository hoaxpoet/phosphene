# Dashboard Fonts

## SF Mono (system — no installation required)

SF Mono is the system monospaced font used for BPM readouts, axis ticks, and
numeric labels. It is accessed at runtime via
`NSFont.monospacedSystemFont(ofSize:weight:)` — no files to place here.

## Epilogue (optional — prose labels)

Epilogue is the dashboard's prose font, used for panel headers and section labels.
It is available from [Fontshare](https://www.fontshare.com/fonts/epilogue) and
[Google Fonts](https://fonts.google.com/specimen/Epilogue) under the **SIL Open
Font License 1.1**.

**To enable Epilogue:**

1. Download `Epilogue-Regular.ttf` and `Epilogue-Medium.ttf` from either source.
2. Place both files in this directory:
   ```
   PhospheneEngine/Sources/Renderer/Resources/Fonts/Epilogue-Regular.ttf
   PhospheneEngine/Sources/Renderer/Resources/Fonts/Epilogue-Medium.ttf
   ```
3. Rebuild. `DashboardFontLoader.resolveFonts()` detects the files at launch and
   registers them automatically. `FontResolution.proseCustomLoaded` will be `true`.

**Without these files** (the default for new checkouts), the dashboard falls back
to the system sans-serif font. This is the expected state for development and CI.
The fallback is intentional — do not commit the TTF files to git.

## Clash Display (optional — card titles and state headlines)

Clash Display is the dashboard's display font, used for card titles (BEAT, STEMS,
PERF) and SwiftUI state headlines per `.impeccable.md`. It is available from
[Fontshare](https://www.fontshare.com/fonts/clash-display) under a free license.

**To enable Clash Display:**

1. Download `ClashDisplay-Medium.otf` (or `.ttf`) from Fontshare.
2. Place it in this directory:
   ```
   PhospheneEngine/Sources/Renderer/Resources/Fonts/ClashDisplay-Medium.otf
   ```
3. Rebuild. `DashboardFontLoader.resolveFonts()` registers it automatically.
   `FontResolution.displayCustomLoaded` will be `true`.

**Without this file**, the dashboard falls back to the system sans-serif at
semibold weight. The fallback is intentional — do not commit the OTF to git.

## Adding fonts to .gitignore

The `.gitignore` at the repo root already excludes `*.ttf` and `*.otf` from
`Resources/Fonts/` so font binaries cannot be accidentally committed.
