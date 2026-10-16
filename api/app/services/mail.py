from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage

from app.config import Settings, get_settings

log = logging.getLogger(__name__)


def send_invite_email(*, to: str, token: str, role: str, settings: Settings | None = None) -> None:
    settings = settings or get_settings()
    link = f"{settings.invite_app_base_url.rstrip('/')}/activate#token={token}"
    msg = EmailMessage()
    msg["Subject"] = "You're invited to Pixorex"
    msg["From"] = f"{settings.smtp_from_name} <{settings.smtp_from}>"
    msg["To"] = to
    msg.set_content(
        f"You have been invited to Pixorex as {role}.\n\n"
        f"Open this link to activate your account:\n{link}\n\n"
        f"This link expires in 24 hours.\n"
    )
    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
            if settings.smtp_starttls:
                smtp.starttls()
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_password or "")
            smtp.send_message(msg)
        log.info("Invite email sent to %s via %s:%s", to, settings.smtp_host, settings.smtp_port)
    except OSError as exc:
        log.exception("Failed to send invite email to %s: %s", to, exc)
        raise
