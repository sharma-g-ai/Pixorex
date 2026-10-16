import httpx

from app.services import readiness
from tests.conftest import make_settings


class _Pool:
    def __init__(self, ok: bool) -> None:
        self.ok = ok

    def connection(self) -> "_Pool":
        return self

    async def __aenter__(self) -> "_Pool":
        if not self.ok:
            raise OSError("down")
        return self

    async def __aexit__(self, *_: object) -> None:
        return None

    async def execute(self, _: str) -> None:
        return None


def _client(failing_host_path: str | None) -> httpx.AsyncClient:
    def handler(request: httpx.Request) -> httpx.Response:
        if failing_host_path and failing_host_path in str(request.url):
            return httpx.Response(503, text="secret version 1.2.3")
        return httpx.Response(200)

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_all_ok() -> None:
    async with _client(None) as client:
        checks = await readiness.check_all(make_settings(), _Pool(True), client)  # type: ignore[arg-type]
    assert checks == {"database": "ok", "keycloak": "ok", "minio": "ok", "vault": "ok"}


async def test_failures_are_only_ok_or_fail() -> None:
    async with _client("/v1/sys/health") as client:
        checks = await readiness.check_all(make_settings(), _Pool(False), client)  # type: ignore[arg-type]
    assert checks == {"database": "fail", "keycloak": "ok", "minio": "ok", "vault": "fail"}
