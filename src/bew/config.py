"""Connection settings from environment variables (prefix BEW_). The defaults are the local Docker databases from
docker-compose.yml, whose passwords come from .env (`make env`); nothing here is a real credential."""

from __future__ import annotations

from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BEW_", env_file=".env", extra="ignore")

    mysql_host: str = "127.0.0.1"
    mysql_port: int = 33306
    mysql_user: str = "bew"
    mysql_password: SecretStr = SecretStr("")
    mysql_database: str = "bew"

    sqlserver_host: str = "127.0.0.1"
    sqlserver_port: int = 31433
    sqlserver_user: str = "sa"
    sqlserver_password: SecretStr = SecretStr("")
    sqlserver_database: str = "bew"

    oracle_dsn: str = "127.0.0.1:31521/FREEPDB1"
    oracle_user: str = "bew"
    oracle_password: SecretStr = SecretStr("")


@lru_cache(maxsize=1)
def settings() -> Settings:
    return Settings()
