# bank-early-warning

[![CI](https://github.com/Tajaddin/bank-early-warning/actions/workflows/ci.yml/badge.svg)](https://github.com/Tajaddin/bank-early-warning/actions/workflows/ci.yml)

A bank-failure early-warning model on public FDIC Call Report data, **fitted and validated out of time in R**, then
**scored by MySQL, SQL Server (T-SQL) and Oracle (PL/SQL)** with each engine's own SQL, and **proven equal to R**
bank by bank. The question it answers is an engineering one banks have every day: is the model running in the
database the model that was validated?

## What it shows

| Area | Where |
|---|---|
| R: a tested package (features, labels, logistic model, bank-level bootstrap, export), R CMD check, testthat, covr, lintr | `r/bankwarn` |
| MySQL 9.7: a feature view (a self-join a year back), stored procedures | `sql/mysql` |
| SQL Server 2025: T-SQL views and procedures, scoring in a transaction | `sql/sqlserver` |
| Oracle 23ai: `BINARY_DOUBLE` schema, a PL/SQL package, utPLSQL unit tests | `sql/oracle` |
| Parity: the same bank-quarters, every score within 1e-9 of R's | `src/bew/parity.py`, [ADR 0002](docs/adr/0002-one-model-three-engines.md) |
| Data from the FDIC BankFind API with a manifest and checks | `src/bew/fdic.py`, `src/bew/checks.py` |
| A label a supervisor could act on and an out-of-time test | [ADR 0001](docs/adr/0001-label-and-split.md), [model card](docs/MODEL-CARD.md) |
| Scrum: backlog, 3 sprints, a pull request and a retro each | [board](https://github.com/users/Tajaddin/projects/6), [retros](docs/sprints) |

## Results

Measured on one workstation (Intel i5-13600KF, 32 GB RAM, Docker Desktop on Windows 11), from committed files.

**Parity** (`reports/parity.json`): each engine scored the same 58,661 bank-quarters as R over the 8 test quarters,
none missing and none extra; the largest difference from R's probability was **7.8e-16** in every engine.

| Engine | Load 229,377 filings | Score 8 quarters |
|---|---|---|
| MySQL 9.7.4 | 8.0 s | 1.0 s |
| SQL Server 2025 | 11.3 s | 1.6 s |
| Oracle Database 23ai Free | 5.8 s | 0.9 s |

**The model** (`reports/r/report.json`), trained on 2007-2009 report dates, tested on 2011-2012:

| | AUC (95% CI) | 100-bank watch list: recall | precision |
|---|---|---|---|
| 14-ratio logistic model | 0.991 (0.989-0.993) | 65.3% | 28.8% |
| Lowest equity ratio first | 0.991 (0.986-0.994) | 77.8% | 34.3% |

The model ties the one-ratio rule on AUC and loses on the watch list. Capital alone explains most failures of
those years. That is reported as found: the design was fixed before the test years were scored.

**Tests**: R: 50 testthat expectations, 99.4% coverage, R CMD check clean. Oracle: 6 utPLSQL tests. All three
engines: 12 integration tests on hand-worked cases. Python: 17 unit tests. CI fetches fresh data, reruns the R
analysis and checks parity in each engine on every push.

## Run it

Needs Docker and [uv](https://docs.astral.sh/uv/). About 10 GB of database images.

```bash
uv sync --all-extras
python scripts/make_env.py                         # .env with generated local passwords
uv run bew fetch && uv run bew check               # FDIC data, about 2 minutes
docker compose run --rm r                          # the R analysis -> reports/r/
docker compose up -d --wait mysql sqlserver oracle
uv run python scripts/oracle_tests.py              # utPLSQL (installs it once)
uv run pytest -m integration                       # the SQL on hand-worked cases
uv run bew parity                                  # every engine vs R -> reports/parity.json
```

R is not needed on the host; it runs in the `rocker/r-ver:4.6.1` image.

## Limits

- A demonstration, not a supervisory tool: public ratios only, no confidential supervisory data.
- Crisis-era evidence; later years have too few failures to test on.
- The timings are one run each on one machine through Python drivers: they show the job takes seconds anywhere,
  not which engine is faster.
- SQL Server runs the free Developer edition (`ACCEPT_EULA=Y`: Microsoft's licence for development and test);
  Oracle runs the Free edition under Oracle's free-use terms.

## Layout

```
r/bankwarn/      the R package (features, labels, model, evaluation, pipeline) and its tests
sql/<engine>/    schema, features and scoring for MySQL, SQL Server, Oracle (+ utPLSQL tests)
src/bew/         fetch and checks, the engines, parity
reports/         data checks, the R analysis, parity, the utPLSQL report
docs/            ADRs, model card, sprint retros
```

MIT licensed. Data: FDIC BankFind Suite (public).
