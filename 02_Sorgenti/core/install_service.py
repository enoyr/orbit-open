"""Install the per-user Orbit Core LaunchAgent on this Mac."""

import os
import plistlib
import subprocess
from pathlib import Path


LABEL = "com.orbit.open.core"
CORE_DIR = Path(__file__).resolve().parent
AGENT = Path.home() / "Library" / "LaunchAgents" / f"{LABEL}.plist"
LOG_DIR = Path.home() / "Library" / "Logs" / "Orbit Open"


def main() -> None:
    uvicorn = CORE_DIR / ".venv" / "bin" / "uvicorn"
    if not uvicorn.is_file():
        raise SystemExit("Installa prima le dipendenze in core/.venv")
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    environment = {"ORBIT_DATABASE_URL": "postgresql:///orbit_open"}
    config = {
        "Label": LABEL,
        "ProgramArguments": [
            str(uvicorn), "orbit_core.main:app", "--host", "127.0.0.1", "--port", "8766",
        ],
        "WorkingDirectory": str(CORE_DIR),
        "EnvironmentVariables": environment,
        "RunAtLoad": True,
        "KeepAlive": True,
        "StandardOutPath": str(LOG_DIR / "core.out.log"),
        "StandardErrorPath": str(LOG_DIR / "core.err.log"),
    }
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", domain, str(AGENT)], capture_output=True)
    AGENT.write_bytes(plistlib.dumps(config))
    subprocess.run(["launchctl", "bootstrap", domain, str(AGENT)], check=True)
    print(f"Servizio Orbit installato: {AGENT}")


if __name__ == "__main__":
    main()
