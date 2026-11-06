"""Calibration of the R model's test-quarter scores: does a predicted probability match the failure rate observed?

Failures are rare (0.6% of test bank-quarters), so the scores are grouped into fixed risk bands, not equal-count
bins, which would leave almost every bin without a failure."""

from __future__ import annotations

from bisect import bisect_right
from itertools import pairwise
from pathlib import Path
from typing import Any

import pyarrow.parquet as pq

BANDS = (0.0, 0.001, 0.01, 0.1, 0.5, 1.0)


def _summary(scores: list[float], failed: list[bool]) -> dict[str, Any]:
    return {
        "rows": len(scores),
        "failed": sum(failed),
        "expected_failures": round(sum(scores), 6),
        "mean_score": round(sum(scores) / len(scores), 6),
        "failure_rate": round(sum(failed) / len(scores), 6),
    }


def reliability(scores_path: Path) -> dict[str, Any]:
    """Expected failures (the sum of the scores) against observed, overall and per band. A score on an edge
    belongs to the band above it."""
    table = pq.read_table(scores_path, columns=["score", "failed"])
    scores, failed = table["score"].to_pylist(), table["failed"].to_pylist()
    bands = list(pairwise(BANDS))
    members: list[list[int]] = [[] for _ in bands]
    for i, s in enumerate(scores):
        members[bisect_right(BANDS, s, 1, len(bands)) - 1].append(i)
    return {
        "scores": scores_path.as_posix(),
        "overall": _summary(scores, failed),
        "bands": [
            {"band": list(band), **_summary([scores[i] for i in rows], [failed[i] for i in rows])}
            for band, rows in zip(bands, members, strict=True)
            if rows
        ],
    }
