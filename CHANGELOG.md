# TrueHire — Changelog

All notable user-facing changes to TrueHire, newest first.

## November 27, 2026

### ✨ New & Improved

- **New look.** A new app icon (a gold check reaching up to a star), a new
  twilight-mountains header banner, and refreshed README artwork. Your data
  now lives in `%APPDATA%\TrueHire\` and backups save as `.truehire.zip`.
- **A new question catalog for any role.** The Question Library is now 65
  behavioral questions across 13 competencies: Problem Solving,
  Communication, Collaboration, Accountability, Adaptability & Resilience,
  Decision Making, Initiative, Customer Focus, Planning & Organization,
  Conflict Resolution, Learning Agility, Integrity, and Leadership &
  Influence. Each question has an interviewer guide that says what strong and
  weak evidence sound like, and works from entry-level to leadership hires in
  any industry.

## June 5, 2026

### ✨ New & Improved

- **Better-looking candidate question set.** The candidate copy now matches the
  polished look of the interviewer handout — the same larger question text,
  navy category headings, and clean header — but keeps several questions per
  page instead of one-per-page, so it stays compact. Each question gets a few
  note lines and no question is ever split across a page break. (The
  interviewer's scoring guidance is still left off the candidate copy.)

- **Fuller handout pages.** The one-question-per-page interviewer handout now
  prints more note lines per page, so each page is filled out rather than
  leaving a big blank gap below the question.

## June 4, 2026

### ✨ New & Improved

- **Weight your categories.** Interview kits can now give each category a
  relative weight, so the categories that matter most for a role count more
  toward a candidate's match score. Set the weights in the kit editor's
  "Category weights" panel. Existing kits are unaffected — every category
  starts equally weighted, so scores don't change until you adjust them.

## June 3, 2026

### ✨ New & Improved

- **One question per page on the handout.** The interview handout now prints
  each question on its own page — the job title and requisition number across
  the top, then the category, its description, the question, and the
  interpretive guidance, with note lines below. Ten questions means ten pages.
  (The candidate question set is unchanged.)

- **Spell check while you type.** Live spell check — red squiggles with
  right-click suggestions — now runs in the longer text fields: job
  descriptions, candidate notes, recommendation write-ups, and the kit
  builder's probe and scoring-guide editors. Names and search boxes are left
  alone so they aren't flagged.

- **Refreshed cover banner.** Updated the banner image at the top of the app.

### 🐛 Fixes

- **Mouse wheel scrolls again.** Fixed the scroll wheel doing nothing across
  the app — candidate and kit lists, dialogs, and long forms now respond to the
  wheel as expected.

## June 2, 2026

### ✨ New & Improved

- **Cleaner printed interview sheets.** The interview handout and rating
  sheets got a print-focused refresh — removed the header banner so
  pages start right at the title, tightened the spacing, and fit more onto
  each page.

- **Easier-to-read printouts.** Bumped up the text size and darkened the
  lighter gray text so everything prints crisp and legible on paper — no more
  washed-out questions or notes.

- **Category names on every sheet.** Each section now shows its category name
  next to the number (e.g. "1. Problem Solving") on the handout, and the rating
  sheet's Category column is filled in — so you always know what you're
  looking at.

- **Custom categories per kit.** Build interview kits with your own custom
  categories in addition to the standard catalog. Custom categories are
  flagged on the evaluation form so reviewers can tell them apart.

- **Alphabetized category lists.** Catalog category lists are now sorted A–Z,
  making it faster to find the one you want.

## June 1, 2026

### ✨ New Features

- **Backup & restore everything.** A new **Export All** button bundles your
  full workspace — every job, interview kit, and candidate — into a single
  portable `.truehire` file. Import it on another machine (or to recover a
  backup) and TrueHire routes it automatically, merging by job so re-importing
  the same file never creates duplicates.

- **Export by date range.** When exporting, pick a time window (e.g. the last
  30 days) to bundle only recent activity instead of your entire history.

- **Bigger, easier-to-read interface.** The whole app now renders 20% larger,
  making the UI more comfortable to read and click — especially on
  high-resolution displays.

- **Built-in demo data.** A sample dataset (30 candidates across 10 jobs, plus a
  ready-made export bundle) is included so you can explore TrueHire's features
  without setting up your own data first.

## May 28, 2026

### 🎉 Initial Release

- **TrueHire hiring evaluation app.** A portable Windows tool for running
  structured interviews and scoring candidates:
  - **Job requisitions, interview kits, and candidates** organized across
    dedicated tabs.
  - **Interview kits built from a catalog** of competency categories and probing
    questions — pick exactly the probes you want for each role.
  - **Printable interview handouts** with the questions, interpretive guidance,
    and space for handwritten notes.
  - **Candidate-copy question sets** — a questions-only handout for the
    candidate that leaves out the interviewer's scoring guidance.
  - **Anchor-based rating sheets** and an evaluation form for scoring each
    candidate against the kit's categories.
  - **Dashboard and analytics** for an at-a-glance view of your pipeline.
  - **Excel export** of candidate results.

### 🐛 Fixes

- Fixed the interview-kit builder, corrected rating-score calculation, and made
  deleted evaluations stay deleted.
