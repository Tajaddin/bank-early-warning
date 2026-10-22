"""The three SQL engines behind one small interface: run the schema scripts, bulk-load the data and the model, score
a quarter with the engine's own procedure, read the scores back.

Each engine keeps its own SQL (sql/<engine>/): the point of the project is that the same model is expressed in each
dialect and proven equal, not generated from one template."""

from __future__ import annotations

import json
import re
import time
from abc import ABC, abstractmethod
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

from bew import log

SQL = Path(__file__).resolve().parents[2] / "sql"
FINANCIAL_COLUMNS = (
    "cert", "repdte", "asset", "dep", "bro", "eqv", "rbc1aaj", "nclnlsr",
    "lnatresr", "elnatry", "roa", "nimy", "eeffr", "lnlsdepr",
)  # fmt: skip
BATCH = 5_000
logger = log.get(__name__)


@dataclass(frozen=True)
class Model:
    intercept: float
    features: list[dict[str, Any]]  # feature, coefficient, lower, upper

    @classmethod
    def load(cls, path: Path) -> Model:
        doc = json.loads(path.read_text(encoding="utf-8"))
        # JSON writes a bound of exactly 0 as an integer; every number is a double to the engines (and mssql-python
        # refuses to bind a column that mixes ints and floats)
        features = [
            {"feature": f["feature"], **{k: float(f[k]) for k in ("coefficient", "lower", "upper")}}
            for f in doc["features"]
        ]
        return cls(float(doc["intercept"]), features)


def batches(rows: Sequence[tuple[Any, ...]], size: int = BATCH) -> Iterator[Sequence[tuple[Any, ...]]]:
    for start in range(0, len(rows), size):
        yield rows[start : start + size]


class Engine(ABC):
    name: str
    placeholder = "%s"

    def __init__(self, connection: Any) -> None:
        self.conn = connection

    # --- scripts -------------------------------------------------------------------------------------------------

    @staticmethod
    @abstractmethod
    def statements(script: str) -> list[str]:
        """Split a script into the statements the driver sends one at a time."""

    def run_script(self, path: Path) -> None:
        with self.conn.cursor() as cur:
            for statement in self.statements(path.read_text(encoding="utf-8")):
                cur.execute(statement)
        self.conn.commit()

    def install(self) -> None:
        for script in self.scripts():
            self.run_script(script)

    @abstractmethod
    def scripts(self) -> list[Path]: ...

    # --- data ----------------------------------------------------------------------------------------------------

    def insert_sql(self, table: str, columns: Sequence[str]) -> str:
        values = ", ".join([self.placeholder] * len(columns))
        return f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({values})"

    def load(self, table: str, columns: Sequence[str], rows: Sequence[tuple[Any, ...]]) -> float:
        """Replace a table's contents; returns the seconds the insert took."""
        started = time.perf_counter()
        with self.conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table}")
            sql = self.insert_sql(table, columns)
            for chunk in batches(rows):
                cur.executemany(sql, list(chunk))
        self.conn.commit()
        return time.perf_counter() - started

    def load_model(self, model: Model) -> None:
        self.load("model_intercept", ("id", "intercept"), [(1, model.intercept)])
        rows = [(f["feature"], f["coefficient"], f["lower"], f["upper"]) for f in model.features]
        self.load("model_feature", ("feature", "coefficient", "lower_bound", "upper_bound"), rows)

    # --- scoring -------------------------------------------------------------------------------------------------

    @abstractmethod
    def score_quarter(self, repdte: date) -> int:
        """Run the engine's scoring procedure for one quarter; returns how many banks it scored."""

    def scores(self, repdte: date) -> dict[int, float]:
        with self.conn.cursor() as cur:
            cur.execute(f"SELECT cert, score FROM risk_score WHERE repdte = {self.placeholder}", (repdte,))
            return {int(cert): float(score) for cert, score in cur.fetchall()}

    def count(self, sql: str) -> int:
        with self.conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()
            return int(row[0])


