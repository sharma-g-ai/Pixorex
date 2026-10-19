"""Work-email validation that still accepts synthetic @demo.local addresses locally.

Pydantic's EmailStr uses email-validator, which rejects reserved TLDs like `.local`.
Our seed and Mailpit demos use `@demo.local`, so invites/removal replacements must allow them.
"""

from typing import Annotated

from email_validator import EmailNotValidError, validate_email
from pydantic import AfterValidator


def _work_email(value: str) -> str:
    text = value.strip()
    # Synthetic local-only addresses (seed users, Mailpit). Shape only — not for production domains.
    if text.lower().endswith("@demo.local"):
        local, _, domain = text.partition("@")
        if local and domain.lower() == "demo.local" and " " not in local:
            return text.lower()
        raise ValueError("Enter a valid work email.")
    try:
        return validate_email(text, check_deliverability=False).normalized
    except EmailNotValidError as exc:
        raise ValueError("Enter a valid work email.") from exc


WorkEmail = Annotated[str, AfterValidator(_work_email)]
