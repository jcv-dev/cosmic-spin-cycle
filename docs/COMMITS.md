# Commit policy (hard rule)

The project owner requires **frequent, logical commits** — not one commit per milestone.
A commit is a checkpoint you would be happy to bisect or revert on its own.

## Rules

1. **Commit at every green step.** After a small unit works and its tests pass, commit.
   Aim for 5–15 commits per milestone/workstream, never fewer than one per deliverable.
2. **Conventional prefixes:** `feat:`, `fix:`, `test:`, `docs:`, `chore:`, `ci:`, `refactor:`,
   `assets:`, `audio:`, `balance:`.
3. **Scope in parentheses** when useful: `feat(rhythm): grade windows`, `test(spawn): seed determinism`.
4. **One concern per commit.** Do not mix a refactor with a behaviour change.
5. **Never commit red.** Run the relevant test/lint command before committing. If a
   temporary break is unavoidable, commit it as `wip:` on a scratch branch — never on `main`.
6. **Commit messages are English**, present tense, ≤ 72 character subject. Body optional,
   explains *why* and lists verification.
7. **Do not amend or rebase pushed history.** Add follow-up commits.
8. **Do not commit** `.work/`, `.godot/`, build outputs, downloads, or secrets.
9. Asset commits: one commit per asset family with source URLs and license in the body.

## Minimum commit ladder for M0–M3

M0: project settings · config · state · rhythm base · autoloads · main scene · tests · CI · docs.

M1: evaluator tests · click-track generator · beat clock · calibration math · calibration UI ·
debug overlay · docs/latency measurements.

M2: item data · item scene · player movement · grabber · throw · item behaviours (one commit
per behaviour) · sandbox scene · perf test.

M3: layout data · belt scene · belt flow · reversal logic · shredder · phase data ·
spawn schedule · spawn director · 480 s simulation · determinism tests.
