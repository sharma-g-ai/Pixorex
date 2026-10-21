"""Synthetic *.local addresses stay on Mailpit when SendGrid is configured."""

from email.message import EmailMessage
from types import SimpleNamespace

import pytest
from pydantic import AnyHttpUrl, SecretStr

from app.services import mail


@pytest.mark.parametrize(
    "address, synthetic",
    [
        ("ea@demo.local", True),
        ("EA@Demo.Local", True),
        ("sms+1@pixorex.local", True),
        ("iswarya.kolimalla@amzur.com", False),
        ("a@example.com", False),
        ("", False),
    ],
)
def test_synthetic_address_detection(address: str, synthetic: bool) -> None:
    assert mail.is_synthetic_address(address) is synthetic


def test_synthetic_mail_uses_local_smtp(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, object] = {}

    class FakeSmtp:
        def __init__(self, host: str, port: int, timeout: int = 20) -> None:
            seen["host"] = host
            seen["port"] = port

        def __enter__(self) -> "FakeSmtp":
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def starttls(self) -> None:
            seen["starttls"] = True

        def login(self, user: str, password: str) -> None:
            seen["login"] = (user, password)

        def send_message(self, message: EmailMessage) -> None:
            seen["from"] = message["From"]

    monkeypatch.setattr(mail.smtplib, "SMTP", FakeSmtp)
    settings = SimpleNamespace(
        invite_base_url=AnyHttpUrl("http://localhost:5173"),
        smtp_host="smtp.sendgrid.net",
        smtp_port=587,
        smtp_user="apikey",
        smtp_password=SecretStr("secret"),
        smtp_starttls=True,
        smtp_from="real@example.com",
        smtp_from_name="Pixorex",
        local_smtp_host="mailpit",
        local_smtp_port=1025,
    )
    message = EmailMessage()
    message["From"] = "Pixorex <no-reply@pixorex.local>"
    message["To"] = "ea@demo.local"
    message["Subject"] = "code"
    message.set_content("123456")
    mail._send(settings, message)
    assert seen == {"host": "mailpit", "port": 1025, "from": "Pixorex <no-reply@pixorex.local>"}


def test_real_mail_uses_configured_smtp(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, object] = {}

    class FakeSmtp:
        def __init__(self, host: str, port: int, timeout: int = 20) -> None:
            seen["host"] = host
            seen["port"] = port

        def __enter__(self) -> "FakeSmtp":
            return self

        def __exit__(self, *args: object) -> None:
            return None

        def starttls(self) -> None:
            seen["starttls"] = True

        def login(self, user: str, password: str) -> None:
            seen["login"] = (user, password)

        def send_message(self, message: object) -> None:
            pass

    monkeypatch.setattr(mail.smtplib, "SMTP", FakeSmtp)
    settings = SimpleNamespace(
        invite_base_url=AnyHttpUrl("http://localhost:5173"),
        smtp_host="smtp.sendgrid.net",
        smtp_port=587,
        smtp_user="apikey",
        smtp_password=SecretStr("secret"),
        smtp_starttls=True,
        smtp_from="real@example.com",
        smtp_from_name="Pixorex",
        local_smtp_host="mailpit",
        local_smtp_port=1025,
    )
    message = EmailMessage()
    message["From"] = "Pixorex <real@example.com>"
    message["To"] = "person@example.com"
    message["Subject"] = "code"
    message.set_content("hi")
    mail._send(settings, message)
    assert seen == {
        "host": "smtp.sendgrid.net",
        "port": 587,
        "starttls": True,
        "login": ("apikey", "secret"),
    }
