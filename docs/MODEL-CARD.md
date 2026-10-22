# Model card: bank-failure early warning (bankwarn 1.0.0)

## What it is

A logistic regression that scores each US insured bank, each quarter, for the chance it fails within a year of its
Call Report becoming public. Fitted in R (`r/bankwarn`), exported as data (`reports/r/model.json`), and scored by
MySQL, SQL Server and Oracle with their own SQL, each proven equal to R (`reports/parity.json`).

## Intended use

A teaching and engineering demonstration: how a validated model is carried into three database engines without
drifting. **Not** a supervisory tool. A real early-warning system would use confidential supervisory data (CAMELS
ratings, exam findings), which this model does not have.

## Data

- FDIC BankFind Suite API, public, no key: quarterly Call Report ratios for every insured bank, 2006-12-31 to
  2013-12-31 (229,377 bank-quarters), and the FDIC failure list (`data/raw/manifest.json` records the API snapshot
  and each file's sha256).
- Features: equity to assets, leverage ratio, noncurrent loans, loan-loss reserve, provisions, ROA, net interest
  margin, efficiency ratio, loans to deposits, brokered-deposit share, log assets, and four-quarter changes in ROA,
  noncurrent loans and assets. Each clipped to its 1st and 99th training percentiles.
- Label: the bank failed within 365 days after its data became public (quarter end plus 60 days). Bank-quarters
  of banks that had already failed by then are dropped.

## Evaluation (out of time)

Trained on report dates 2007-12-31 to 2009-12-31 (73,492 bank-quarters, 356 failing banks); tested on 2011-03-31 to
2012-12-31 (58,443 bank-quarters, 128 failing banks); 2010 used by neither (`reports/r/report.json`).

| | AUC (95% CI, banks resampled) | Brier | 100-bank watch list: recall | precision |
|---|---|---|---|---|
| This model | 0.991 (0.989-0.993) | 0.0045 | 65.3% | 28.8% |
| Lowest equity ratio first | 0.991 (0.986-0.994) | n/a | 77.8% | 34.3% |

**The model does not beat the one-ratio rule.** It ties on AUC and, on the watch list a supervisor would actually
use, the rule catches more failing banks. Capital explains most of who failed in 2011-2012.

## Limits

- Crisis-era evidence only: after 2014, failures are single digits a year, too few to test on.
- Correlated ratios give some coefficients signs that make no economic sense (asset growth positive, provisions
  negative): read the scores, not the coefficients.
- The 60-day publication lag is an assumption; filing and publication dates varied.
- AUC near 0.99 for both rows says that, in this period, failing banks were visibly weak a year out; it does not
  say failures are predictable in calmer times.

## Next steps that would change the model

A sparse model (lasso) or capital plus asset quality only, selected inside the training years, then the same
out-of-time test. Recorded in the Sprint 1 retro as new work, not done here.
