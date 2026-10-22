"""Run the PL/SQL unit tests with utPLSQL inside the Oracle container.

    python scripts/oracle_tests.py [--out reports/oracle-utplsql.xml]

Installs utPLSQL once (the release zip, checked against its published sha256, installed headless as SYSDBA inside
the container), then, as the application user: the schema, the bank_risk package and its test package, and
ut.run with the JUnit reporter. Exits 1 if any test fails or errors. Run it on an empty schema, before `bew parity`
loads the real data, because the tests replace the model."""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import re
import secrets
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from bew.config import settings  # noqa: E402
from bew.connect import oracle_connection  # noqa: E402
from bew.engines import SQL, Oracle  # noqa: E402

VERSION = "v.3.2.3"  # the project tags releases with a dot after the v
RELEASE = f"https://github.com/utPLSQL/utPLSQL/releases/download/{VERSION}"


def compose(*args: str, stdin: str | None = None) -> str:
    out = subprocess.run(
        ["docker", "compose", *args], input=stdin, capture_output=True, text=True, check=False, cwd=ROOT
    )
    if out.returncode != 0:
        log = ROOT / ".cache" / "compose-error.log"
        log.write_text(out.stdout + out.stderr, encoding="utf-8")
        raise SystemExit(f"docker compose {' '.join(args[:4])} failed; output in {log.relative_to(ROOT)}")
    return out.stdout


def install_utplsql(conn: object) -> None:
    with conn.cursor() as cur:  # type: ignore[attr-defined]
        # complete when the UT package is there (the install grants it to PUBLIC); a bare UT3 user is a failed one
        cur.execute("SELECT COUNT(*) FROM all_objects WHERE owner = 'UT3' AND object_name = 'UT'")
        if cur.fetchone()[0]:
            print("utPLSQL already installed")
            return
    archive = httpx.get(f"{RELEASE}/utPLSQL.zip", follow_redirects=True, timeout=120).raise_for_status().content
    # BSD format: "SHA256 (utPLSQL.zip) = <64 hex>"
    checksum = httpx.get(f"{RELEASE}/utPLSQL.zip.sha256", follow_redirects=True, timeout=60).raise_for_status().text
    found = re.search(r"\b[0-9a-f]{64}\b", checksum)
    if found is None:
        raise SystemExit(f"no sha256 in {checksum!r}")
    published = found.group(0)
    if hashlib.sha256(archive).hexdigest() != published:
        raise SystemExit("utPLSQL.zip does not match its published sha256")
    staging = ROOT / ".cache" / "utPLSQL"
    zipfile.ZipFile(io.BytesIO(archive)).extractall(staging)
    container = compose("ps", "-q", "oracle").strip()
    target = "/tmp/utplsql"  # noqa: S108 (a path inside the Oracle container, not on this machine)
    subprocess.run(["docker", "cp", str(staging / "utPLSQL" / "source"), f"{container}:{target}"], check=True)
    # the installer writes temporary files next to itself, as the oracle user; docker cp left the folder root's
    compose("exec", "-T", "-u", "root", "oracle", "chmod", "-R", "a+rwX", target)
    # the passwords go in on stdin, not the command line, so they never show in the container's process list;
    # UT3 gets a generated password instead of the installer's built-in default (nobody logs in as UT3)
    ut3_password = "U" + secrets.token_hex(12)
    script = (
        f"connect sys/{os.environ['ORACLE_SYS_PASSWORD']}@//localhost/FREEPDB1 as sysdba\n"
        "drop user ut3 cascade;\n"  # a half-finished earlier attempt; harmless when there is none
        f"@install_headless.sql UT3 {ut3_password} users\n"
        "exit\n"
    )
    output = compose("exec", "-T", "-w", target, "oracle", "sqlplus", "-s", "/nolog", stdin=script)
    (ROOT / ".cache" / "utplsql-install.log").write_text(output, encoding="utf-8")
    print(f"utPLSQL {VERSION} installed (sha256 {published[:12]})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=ROOT / "reports" / "oracle-utplsql.xml")
    a = ap.parse_args()
    s = settings()
    conn = oracle_connection(s)
    install_utplsql(conn)
    engine = Oracle(conn)
    engine.install()
    engine.run_script(SQL / "oracle" / "test_bank_risk.sql")
    with conn.cursor() as cur:
        cur.execute("SELECT column_value FROM TABLE(ut.run('test_bank_risk', ut_junit_reporter()))")
        xml = "\n".join(row[0] or "" for row in cur.fetchall())
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(xml + "\n", encoding="utf-8", newline="\n")
    root = ET.fromstring(xml)  # noqa: S314 (utPLSQL's own report from our container, not outside input)
    tests, failures, errors = (int(root.get(k, 0)) for k in ("tests", "failures", "errors"))
    print(f"utPLSQL: {tests} tests, {failures} failures, {errors} errors ({a.out})")
    return 0 if tests and not failures and not errors else 1


if __name__ == "__main__":
    sys.exit(main())
