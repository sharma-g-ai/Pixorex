from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Prefer api/.env, then repo-root .env (Pixorex/.env) when uvicorn runs from api/.
    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Postgres as pixorex_app (RLS). Host "postgres" inside Compose; localhost from the host.
    database_url: str = "postgresql://pixorex_app:local-only@localhost:5433/pixorex"
    # Owner URL for bootstrap, invite public lookup, and inserts that need to bypass RLS (MVP).
    # Replace with SECURITY DEFINER functions before production (baseline README open point #6).
    database_owner_url: str = "postgresql://pixorex_owner:local-only@localhost:5433/pixorex"

    # Keycloak
    kc_issuer: str = "http://localhost:8180/realms/pixorex"
    kc_api_admin_client_id: str = "pixorex-api-admin"
    kc_api_admin_secret: str = ""
    # Browser-reachable issuer for JWKS when API runs in Docker but tokens use localhost
    kc_public_issuer: str | None = None

    # Invite emails (Mailpit locally; SendGrid host/user/password for real mail)
    invite_app_base_url: str = "http://localhost:5173"
    smtp_host: str = "localhost"
    smtp_port: int = 1025
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_starttls: bool = False
    smtp_from: str = "no-reply@pixorex.local"
    smtp_from_name: str = "Pixorex"

    cors_origins: str = "http://localhost:5173"

    @property
    def issuer_for_validation(self) -> str:
        return (self.kc_public_issuer or self.kc_issuer).rstrip("/")

    @property
    def jwks_url(self) -> str:
        return f"{self.kc_issuer.rstrip('/')}/protocol/openid-connect/certs"

    @property
    def token_url(self) -> str:
        return f"{self.kc_issuer.rstrip('/')}/protocol/openid-connect/token"

    @property
    def admin_base(self) -> str:
        # http://host/realms/pixorex → http://host/admin/realms/pixorex
        root = self.kc_issuer.rstrip("/").rsplit("/realms/", 1)[0]
        realm = self.kc_issuer.rstrip("/").rsplit("/realms/", 1)[1]
        return f"{root}/admin/realms/{realm}"


@lru_cache
def get_settings() -> Settings:
    return Settings()
