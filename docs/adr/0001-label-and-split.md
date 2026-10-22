# 0001. What counts as a warning, and which years test it

Date: 2026-10-22. Status: accepted.

## Context

A bank-failure model can look excellent for reasons that would never help a supervisor: by "predicting" failures
that happened before anyone could see the data, or by being tested on the same crisis it was fitted to.

## Decision

1. **A label a supervisor could act on.** Call Report data for a quarter end becomes public about 60 days later.
   A bank-quarter is positive when the bank failed within 365 days *after* that publication date. A bank-quarter
   whose bank had already failed by the publication date is dropped, not counted as an easy hit: 497 of the 502
   failures of 2008-2013 came within 90 days of the bank's last filing, so without this rule most positives would
   be filings no one could have used.
2. **Out of time, with a gap.** Train on report dates 2007-12-31 to 2009-12-31 (labels reach into early 2011);
   test on 2011-03-31 to 2012-12-31. Report dates in 2010 are used by neither, so no training label overlaps a
   test feature. The test years are after the peak of the crisis, so the model meets a different mix of failures
   than it learned from.
3. **Evaluation a supervisor would recognise.** AUC with a 95% interval from resampling whole banks (a bank's
   quarters are not independent), the Brier score, and a watch list: of each quarter's 100 highest-scored banks,
   how many fail within the horizon (recall over all failing banks, precision over the list). The same numbers for
   the obvious one-ratio rule, lowest equity-to-assets first, so the model has to earn its complexity.
4. **Features defined once** (`r/bankwarn/R/features.R`) and computed with a self-join one year back, not
   `LAG(..., 4)`, which would silently pair the wrong quarters for a bank with a missing filing.

## Consequences

- 2013-2026 failures are too few to test on (single digits a year), so this model's evidence is crisis-era.
- The publication lag is an approximation (filing deadlines were 30 days, FDIC publication later); 60 days is a
  stated assumption, a parameter of `label_failures()`.
