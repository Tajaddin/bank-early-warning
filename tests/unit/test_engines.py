from pathlib import Path

import pytest

from bew.engines import SQL, Model, MySQL, Oracle, SqlServer, batches
from bew.parity import compare


def test_mysql_statements_keep_procedure_bodies_whole() -> None:
    script = """
-- a comment
CREATE TABLE t (a INT);
DROP PROCEDURE IF EXISTS p;
CREATE PROCEDURE p(IN x INT)
BEGIN
  DELETE FROM t WHERE a = x;
  INSERT INTO t VALUES (x);
END;
CREATE OR REPLACE VIEW v AS SELECT MAX(CASE a WHEN 1 THEN a END) AS one FROM t;
"""
    out = MySQL.statements(script)
    assert len(out) == 4
    assert out[2].startswith("CREATE PROCEDURE") and "INSERT INTO t VALUES (x);" in out[2] and out[2].endswith("END")
    assert out[3].startswith("CREATE OR REPLACE VIEW")


def test_sqlserver_batches_split_on_go() -> None:
    script = "CREATE TABLE t (a INT);\nGO\n-- only a comment\nGO\nCREATE OR ALTER PROCEDURE p AS SELECT 1;\ngo\n"
    assert SqlServer.statements(script) == ["CREATE TABLE t (a INT);", "CREATE OR ALTER PROCEDURE p AS SELECT 1;"]


def test_oracle_statements_and_plsql_units() -> None:
    script = """
CREATE TABLE t (a NUMBER);
CREATE OR REPLACE PACKAGE k AS
  FUNCTION f RETURN NUMBER;
END k;
/
CREATE OR REPLACE VIEW v AS SELECT a FROM t;
"""
    out = Oracle.statements(script)
    assert out[0] == "CREATE TABLE t (a NUMBER)"
    assert out[1].startswith("CREATE OR REPLACE PACKAGE k") and out[1].endswith("END k;")
    assert out[2] == "CREATE OR REPLACE VIEW v AS SELECT a FROM t"


def test_the_committed_scripts_split_into_the_expected_statements() -> None:
    assert len(MySQL.statements((SQL / "mysql" / "schema.sql").read_text())) == 6
    assert (
        sum(s.startswith("CREATE PROCEDURE") for s in MySQL.statements((SQL / "mysql" / "procedures.sql").read_text()))
        == 2
    )
    assert len(SqlServer.statements((SQL / "sqlserver" / "procedures.sql").read_text())) == 2
    oracle = Oracle.statements((SQL / "oracle" / "bank_risk.sql").read_text())
    assert [s.split()[3] for s in oracle] == ["PACKAGE", "PACKAGE"]


def test_every_engine_computes_every_feature() -> None:
    features = (
        "eqv",
        "lev",
        "ncl",
        "reserve",
        "prov",
        "roa",
        "nim",
        "eff",
        "ltd",
        "brokered",
        "log_assets",
        "d_roa",
        "d_ncl",
        "growth",
    )
    for engine, scoring in (("mysql", "procedures.sql"), ("sqlserver", "procedures.sql"), ("oracle", "bank_risk.sql")):
        text = (SQL / engine / scoring).read_text().lower()
        for f in features:
            assert f"c.{f} " in text and f"b.{f}," in text, (engine, f)


def test_model_and_batches(tmp_path: Path) -> None:
    path = tmp_path / "model.json"
    path.write_text(
        '{"intercept": -2.5, "features": [{"feature": "eqv", "coefficient": -0.1, "lower": 1, "upper": 30}]}'
    )
    m = Model.load(path)
    assert m.intercept == -2.5 and m.features[0]["feature"] == "eqv"
    assert [len(b) for b in batches([(i,) for i in range(12)], size=5)] == [5, 5, 2]


def test_compare() -> None:
    r = {1: 0.10, 2: 0.20, 3: 0.30}
    assert compare(r, {1: 0.10, 2: 0.20 + 1e-12, 4: 0.5}) == {
        "banks": 3,
        "missing": 1,
        "extra": 1,
        "max_abs_diff": pytest.approx(1e-12, abs=1e-15),
    }


def test_model_numbers_are_all_doubles(tmp_path: Path) -> None:
    path = tmp_path / "model.json"
    path.write_text('{"intercept": -4, "features": [{"feature": "ncl", "coefficient": 0.17, "lower": 0, "upper": 15}]}')
    m = Model.load(path)
    assert isinstance(m.intercept, float)
    assert all(isinstance(m.features[0][k], float) for k in ("coefficient", "lower", "upper"))
