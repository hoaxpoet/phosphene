# DS.3 task 1 — the three severity-to-colour maps, before consolidation

Every cell read from source at branch point (`main` @ 86fc943b). No cell inferred.

## Before

Four surfaces. Two source enums. Three independent colour maps.

| Severity | Full-screen<br>`FullScreenErrorView` : 112–128<br>`PreparationFailureView` : 116–132 | Toast<br>`ToastView` : 70–76 | Banner<br>`TopBannerView` : 30–57 | Inline<br>`LocalFileErrorBanner` : 109–114 |
|---|---|---|---|---|
| `info` | `UzumeAppColor.textPrimary` #F4F6F1<br>`info.circle` | `Status.infoForeground` #64D2FF<br>*(no icon — 4pt accent bar)* | — | — |
| `warning` | `.orange` **system** <br>`exclamationmark.circle` | `Status.warningForeground` #FFD60A<br>*(no icon)* | — | — |
| `degradation` | `.yellow` **system**<br>`exclamationmark.triangle` | `Status.dangerForeground` #FF8A75<br>*(no icon)* | — | — |
| `fatal` | `.red` **system**<br>`xmark.circle` | *(not representable — `UzumeToast.Severity` has no `fatal`; `PlaybackErrorBridge` : 203 folds `.fatal` into `.degradation`)* | — | — |
| *(severity ignored)* | — | — | fill `UzumeAppColor.warning` #FFD60A @ 0.88<br>text/icon `onAccent` #0B0C10<br>`exclamationmark.triangle.fill` | pip `UzumeAppColor.danger` #FF8A75<br>text `textSecondary` #C5C9C3<br>*(no icon — 6pt circle)* |

### Conflict 1 — `degradation` renders yellow on the full-screen surfaces and red in toasts.

`FullScreenErrorView` : 125 and `PreparationFailureView` : 129 both return `.yellow` for `degradation`, positioning it as the middle step between `.orange` warning and `.red` fatal. `ToastView` : 74 returns `Status.dangerForeground` — the same red it would use for a fatal error, and the loudest colour on a playing screen. One severity, two opposite readings, because two authors wrote two maps.

### Conflict 2 — the banner ignores severity entirely.

`TopBannerView` takes `error: UserFacingError` (line 18) but never reads `error.severity`. Its fill is hard-coded `UzumeAppColor.warning.opacity(0.88)` at line 57. All three errors routed to `.topBanner` by `presentationMode` — `previewRateLimited`, `preparationSlowOnFirstTrack`, `preparationTotalTimeout` — render identically amber, and a `degradation` banner is pixel-identical to a `warning` banner.

## Secondary findings recorded while filling the table

- **The prompt's `DashboardTokens.Color.coral` claim is stale.** `LocalFileErrorBanner` : 110 reads `UzumeAppColor.danger`, not `DashboardTokens`. DS.1 already moved it off the diagnostic palette; the census (`PHOSPHENE-COMPONENT-CENSUS.md` : 157) still lists the local-file error banner as a `DashboardTokens` consumer. Recorded in UPSTREAM-FINDINGS.md. The rest of task 5's instruction for this component — move it out of the store file, keep the 6-second clear, tap-to-dismiss, no background — is unaffected.
- **`ToastView` is already tokenized.** DS.1 moved it onto `UzumeAppColor.Status.*`. Its DS.3 defect is not raw colour but that the map is written inline, and that it disagrees with the full-screen map on `degradation`.
- **The full-screen surfaces are the only raw-system-colour holdouts** (`.red` / `.orange` / `.yellow`), and both copies are byte-identical.
- **`.fatal` reaches a toast.** `PlaybackErrorBridge` : 203 maps both `.degradation` and `.fatal` onto `UzumeToast.Severity.degradation`, so the narrower app enum loses the distinction before `ToastView` ever sees it. `StatusTone` cannot recover it; the collapse happens upstream of presentation and is out of scope (do-NOT: bridge/severity assignment unchanged).
