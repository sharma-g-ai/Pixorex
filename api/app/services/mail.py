"""Invite email. Sent after the invite's transaction commits.

TODO (PX-10-T01 worker): contract 1.8 says the outbox worker sends it. Until the worker
exists the API sends it directly; a failed send leaves the invite for "Resend".
"""

import smtplib
from email.message import EmailMessage

import anyio
import structlog

from app.core.config import Settings

_log = structlog.get_logger("pixorex.mail")
_ROLE_TEXT = {"bu_admin": "a BU Admin", "field_technician": "a field technician"}


def invite_link(settings: Settings, token: str) -> str:
    # The token sits in the fragment, so it never reaches a server log (contract 1.6, D-11).
    return f"{str(settings.invite_base_url).rstrip('/')}/activate#token={token}"


async def send_invite(settings: Settings, *, to: str, token: str, role: str) -> bool:
    """True when sent. Failures are logged without the address or the link."""
    message = EmailMessage()
    message["Subject"] = "You're invited to Pixorex"
    message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from}>"
    message["To"] = to
    message.set_content(
        f"You've been invited to Pixorex as {_ROLE_TEXT.get(role, role)}.\n\n"
        f"Open this link to activate your account:\n{invite_link(settings, token)}\n\n"
        "The link works for 24 hours.\n"
    )
    try:
        await anyio.to_thread.run_sync(_send, settings, message)
    except (OSError, smtplib.SMTPException) as exc:
        _log.warning("invite_email_failed", error=type(exc).__name__)
        return False
    return True


def _send(settings: Settings, message: EmailMessage) -> None:
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
        if settings.smtp_starttls:
            smtp.starttls()
        if settings.smtp_user and settings.smtp_password:
            smtp.login(settings.smtp_user, settings.smtp_password.get_secret_value())
        smtp.send_message(message)
