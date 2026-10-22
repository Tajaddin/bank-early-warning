.PHONY: help install env lint format typecheck test check secret-scan fetch up down r-image r-test analysis \
        oracle-tests test-integration parity backlog

help:               ## this list
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

install:            ## Python dependencies
	uv sync --all-extras

env:                ## .env with generated passwords for the local databases (refuses to overwrite)
	python scripts/make_env.py

lint:
	uv run ruff check . && uv run ruff format --check .

format:
	uv run ruff format . && uv run ruff check --fix .

typecheck:
	uv run mypy

test:               ## Python unit tests
	uv run pytest -m "not integration and not data" --cov --cov-report=term-missing

check: lint typecheck test

secret-scan:        ## run before every push
	bash scripts/secret_scan.sh

fetch:              ## FDIC financials 2006-2013, failures and institutions into data/raw (about 2 minutes)
	uv run bew fetch

up:                 ## MySQL, SQL Server and Oracle (needs .env)
	docker compose up -d --wait --wait-timeout 600 mysql sqlserver oracle

down:               ## stop the databases and DROP their data
	docker compose down -v

r-image:            ## R 4.6.1 with the package and its dependencies
	docker compose build r

r-test: r-image     ## testthat inside the R image
	docker compose run --rm --entrypoint Rscript r -e 'testthat::test_local("/src/bankwarn", reporter = "summary")'

analysis: r-image   ## fit and evaluate in R: reports/r/ (model.json, scores, report.json)
	docker compose run --rm r

oracle-tests:       ## utPLSQL suite in Oracle (installs utPLSQL once)
	uv run python scripts/oracle_tests.py

test-integration:   ## each engine's SQL on hand-worked cases
	uv run pytest -m integration -v

parity: analysis    ## score the test quarters in every engine and compare with R (reports/parity.json)
	uv run bew parity

backlog:            ## issues, milestones and the board from docs/agile/backlog.json
	uv run python scripts/agile/sync_backlog.py --board && uv run python scripts/agile/board.py sprints
