from datetime import date
from pathlib import Path

import httpx
import pyarrow as pa
import pytest
import respx

from bew import fdic


def test_quarter_ends() -> None:
    assert fdic.quarter_ends(date(2006, 12, 31), date(2007, 12, 31)) == [
        date(2006, 12, 31), date(2007, 3, 31), date(2007, 6, 30), date(2007, 9, 30), date(2007, 12, 31),
    ]  # fmt: skip
    assert fdic.quarter_ends(date(2007, 1, 1), date(2007, 3, 30)) == []


@pytest.mark.parametrize(
    ("value", "kind", "want"),
    [
        ("20091231", pa.date32(), date(2009, 12, 31)),
        ("7/17/2026", pa.date32(), date(2026, 7, 17)),
        ("3511", pa.int64(), 3511),
        (1.25, pa.float64(), 1.25),
        (None, pa.float64(), None),
        ("", pa.string(), None),
    ],
)
def test_convert(value: object, kind: pa.DataType, want: object) -> None:
    assert fdic._convert(value, kind) == want


@respx.mock
def test_fetch_pages_and_checks_the_count(tmp_path: Path) -> None:
    def page(request: httpx.Request) -> httpx.Response:
        offset = int(request.url.params["offset"])
        rows = [
            {"data": {"CERT": c, "NAME": f"Bank {c}", "STALP": "FL", "CITY": "Tampa", "BKCLASS": "N", "ACTIVE": 1}}
            for c in range(offset, min(offset + 2, 3))
        ]
        return httpx.Response(200, json={"meta": {"total": 3, "index": {"name": "institutions_x"}}, "data": rows})

    respx.get(f"{fdic.API}/institutions").mock(side_effect=page)
    monkey = fdic.PAGE
    fdic.PAGE = 2
    try:
        with httpx.Client() as client:
            table, info = fdic.fetch(client, "institutions", {}, fdic.INSTITUTION_FIELDS)
    finally:
        fdic.PAGE = monkey
    assert table.num_rows == 3 and table["CERT"].to_pylist() == [0, 1, 2]
    assert info["rows"] == 3 and info["api_index"]["name"] == "institutions_x"


@respx.mock
def test_a_short_read_is_refused() -> None:
    respx.get(f"{fdic.API}/failures").mock(return_value=httpx.Response(200, json={"meta": {"total": 5}, "data": []}))
    with httpx.Client() as client, pytest.raises(RuntimeError, match="got 0 rows"):
        fdic.fetch(client, "failures", {}, fdic.FAILURE_FIELDS)
