# Sprint 1 retro: data and the model in R

Dates: 2026-10-22. Milestone: [Sprint 1 - Data and the model in R](https://github.com/Tajaddin/bank-early-warning/milestone/1).

**Goal:** FDIC Call Report data fetched and checked, an R package that builds features and labels, fits the
early-warning model on 2007-2009 and evaluates it out of time on 2011-2012 against a one-ratio baseline. **Met,**
and the answer is not the one a model-builder hopes for: the model does not beat the one-ratio rule.

## Delivered

| Issue | Points | Result |
|---|---|---|
| #1 scaffold | 2 | Python package, generated local passwords, CI with lint, types, tests, R CMD check, gitleaks, pip-audit |
| #2 data | 3 | 29 quarters of financials (229,377 bank-quarters), 4,117 failures, 27,835 institutions; counts equal to the API's; manifest with sha256; `bew check` |
| #3 R package | 5 | features, labels with a 60-day publication lag, clipped logistic model, export, evaluation; R CMD check OK |
| #4 evaluation | 3 | out-of-time AUC with a bank-level bootstrap, Brier, a 100-bank watch list; the same for lowest-equity-first |
| #12 bug: export precision | 1 | coefficients now round-trip exactly (17 significant digits) |

14 of 14 points done (13 committed, 1 added for the bug).

## Measured

- **Data** (`reports/data-checks.json`): 0 duplicate (bank, quarter) keys; 491 rows without brokered deposits or
  provisions, dropped from features; all 502 failures of 2008-2013 matched to filings, 499 of them within one
  quarter of the bank's last filing.
- **Model** (`reports/r/report.json`; R 4.6.1 in Docker): trained on 73,492 bank-quarters with 356 failing banks,
  tested on 58,443 bank-quarters of 2011-2012 with 128 failing banks.

  | | AUC (95% CI, banks resampled) | Watch-list recall | Watch-list precision |
  |---|---|---|---|
  | 14-feature logistic model | 0.991 (0.989-0.993) | 65.3% | 28.8% |
  | Lowest equity ratio first | 0.991 (0.986-0.994) | 77.8% | 34.3% |

  The model ties the one-ratio rule on AUC and loses on the watch list, the metric a supervisor would use.
  Several coefficients have signs that make no economic sense (asset growth positive, provisions negative), the
  usual mark of correlated ratios. The design was fixed before the test years were scored, so the model was not
  re-tuned on them.
- **Tests**: 50 testthat expectations (features and labels checked against hand-worked cases, the exported model
  round-tripping every digit, the whole pipeline on a synthetic 400-bank panel), R CMD check with warnings as
  errors.

## What went well

- The publication-lag rule mattered: 499 of 502 failures came within a quarter of the last filing, so without it
  most "warnings" would have been filings no one could act on.
- Two of the three bugs this sprint were caught by tests before any number was reported: the export losing the
  last bits of each coefficient, and the synthetic test data being perfectly separable.

## What did not

- **The model does not beat capital alone.** In 2011-2012 the banks that failed were the thinly capitalised ones,
  and adding thirteen more ratios added noise. The next model to try, with a selection fitted inside the training
  years only, is a sparse one (lasso) or capital plus asset quality; that is new work, not a fix.
- A comma in a milestone title split one board option into two (the `gh` CLI takes options comma-separated); the
  backlog script now refuses such titles.
- `jsonlite::toJSON(digits = NA)` writes 15 significant digits, not "full precision"; the round-trip test caught
  it in CI (#12).
- The utPLSQL release tag is `v.3.2.3` (with a dot) and its checksum file is in BSD format; both broke the first
  install attempt (fixed in Sprint 2's tooling).

## Carried into Sprint 2

- The scoring SQL for MySQL, SQL Server and Oracle, and parity with R (written and run during this sprint, merged
  in Sprint 2's pull request).
