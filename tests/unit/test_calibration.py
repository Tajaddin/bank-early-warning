from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from bew.calibration import reliability


def test_reliability_by_band(tmp_path: Path) -> None:
    path = tmp_path / "test_scores.parquet"
    scores = [0.0004, 0.0006, 0.001, 0.02, 0.04, 0.6, 0.8]
    failed = [False, False, False, False, True, True, True]
    pq.write_table(pa.table({"score": scores, "failed": failed}), path)

    result = reliability(path)

    assert result["overall"] == {
        "rows": 7,
        "failed": 3,
        "expected_failures": pytest.approx(1.462),
        "mean_score": pytest.approx(1.462 / 7, abs=1e-6),
        "failure_rate": pytest.approx(3 / 7, abs=1e-6),
    }
    bands = {tuple(b["band"]): b for b in result["bands"]}
    assert list(bands) == [(0.0, 0.001), (0.001, 0.01), (0.01, 0.1), (0.5, 1.0)]  # the empty 10-50% band is left out
    assert bands[(0.0, 0.001)]["rows"] == 2 and bands[(0.0, 0.001)]["failed"] == 0
    assert bands[(0.001, 0.01)]["rows"] == 1  # a score on an edge belongs to the band above
    assert bands[(0.01, 0.1)] == {
        "band": [0.01, 0.1],
        "rows": 2,
        "failed": 1,
        "expected_failures": pytest.approx(0.06),
        "mean_score": pytest.approx(0.03),
        "failure_rate": pytest.approx(0.5),
    }
    assert bands[(0.5, 1.0)]["failed"] == 2 and bands[(0.5, 1.0)]["mean_score"] == pytest.approx(0.7)
