"""Sign in with ChatGPT for the open-source Orbit edition."""

import base64
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
from pathlib import Path
from urllib.parse import urlencode
from uuid import uuid4

import httpx
import jwt
import keyring

from .auth import token_path


ISSUER = "https://auth.openai.com"
AUTHORIZE_URL = f"{ISSUER}/api/accounts/authorize"
TOKEN_URL = f"{ISSUER}/api/accounts/oauth/token"
JWKS_URL = f"{ISSUER}/.well-known/jwks.json"
RESOURCE = "https://api.openai.com/v1"
REDIRECT_URI = "http://127.0.0.1:8766/auth/callback"
SCOPES = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
KEYCHAIN_SERVICE = "com.orbit.open.chatgpt-oauth"
KEYCHAIN_ACCOUNT = "selected-account"
_pending: dict[str, dict] = {}
_lock = threading.Lock()
_refresh_lock = threading.Lock()


class OAuthError(Exception):
    pass


def _host_id_path() -> Path:
    return token_path().parent / "chatgpt-host-id"


def host_id() -> str:
    path = _host_id_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists():
        if path.stat().st_mode & 0o077:
            raise OAuthError("Permessi non sicuri per l'identificatore del Mac")
        value = path.read_text().strip()
        if not value.startswith("urn:uuid:"):
            raise OAuthError("Identificatore del Mac non valido")
        return value
    value = f"urn:uuid:{uuid4()}"
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return host_id()
    with os.fdopen(fd, "w") as handle:
        handle.write(value)
    return value


def saved_account() -> dict | None:
    raw = keyring.get_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
    if not raw:
        return None
    try:
        value = json.loads(raw)
        if value.get("issuer") != ISSUER or not value.get("client_id") or not value.get("subject"):
            raise ValueError("Invalid credential record")
        return value
    except (ValueError, TypeError) as exc:
        raise OAuthError("Account ChatGPT salvato non valido") from exc


def account_status() -> dict:
    account = saved_account()
    if not account or not account.get("refresh_token"):
        return {"connected": False, "email": None, "plan_enabled": False}
    return {
        "connected": True,
        "email": account.get("email"),
        "plan_enabled": "chatgpt.tokens.use.direct" in account.get("scopes", []),
    }


def start_sign_in() -> str:
    previous = saved_account()
    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(32)
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    issued_id = previous["client_id"] if previous else None
    parameters = {
        "client_id": issued_id or "dynamic_agent_client",
        "ext_agent_host_id": host_id(),
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPES,
        "resource": RESOURCE,
        "state": state,
        "nonce": nonce,
        "code_challenge_method": "S256",
        "code_challenge": challenge,
    }
    if previous:
        if previous.get("id_token"):
            parameters["id_token_hint"] = previous["id_token"]
        if previous.get("email"):
            parameters["login_hint"] = previous["email"]
    else:
        parameters["agent_name_hint"] = "Orbit Open"
    with _lock:
        _pending.clear()
        _pending[state] = {
            "nonce": nonce, "verifier": verifier, "client_id": issued_id,
            "previous_subject": previous["subject"] if previous else None,
            "created": time.monotonic(),
        }
    return AUTHORIZE_URL + "?" + urlencode(parameters)


def _consume_state(state: str) -> dict:
    with _lock:
        matching = next((key for key in _pending if hmac.compare_digest(key, state)), None)
        attempt = _pending.pop(matching, None) if matching else None
    if not attempt or time.monotonic() - attempt["created"] > 600:
        raise OAuthError("Accesso scaduto o non richiesto")
    return attempt


