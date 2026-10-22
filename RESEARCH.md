# Research notes (2026-10-22)

What I looked at before shaping this project, with sources. Read with the postings in `G:\Jobs\applications`.

## What the target employers ask for

The skill-gap report (`G:\Jobs\profile\PROJECT-SKILL-GAPS.md`, regenerated 2026-10-22) lists R (2 postings),
MySQL / SQL Server (2) and Oracle / PL-SQL (1) as skills postings name that no repository of mine proves. Banks
and bank-adjacent employers in Tampa (JPMorgan, Citi, Raymond James) run all three engines side by side, and
credit-risk teams model in R. So one project: a credit-risk model built in R, served as SQL inside all three
engines, with proof the four agree.

## Data: FDIC BankFind Suite API (public, no key)

- `https://api.fdic.gov/banks/` (the older `banks.data.fdic.gov/api` redirects there). Endpoints used:
  `institutions`, `failures` (4,117 since 1934; 565 from 2007 to 2026) and `financials` (quarterly Call Report
  ratios; 8,103 banks reported for 2009-12-31). Field definitions:
  [risview_properties.yaml](https://api.fdic.gov/banks/docs/risview_properties.yaml).
- Failures by year, 2007-2026 (queried 2026-10-22): 2007: 3, 2008: 30, 2009: 148, 2010: 157, 2011: 92, 2012: 51,
  2013: 24, 2014: 18, then single digits. Enough positives for an out-of-time test only in the crisis years.
- Ratios used, all in the financials endpoint: equity capital to assets (`EQV`), leverage ratio (`RBC1AAJ`),
  noncurrent loans to loans (`NCLNLSR`), loan-loss reserve to loans (`LNATRESR`), provisions to assets (`ELNATRY`),
  return on assets (`ROA`), net interest margin (`NIMY`), efficiency ratio (`EEFFR`), loans to deposits
  (`LNLSDEPR`), brokered deposits (`BRO`) over deposits (`DEP`), total assets (`ASSET`). These follow the CAMELS
  areas regulators use (capital, asset quality, earnings, liquidity).

## Modelling choice

A logistic regression on those ratios and their four-quarter changes, label "fails within the next four quarters",
trained on report dates 2007-2009 and tested on 2011-2012, with 2010 left out so no training label overlaps a test
feature. Logistic regression is the standard baseline in the bank-failure literature and has one property this
project needs: its score is a dot product and a logistic function, which every SQL dialect can compute exactly, so
the same model runs inside MySQL, SQL Server and Oracle and can be checked against R to the last digit.

## Engines (free for development, run in Docker)

- **MySQL 9.7 LTS** (`mysql:9.7.4`, GPL) with window functions and stored procedures.
- **SQL Server 2025** (`mcr.microsoft.com/mssql/server:2025-latest`, Developer edition: free for development and
  test; the container needs `ACCEPT_EULA=Y`, i.e. accepting Microsoft's licence for that use).
- **Oracle Database 23ai Free** (`gvenzl/oracle-free:23-slim`, Oracle Free Use terms) with PL/SQL packages.
- Unit tests in the database: **utPLSQL 3.2.3** for Oracle (Apache 2.0, [utPLSQL/utPLSQL](https://github.com/utPLSQL/utPLSQL),
  release checksums published). tSQLt was considered for SQL Server but its repository states no licence, so the
  T-SQL and MySQL procedures are tested from Python instead.
- Drivers from Python, none needing a native client: `pymysql` (MIT), Microsoft's `mssql-python` (driver bundled
  in the wheel), `oracledb` in thin mode (Apache 2.0 / UPL).

## R

`rocker/r-ver:4.6.1` (R 4.6.1, 2026-10-15) in Docker, since R is not installed on this machine; packages from
CRAN: testthat, covr, lintr, arrow. CI uses `r-lib/actions` with R CMD check.

## Not done here, and why

- **Qlik** (1 posting): proving it needs Qlik Sense or Qlik Cloud, both behind an account. Writing a QVD file
  without loading it into Qlik would prove nothing.
- **Palantir Foundry** (1 posting): needs a Palantir account (AIP Developer tier sign-up).
