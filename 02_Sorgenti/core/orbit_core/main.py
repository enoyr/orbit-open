import json
import re
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4

import psycopg
import keyring
from keyring.errors import KeyringError, PasswordDeleteError
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import HTMLResponse, Response, StreamingResponse
from pydantic import BaseModel, Field, SecretStr

from .db import connection
from .auth import load_or_create_token, require_token
from . import chatgpt_oauth
from .providers import (
    ProviderConfigurationError,
    stream_reply,
    validate_endpoint,
    validate_ollama_url,
    validate_custom_url,
)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    load_or_create_token()
    yield


app = FastAPI(
    title="Orbit Core", version="0.2.0", dependencies=[Depends(require_token)], lifespan=lifespan
)

callback_app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.mount("/auth", callback_app)


@callback_app.get("/callback", response_class=HTMLResponse)
def chatgpt_callback(request: Request) -> HTMLResponse:
    if request.url.hostname != "127.0.0.1" or not request.client or request.client.host != "127.0.0.1":
        return HTMLResponse("Callback locale non valido", status_code=403)
    params = request.query_params
    if any(len(params.getlist(name)) != 1 for name in ("state",)) or any(
        len(params.getlist(name)) > 1 for name in ("code", "client_id", "error")
    ):
        return HTMLResponse("Risposta di accesso non valida", status_code=400)
    try:
        chatgpt_oauth.finish_sign_in(
            state=params["state"], code=params.get("code"),
            client_id=params.get("client_id"), error=params.get("error"),
        )
    except (chatgpt_oauth.OAuthError, keyring.errors.KeyringError, KeyError):
        return HTMLResponse(
            "<html><body><h1>Accesso non completato</h1>"
            "<p>Torna in Orbit Open e riprova.</p></body></html>", status_code=400,
        )
    return HTMLResponse(
        "<html><body><h1>ChatGPT collegato a Orbit Open</h1>"
        "<p>Puoi chiudere questa scheda e tornare all'app.</p></body></html>"
    )


@app.get("/v1/chatgpt/status")
def chatgpt_status() -> dict:
    try:
        return chatgpt_oauth.account_status()
    except (chatgpt_oauth.OAuthError, keyring.errors.KeyringError):
        raise HTTPException(status_code=503, detail="Account ChatGPT non disponibile")


@app.post("/v1/chatgpt/start")
def chatgpt_start() -> dict[str, str]:
    try:
        return {"authorization_url": chatgpt_oauth.start_sign_in()}
    except (chatgpt_oauth.OAuthError, keyring.errors.KeyringError):
        raise HTTPException(status_code=503, detail="Impossibile avviare l'accesso ChatGPT")


@app.delete("/v1/chatgpt/account")
def chatgpt_disconnect() -> dict[str, bool]:
    try:
        remote_revoked = chatgpt_oauth.disconnect()
    except keyring.errors.KeyringError:
        raise HTTPException(status_code=503, detail="Impossibile scollegare ChatGPT")
    return {"remote_revoked": remote_revoked}


@app.get("/v1/chatgpt/models")
def chatgpt_models() -> list[dict[str, str]]:
    try:
        return chatgpt_oauth.available_models()
    except (chatgpt_oauth.OAuthError, keyring.errors.KeyringError):
        raise HTTPException(status_code=503, detail="Modelli ChatGPT non disponibili")


class ConversationCreate(BaseModel):
    title: str = Field(default="Nuova chat", min_length=1, max_length=200)


class ConversationRename(BaseModel):
    title: str = Field(min_length=1, max_length=200)


class Conversation(BaseModel):
    id: UUID
    title: str
    endpoint_id: UUID
    agent_name: str
    access_mode: Literal["approval_required", "full_access"]
    created_at: datetime
    updated_at: datetime


class AgentSettings(BaseModel):
    name: str
    instructions: str
    default_endpoint_id: UUID


class AgentSettingsUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    instructions: str = Field(max_length=20_000)
    default_endpoint_id: UUID


