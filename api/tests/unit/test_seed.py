"""The database seed and Keycloak's test users must describe the same people."""

import json
from pathlib import Path

from scripts import seed_synthetic

KEYCLOAK_SEED = Path(__file__).resolve().parents[3] / "keycloak" / "scripts" / "seed-users.json"


def test_seed_matches_the_keycloak_test_users() -> None:
    keycloak = json.loads(KEYCLOAK_SEED.read_text(encoding="utf-8"))
    assert str(seed_synthetic.TENANT_A) == keycloak["tenantId"]
    ours = {str(u["id"]): u["email"] for u in seed_synthetic.USERS}
    for user in keycloak["users"]:
        assert ours.get(user["username"]) == user["email"], user["key"]
