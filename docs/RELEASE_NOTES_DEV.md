# Phosphene — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes are not yet in scope (no public build).

Older entries: `RELEASE_NOTES_DEV_YYYY-MM.md` (one file per month).

**Entry ids are `[dev-YYYY-MM-DD-HHMMSS]`** (UTC time-of-day the entry is written — e.g. `date -u +%Y-%m-%d-%H%M%S`). They are unique by construction, so **never hand-assign sequential `-a`/`-b`/`-c` letters** — parallel sessions independently picking the next letter was a recurring merge-renumbering tax (DOC.8). Older `-a/-b/-c` entries are grandfathered; `rotate_docs.sh` / `DocIntegrityTests` key only on the `YYYY-MM-DD` date, so the suffix format is free. This file is also **`merge=union`** (`.gitattributes`): concurrent appends from two sessions auto-combine instead of conflicting — so keep it **prepend-only prose**, never edit an existing entry in place (union would duplicate it).

---

