"""Checks on the fetched data before anything is modelled: keys unique, missing values counted, every failure
matched to the bank's filings, and how close to its last filing each bank failed (which is why labels need a
publication lag, ADR 0001)."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
from typing import Any

import pyarrow.parquet as pq


def check(raw: Path, first: date = date(2008, 1, 1), last: date = date(2013, 12, 31)) -> dict[str, Any]:
    fin = pq.read_table(raw / "financials.parquet")
    fails = pq.read_table(raw / "failures.parquet").to_pylist()
    certs, dates = fin["CERT"].to_pylist(), fin["REPDTE"].to_pylist()
    keys = Counter(zip(certs, dates, strict=True))
    filings: dict[int, list[date]] = defaultdict(list)
    for cert, day in zip(certs, dates, strict=True):
        filings[cert].append(day)

    window = [f for f in fails if f["FAILDATE"] and first <= f["FAILDATE"] <= last]
    matched = [f for f in window if f["CERT"] in filings]
    gaps: Counter[int] = Counter()
    for f in matched:
        before = [d for d in filings[f["CERT"]] if d < f["FAILDATE"]]
        if before:
            gaps[(f["FAILDATE"] - max(before)).days // 91] += 1
    by_quarter = Counter(dates)
    return {
        "financials": {
            "rows": fin.num_rows,
            "quarters": len(by_quarter),
            "banks_per_quarter": {"min": min(by_quarter.values()), "max": max(by_quarter.values())},
            "duplicate_keys": sum(1 for n in keys.values() if n > 1),
            "missing_values": {name: fin[name].null_count for name in fin.column_names if fin[name].null_count},
        },
        "failures": {
            "window": [first.isoformat(), last.isoformat()],
            "in_window": len(window),
            "matched_to_filings": len(matched),
            "without_cert": sum(1 for f in window if f["CERT"] is None),
            "quarters_from_last_filing_to_failure": dict(sorted(gaps.items())),
        },
        "passed": {
            "unique_keys": all(n == 1 for n in keys.values()),
            "every_failure_matched": len(matched) == len(window),
        },
    }