class MySQL(Engine):
    name = "mysql"

    @staticmethod
    def statements(script: str) -> list[str]:
        # procedures are written as one statement each (no DELIMITER); split at ';' outside BEGIN ... END bodies
        out: list[str] = []
        current: list[str] = []
        depth = 0
        for line in script.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("--"):
                continue
            current.append(line)
            depth += len(re.findall(r"\bBEGIN\b", stripped, re.IGNORECASE))
            depth -= len(re.findall(r"\bEND\b\s*;", stripped, re.IGNORECASE))
            if stripped.endswith(";") and depth <= 0:
                out.append("\n".join(current).rstrip().rstrip(";"))
                current, depth = [], 0
        return out

    def scripts(self) -> list[Path]:
        return [SQL / "mysql" / "schema.sql", SQL / "mysql" / "procedures.sql"]

    def score_quarter(self, repdte: date) -> int:
        with self.conn.cursor() as cur:
            cur.execute("CALL score_quarter(%s)", (repdte,))
            scored = int(cur.fetchone()[0])
            while cur.nextset():
                pass
        self.conn.commit()
        return scored


class SqlServer(Engine):
    name = "sqlserver"
    placeholder = "?"

    @staticmethod
    def statements(script: str) -> list[str]:
        batches_ = re.split(r"^\s*GO\s*$", script, flags=re.MULTILINE | re.IGNORECASE)
        return [b.strip() for b in batches_ if re.sub(r"--[^\n]*", "", b).strip()]

    def scripts(self) -> list[Path]:
        return [SQL / "sqlserver" / "schema.sql", SQL / "sqlserver" / "procedures.sql"]

    def score_quarter(self, repdte: date) -> int:
        with self.conn.cursor() as cur:
            cur.execute("EXEC dbo.score_quarter ?", (repdte,))
            scored = int(cur.fetchone()[0])
        self.conn.commit()
        return scored


class Oracle(Engine):
    name = "oracle"
    placeholder = ":1"

    def insert_sql(self, table: str, columns: Sequence[str]) -> str:
        values = ", ".join(f":{i + 1}" for i in range(len(columns)))
        return f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({values})"

    def load(self, table: str, columns: Sequence[str], rows: Sequence[tuple[Any, ...]]) -> float:
        """As the base class, but binds floats as BINARY_DOUBLE: oracledb's default for a Python float is NUMBER,
        and the doubles must reach the table bit for bit."""
        import oracledb

        started = time.perf_counter()
        sample = next((r for r in rows), ())
        kinds = [
            oracledb.DB_TYPE_BINARY_DOUBLE if any(isinstance(r[i], float) for r in rows[:1000]) else None
            for i in range(len(sample))
        ]
        with self.conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table}")
            sql = self.insert_sql(table, columns)
            for chunk in batches(rows):
                cur.setinputsizes(*kinds)
                cur.executemany(sql, list(chunk))
        self.conn.commit()
        return time.perf_counter() - started

    @staticmethod
    def statements(script: str) -> list[str]:
        """SQL statements end with ';'; PL/SQL units (CREATE ... PACKAGE/FUNCTION/PROCEDURE) end with a '/' line."""
        out: list[str] = []
        current: list[str] = []
        plsql = False
        for line in script.splitlines():
            stripped = line.strip()
            if not current and (not stripped or stripped.startswith("--")):
                continue
            if stripped == "/":
                out.append("\n".join(current).strip())
                current, plsql = [], False
                continue
            current.append(line)
            if len(current) == 1 and re.match(
                r"CREATE\s+(OR\s+REPLACE\s+)?(PACKAGE|FUNCTION|PROCEDURE|TRIGGER)", stripped, re.I
            ):
                plsql = True
            if not plsql and stripped.endswith(";"):
                out.append("\n".join(current).strip().rstrip(";"))
                current = []
        return out

    def scripts(self) -> list[Path]:
        return [SQL / "oracle" / "schema.sql", SQL / "oracle" / "bank_risk.sql"]

    def score_quarter(self, repdte: date) -> int:
        with self.conn.cursor() as cur:
            return int(cur.callfunc("bank_risk.score_quarter", int, [repdte]))
