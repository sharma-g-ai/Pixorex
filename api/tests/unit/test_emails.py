"""WorkEmail accepts real addresses and synthetic @demo.local ones."""

import pytest
from pydantic import BaseModel, ValidationError

from app.core.emails import WorkEmail


class Body(BaseModel):
    email: WorkEmail


def test_a_normal_work_email_is_accepted() -> None:
    assert Body(email="Ada@Example.com").email == "Ada@example.com"


def test_demo_local_addresses_are_accepted_for_seed_users() -> None:
    assert Body(email="buadmin.p04@demo.local").email == "buadmin.p04@demo.local"


@pytest.mark.parametrize("bad", ["", "not-an-email", "a@b", "spaces ok@demo.local"])
def test_junk_is_rejected(bad: str) -> None:
    with pytest.raises(ValidationError):
        Body(email=bad)
