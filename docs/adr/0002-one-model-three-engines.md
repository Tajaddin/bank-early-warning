# 0002. One model, fitted in R, scored by each engine's own SQL and proven equal

Date: 2026-10-22. Status: accepted.

## Context

Banks run more than one database. A risk score validated in R is often re-implemented by hand in the warehouse,
and the two drift apart without anyone noticing. The question this project answers: can the model that was
validated be shown, bank by bank, to be the model that runs in MySQL, SQL Server and Oracle?

## Decision

1. **A model SQL can compute exactly**: logistic regression on clipped features. Scoring is a clip
   (`LEAST(GREATEST(x, lo), hi)`), a dot product and `1 / (1 + EXP(-z))`, available in all three dialects.
2. **The model travels as data**, not code: R exports the intercept, coefficients and clipping bounds as JSON
   with every digit of each double; each engine loads them into `model_feature` and `model_intercept`. Refitting
   changes rows, not SQL.
3. **Each engine has its own SQL**, written in its dialect (`LN` vs `LOG`, `DATE_SUB` vs `DATEADD` vs
   `ADD_MONTHS`, procedures vs a PL/SQL package), not generated from one template: maintaining three dialects is the
   real job.
4. **IEEE doubles everywhere**: MySQL `DOUBLE`, SQL Server `FLOAT`, Oracle `BINARY_DOUBLE` (Oracle's `NUMBER` is
   decimal and would round differently), and the Oracle loader binds Python floats as `BINARY_DOUBLE`.
5. **Parity is a test, not a claim**: `bew parity` scores every test quarter in each engine and compares with
   R's scores for the same bank-quarters: the same set of banks, and every score within 1e-9.
6. **Tests in each engine's own terms where a free framework exists**: utPLSQL for the PL/SQL package; for MySQL
   and T-SQL, the same hand-worked cases from Python (tSQLt's repository states no licence).

## Consequences

- A more flexible model (gradient boosting, splines) would need a scoring table or an external service instead.
- The three engines can differ in the last bits of a sum of 15 products; the tolerance allows for that and the
  report shows the largest difference actually found.
