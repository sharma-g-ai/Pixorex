import pytest
from pydantic import ValidationError

from tests.conftest import make_settings


@pytest.mark.parametrize("user", ["postgres", "pixorex_owner"])
def test_refuses_roles_that_bypass_rls(user: str) -> None:
    with pytest.raises(ValidationError, match="pixorex_app"):
        make_settings(database_url=f"postgresql://{user}:x@db/pixorex")


def test_docs_only_outside_deployed_envs() -> None:
    assert make_settings(env="local").docs_enabled
    assert not make_settings(env="production").docs_enabled
