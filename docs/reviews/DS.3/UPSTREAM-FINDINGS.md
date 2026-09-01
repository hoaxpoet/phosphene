# DS.3 — findings for `uzume-site`

Read-only observations from adopting the status roles in the app. Nothing was
committed to `uzume-site`. Each names the app file that motivated it.

---

## 1. The app carries two severity vocabularies, and the design system models neither

`COMPONENTS.md` § Status placements names the four placements and says they share
"status tone and icon rules". It does not say what a tone is a function *of*. The app
has two answers, at different widths:

| Vocabulary | Where | Cases |
|---|---|---|
| `ErrorSeverity` | `UzumeEngine/Sources/Shared/UserFacingError+Presentation.swift:29` — engine-owned | `info`, `warning`, `degradation`, `fatal` |
| `UzumeToast.Severity` | `UzumeApp/Models/UzumeToast.swift:18` — app-owned | `info`, `warning`, `degradation` |

Neither matches the published role set (`info`, `success`, `warning`, `danger`), and
they do not match each other. The toast enum has no `fatal`, so
`UzumeApp/Services/PlaybackErrorBridge.swift:203` folds `fatal` into `degradation`
before a toast is ever built — a real distinction lost upstream of presentation, which
no amount of tone work in the view layer can recover.

**Two consequences the design system should know about.**

- **`degradation` has no home in the published roles.** It is the app's name for
  "Uzume still works, but something is compromised", and the four roles have no such
  step. DS.3 resolved it by mapping onto `warning` (D-235); the alternative Matt was
  offered was inventing a fifth colour, which the vendored-token discipline exists to
  prevent. If the design system ever wants to model degraded operation as its own
  thing, this is the case for it.
- **`success` has no producer.** `StatusTone.success` exists because the role set is
  four, but neither source vocabulary can express it — both describe things going
  wrong. The first non-error status surface will be its first consumer.

## 2. The tone mapping as built

`UzumeApp/Views/Components/StatusTone.swift`. Every tone resolves to a
`--color-status-*` triple plus one SF Symbol; dark block only, no appearance branch
(per D-232).

| Source severity | → tone | Token triple | Symbol |
|---|---|---|---|
| `ErrorSeverity.info` / `UzumeToast.Severity.info` | `info` | `#64D2FF` on `#102735`, border `#1976A3` | `info.circle` |
| `ErrorSeverity.warning` / `UzumeToast.Severity.warning` | `warning` | `#FFD60A` on `#282400`, border `#8C7600` | `exclamationmark.triangle` |
| `ErrorSeverity.degradation` / `UzumeToast.Severity.degradation` | `warning` | as above | `exclamationmark.triangle` |
| `ErrorSeverity.fatal` | `danger` | `#FF8A75` on `#321914`, border `#C55646` | `xmark.circle` |
| *(no producer)* | `success` | `#67D6A2` on `#122B21`, border `#2E835E` | `checkmark.circle` |

## 3. No `--color-status-*` role proved unusable, but only three of four triples get used whole

Task 10 asks which roles failed at the app's contrast requirements. **None did.** The
triples were adopted as published, and the flip they cause on the banner — from an
amber fill with near-black text to bright yellow on a deep field — is the increment's
largest visible change and went to Matt at the M7 hard stop.

Worth recording, though: **the four placements consume the triple at four different
depths**, and only two use all three values.

| Placement | foreground | background | border |
|---|---|---|---|
| `NoticeBanner` | text + icon | strip fill | 1pt bottom rule |
| `RecoveryScreen` | icon only (at 0.7) | — (sits on `--color-canvas`) | — |
| `InlineNotice` | 6pt pip only | — (deliberately none) | — |
| `PerformanceToast` | 4pt accent bar + action label | — (`.ultraThinMaterial`) | — |

The two quiet placements take **only the foreground**, and do so against the app
canvas rather than the tone's own background — a contrast pairing the published triple
does not describe, since it assumes foreground-on-its-own-background. It holds
comfortably here — measured, not assumed:

| Pairing | Ratio |
|---|---|
| `danger` fg `#FF8A75` on canvas `#0B0C10` | **8.51:1** |
| `warning` fg `#FFD60A` on canvas `#0B0C10` | **13.85:1** |
| `warning` fg on its own field `#282400` | 11.08:1 |
| `danger` fg on its own field `#321914` | 7.12:1 |
| `info` fg on its own field `#102735` | 8.95:1 |

Every pairing clears 4.5:1, and the canvas pairings clear it by more than the
field pairings do — but they clear it by luck of a dark canvas rather than by
anything the tokens guarantee. **If the design
system intends foregrounds to be canvas-safe as well as field-safe, that is worth
stating in `COMPONENTS.md`;** if it does not, the two quiet placements are relying on
an undocumented property.

## 4. Two census claims are now stale

Both in `docs/design/PHOSPHENE-COMPONENT-CENSUS.md`.

- **Line 157** lists the "local-file error banner" among the `DashboardTokens`
  consumers. It is not one, and had already stopped being one before DS.3 started:
  `LocalFileErrorStore.swift:110` read `UzumeAppColor.danger`, not
  `DashboardTokens.Color.coral`. DS.1 moved it. (DS.3 still moved the *view* out of the
  store file, which was the other half of that item.)
- **Line 165 / § Migration order step 3** describes consolidating the two full-screen
  views as if both were live. One of them — `FullScreenErrorView` — had **no
  construction site at all** and had never appeared in a shipped build. The related
  `docs/CAPABILITY_REGISTRY/APP_VIEWS.md:440` marks it `production-active`, which is
  wrong in the app repo's own registry. Recorded as **DEAD-003** in
  `docs/QUALITY/KNOWN_ISSUES.md`.

The second one changed the shape of the work: step 3 reads as a merge of two active
components, and was in fact a deletion plus a rename.
