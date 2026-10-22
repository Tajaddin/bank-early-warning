"""Write .env with fresh random passwords for the local databases (refuses to overwrite an existing one).

    python scripts/make_env.py

The passwords only protect containers bound to 127.0.0.1; they are generated, never typed, and .env is git-ignored.
SQL Server requires upper and lower case, digits and a symbol, so every password has all four."""

from __future__ import annotations

import secrets
import string
import sys
from pathlib import Path

NAMES = (
    "MYSQL_ROOT_PASSWORD",
    "BEW_MYSQL_PASSWORD",
    "BEW_SQLSERVER_PASSWORD",
    "ORACLE_SYS_PASSWORD",
    "BEW_ORACLE_PASSWORD",
)


def password(length: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits
    body = "".join(secrets.choice(alphabet) for _ in range(length - 4))
    # one of each class SQL Server's policy wants; '_' is safe in shells, URLs and every driver's connect string
    return (
        body
        + secrets.choice(string.ascii_uppercase)
        + secrets.choice(string.ascii_lowercase)
        + secrets.choice(string.digits)
        + "_"
    )


def main() -> int:
    env = Path(".env")
    if env.exists():
        print(".env exists; not overwriting it")
        return 0
    lines = [f"{name}={password()}" for name in NAMES]
    lines.append("BEW_SQLSERVER_USER=sa")
    env.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {env} ({len(NAMES)} generated passwords)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
