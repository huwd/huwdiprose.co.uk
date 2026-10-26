---
name: sync-abs-books
description: Runs the deterministic Audiobookshelf sync script against _books/, sanity-checks the resulting stub files and patches, prompts for a rating on any newly finished book, plays back a summary, commits, and offers to open a PR. Use when asked to sync, reconcile, or pull in recently read or in-progress books from Audiobookshelf.
---

# Sync ABS Books

Wraps `scripts/sync_abs_books.rb` — a deterministic, non-AI script that reads
Audiobookshelf (ABS) and creates/patches `_books/*.md` stub files. This skill
adds the review, commit, and PR steps around it. Must be run from the
`huwdiprose.co.uk` project root, on a non-`main` branch (create one if needed).

The script itself never needs an LLM: it just talks to the ABS API and writes
frontmatter. Your job is to run it, then act as the human-in-the-loop check
before anything ships.

## Step 1 — Dry run

Always preview before writing:

```bash
bundle exec ruby scripts/sync_abs_books.rb --finished
```

This defaults the "finished" cutoff to the most recent `date_finished` already
in `_books/`. Read the output: it lists candidate stubs (in-progress and
finished) and any `date_finished` patches to existing stubs.

If it reports "Nothing to do", stop here and tell the user.

## Step 2 — Sanity-check the preview

Before writing anything, check the dry-run output against this list. Flag
anything suspicious to the user rather than silently proceeding:

- **Low-progress items** (roughly under 5%) — could be an accidental open or
  a sample rather than a deliberate start. List these separately and ask the
  user to confirm before including them.
- **Date sanity** — `date_started`/`date_finished` should not be in the
  future, and `date_finished` (if present) should be after `date_started`.
- **Title/author quality** — no empty author list, no obviously mangled
  encoding (mojibake, stray escape sequences).
- **Duplicates** — check the candidate title isn't already a stub in
  `_books/` under a different slug or filename date (the script only
  dedupes on normalized title match — a near-miss could slip through).
- **Filename collisions** — the target path doesn't already exist.

If everything looks sane, proceed. If something's flagged, present it to the
user and ask whether to include or skip it (skipping means adding the ABS
item ID to `IGNORE_IDS` in the script, or the finish date to
`IGNORE_FINISH_DATES` — see the constants near the top of
`scripts/sync_abs_books.rb`).

## Step 3 — Write

```bash
bundle exec ruby scripts/sync_abs_books.rb --finished --write
```

If the auto cutoff advanced past a pending patch on a re-run (e.g. because a
newly-created finished stub is now the most recent `date_finished`), re-run
with an explicit `--finished-since <date>` covering the older item instead of
relying on the auto cutoff.

## Step 4 — Verify writes actually landed

Don't trust the script's stdout alone — confirm with git:

```bash
git status --short
git diff -- _books/
```

For every file the script claimed to **patch**, confirm the diff is
non-empty and actually contains the expected `date_finished` line. A patch
that reports "patched" but produces no diff means the regex didn't match
(this has happened before — hand-edited stubs can use different YAML quote
styles than the generator). If you find a silent no-op like this, treat it as
a script bug: fix the regex/matching logic in `sync_abs_books.rb`, re-run,
and re-verify, rather than manually hand-patching the frontmatter.

For every **new** stub, open it and re-check title, authors, dates, and the
`format` block look complete and plausible.

## Step 5 — Rate newly finished books

A finished book must never sit in `_books/` without a `rating`. Check every
stub this run touched — new or patched — for a `date_finished` field:

- No `date_finished` → still in progress. Skip it; no rating needed yet.
- `date_finished` present and `rating` already set → skip it.
- `date_finished` present and `rating` missing → ask the user for a rating
  (1-5) before moving on. A patch can turn a stub from in-progress to
  finished, so this applies to patched stubs too, not just new ones.

Insert `rating: N` directly after `date_started` (before `date_finished`),
matching the ordering used elsewhere in `_books/`. If the user genuinely
doesn't have a rating yet, don't force it — but call that out explicitly in
the playback (Step 6) and again before offering the PR (Step 8), so it isn't
committed silently unrated.

## Step 6 — Playback

Before committing, summarize what this run is about to add or change so the
user can review it in one place:

- **New stubs**: title, author(s), date started, date finished (if any),
  rating (if collected).
- **Patches**: title and which field(s) changed (e.g. `date_finished`
  backfilled, `rating` added).

Keep it short — a bullet list is enough.

## Step 7 — Commit

Split into logical commits per the repo's commit standards:

1. If Step 4 required a script fix, commit that separately first
   (`fix(pipeline): ...`), before the content commit.
2. Commit the `_books/` additions/patches as one commit
   (`feat(books): sync N audiobooks from Audiobookshelf` or similar),
   summarizing what was added/patched in the body.

Stage files explicitly by name — never `git add -A`/`git add .`.

## Step 8 — Offer a PR

Ask the user: "Shall I open a pull request for these changes?"

If yes:

```bash
git push -u origin <branch>
gh pr create --base main --title "feat: sync N audiobooks from Audiobookshelf" --body "$(cat <<'EOF'
## Summary
- N new stub(s): <titles>
- N patch(es): <titles> (date_finished backfilled)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Return the PR URL. Do not push or open a PR without explicit confirmation.

## Notes

- Requires `AUDIOBOOKSTORE_HOST_LAN`, `ABS_TOKEN_FILE`, `AUDIOBOOKSTORE_LIBRARY_ID` in `.env`
  (`scripts/support/helpers.rb` loads dotenv automatically).
- `work_iri`/`edition_iri` are written as placeholder `https://www.wikidata.org/wiki/Q`
  — backfilling those is a separate step, covered by the `wikidata-books` skill.
- Never edit `IGNORE_IDS`/`IGNORE_FINISH_DATES` to hide a real bug — they exist
  for genuine one-off exclusions (e.g. bulk import artifacts), not as a patch
  for broken matching logic.
