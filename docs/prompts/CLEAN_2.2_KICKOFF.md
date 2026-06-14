# CLEAN Phase 2.2 — Kickoff: Spotify OAuth correctness

## Where things stand (as of 2026-06-14)

CLEAN.2.1 landed on `main` (`5c74d26`): the bundled Spotify **client secret** is gone (`Info.plist` + `Phosphene.xcconfig`), the engine-side client-credentials `DefaultSpotifyTokenProvider` (D-068) was deleted, and the env-var `SpotifyFetcher` (the last client-secret consumer) was removed in the follow-up. Matt confirmed the login E2E works on `main`.

The sole Spotify token path is now **`SpotifyOAuthTokenProvider`** (app layer, Authorization Code + PKCE, client ID only), injected by `ConnectorPickerView`. CLEAN.2.2 hardens the correctness of *that* provider — the one remaining Spotify auth path. **None of these block login today**, but they are real latent defects on the live user-facing flow.

## MANDATORY session setup (before any code)

1. Be on latest `main`. Sanity-grep: `grep -rn "SPOTIFY_CLIENT_SECRET\|DefaultSpotifyTokenProvider\|SpotifyFetcher" PhospheneApp PhospheneEngine --include=*.swift` should return **nothing** (all removed in 2.1). If it doesn't, you're not on the right base — stop.
2. Read: this doc; `docs/diagnostics/CODE_AUDIT_2026-06-13.md` Phase 2 row **CLEAN.2.2** + the P3 latent-bug list; `docs/QUALITY/KNOWN_ISSUES.md` AUDIT-2026-06-09 OAuth items (the re-entrant `login()` leak); `CLAUDE.md` §Defect Handling Protocol + §What NOT To Do.
3. The whole increment lives in **one file**: `PhospheneApp/Services/SpotifyOAuthTokenProvider.swift` (a ~413-line actor) + its app-target tests (`PhospheneAppTests/.../SpotifyOAuthTokenProviderTests`). **Cited line numbers below are from 2026-06-14 — re-grep, the file may have shifted.**

## The work — OAuth correctness (suggested 3 sub-increments)

Each sub-increment: write a **red** regression test that reproduces the defect, fix it, closeout green.

| ID | What | Done-when |
|---|---|---|
| **CLEAN.2.2.1** | **Re-entrant `login()` leak (the headline — `KNOWN_ISSUES` AUDIT line, P1-adjacent).** `login()` (`:~122-147`) stores a `pendingContinuation` and arms a `timeoutTask`. A SECOND `login()` while one is pending **overwrites `pendingContinuation`** — the first continuation never resumes (its caller hangs until the 5-min timeout, or leaks) — and arms a **second stray `timeoutTask`** that can later fire against the wrong attempt. Make `login()` re-entrancy-safe: exactly one in-flight attempt (reject or coalesce a concurrent call), exactly one continuation + one timeout per attempt, and cancel the timeout on every resume path. | Regression test: two overlapping `login()` calls — neither continuation leaks, no stray timeout survives; closeout green. |
| **CLEAN.2.2.2** | **Refresh double-spend (in-flight dedup).** `acquire()` (`:~211-245`) does a silent refresh when the token is near expiry. Concurrent `acquire()` calls each fire `refreshAccessToken` independently → multiple refreshes with the SAME refresh token. Spotify **rotates** refresh tokens, so the 2nd+ refresh sends an already-invalidated token → spurious `.spotifyAuthFailure` and a needless forced re-login. Dedup concurrent refreshes onto a single in-flight `Task` (this is exactly the `refreshTask` pattern the deleted `DefaultSpotifyTokenProvider` used — port that shape into the OAuth actor). | Regression test: N concurrent `acquire()` on an expired token → exactly ONE refresh request; closeout green. |
| **CLEAN.2.2.3** | **P3 hardening.** (a) **`state` param** — `makeAuthorizeURL` (`:~282-293`) omits the OAuth `state` parameter, so the callback has no CSRF/replay guard; generate a random `state`, include it in the authorize URL, verify it in `handleCallback`. (b) **form-encoding** gaps in `formEncoded()` (`:~417-423`) — confirm every field is correctly percent-encoded. (c) **Keychain error handling** — `try?` currently swallows save failures silently; at least log, ideally surface. (d) confirm the callback **host validation** (`host == "spotify-callback"`) is robust. | Tests for the `state` round-trip + encoding; closeout green. |

**Provider-consolidation status:** CLEAN.2.1 already deleted `DefaultSpotifyTokenProvider`. What remains is the `SpotifyTokenProviding` protocol + the `MissingCredentialsTokenProvider` sentinel + `SpotifyOAuthTokenProvider`. The audit's "consolidate token providers" line is therefore largely satisfied — just confirm there's no lingering duplication, don't manufacture a refactor.

## Rules / pitfalls

- This is the **live login path** — **manual E2E (Matt: log in → playlist loads) is required** before marking any sub-increment Resolved. Unit tests prove the mechanism; only a real login proves the end-to-end auth. Hand Matt a short checklist; don't claim Resolved on green units alone.
- App-layer tests run via `xcodebuild -scheme PhospheneApp test` (the engine `swift test` does NOT see them). If you ADD a test file, register it in all four `project.pbxproj` sections (see `docs/RUNBOOK.md §Engineering notes`).
- Don't change the engine-side `SpotifyWebAPIConnector`'s `tokenProvider: any SpotifyTokenProviding` contract — the OAuth provider is injected through it.
- Cite + verify line numbers by grepping; treat the `:~NNN` refs here as approximate.

## Closeout (per sub-increment)

Standard protocol: `Scripts/closeout_evidence.sh` evidence block (ALL GREEN), mark the AUDIT-2026-06-09 OAuth items Resolved in `KNOWN_ISSUES.md` as you land them, `RELEASE_NOTES_DEV.md` entry, `ENGINEERING_PLAN.md` row under Phase CLEAN. **Push requires Matt's explicit "yes, push."**
