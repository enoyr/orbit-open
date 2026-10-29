"""Model adapters. Orbit's database format does not depend on a provider."""

import json
import os
from collections.abc import Iterator
from urllib.parse import urlparse
from ipaddress import ip_address

import httpx
import keyring

from . import chatgpt_oauth


class ProviderConfigurationError(Exception):
    pass


def validate_ollama_url(base_url: str | None) -> str:
    value = base_url or "http://127.0.0.1:11434"
    parsed = urlparse(value)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise ProviderConfigurationError("Ollama deve usare un indirizzo locale HTTP")
    if parsed.username or parsed.password or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise ProviderConfigurationError("Indirizzo Ollama non valido")
    return value.rstrip("/")


def _openai_api_key() -> str:
    key = os.environ.get("ORBIT_OPEN_OPENAI_API_KEY")
    if key:
        return key
    key = keyring.get_password("com.orbit.open.openai-api-key", "orbit")
    if not key:
        raise ProviderConfigurationError("Chiave API OpenAI assente dal Portachiavi")
    return key


def _anthropic_api_key() -> str:
    key = os.environ.get("ORBIT_OPEN_ANTHROPIC_API_KEY") or keyring.get_password(
        "com.orbit.open.anthropic-api-key", "orbit"
    )
    if not key:
        raise ProviderConfigurationError("Chiave API Claude assente dal Portachiavi")
    return key


def validate_custom_url(base_url: str | None) -> str:
    if not base_url:
        raise ProviderConfigurationError("Inserisci l'indirizzo dell'endpoint")
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ProviderConfigurationError("Indirizzo endpoint non valido")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ProviderConfigurationError("Non inserire credenziali nell'indirizzo")
    if parsed.scheme == "http":
        try:
            local = ip_address(parsed.hostname).is_private or ip_address(parsed.hostname).is_loopback
        except ValueError:
            local = parsed.hostname == "localhost"
        if not local:
            raise ProviderConfigurationError("Usa HTTPS per endpoint fuori dalla rete locale")
    return base_url.rstrip("/")


def validate_endpoint(endpoint: dict) -> None:
    provider = endpoint["provider"]
    if provider == "openai":
        _openai_api_key()
    elif provider == "chatgpt_plan":
        try:
            chatgpt_oauth.access_token()
        except chatgpt_oauth.OAuthError as exc:
            raise ProviderConfigurationError(str(exc)) from exc
    elif provider == "anthropic":
        _anthropic_api_key()
    elif provider == "ollama":
        validate_ollama_url(endpoint.get("base_url"))
    elif provider == "openai_compatible":
        validate_custom_url(endpoint.get("base_url"))
    elif provider != "demo":
        raise ProviderConfigurationError(f"Provider non supportato: {provider}")


def stream_reply(history: list[dict[str, str]], endpoint: dict) -> Iterator[str]:
    provider = endpoint["provider"]
    if provider == "demo":
        yield "Modalità demo locale: i messaggi sono salvati, ma non è ancora configurato un modello."
        return
    if provider == "openai":
        from openai import OpenAI

        client = OpenAI(api_key=_openai_api_key())
        stream = client.responses.create(
            model=endpoint["model_name"],
            input=[{"role": item["role"], "content": item["content"]} for item in history],
            stream=True,
            store=False,
        )
        try:
            for event in stream:
                if event.type == "response.output_text.delta":
                    yield event.delta
                elif event.type in {"response.failed", "error"}:
                    raise RuntimeError("Il provider ha interrotto la risposta")
        finally:
            stream.close()
        return
    if provider == "chatgpt_plan":
        from openai import OpenAI

        client = OpenAI(api_key=chatgpt_oauth.access_token(), base_url=chatgpt_oauth.RESOURCE,
                        max_retries=0)
        stream = client.responses.create(
            model=endpoint["model_name"],
            input=[{"role": item["role"], "content": item["content"]} for item in history],
            stream=True, store=False,
        )
        completed = False
        try:
            for event in stream:
                if event.type == "response.output_text.delta":
                    yield event.delta
                elif event.type == "response.completed":
                    completed = True
                elif event.type in {"response.failed", "response.incomplete", "error"}:
                    raise RuntimeError("ChatGPT ha interrotto la risposta")
            if not completed:
                raise RuntimeError("Risposta ChatGPT incompleta")
        finally:
            stream.close()
        return
    if provider == "ollama":
        base_url = validate_ollama_url(endpoint.get("base_url"))
        with httpx.Client(timeout=None) as client:
            with client.stream(
                "POST", f"{base_url}/api/chat",
                json={"model": endpoint["model_name"], "messages": history, "stream": True},
            ) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if line:
                        event = json.loads(line)
                        if event.get("error"):
                            raise RuntimeError("Il modello locale ha interrotto la risposta")
                        delta = event.get("message", {}).get("content", "")
                        if delta:
                            yield delta
        return
    if provider == "anthropic":
        system = "\n\n".join(item["content"] for item in history if item["role"] == "system")
        messages = [item for item in history if item["role"] != "system"]
        with httpx.Client(timeout=None) as client:
            with client.stream(
                "POST", "https://api.anthropic.com/v1/messages",
                headers={"x-api-key": _anthropic_api_key(), "anthropic-version": "2023-06-01"},
                json={"model": endpoint["model_name"], "messages": messages,
                      "system": system, "max_tokens": 4096, "stream": True},
            ) as response:
                response.raise_for_status()
                for line in response.iter_lines():
                    if line.startswith("data: "):
                        event = json.loads(line[6:])
                        if event.get("type") == "error":
                            raise RuntimeError("Claude ha interrotto la risposta")
                        delta = event.get("delta", {})
                        if event.get("type") == "content_block_delta" and delta.get("type") == "text_delta":
                            yield delta.get("text", "")
        return
    if provider == "openai_compatible":
        from openai import OpenAI

        base_url = validate_custom_url(endpoint.get("base_url"))
        key = keyring.get_password("com.orbit.open.endpoint-api-key", str(endpoint["id"])) or "not-required"
        client = OpenAI(api_key=key, base_url=base_url)
        stream = client.chat.completions.create(
            model=endpoint["model_name"], messages=history, stream=True,
        )
        try:
            for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
        finally:
            stream.close()
        return
    raise ProviderConfigurationError(f"Provider non supportato: {provider}")