class EndpointCreate(BaseModel):
    label: str = Field(min_length=1, max_length=100)
    provider: Literal["openai", "anthropic", "ollama", "openai_compatible", "chatgpt_plan"]
    model_name: str = Field(min_length=1, max_length=200)
    base_url: str | None = None
    api_key: SecretStr | None = None


class Endpoint(BaseModel):
    id: UUID
    label: str
    provider: str
    model_name: str
    base_url: str | None
    is_local: bool
    enabled: bool


class ConversationEndpointUpdate(BaseModel):
    endpoint_id: UUID


class ConversationAccessModeUpdate(BaseModel):
    access_mode: Literal["approval_required", "full_access"]


class OpenAIKeyUpdate(BaseModel):
    key: SecretStr


@app.get("/v1/secrets/anthropic")
def anthropic_key_status() -> dict[str, bool]:
    try:
        return {"configured": bool(keyring.get_password("com.orbit.open.anthropic-api-key", "orbit"))}
    except KeyringError:
        raise HTTPException(status_code=503, detail="Portachiavi non disponibile")


@app.put("/v1/secrets/anthropic")
def save_anthropic_key(payload: OpenAIKeyUpdate) -> dict[str, bool]:
    key = payload.key.get_secret_value().strip()
    if not key or any(character.isspace() for character in key):
        raise HTTPException(status_code=422, detail="Chiave API Claude non valida")
    try:
        keyring.set_password("com.orbit.open.anthropic-api-key", "orbit", key)
    except KeyringError:
        raise HTTPException(status_code=503, detail="Impossibile salvare nel Portachiavi")
    return {"configured": True}


@app.delete("/v1/secrets/anthropic")
def delete_anthropic_key() -> dict[str, bool]:
    try:
        keyring.delete_password("com.orbit.open.anthropic-api-key", "orbit")
    except PasswordDeleteError:
        pass
    except KeyringError:
        raise HTTPException(status_code=503, detail="Portachiavi non disponibile")
    return {"configured": False}


@app.get("/v1/secrets/openai")
def openai_key_status() -> dict[str, bool]:
    try:
        return {"configured": bool(keyring.get_password("com.orbit.open.openai-api-key", "orbit"))}
    except KeyringError:
        raise HTTPException(status_code=503, detail="Portachiavi non disponibile")


@app.put("/v1/secrets/openai")
def save_openai_key(payload: OpenAIKeyUpdate) -> dict[str, bool]:
    key = payload.key.get_secret_value().strip()
    if not key.startswith("sk-") or any(character.isspace() for character in key):
        raise HTTPException(status_code=422, detail="Formato chiave API OpenAI non valido")
    try:
        keyring.set_password("com.orbit.open.openai-api-key", "orbit", key)
    except KeyringError:
        raise HTTPException(status_code=503, detail="Impossibile salvare nel Portachiavi")
    return {"configured": True}


@app.delete("/v1/secrets/openai")
def delete_openai_key() -> dict[str, bool]:
    try:
        keyring.delete_password("com.orbit.open.openai-api-key", "orbit")
    except PasswordDeleteError:
        pass
    except KeyringError:
        raise HTTPException(status_code=503, detail="Portachiavi non disponibile")
    return {"configured": False}


class MessageCreate(BaseModel):
    content: str = Field(min_length=1, max_length=100_000)


class Message(BaseModel):
    id: UUID
    conversation_id: UUID
    role: str
    content: str
    status: str
    created_at: datetime


@app.get("/v1/capabilities")
def capabilities() -> dict[str, str]:
    return {"provider": "per-conversation", "model": "Selezionabile nella chat"}


@app.get("/v1/endpoints", response_model=list[Endpoint])
def list_endpoints() -> list[dict]:
    with connection() as conn:
        return conn.execute(
            "SELECT id, label, provider, model_name, base_url, is_local, enabled "
            "FROM model_endpoints WHERE enabled ORDER BY is_local DESC, label"
        ).fetchall()


@app.get("/v1/agent", response_model=AgentSettings)
def get_agent_settings() -> dict:
    with connection() as conn:
        return conn.execute(
            "SELECT name, instructions, default_endpoint_id FROM agent_settings WHERE id = true"
        ).fetchone()


