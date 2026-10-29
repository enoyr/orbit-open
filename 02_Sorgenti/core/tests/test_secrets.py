from fastapi.testclient import TestClient

from orbit_core.auth import load_or_create_token
from orbit_core.main import app


def test_openai_key_management_uses_keychain_without_echoing_secret(monkeypatch):
    values = {}
    monkeypatch.setattr("orbit_core.main.keyring.get_password", lambda service, account: values.get((service, account)))
    monkeypatch.setattr("orbit_core.main.keyring.set_password", lambda service, account, key: values.__setitem__((service, account), key))
    monkeypatch.setattr("orbit_core.main.keyring.delete_password", lambda service, account: values.pop((service, account)))
    client = TestClient(app, headers={"X-Orbit-Token": load_or_create_token()})
    assert client.get("/v1/secrets/openai").json() == {"configured": False}
    assert client.put("/v1/secrets/openai", json={"key": "invalid"}).status_code == 422
    saved = client.put("/v1/secrets/openai", json={"key": "sk-test-only"})
    assert saved.status_code == 200
    assert saved.json() == {"configured": True}
    assert "sk-test-only" not in saved.text
    assert client.get("/v1/secrets/openai").json() == {"configured": True}
    assert client.delete("/v1/secrets/openai").json() == {"configured": False}
