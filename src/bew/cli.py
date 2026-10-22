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