@app.put("/v1/agent", response_model=AgentSettings)
def update_agent_settings(payload: AgentSettingsUpdate) -> dict:
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Il nome dell'agente è obbligatorio")
    with connection() as conn:
        if not conn.execute(
            "SELECT 1 FROM model_endpoints WHERE id = %s AND enabled", (payload.default_endpoint_id,)
        ).fetchone():
            raise HTTPException(status_code=404, detail="Modello predefinito non trovato")
        return conn.execute(
            "UPDATE agent_settings SET name = %s, instructions = %s, "
            "default_endpoint_id = %s, updated_at = now() WHERE id = true "
            "RETURNING name, instructions, default_endpoint_id",
            (name, payload.instructions, payload.default_endpoint_id),
        ).fetchone()


@app.post("/v1/endpoints", response_model=Endpoint, status_code=status.HTTP_201_CREATED)
def create_endpoint(payload: EndpointCreate) -> dict:
    label = payload.label.strip()
    model = payload.model_name.strip()
    if not label or not model:
        raise HTTPException(status_code=422, detail="Nome e modello obbligatori")
    if payload.provider == "openai" and payload.base_url:
        raise HTTPException(status_code=422, detail="L'indirizzo OpenAI non è modificabile")
    if payload.provider == "anthropic" and payload.base_url:
        raise HTTPException(status_code=422, detail="L'indirizzo Claude non è modificabile")
    if payload.provider == "chatgpt_plan" and payload.base_url:
        raise HTTPException(status_code=422, detail="L'indirizzo ChatGPT non è modificabile")
    if payload.provider == "chatgpt_plan":
        try:
            if model not in {item["slug"] for item in chatgpt_oauth.available_models()}:
                raise HTTPException(status_code=422, detail="Modello ChatGPT non disponibile per l'account")
        except (chatgpt_oauth.OAuthError, keyring.errors.KeyringError):
            raise HTTPException(status_code=503, detail="Catalogo modelli ChatGPT non disponibile")
    try:
        if payload.provider == "ollama":
            base_url = validate_ollama_url(payload.base_url)
        elif payload.provider == "openai_compatible":
            base_url = validate_custom_url(payload.base_url)
        else:
            base_url = None
    except ProviderConfigurationError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    if payload.api_key and payload.provider != "openai_compatible":
        raise HTTPException(status_code=422, detail="La chiave qui è prevista solo per endpoint personalizzati")
    endpoint_id = uuid4()
    custom_key = payload.api_key.get_secret_value().strip() if payload.api_key else ""
    if custom_key and any(character.isspace() for character in custom_key):
        raise HTTPException(status_code=422, detail="Chiave endpoint non valida")
    if custom_key:
        try:
            keyring.set_password("com.orbit.open.endpoint-api-key", str(endpoint_id), custom_key)
        except KeyringError:
            raise HTTPException(status_code=503, detail="Impossibile salvare nel Portachiavi")
    with connection() as conn:
        return conn.execute(
            "INSERT INTO model_endpoints (id, label, provider, model_name, base_url, is_local) "
            "VALUES (%s, %s, %s, %s, %s, %s) "
            "RETURNING id, label, provider, model_name, base_url, is_local, enabled",
            (endpoint_id, label, payload.provider, model, base_url,
             payload.provider == "ollama" or (payload.provider == "openai_compatible" and base_url.startswith("http://"))),
        ).fetchone()


@app.get("/v1/health")
def health() -> dict[str, str]:
    try:
        with connection() as conn:
            conn.execute("SELECT 1")
    except (psycopg.Error, RuntimeError):
        raise HTTPException(status_code=503, detail="Database non disponibile")
    return {"status": "ok"}


@app.get("/v1/conversations", response_model=list[Conversation])
def list_conversations() -> list[dict]:
    try:
        with connection() as conn:
            return conn.execute(
                "SELECT id, title, endpoint_id, agent_name, access_mode, created_at, updated_at FROM conversations "
                "ORDER BY updated_at DESC, id DESC"
            ).fetchall()
    except psycopg.Error:
        raise HTTPException(status_code=503, detail="Database non disponibile")


