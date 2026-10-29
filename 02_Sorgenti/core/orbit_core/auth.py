"""Local, per-user authentication for the Orbit development service."""

import hmac
import os
import secrets
from pathlib import Path

from fastapi import Header, HTTPException


def token_path() -> Path:
    override = os.environ.get("ORBIT_TOKEN_FILE")
    if override:
        return Path(override).expanduser()
    return Path.home() / "Library" / "Application Support" / "Orbit Open" / "core-token"


def load_or_create_token() -> str:
    path = token_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.exists():
        if path.stat().st_mode & 0o077:
            raise RuntimeError("Permessi non sicuri per il token Orbit")
        return path.read_text().strip()
    token = secrets.token_urlsafe(48)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return load_or_create_token()
    with os.fdopen(fd, "w") as handle:
        handle.write(token)
    return token


def require_token(x_orbit_token: str | None = Header(default=None)) -> None:
    expected = load_or_create_token()
    if not x_orbit_token or not hmac.compare_digest(x_orbit_token, expected):
        raise HTTPException(status_code=401, detail="Accesso locale non autorizzato")
