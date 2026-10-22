"""Load the same data and the R model into each engine, score every test quarter with the engine's own procedure,
and compare with R: the same banks, and scores equal to within floating-point rounding. Also records how long each
step took on each engine (one machine, Docker; not a benchmark of the engines)."""

from __future__ import annotations

import json
import platform
import time
from collections import defaultdict
from datetime import date
from pathlib import Path
from typing import Any

import pyarrow.parquet as pq

from bew import log
from bew.config import Settings
from bew.connect import engine
from bew.engines import FINANCIAL_COLUMNS, Model

TOLERANCE = 1e-9  # on a probability; the engines and R round sums of 15 products slightly differently
logger = log.get(__name__)


def financial_rows(raw: Path) -> list[tuple[Any, ...]]:
    table = pq.read_table(raw / "financials.parquet")
    columns = [table[name.upper()].to_pylist() for name in FINANCIAL_COLUMNS]
    return list(zip(*columns, strict=True))


def failure_rows(raw: Path) -> list[tuple[Any, ...]]:
    table = pq.read_table(raw / "failures.parquet").to_pylist()
    seen: dict[tuple[int, date], str] = {}
    for row in table:
        if row["CERT"] is not None and row["FAILDATE"] is not None:
            seen.setdefault((row["CERT"], row["FAILDATE"]), row["NAME"] or "")
    return [(cert, day, name) for (cert, day), name in sorted(seen.items())]


def r_scores(path: Path) -> dict[date, dict[int, float]]:
    out: dict[date, dict[int, float]] = defaultdict(dict)
    for row in pq.read_table(path).to_pylist():
        out[row["REPDTE"]][int(row["CERT"])] = float(row["score"])
    return dict(out)


def compare(theirs: dict[int, float], ours: dict[int, float]) -> dict[str, Any]:
    common = theirs.keys() & ours.keys()
    diffs = [abs(theirs[c] - ours[c]) for c in common]
    return {
        "banks": len(ours),
        "missing": len(theirs.keys() - ours.keys()),
        "extra": len(ours.keys() - theirs.keys()),
        "max_abs_diff": max(diffs) if diffs else None,
    }


def run(engines: list[str], raw: Path, model_path: Path, reference: Path, settings: Settings) -> dict[str, Any]:
    model = Model.load(model_path)
    expected = r_scores(reference)
    financials, failures = financial_rows(raw), failure_rows(raw)
    report: dict[str, Any] = {
        "what": "the R model scored by each engine's own SQL, compared with R's scores, bank by bank",
        "tolerance": TOLERANCE,
        "machine": {"cpu": platform.processor(), "os": platform.platform(terse=True)},
        "rows": {"financials": len(financials), "failures": len(failures), "test_quarters": len(expected)},
        "engines": {},
    }
    for name in engines:
        started = time.perf_counter()
        e = engine(name, settings)
        e.install()
        install_s = time.perf_counter() - started
        load_fin = e.load("financials", FINANCIAL_COLUMNS, financials)
        load_fail = e.load("failures", ("cert", "faildate", "name"), failures)
        e.load_model(model)
        quarters = {}
        for q in sorted(expected):
            t = time.perf_counter()
            scored = e.score_quarter(q)
            seconds = time.perf_counter() - t
            quarters[q.isoformat()] = {
                "scored": scored,
                "seconds": round(seconds, 3),
                **compare(expected[q], e.scores(q)),
            }
            logger.info("scored", engine=name, quarter=q.isoformat(), banks=scored, seconds=round(seconds, 3))
        worst = max((v["max_abs_diff"] or 0.0) for v in quarters.values())
        report["engines"][name] = {
            "install_s": round(install_s, 2),
            "load_financials_s": round(load_fin, 2),
            "load_failures_s": round(load_fail, 2),
            "score_all_quarters_s": round(sum(v["seconds"] for v in quarters.values()), 2),
            "banks_scored": sum(v["scored"] for v in quarters.values()),
            "missing_vs_r": sum(v["missing"] for v in quarters.values()),
            "extra_vs_r": sum(v["extra"] for v in quarters.values()),
            "max_abs_diff_vs_r": worst,
            "equal_to_r": worst <= TOLERANCE and all(v["missing"] == v["extra"] == 0 for v in quarters.values()),
            "quarters": quarters,
        }
        e.conn.close()
    return report


def write(report: dict[str, Any], out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
