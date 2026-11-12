"""Worker settings: how many AI calls an extraction container makes at once."""

import pytest
from pydantic import ValidationError

from app.workers import runner
from app.workers.settings import WorkerSettings

WORKER_DB = "postgresql://pixorex_worker:x@localhost/pixorex"


def _settings(monkeypatch: pytest.MonkeyPatch, **env: str) -> WorkerSettings:
    monkeypatch.setenv("PIXOREX_WORKER_DATABASE_URL", WORKER_DB)
    for name, value in env.items():
        monkeypatch.setenv(f"PIXOREX_{name.upper()}", value)
    return WorkerSettings()


def test_an_extraction_container_makes_4_calls_at_once_unless_told_otherwise(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    assert _settings(monkeypatch).extraction_concurrency == 4
    assert _settings(monkeypatch, extraction_concurrency="8").extraction_concurrency == 8


@pytest.mark.parametrize("value", ["0", "-1", "33"])
def test_the_concurrency_is_between_1_and_32(monkeypatch: pytest.MonkeyPatch, value: str) -> None:
    with pytest.raises(ValidationError):
        _settings(monkeypatch, extraction_concurrency=value)


def test_the_extraction_pool_has_a_connection_for_every_claim_loop_and_one_more(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    extraction = _settings(monkeypatch, worker_role="extraction", extraction_concurrency="6")
    assert runner._pool(extraction).max_size == 7
    assert runner._pool(_settings(monkeypatch, worker_role="general")).max_size == 2
