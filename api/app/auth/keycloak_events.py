"""Signature check for Keycloak's audit events (docs/keycloak.md 8.3, PX-01-T04).

A0 DRAFT, NEEDS ARCHITECT REVIEW (CONSTITUTION §5). Keycloak's listener (Iswarya's
AuditDelivery.java) signs the raw JSON body with HMAC-SHA256 and the shared secret and sends
X-Pixorex-Signature: sha256=<hex>. The endpoint must also be reachable only on the internal
network: deployed ingress has to block /internal/ (DevOps)."""

import hashlib
import hmac

from pydantic import SecretStr


def valid_signature(secret: SecretStr, body: bytes, header: str | None) -> bool:
    if not header or not header.startswith("sha256="):
        return False
    expected = hmac.new(secret.get_secret_value().encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header.removeprefix("sha256=").lower())
