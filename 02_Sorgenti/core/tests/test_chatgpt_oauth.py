import json
import time
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import jwt
import httpx
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from orbit_core import chatgpt_oauth as oauth
from orbit_core.main import app


@pytest.fixture
def oauth_state(monkeypatch, tmp_path):
    values = {}
    oauth._pending.clear()
    monkeypatch.setattr(oauth, "_host_id_path", lambda: tmp_path / "host-id")
    monkeypatch.setattr(oauth.keyring, "get_password", lambda service, account: values.get((service, account)))
    monkeypatch.setattr(oauth.keyring, "set_password", lambda service, account, value: values.__setitem__((service, account), value))
    return values


def _authorize_params():
    return {key: value[0] for key, value in parse_qs(urlparse(oauth.start_sign_in()).query).items()}


def test_first_sign_in_uses_dynamic_registration_and_stable_host(oauth_state):
    first = _authorize_params()
    second = _authorize_params()
    assert first["client_id"] == "dynamic_agent_client"
    assert first["agent_name_hint"] == "Orbit Open"
    assert first["ext_agent_host_id"] == second["ext_agent_host_id"]
    assert first["ext_agent_host_id"].startswith("urn:uuid:")
    assert first["state"] != second["state"]
    assert first["nonce"] != second["nonce"]
    assert first["code_challenge"] != second["code_challenge"]
    assert first["redirect_uri"] == oauth.REDIRECT_URI
    assert oauth._host_id_path().stat().st_mode & 0o077 == 0


def test_callback_checks_state_signature_nonce_and_stores_granted_scopes(oauth_state, monkeypatch):
    params = _authorize_params()
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    issued_id = "oaiapp_test"
    id_token = jwt.encode({
        "iss": oauth.ISSUER, "aud": issued_id, "sub": "person-1",
        "email": "person@example.com", "nonce": params["nonce"],
        "exp": int(time.time()) + 3600,
    }, private_key, algorithm="RS256", headers={"kid": "test"})
    token_response = {
        "id_token": id_token, "access_token": "access-test", "refresh_token": "refresh-test",
        "token_type": "Bearer", "expires_in": 3600,
        "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
    }
    monkeypatch.setattr(oauth.httpx, "post", lambda *args, **kwargs: SimpleNamespace(
        raise_for_status=lambda: None, json=lambda: token_response,
    ))
    monkeypatch.setattr(oauth.jwt, "PyJWKClient", lambda url: SimpleNamespace(
        get_signing_key_from_jwt=lambda token: SimpleNamespace(key=private_key.public_key()),
    ))
    with pytest.raises(oauth.OAuthError):
        oauth.finish_sign_in(state="wrong", code="code", client_id=issued_id)
    status = oauth.finish_sign_in(state=params["state"], code="code", client_id=issued_id)
    assert status == {"connected": True, "email": "person@example.com", "plan_enabled": True}
    stored = json.loads(oauth_state[(oauth.KEYCHAIN_SERVICE, oauth.KEYCHAIN_ACCOUNT)])
    assert stored["client_id"] == issued_id
    assert stored["subject"] == "person-1"
    with pytest.raises(oauth.OAuthError):
        oauth.finish_sign_in(state=params["state"], code="code", client_id=issued_id)
    returning = _authorize_params()
    assert returning["client_id"] == issued_id
    assert "agent_name_hint" not in returning
    assert returning["id_token_hint"] == id_token


def test_refuses_changed_account_and_rotates_refresh_token(oauth_state, monkeypatch):
    account = {"issuer": oauth.ISSUER, "client_id": "oaiapp_test", "subject": "person-1",
               "email": "person@example.com", "access_token": "old-access",
               "refresh_token": "old-refresh", "scopes": ["chatgpt.tokens.use.direct"],
               "expires_at": 0}
    oauth_state[(oauth.KEYCHAIN_SERVICE, oauth.KEYCHAIN_ACCOUNT)] = json.dumps(account)
    params = _authorize_params()
    with pytest.raises(oauth.OAuthError, match="client"):
        oauth.finish_sign_in(state=params["state"], code="code", client_id="oaiapp_other")
    def refresh(url, data, timeout):
        assert data["client_id"] == "oaiapp_test"
        assert data["refresh_token"] == "old-refresh"
        assert data["resource"] == oauth.RESOURCE
        return SimpleNamespace(raise_for_status=lambda: None, json=lambda: {
            "access_token": "new-access", "refresh_token": "new-refresh",
            "scope": "chatgpt.tokens.use.direct", "expires_in": 3600,
            "token_type": "Bearer",
        })
    monkeypatch.setattr(oauth.httpx, "post", refresh)
    assert oauth.access_token() == "new-access"
    stored = json.loads(oauth_state[(oauth.KEYCHAIN_SERVICE, oauth.KEYCHAIN_ACCOUNT)])
    assert stored["refresh_token"] == "new-refresh"
    assert oauth.access_token() == "new-access"


def test_browser_callback_is_local_only_and_does_not_need_core_token(oauth_state):
    remote = TestClient(app, base_url="http://127.0.0.1:8766", client=("192.0.2.2", 3456))
    assert remote.get("/auth/callback?state=unknown&error=access_denied").status_code == 403
    local = TestClient(app, base_url="http://127.0.0.1:8766", client=("127.0.0.1", 3456))
    assert local.get("/auth/callback?state=unknown&error=access_denied").status_code == 400
    assert local.get("/auth/callback?state=a&state=b").status_code == 400


def test_expired_refresh_retains_client_registration_without_tokens(oauth_state, monkeypatch):
    account = {"issuer": oauth.ISSUER, "client_id": "oaiapp_test", "subject": "person-1",
               "email": "person@example.com", "access_token": "old-access",
               "refresh_token": "old-refresh", "scopes": ["chatgpt.tokens.use.direct"],
               "expires_at": 0}
    oauth_state[(oauth.KEYCHAIN_SERVICE, oauth.KEYCHAIN_ACCOUNT)] = json.dumps(account)
    response = httpx.Response(400, json={"error": "invalid_grant"},
                              request=httpx.Request("POST", oauth.TOKEN_URL))
    monkeypatch.setattr(oauth.httpx, "post", lambda *args, **kwargs: response)
    with pytest.raises(oauth.OAuthError, match="Accedi di nuovo"):
        oauth.access_token()
    saved = oauth.saved_account()
    assert saved["client_id"] == "oaiapp_test"
    assert "refresh_token" not in saved
    assert oauth.account_status()["connected"] is False
