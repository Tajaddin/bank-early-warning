# Sprint 2 retro: the model in three SQL engines

Dates: 2026-10-22. Milestone: [Sprint 2 - The model in three SQL engines](https://github.com/Tajaddin/bank-early-warning/milestone/2).

**Goal:** MySQL, SQL Server and Oracle each compute the features and scores with their own SQL, tested in the
engine where it has a framework, and proven equal to R bank by bank. **Met.**

## Delivered

| Issue | Points | Result |
|---|---|---|
| #5 MySQL | 3 | schema, the feature view (a self-join a year back), scoring and watch-list procedures |
| #6 SQL Server | 3 | the same in T-SQL; a quarter is scored in one transaction |
| #7 Oracle | 5 | `BINARY_DOUBLE` schema, the `bank_risk` package, a utPLSQL suite |
| #8 parity | 3 | every test bank-quarter scored by each engine and compared with R; load and scoring times |
| #9 CI | 3 | moved in from Sprint 3: the analysis once, then one job per engine with its tests and parity |
| #14 bug: SQL Server and an int bound | 1 | every model number is a double |
| #15 bug: utPLSQL install | 2 | the exact tag, the BSD checksum format, folder permissions, a generated UT3 password |

20 of 20 points done (14 planned, 3 pulled in from Sprint 3, 3 added for bugs).

## Measured

- **Parity** (`reports/parity.json`, on this machine: i5-13600KF, 32 GB, Docker Desktop): each engine scored the
  same 58,661 bank-quarters as R across the 8 test quarters, none missing and none extra. The largest difference
  from R's probability was 7.8e-16 in every engine (tolerance 1e-9).

  | Engine | Load 229,377 filings | Score 8 quarters |
  |---|---|---|
  | MySQL 9.7.4 | 8.0 s | 1.0 s |
  | SQL Server 2025 RTM | 11.3 s | 1.6 s |
  | Oracle Database 23ai Free | 5.8 s | 0.9 s |

  One run each, through each Python driver's batched inserts: they say the job is seconds in every engine, not
  which engine is faster.
- **Tests**: utPLSQL 6 tests in Oracle (clip, logistic, eligible banks, scores worked by hand to 1e-15, rescoring,
  watch-list order; `reports/oracle-utplsql.xml`); 12 integration tests from Python (the same cases on all three
  engines); 17 unit tests (script splitting, the model loader, the data fetch).

## What went well

- Writing the hand-worked cases once and running them in every engine found nothing to fix in the SQL itself:
  all 12 passed on the first run against real databases.
- Using `BINARY_DOUBLE` in Oracle and binding Python floats as doubles kept every engine within one rounding of R.

## What did not

- The first parity run stopped on SQL Server: a bound of exactly 0 in the model JSON is an integer to Python and
  `mssql-python` will not bind a column that mixes ints and floats (#14).
- utPLSQL took three attempts to install (#15): the release tag has a dot (`v.3.2.3`), the checksum file is in BSD
  format, and the installer writes temporary files next to itself, which a root-owned folder refused; when that
  failed it fell back to prompting and read the next input line as the grantee. Its default schema password is
  built in, so the runner now generates one.
- Three times this sprint a shell heredoc halved backslashes (`\n`) in an inline patch; one of those commits said
  more than it changed and needed a follow-up. Edits with escapes now go through the editor, not a heredoc.

## Carried into Sprint 3

- README, model card and release; the CI jobs run against a fresh fetch, so the README states which numbers come
  from the committed snapshot.