def finish_sign_in(*, state: str, code: str | None, client_id: str | None,
                   error: str | None = None) -> dict:
    attempt = _consume_state(state)
    if error:
        raise OAuthError("Accesso non autorizzato")
    if not code:
        raise OAuthError("Codice di accesso mancante")
    previous_id = attempt["client_id"]
    if previous_id:
        if client_id and not hmac.compare_digest(client_id, previous_id):
            raise OAuthError("Identità del client non corrispondente")
        issued_id = previous_id
    else:
        if not client_id or client_id == "dynamic_agent_client":
            raise OAuthError("Registrazione del client incompleta")
        issued_id = client_id
    try:
        response = httpx.post(TOKEN_URL, data={
            "grant_type": "authorization_code",
            "client_id": issued_id,
            "code": code,
            "code_verifier": attempt["verifier"],
            "redirect_uri": REDIRECT_URI,
            "resource": RESOURCE,
        }, timeout=20)
        response.raise_for_status()
        tokens = response.json()
        id_token = tokens["id_token"]
        signing_key = jwt.PyJWKClient(JWKS_URL).get_signing_key_from_jwt(id_token)
        claims = jwt.decode(id_token, signing_key.key, algorithms=["RS256"],
                            audience=issued_id, issuer=ISSUER, options={"require": ["exp", "sub", "nonce"]})
    except (httpx.HTTPError, ValueError, KeyError, jwt.PyJWTError) as exc:
        raise OAuthError("Verifica dell'accesso ChatGPT non riuscita") from exc
    if not hmac.compare_digest(str(claims["nonce"]), attempt["nonce"]):
        raise OAuthError("Verifica dell'accesso ChatGPT non riuscita")
    subject = claims["sub"]
    if attempt["previous_subject"] and not hmac.compare_digest(subject, attempt["previous_subject"]):
        raise OAuthError("Account ChatGPT diverso da quello selezionato")
    if tokens.get("token_type", "").lower() != "bearer":
        raise OAuthError("Tipo di token non supportato")
    if not tokens.get("access_token") or not tokens.get("refresh_token"):
        raise OAuthError("Credenziali ChatGPT incomplete")
    granted = tokens.get("scope", "").split()
    account = {
        "issuer": ISSUER, "subject": subject, "email": claims.get("email"),
        "client_id": issued_id, "ext_agent_host_id": host_id(),
        "id_token": id_token, "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"], "scopes": granted,
        "expires_at": time.time() + int(tokens.get("expires_in", 0)),
    }
    keyring.set_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, json.dumps(account))
    return account_status()


def disconnect() -> bool:
    account = saved_account()
    if not account:
        return True
    remote_revoked = False
    if account.get("refresh_token"):
        try:
            response = httpx.post(f"{ISSUER}/api/accounts/oauth/revoke", data={
                "token": account["refresh_token"], "token_type_hint": "refresh_token",
                "client_id": account["client_id"],
            }, timeout=15)
            remote_revoked = response.status_code == 200
        except httpx.HTTPError:
            pass
    _retain_registration(account)
    return remote_revoked


def _retain_registration(account: dict) -> None:
    retained = {key: account[key] for key in ("issuer", "subject", "email", "client_id", "ext_agent_host_id")
                if key in account}
    keyring.set_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, json.dumps(retained))


def access_token() -> str:
    with _refresh_lock:
        account = saved_account()
        if not account or not account.get("refresh_token"):
            raise OAuthError("Collega prima l'account ChatGPT")
        if "chatgpt.tokens.use.direct" not in account.get("scopes", []):
            raise OAuthError("L'uso del piano ChatGPT non è autorizzato")
        if account.get("expires_at", 0) > time.time() + 60:
            return account["access_token"]
        try:
            response = httpx.post(TOKEN_URL, data={
                "grant_type": "refresh_token", "client_id": account["client_id"],
                "refresh_token": account["refresh_token"], "resource": RESOURCE,
            }, timeout=20)
            response.raise_for_status()
            tokens = response.json()
        except httpx.HTTPStatusError as exc:
            try:
                error_body = exc.response.json()
                error_code = error_body.get("error", "")
                if isinstance(error_code, dict):
                    error_code = error_code.get("code", "")
            except ValueError:
                error_code = ""
            if error_code in {"invalid_grant", "invalid_refresh_token", "token_expired",
                              "refresh_token_expired", "refresh_token_invalidated",
                              "refresh_token_reused"}:
                _retain_registration(account)
                raise OAuthError("Sessione ChatGPT scaduta. Accedi di nuovo.") from exc
            raise OAuthError("Impossibile rinnovare l'accesso ChatGPT") from exc
        except (httpx.HTTPError, ValueError) as exc:
            raise OAuthError("Impossibile rinnovare l'accesso ChatGPT") from exc
        if not tokens.get("access_token") or not tokens.get("refresh_token"):
            raise OAuthError("Rinnovo ChatGPT incompleto")
        if tokens.get("token_type", "").lower() != "bearer":
            raise OAuthError("Tipo di token non supportato")
        scopes = tokens.get("scope", "").split()
        updated = {**account, "access_token": tokens["access_token"],
                   "refresh_token": tokens["refresh_token"], "scopes": scopes,
                   "expires_at": time.time() + int(tokens.get("expires_in", 0))}
        keyring.set_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, json.dumps(updated))
        if "chatgpt.tokens.use.direct" not in scopes:
            raise OAuthError("L'uso del piano ChatGPT non è più autorizzato")
        return updated["access_token"]


def available_models() -> list[dict[str, str]]:
    try:
        response = httpx.get(f"{RESOURCE}/models", headers={
            "Authorization": f"Bearer {access_token()}"
        }, timeout=20)
        response.raise_for_status()
        data = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise OAuthError("Catalogo modelli ChatGPT non disponibile") from exc
    return [{"slug": item["slug"], "display_name": item["display_name"]}
            for item in data.get("models", [])
            if item.get("visibility") == "list" and item.get("slug") and item.get("display_name")]