@app.post("/v1/conversations", response_model=Conversation, status_code=status.HTTP_201_CREATED)
def create_conversation(payload: ConversationCreate) -> dict:
    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=422, detail="Il titolo non può essere vuoto")
    try:
        with connection() as conn:
            return conn.execute(
                "INSERT INTO conversations (id, title, endpoint_id, agent_name, agent_instructions) "
                "SELECT %s, %s, default_endpoint_id, name, instructions "
                "FROM agent_settings WHERE id = true "
                "RETURNING id, title, endpoint_id, agent_name, access_mode, created_at, updated_at",
                (uuid4(), title),
            ).fetchone()
    except psycopg.Error:
        raise HTTPException(status_code=503, detail="Database non disponibile")


@app.patch("/v1/conversations/{conversation_id}", response_model=Conversation)
def rename_conversation(conversation_id: UUID, payload: ConversationRename) -> dict:
    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=422, detail="Il titolo non può essere vuoto")
    with connection() as conn:
        updated = conn.execute(
            "UPDATE conversations SET title = %s, updated_at = now() WHERE id = %s "
            "RETURNING id, title, endpoint_id, agent_name, access_mode, created_at, updated_at",
            (title, conversation_id),
        ).fetchone()
        if not updated:
            raise HTTPException(status_code=404, detail="Chat non trovata")
        return updated


