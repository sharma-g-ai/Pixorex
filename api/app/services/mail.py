"""Email over SMTP: Mailpit locally, the real provider when .env sets one.

Invite emails are sent by the API right after the invite commits. They do not go through
the outbox: its payload would keep the raw link token in the database until sent, and only
the token's hash may be stored (contract 1.6). A failed send leaves the invite for "Resend".
Notification emails go through the outbox; the worker sends them (FR-6.2, 6.3).

Synthetic addresses (*.local, e.g. demo users) always go to Mailpit, even when
SendGrid is configured for real inboxes — no .env flip required.
"""

import smtplib
from email.message import EmailMessage
from typing import Protocol

import anyio
import structlog
from pydantic import AnyHttpUrl, SecretStr

_log = structlog.get_logger("pixorex.mail")
_ROLE_TEXT = {"bu_admin": "a BU Admin", "field_technician": "a field technician"}


class MailSettings(Protocol):
    """What sending needs; the API's and the worker's settings both have it."""

    @property
    def invite_base_url(self) -> AnyHttpUrl: ...
    @property
    def smtp_host(self) -> str: ...
    @property
    def smtp_port(self) -> int: ...
    @property
    def smtp_user(self) -> str | None: ...
    @property
    def smtp_password(self) -> SecretStr | None: ...
    @property
    def smtp_starttls(self) -> bool: ...
    @property
    def smtp_from(self) -> str: ...
    @property
    def smtp_from_name(self) -> str: ...
    @property
    def local_smtp_host(self) -> str: ...
    @property
    def local_smtp_port(self) -> int: ...


def is_synthetic_address(address: str) -> bool:
    """True for demo / Mailpit-only addresses (*@*.local)."""
    text = (address or "").strip()
    at = text.rfind("@")
    if at < 0 or at == len(text) - 1:
        return False
    return text[at + 1 :].lower().endswith(".local")


def web_link(settings: MailSettings, path: str = "/") -> str:
    return f"{str(settings.invite_base_url).rstrip('/')}{path}"


def invite_link(settings: MailSettings, token: str) -> str:
    # The token sits in the fragment, so it never reaches a server log (contract 1.6, D-11).
    return web_link(settings, f"/activate#token={token}")


async def send_email(settings: MailSettings, *, to: str, subject: str, text: str) -> None:
    """Raises OSError or smtplib.SMTPException when the server refuses it."""
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = f"{settings.smtp_from_name} <{_from_address(settings, to)}>"
    message["To"] = to
    message.set_content(text)
    await anyio.to_thread.run_sync(_send, settings, message)


async def send_invite(settings: MailSettings, *, to: str, token: str, role: str) -> bool:
    """True when sent. Failures are logged without the address or the link."""
    try:
        await send_email(
            settings,
            to=to,
            subject="You're invited to Pixorex",
            text=(
                f"You've been invited to Pixorex as {_ROLE_TEXT.get(role, role)}.\n\n"
                f"Open this link to activate your account:\n{invite_link(settings, token)}\n\n"
                "The link works for 24 hours.\n"
            ),
        )
    except (OSError, smtplib.SMTPException) as exc:
        _log.warning("invite_email_failed", error=type(exc).__name__)
        return False
    return True


def _from_address(settings: MailSettings, to: str) -> str:
    if is_synthetic_address(to):
        return "no-reply@pixorex.local"
    return settings.smtp_from


def _send(settings: MailSettings, message: EmailMessage) -> None:
    to = str(message["To"] or "")
    if is_synthetic_address(to):
        host, port, starttls = settings.local_smtp_host, settings.local_smtp_port, False
        user, password = None, None
    else:
        host, port, starttls = settings.smtp_host, settings.smtp_port, settings.smtp_starttls
        user, password = settings.smtp_user, settings.smtp_password
    with smtplib.SMTP(host, port, timeout=20) as smtp:
        if starttls:
            smtp.starttls()
        if user and password:
            smtp.login(user, password.get_secret_value())
        smtp.send_message(message)
