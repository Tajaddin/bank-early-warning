"""Open a connection to each engine (and create the SQL Server database on first use)."""

from __future__ import annotations

from typing import Any

from bew.config import Settings
from bew.engines import Engine, MySQL, Oracle, SqlServer

ENGINES = ("mysql", "sqlserver", "oracle")


def mysql_connection(s: Settings) -> Any:
    import pymysql

    return pymysql.connect(
        host=s.mysql_host,
        port=s.mysql_port,
        user=s.mysql_user,
        password=s.mysql_password.get_secret_value(),
        database=s.mysql_database,
        autocommit=False,
    )


def sqlserver_connection(s: Settings, database: str | None = None) -> Any:
    import mssql_python

    conn = mssql_python.connect(
        f"Server={s.sqlserver_host},{s.sqlserver_port};Database={database or s.sqlserver_database};"
        f"Uid={s.sqlserver_user};Pwd={s.sqlserver_password.get_secret_value()};Encrypt=yes;TrustServerCertificate=yes"
    )
    conn.autocommit = False
    return conn


def ensure_sqlserver_database(s: Settings) -> None:
    conn = sqlserver_connection(s, "master")
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(f"IF DB_ID('{s.sqlserver_database}') IS NULL CREATE DATABASE [{s.sqlserver_database}]")
    conn.close()


def oracle_connection(s: Settings) -> Any:
    import oracledb

    return oracledb.connect(user=s.oracle_user, password=s.oracle_password.get_secret_value(), dsn=s.oracle_dsn)


def engine(name: str, s: Settings) -> Engine:
    if name == "mysql":
        return MySQL(mysql_connection(s))
    if name == "sqlserver":
        ensure_sqlserver_database(s)
        return SqlServer(sqlserver_connection(s))
    if name == "oracle":
        return Oracle(oracle_connection(s))
    raise ValueError(f"unknown engine {name}")