@app.delete("/v1/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_conversation(conversation_id: UUID) -> Response:
    try:
        with connection() as conn:
            deleted = conn.execute(
                "DELETE FROM conversations WHERE id = %s RETURNING id", (conversation_id,)
            ).fetchone()
            if not deleted:
                raise HTTPException(status_code=404, detail="Chat non trovata")
    except psycopg.Error:
        raise HTTPException(status_code=503, detail="Database non disponibile")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.patch("/v1/conversations/{conversation_id}/endpoint", response_model=Conversation)
def set_conversation_endpoint(conversation_id: UUID, payload: ConversationEndpointUpdate) -> dict:
    with connection() as conn:
        endpoint = conn.execute(
            "SELECT 1 FROM model_endpoints WHERE id = %s AND enabled", (payload.endpoint_id,)
        ).fetchone()
        if not endpoint:
            raise HTTPException(status_code=404, detail="Endpoint non trovato")
        updated = conn.execute(
            "UPDATE conversations SET endpoint_id = %s, updated_at = now() WHERE id = %s "
            "RETURNING id, title, endpoint_id, agent_name, access_mode, created_at, updated_at",
            (payload.endpoint_id, conversation_id),
        ).fetchone()
        if not updated:
            raise HTTPException(status_code=404, detail="Chat non trovata")
        return updated


@app.patch("/v1/conversations/{conversation_id}/access-mode", response_model=Conversation)
def set_conversation_access_mode(conversation_id: UUID, payload: ConversationAccessModeUpdate) -> dict:
    with connection() as conn:
        updated = conn.execute(
            "UPDATE conversations SET access_mode = %s, updated_at = now() WHERE id = %s "
            "RETURNING id, title, endpoint_id, agent_name, access_mode, created_at, updated_at",
            (payload.access_mode, conversation_id),
        ).fetchone()
        if not updated:
            raise HTTPException(status_code=404, detail="Chat non trovata")
        return updated


@app.get("/v1/conversations/{conversation_id}/messages", response_model=list[Message])
def list_messages(conversation_id: UUID) -> list[dict]:
    try:
        with connection() as conn:
            if not conn.execute("SELECT 1 FROM conversations WHERE id = %s", (conversation_id,)).fetchone():
                raise HTTPException(status_code=404, detail="Chat non trovata")
            return conn.execute(
                "SELECT id, conversation_id, role, content, status, created_at FROM messages "
                "WHERE conversation_id = %s ORDER BY created_at, id",
                (conversation_id,),
            ).fetchall()
    except psycopg.Error:
        raise HTTPException(status_code=503, detail="Database non disponibile")


def _event(name: str, payload: dict) -> str:
    return f"event: {name}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"


def title_from_first_phrase(content: str) -> str:
    line = next((part.strip() for part in content.splitlines() if part.strip()), "")
    line = re.sub(r"^(?:[#>*-]\s*)+", "", line)
    line = re.sub(r"\s+", " ", line).strip()
    if not line:
        return "Nuova chat"
    boundary = re.search(r"[.!?](?=\s|$)", line)
    phrase = line[:boundary.end()] if boundary else line
    if len(phrase) <= 72:
        return phrase
    shorter = phrase[:69].rsplit(" ", 1)[0].rstrip(" ,;:-")
    return (shorter or phrase[:69]).rstrip() + "…"


@app.post("/v1/conversations/{conversation_id}/messages/stream")
def send_message(conversation_id: UUID, payload: MessageCreate) -> StreamingResponse:
    content = payload.content.strip()
    if not content:
        raise HTTPException(status_code=422, detail="Il messaggio non può essere vuoto")
    try:
        with connection() as conn:
            endpoint = conn.execute(
                "SELECT e.id, e.provider, e.model_name, e.base_url, c.agent_instructions, c.title "
                "FROM conversations c "
                "JOIN model_endpoints e ON e.id = c.endpoint_id "
                "WHERE c.id = %s AND e.enabled FOR UPDATE OF c", (conversation_id,),
            ).fetchone()
            if not endpoint:
                raise HTTPException(status_code=404, detail="Chat non trovata")
            validate_endpoint(endpoint)
            first_message = not conn.execute(
                "SELECT 1 FROM messages WHERE conversation_id = %s AND role = 'user' LIMIT 1",
                (conversation_id,),
            ).fetchone()
            auto_title = title_from_first_phrase(content) if first_message and endpoint["title"] == "Nuova chat" else None
            user_id = uuid4()
            conn.execute(
                "INSERT INTO messages (id, conversation_id, role, content) VALUES (%s, %s, 'user', %s)",
                (user_id, conversation_id, content),
            )
            if auto_title:
                conn.execute("UPDATE conversations SET title = %s, updated_at = now() WHERE id = %s",
                             (auto_title, conversation_id))
            else:
                conn.execute("UPDATE conversations SET updated_at = now() WHERE id = %s", (conversation_id,))
            history = conn.execute(
                "SELECT role, content FROM messages WHERE conversation_id = %s "
                "AND status = 'complete' ORDER BY created_at, id",
                (conversation_id,),
            ).fetchall()
            if endpoint["agent_instructions"]:
                history.insert(0, {"role": "system", "content": endpoint["agent_instructions"]})
            history.insert(1 if endpoint["agent_instructions"] else 0, {
                "role": "system",
                "content": "Orbit mostra Markdown, tabelle e blocchi di codice. "
                           "Solo quando l'utente chiede un grafico a barre, puoi usare un blocco "
                           "```chart con JSON: {\"title\":\"Titolo\",\"data\":[{\"label\":\"A\",\"value\":12}]}. "
                           "Usa numeri reali e non inventare dati.",
            })
    except ProviderConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except psycopg.Error:
        raise HTTPException(status_code=503, detail="Database non disponibile")

    def generate():
        chunks: list[str] = []
        yield _event("user.saved", {"id": str(user_id), "title": auto_title})
        try:
            for delta in stream_reply(history, endpoint):
                chunks.append(delta)
                yield _event("text.delta", {"text": delta})
            answer = "".join(chunks)
            with connection() as conn:
                assistant_id = uuid4()
                conn.execute(
                    "INSERT INTO messages (id, conversation_id, role, content) "
                    "VALUES (%s, %s, 'assistant', %s)",
                    (assistant_id, conversation_id, answer),
                )
                conn.execute("UPDATE conversations SET updated_at = now() WHERE id = %s", (conversation_id,))
            yield _event("response.completed", {"id": str(assistant_id)})
        except Exception:
            # Do not expose provider errors or credentials in the event stream.
            yield _event("response.failed", {"message": "Risposta non disponibile. Riprova."})

    return StreamingResponse(generate(), media_type="text/event-stream")
