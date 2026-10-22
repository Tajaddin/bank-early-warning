"""Fetch the inputs from the FDIC BankFind Suite API (public, no key) into Parquet files under data/raw/.

The API is a moving snapshot; there is no published checksum. So the manifest records, for every file, the query,
the row count the API reported, the API's own index name and timestamp (its snapshot version), and the sha256 of
the file written, and every later step reads only these files."""

from __future__ import annotations

import hashlib
import json
import time
from collections.abc import Iterator
from datetime import date
from pathlib import Path
from typing import Any

import httpx
import pyarrow as pa
import pyarrow.parquet as pq

from bew import log

API = "https://api.fdic.gov/banks"
PAGE = 10_000
logger = log.get(__name__)

FINANCIAL_FIELDS = {
    "CERT": pa.int64(),
    "REPDTE": pa.date32(),
    "ASSET": pa.float64(),  # total assets, $ thousands
    "DEP": pa.float64(),  # total deposits
    "BRO": pa.float64(),  # brokered deposits
    "EQV": pa.float64(),  # equity capital / assets, %
    "RBC1AAJ": pa.float64(),  # leverage ratio (PCA), %
    "NCLNLSR": pa.float64(),  # noncurrent loans / gross loans, %
    "LNATRESR": pa.float64(),  # loan-loss reserve / gross loans, %
    "ELNATRY": pa.float64(),  # credit-loss provisions / average assets, %
    "ROA": pa.float64(),  # return on assets, %
    "NIMY": pa.float64(),  # net interest margin, %
    "EEFFR": pa.float64(),  # efficiency ratio, %
    "LNLSDEPR": pa.float64(),  # net loans / deposits, %
}
FAILURE_FIELDS = {
    "CERT": pa.int64(),
    "NAME": pa.string(),
    "CITYST": pa.string(),
    "FAILDATE": pa.date32(),
    "RESTYPE": pa.string(),
    "QBFASSET": pa.float64(),
    "COST": pa.float64(),
}
INSTITUTION_FIELDS = {
    "CERT": pa.int64(),
    "NAME": pa.string(),
    "STALP": pa.string(),
    "CITY": pa.string(),
    "BKCLASS": pa.string(),
    "ACTIVE": pa.int64(),
}


def quarter_ends(first: date, last: date) -> list[date]:
    out: list[date] = []
    year, quarter = first.year, (first.month - 1) // 3
    while True:
        month = 3 * quarter + 3
        end = date(year, month, 31 if month in (3, 12) else 30)
        if end > last:
            return out
        if end >= first:
            out.append(end)
        quarter += 1
        if quarter == 4:
            year, quarter = year + 1, 0


def _convert(value: Any, kind: pa.DataType) -> Any:
    if value is None or value == "":
        return None
    if kind == pa.date32():
        text = str(value)
        if "/" in text:  # failures: 7/17/2026
            m, d, y = (int(x) for x in text.split("/"))
            return date(y, m, d)
        return date(int(text[:4]), int(text[4:6]), int(text[6:8]))  # financials: 20091231
    if kind == pa.int64():
        return int(value)
    if kind == pa.float64():
        return float(value)
    return str(value)


def pages(
    client: httpx.Client, endpoint: str, params: dict[str, Any]
) -> Iterator[tuple[dict[str, Any], list[dict[str, Any]]]]:
    """Every page of a query, with retries on 429 and 5xx; yields (meta, rows)."""
    offset = 0
    while True:
        for attempt in range(5):
            r = client.get(f"{API}/{endpoint}", params={**params, "limit": PAGE, "offset": offset})
            if r.status_code < 500 and r.status_code != 429:
                break
            time.sleep(2**attempt)
        r.raise_for_status()
        body = r.json()
        rows = [item["data"] for item in body["data"]]
        yield body["meta"], rows
        offset += len(rows)
        if not rows or offset >= body["meta"]["total"]:
            return


def fetch(
    client: httpx.Client, endpoint: str, params: dict[str, Any], schema: dict[str, pa.DataType]
) -> tuple[pa.Table, dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    meta: dict[str, Any] = {}
    for page_meta, page in pages(client, endpoint, {**params, "fields": ",".join(schema)}):
        meta = page_meta
        rows += page
    if len(rows) != meta.get("total"):
        raise RuntimeError(f"{endpoint}: got {len(rows)} rows, the API reported {meta.get('total')}")
    columns = {name: [_convert(row.get(name), kind) for row in rows] for name, kind in schema.items()}
    table = pa.table({name: pa.array(values, type=schema[name]) for name, values in columns.items()})
    return table, {"endpoint": endpoint, "params": params, "rows": len(rows), "api_index": meta.get("index")}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch_all(raw: Path, first: date, last: date) -> dict[str, Any]:
    raw.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, Any] = {"source": API, "fetched": date.today().isoformat(), "files": {}}
    with httpx.Client(timeout=120) as client:
        quarters = quarter_ends(first, last)
        tables = []
        for q in quarters:
            table, info = fetch(
                client,
                "financials",
                {"filters": f"REPDTE:{q:%Y%m%d}", "sort_by": "CERT", "sort_order": "ASC"},
                FINANCIAL_FIELDS,
            )
            tables.append(table)
            logger.info("fetched", endpoint="financials", quarter=q.isoformat(), rows=info["rows"])
        financials = pa.concat_tables(tables)
        info = {
            "endpoint": "financials",
            "quarters": [q.isoformat() for q in quarters],
            "rows": financials.num_rows,
            "api_index": info["api_index"],
        }
        outputs = {"financials": (financials, info)}
        outputs["failures"] = fetch(client, "failures", {"sort_by": "FAILDATE", "sort_order": "ASC"}, FAILURE_FIELDS)
        outputs["institutions"] = fetch(
            client, "institutions", {"sort_by": "CERT", "sort_order": "ASC"}, INSTITUTION_FIELDS
        )
    for name, (table, info) in outputs.items():
        path = raw / f"{name}.parquet"
        pq.write_table(table, path, compression="zstd")
        manifest["files"][name] = {**info, "path": path.name, "sha256": sha256(path)}
        logger.info("written", file=path.name, rows=table.num_rows)
    (raw / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return manifest
