import os
from contextlib import contextmanager
from importlib import resources

import psycopg
from psycopg.rows import dict_row


def database_url() -> str:
    value = os.environ.get("ORBIT_DATABASE_URL")
    if not value:
        raise RuntimeError("Imposta ORBIT_DATABASE_URL prima di avviare Orbit Core")
    return value


@contextmanager
def connection():
    with psycopg.connect(database_url(), row_factory=dict_row) as conn:
        yield conn


def initialize_schema() -> None:
    migrations = resources.files("orbit_core").joinpath("migrations")
    with connection() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            "version TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
        )
        conn.execute("SELECT pg_advisory_xact_lock(664238841)")
        applied = {
            row["version"]
            for row in conn.execute("SELECT version FROM schema_migrations").fetchall()
        }
        for migration in sorted(migrations.iterdir(), key=lambda item: item.name):
            if migration.name.endswith(".sql") and migration.name not in applied:
                conn.execute(migration.read_text())
                conn.execute(
                    "INSERT INTO schema_migrations (version) VALUES (%s)",
                    (migration.name,),
                )
