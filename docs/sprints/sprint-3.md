# Sprint 3 retro: CI, documents and release

Dates: 2026-10-22. Milestone: [Sprint 3 - CI and release](https://github.com/Tajaddin/bank-early-warning/milestone/3).

**Goal:** CI runs R CMD check and all three engines, the results and their limits are documented, release v1.0.0.
**Met.** The CI work (#9) was finished in Sprint 2, where the database code it tests was merged.

## Delivered

| Issue | Points | Result |
|---|---|---|
| #10 docs and release | 2 | README (question, results with the machine, how to run, limits), model card, v1.0.0 |

2 of 2 points done here; #9 (3 points) moved to Sprint 2.

## What went well

- Every number in the README and the model card points to a committed report, and CI reproduces the parity check
  from a fresh fetch on every push, so the main claim does not rest on one local run.
- The model card leads with the result that the model ties a one-ratio rule, so nobody reads 0.991 as a win.

## What did not

- The project needed three sprints, not the four the other two projects used: the CI work fit in Sprint 2 once the
  per-engine jobs were split up (one database per runner, because the three images together are about 10 GB).

## Left in the backlog

- #11: the watch list in Qlik Cloud (needs a Qlik account).
- A sparser model selected inside the training years (in the model card's next steps).
