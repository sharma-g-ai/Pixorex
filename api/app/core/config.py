"""Settings, checked once at startup (CONSTITUTION: config validation at startup)."""

from functools import lru_cache
from typing import Literal

from psycopg.conninfo import conninfo_to_dict
from pydantic import AnyHttpUrl, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Roles that bypass row-level security; the API must never connect as them.
_RLS_BYPASS_ROLES = {"postgres", "pixorex_owner"}


class Settings(BaseSettings):
    # TODO (A0, PX-10-T03): secrets come from Vault at start, not env vars.
    # Until then local dev passes them as PIXOREX_* env vars.
    model_config = SettingsConfigDict(env_prefix="PIXOREX_", frozen=True)

    env: Literal["local", "test", "staging", "production"] = "local"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    database_url: SecretStr
    db_pool_min: int = 1
    db_pool_max: int = 10
    minio_url: AnyHttpUrl
    vault_url: AnyHttpUrl
    readiness_timeout_s: float = 2.0

    # Keycloak. oidc_issuer is the `iss` in tokens (the address browsers use);
    # oidc_internal_url is how this service reaches Keycloak when that differs (Docker).
    oidc_issuer: AnyHttpUrl
    oidc_internal_url: AnyHttpUrl | None = None
    oidc_audience: str = "pixorex-api"
    oidc_clients: frozenset[str] = frozenset({"pixorex-web", "pixorex-mobile"})
    keycloak_admin_client_id: str = "pixorex-api-admin"
    keycloak_admin_secret: SecretStr | None = None

    # Invite email. The link opens the web app (/activate#token=...).
    invite_base_url: AnyHttpUrl = AnyHttpUrl("http://localhost:5173")
    smtp_host: str = "localhost"
    smtp_port: int = 1025
    smtp_user: str | None = None
    smtp_password: SecretStr | None = None
    smtp_starttls: bool = False
    smtp_from: str = "no-reply@pixorex.local"
    smtp_from_name: str = "Pixorex"

    @field_validator("keycloak_admin_secret", "smtp_password", "smtp_user", mode="before")
    @classmethod
    def _empty_is_unset(cls, value: object) -> object:
        """Compose passes unset variables as empty strings."""
        return None if value == "" else value

    @field_validator("database_url")
    @classmethod
    def _not_an_rls_bypass_role(cls, value: SecretStr) -> SecretStr:
        user = conninfo_to_dict(value.get_secret_value()).get("user")
        if user is None or user in _RLS_BYPASS_ROLES:
            raise ValueError("database_url must name the API role (pixorex_app), not an owner")
        return value

    @property
    def docs_enabled(self) -> bool:
        return self.env in ("local", "test")

    @property
    def keycloak_realm_url(self) -> str:
        """The realm as this service reaches it, e.g. http://keycloak:8080/realms/pixorex."""
        return str(self.oidc_internal_url or self.oidc_issuer).rstrip("/")


@lru_cache
def get_settings() -> Settings:
    return Settings()  # values come from the environment
