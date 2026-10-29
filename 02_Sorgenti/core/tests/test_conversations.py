import os
from uuid import uuid4

import psycopg
from fastapi.testclient import TestClient

from orbit_core.main import app
from orbit_core.auth import load_or_create_token


def authenticated_client():
    return TestClient(app, headers={"X-Orbit-Token": load_or_create_token()})


def test_requires_local_token():
    assert TestClient(app).get("/v1/health").status_code == 401


def test_create_and_list_conversation():
    client = authenticated_client()
    title = f"Test Orbit {uuid4()}"
    created_id = None
    try:
        assert client.get("/v1/health").json() == {"status": "ok"}
        created = client.post("/v1/conversations", json={"title": title})
        assert created.status_code == 201
        body = created.json()
        created_id = body["id"]
        assert body["title"] == title
        listed = client.get("/v1/conversations")
        assert listed.status_code == 200
        assert any(item["id"] == created_id for item in listed.json())
    finally:
        if created_id:
            with psycopg.connect(os.environ["ORBIT_DATABASE_URL"]) as conn:
                conn.execute("DELETE FROM conversations WHERE id = %s", (created_id,))


def test_delete_conversation_removes_messages():
    client = authenticated_client()
    created = client.post("/v1/conversations", json={"title": "Da eliminare"})
    assert created.status_code == 201
    conversation_id = created.json()["id"]
    try:
        sent = client.post(
            f"/v1/conversations/{conversation_id}/messages/stream",
            json={"content": "Messaggio da eliminare"},
        )
        assert sent.status_code == 200
        assert client.delete(f"/v1/conversations/{conversation_id}").status_code == 204
        assert client.delete(f"/v1/conversations/{conversation_id}").status_code == 404
        assert client.get(f"/v1/conversations/{conversation_id}/messages").status_code == 404
        with psycopg.connect(os.environ["ORBIT_DATABASE_URL"]) as conn:
            count = conn.execute(
                "SELECT count(*) FROM messages WHERE conversation_id = %s", (conversation_id,)
            ).fetchone()[0]
            assert count == 0
    finally:
        with psycopg.connect(os.environ["ORBIT_DATABASE_URL"]) as conn:
            conn.execute("DELETE FROM conversations WHERE id = %s", (conversation_id,))


def test_demo_stream_saves_both_messages(monkeypatch):
    monkeypatch.setenv("ORBIT_PROVIDER", "demo")
    client = authenticated_client()
    conversation_id = None
    try:
        conversation = client.post("/v1/conversations", json={"title": "Prova messaggi"})
        assert conversation.status_code == 201
        conversation_id = conversation.json()["id"]
        response = client.post(
            f"/v1/conversations/{conversation_id}/messages/stream",
            json={"content": "Ciao Orbit"},
        )
        assert response.status_code == 200
        assert "event: text.delta" in response.text
        assert "event: response.completed" in response.text
        messages = client.get(f"/v1/conversations/{conversation_id}/messages").json()
        assert [item["role"] for item in messages] == ["user", "assistant"]
        assert messages[0]["content"] == "Ciao Orbit"
        assert "Modalità demo locale" in messages[1]["content"]
    finally:
        if conversation_id:
            with psycopg.connect(os.environ["ORBIT_DATABASE_URL"]) as conn:
                conn.execute("DELETE FROM conversations WHERE id = %s", (conversation_id,))


def test_endpoint_is_selected_per_conversation():
    client = authenticated_client()
    chat_id = None
    endpoint_id = None
    try:
        endpoint = client.post("/v1/endpoints", json={
            "label": "Ollama di prova", "provider": "ollama",
            "model_name": "test-model", "base_url": "http://127.0.0.1:11434",
        })
        assert endpoint.status_code == 201
        endpoint_id = endpoint.json()["id"]
        chat = client.post("/v1/conversations", json={"title": "Selezione modello"})
        assert chat.status_code == 201
        chat_id = chat.json()["id"]
        assert chat.json()["endpoint_id"] != endpoint_id
        updated = client.patch(f"/v1/conversations/{chat_id}/endpoint", json={"endpoint_id": endpoint_id})
        assert updated.status_code == 200
        assert updated.json()["endpoint_id"] == endpoint_id
        listed = client.get("/v1/conversations").json()
        assert next(item for item in listed if item["id"] == chat_id)["endpoint_id"] == endpoint_id
    finally:
        with psycopg.connect(os.environ["ORBIT_DATABASE_URL"]) as conn:
            if chat_id:
                conn.execute("DELETE FROM conversations WHERE id = %s", (chat_id,))
            if endpoint_id:
                conn.execute("DELETE FROM model_endpoints WHERE id = %s", (endpoint_id,))


def test_agent_settings_are_snapshotted_for_new_chat(monkeypatch):
    client = authenticated_client()
    original = client.get("/v1/agent").json()
    chat_id = None
    endpoint_id = None
    captured = {}

    def fake_stream(history, endpoint):
        captured["history"] = history
        captured["endpoint"] = endpoint
        yield "Risposta di prova"

    monkeypatch.setattr("orbit_core.main.stream_reply", fake_stream)
    try:
        endpoint = client.post("/v1/endpoints", json={
            "label": "Modello agente di prova", "provider": "ollama",
            "model_name": "test-model", "base_url": "http://127.0.0.1:11434",
        })
        assert endpoint.status_code == 201
        endpoint_id = endpoint.json()["id"]
        updated = client.put("/v1/agent", json={
            "name": "Orbit test", "instructions": "Rispondi in italiano.",
            "default_endpoint_id": endpoint_id,
        })
        assert updated.status_code == 200
        chat = client.post("/v1/conversations", json={"title": "Test agente"})
        assert chat.status_code == 201
        chat_id = chat.json()["id"]
        assert chat.json()["agent_name"] == "Orbit test"
        assert chat.json()["endpoint_id"] == endpoint_id

        changed = client.put("/v1/agent", json={
            "name": "Nuovo nome", "instructions": "Nuove istruzioni",
            "default_endpoint_id": original["default_endpoint_id"],
        })
        assert changed.status_code == 200
        response = client.post(
            f"/v1/conversations/{chat_id}/messages/stream", json={"content": "Ciao"}
        )
        assert response.status_code == 200
        assert captured["history"][0] == {"role": "system", "content": "Rispondi in italiano."}
        assert str(captured["endpoint"]["id"]) == endpoint_id
        listed = client.get("/v1/conversations").json()
        assert next(item for item in listed if item["id"] == chat_id)["agent_name"] == "Orbit test"
    finally:
        client.put("/v1/agent", json=original)
        with psycopg.connect(os.environ["ORBIT_DATABASE_URL"]) as conn:
            if chat_id:
                conn.execute("DELETE FROM conversations WHERE id = %s", (chat_id,))
            if endpoint_id:
                conn.execute("DELETE FROM model_endpoints WHERE id = %s", (endpoint_id,))
