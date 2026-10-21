"""Worker settings, checked at start. TODO (A0, PX-10-T03): secrets from Vault."""

from functools import lru_cache
from typing import Literal

from psycopg.conninfo import conninfo_to_dict
from pydantic import AnyHttpUrl, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class WorkerSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="PIXOREX_", frozen=True, extra="ignore")

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    worker_database_url: SecretStr  # the pixorex_worker role
    worker_tick_s: float = 15.0  # how often due emails are sent
    worker_jobs_every_s: float = 60.0  # how often the scheduled jobs run

    minio_url: AnyHttpUrl = AnyHttpUrl("http://localhost:9000")
    minio_access_key: str | None = None
    minio_secret_key: SecretStr | None = None
    minio_bucket: str = "pixorex"

    # AI Inference Proxy (Portkey), for scan extraction. Unset key: extraction waits and
    # retries, then the attempt fails.
    portkey_url: AnyHttpUrl = AnyHttpUrl("https://api.portkey.ai/v1")
    portkey_api_key: SecretStr | None = None
    portkey_config_id: str | None = None
    ai_timeout_s: float = 60.0

    invite_base_url: AnyHttpUrl = AnyHttpUrl("http://localhost:5173")  # the web app
    smtp_host: str = "localhost"
    smtp_port: int = 1025
    smtp_user: str | None = None
    smtp_password: SecretStr | None = None
    smtp_starttls: bool = False
    smtp_from: str = "no-reply@pixorex.local"
    smtp_from_name: str = "Pixorex"
    local_smtp_host: str = "mailpit"
    local_smtp_port: int = 1025

    @field_validator(
        "smtp_password",
        "smtp_user",
        "minio_access_key",
        "minio_secret_key",
        "portkey_api_key",
        "portkey_config_id",
        mode="before",
    )
    @classmethod
    def _empty_is_unset(cls, value: object) -> object:
        return None if value == "" else value

    @field_validator("worker_database_url")
    @classmethod
    def _worker_role(cls, value: SecretStr) -> SecretStr:
        if conninfo_to_dict(value.get_secret_value()).get("user") != "pixorex_worker":
            raise ValueError("worker_database_url must name the pixorex_worker role")
        return value


@lru_cache
def get_worker_settings() -> WorkerSettings:
    return WorkerSettings()  # values come from the environment
