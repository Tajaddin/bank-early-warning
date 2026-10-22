"""Each engine's own SQL against the same hand-worked cases (the same ones the utPLSQL suite checks in Oracle):
three synthetic banks with negative certificate numbers in 1999, a model where only equity counts.

Needs the databases (`docker compose up -d --wait mysql sqlserver oracle`); an engine that is not running is skipped.
The model tables are restored afterwards, so the tests can run against a loaded database."""

from __future__ import annotations

import math
from collections.abc import Iterator
from datetime import date
from typing import Any

import pytest

from bew.config import settings
from bew.connect import ENGINES, engine
from bew.engines import FINANCIAL_COLUMNS, Engine

pytestmark = pytest.mark.integration
Q = date(1999, 12, 31)
YEAR_AGO = date(1998, 12, 31)
FEATURES = (
    "eqv",
    "lev",
    "ncl",
    "reserve",
    "prov",
    "roa",
    "nim",
    "eff",
    "ltd",
    "brokered",
    "log_assets",
    "d_roa",
    "d_ncl",
    "growth",
)
BIG = 1e300


def filing(cert: int, repdte: date, eqv: float) -> tuple[Any, ...]:
    return (cert, repdte, 1000.0, 800.0, 40.0, eqv, 8.0, 1.0, 1.5, 0.2, 1.0, 3.5, 70.0, 80.0)


@pytest.fixture(params=ENGINES)
def e(request: pytest.FixtureRequest) -> Iterator[Engine]:
    try:
        eng = engine(request.param, settings())
    except Exception as exc:  # a driver error, a refused connection: the engine is not up
        pytest.skip(f"{request.param} not reachable: {type(exc).__name__}")
    eng.install()
    with eng.conn.cursor() as cur:
        cur.execute("SELECT feature, coefficient, lower_bound, upper_bound FROM model_feature")
        saved_features = [tuple(r) for r in cur.fetchall()]
        cur.execute("SELECT id, intercept FROM model_intercept")
        saved_intercept = [tuple(r) for r in cur.fetchall()]
    _insert(
        eng,
        [
            filing(-1, Q, 30.0),
            filing(-1, YEAR_AGO, 25.0),
            filing(-2, Q, 10.0),
            filing(-2, YEAR_AGO, 12.0),
            filing(-3, Q, 5.0),
        ],
    )
    eng.load("model_intercept", ("id", "intercept"), [(1, -1.0)])
    model = [
        (f, -0.1 if f == "eqv" else 0.0, 0.0 if f == "eqv" else -BIG, 20.0 if f == "eqv" else BIG) for f in FEATURES
    ]
    eng.load("model_feature", ("feature", "coefficient", "lower_bound", "upper_bound"), model)
    yield eng
    with eng.conn.cursor() as cur:
        cur.execute("DELETE FROM risk_score WHERE cert < 0")
        cur.execute("DELETE FROM financials WHERE cert < 0")
    eng.conn.commit()
    eng.load("model_feature", ("feature", "coefficient", "lower_bound", "upper_bound"), saved_features)
    eng.load("model_intercept", ("id", "intercept"), saved_intercept)
    eng.conn.close()


def _insert(eng: Engine, rows: list[tuple[Any, ...]]) -> None:
    with eng.conn.cursor() as cur:
        cur.execute("DELETE FROM risk_score WHERE cert < 0")
        cur.execute("DELETE FROM financials WHERE cert < 0")
        cur.executemany(eng.insert_sql("financials", FINANCIAL_COLUMNS), rows)
    eng.conn.commit()


def logistic(z: float) -> float:
    return 1 / (1 + math.exp(-z))


def test_scores_only_banks_with_a_filing_a_year_earlier(e: Engine) -> None:
    assert e.score_quarter(Q) == 2
    assert set(e.scores(Q)) == {-1, -2}


def test_scores_worked_by_hand(e: Engine) -> None:
    e.score_quarter(Q)
    scores = e.scores(Q)
    assert scores[-1] == pytest.approx(logistic(-1 - 0.1 * 20), abs=1e-15)  # equity 30% clipped to 20
    assert scores[-2] == pytest.approx(logistic(-1 - 0.1 * 10), abs=1e-15)


def test_rescoring_replaces(e: Engine) -> None:
    e.score_quarter(Q)
    e.load("model_intercept", ("id", "intercept"), [(1, 0.0)])
    e.score_quarter(Q)
    scores = e.scores(Q)
    assert len(scores) == 2
    assert scores[-2] == pytest.approx(logistic(-1.0), abs=1e-15)


def test_features_match_their_definitions(e: Engine) -> None:
    with e.conn.cursor() as cur:
        cur.execute(
            f"SELECT brokered, log_assets, d_roa, growth FROM bank_features WHERE cert = -2 AND repdte = {e.placeholder}",
            (Q,),
        )
        brokered, log_assets, d_roa, growth = (float(v) for v in cur.fetchone())
    assert brokered == pytest.approx(100 * 40 / 800, abs=1e-12)
    assert log_assets == pytest.approx(math.log(1000), abs=1e-12)
    assert d_roa == 0.0 and growth == 0.0
