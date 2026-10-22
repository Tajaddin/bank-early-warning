"""`bew` command line."""

from __future__ import annotations

import json
import sys
from datetime import date
from pathlib import Path
from typing import Annotated

import typer

from bew import log

app = typer.Typer(no_args_is_help=True, add_completion=False)
RAW = Path("data/raw")


@app.callback()
def main(level: Annotated[str, typer.Option(envvar="BEW_LOG_LEVEL")] = "INFO") -> None:
    log.configure(level)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")


@app.command()
def fetch(
    first: Annotated[str, typer.Option(help="first report date")] = "2006-12-31",
    last: Annotated[str, typer.Option(help="last report date")] = "2013-12-31",
    raw: Annotated[Path, typer.Option()] = RAW,
) -> None:
    """Financials for every quarter in the range, all failures and all institutions, from the FDIC API."""
    from bew.fdic import fetch_all

    manifest = fetch_all(raw, date.fromisoformat(first), date.fromisoformat(last))
    typer.echo(
        json.dumps({k: {"rows": v["rows"], "sha256": v["sha256"][:12]} for k, v in manifest["files"].items()}, indent=2)
    )


@app.command("check")
def check_data(
    raw: Annotated[Path, typer.Option()] = RAW, out: Annotated[Path, typer.Option()] = Path("reports/data-checks.json")
) -> None:
    """Data checks on the fetched files; exits 1 if a key repeats or a failure has no filings."""
    from bew.checks import check

    result = check(raw)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    typer.echo(json.dumps(result, indent=2))
    if not all(result["passed"].values()):
        raise typer.Exit(1)


@app.command()
def parity(
    engines: Annotated[str, typer.Option(help="comma-separated: mysql,sqlserver,oracle")] = "mysql,sqlserver,oracle",
    raw: Annotated[Path, typer.Option()] = RAW,
    model: Annotated[Path, typer.Option(help="model.json from the R pipeline")] = Path("reports/r/model.json"),
    reference: Annotated[Path, typer.Option(help="R's scores for every test bank-quarter")] = Path(
        "reports/r/test_scores_all.parquet"
    ),
    out: Annotated[Path, typer.Option()] = Path("reports/parity.json"),
) -> None:
    """Score the test quarters in each engine and compare with R."""
    from bew.config import settings
    from bew.parity import run, write

    report = run([e.strip() for e in engines.split(",") if e.strip()], raw, model, reference, settings())
    write(report, out)
    summary = {
        k: {
            f: v[f]
            for f in ("banks_scored", "max_abs_diff_vs_r", "equal_to_r", "load_financials_s", "score_all_quarters_s")
        }
        for k, v in report["engines"].items()
    }
    typer.echo(json.dumps(summary, indent=2))
    if not all(v["equal_to_r"] for v in report["engines"].values()):
        raise typer.Exit(1)
