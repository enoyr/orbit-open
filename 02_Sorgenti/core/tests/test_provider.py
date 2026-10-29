import json
from types import SimpleNamespace
import pytest
import httpx

import openai

from orbit_core.providers import ProviderConfigurationError, stream_reply, validate_ollama_url, validate_custom_url


def test_openai_adapter_streams_text_without_remote_storage(monkeypatch):
    captured = {}

    class FakeStream:
        def __iter__(self):
            yield SimpleNamespace(type="response.output_text.delta", delta="Ciao")
            yield SimpleNamespace(type="response.output_text.delta", delta="!")

        def close(self):
            captured["closed"] = True

    class FakeClient:
        def __init__(self, api_key):
            captured["api_key_configured"] = bool(api_key)
            self.responses = self

        def create(self, **kwargs):
            captured.update(kwargs)
            return FakeStream()

    monkeypatch.setenv("ORBIT_PROVIDER", "openai")
    monkeypatch.setenv("ORBIT_OPENAI_MODEL", "test-model")
    monkeypatch.setenv("ORBIT_OPEN_OPENAI_API_KEY", "test-only")
    monkeypatch.setattr(openai, "OpenAI", FakeClient)

    endpoint = {"provider": "openai", "model_name": "test-model", "base_url": None}
    assert "".join(stream_reply([{"role": "user", "content": "Ciao"}], endpoint)) == "Ciao!"
    assert captured["model"] == "test-model"
    assert captured["store"] is False
    assert captured["stream"] is True
    assert captured["closed"] is True


def test_ollama_adapter_streams_local_chat(monkeypatch):
    real_client = httpx.Client

    def respond(request):
        assert request.url.path == "/api/chat"
        return httpx.Response(200, text=(
            '{"message":{"content":"Ciao"},"done":false}\n'
            '{"message":{"content":"!"},"done":false}\n'
            '{"done":true}\n'
        ))

    monkeypatch.setattr(httpx, "Client", lambda **kwargs: real_client(
        transport=httpx.MockTransport(respond), **kwargs
    ))
    endpoint = {
        "provider": "ollama", "model_name": "test-model",
        "base_url": "http://127.0.0.1:11434",
    }
    assert "".join(stream_reply([{"role": "user", "content": "Ciao"}], endpoint)) == "Ciao!"


def test_ollama_rejects_remote_url():
    with pytest.raises(ProviderConfigurationError):
        validate_ollama_url("https://example.com")


def test_claude_adapter_streams_text(monkeypatch):
    real_client = httpx.Client
    monkeypatch.setenv("ORBIT_OPEN_ANTHROPIC_API_KEY", "test-only")

    def respond(request):
        assert request.url.path == "/v1/messages"
        assert request.headers["x-api-key"] == "test-only"
        assert json.loads(request.content)["system"] == "Sei Orbit"
        return httpx.Response(200, text=(
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Ciao"}}\n\n'
            'event: message_stop\n'
            'data: {"type":"message_stop"}\n\n'
        ))

    monkeypatch.setattr(httpx, "Client", lambda **kwargs: real_client(
        transport=httpx.MockTransport(respond), **kwargs
    ))
    endpoint = {"provider": "anthropic", "model_name": "test-model", "base_url": None}
    assert "".join(stream_reply([
        {"role": "system", "content": "Sei Orbit"},
        {"role": "user", "content": "Ciao"},
    ], endpoint)) == "Ciao"


def test_custom_endpoint_url_requires_https_outside_local_network():
    assert validate_custom_url("http://127.0.0.1:1234/v1") == "http://127.0.0.1:1234/v1"
    assert validate_custom_url("https://models.example/v1") == "https://models.example/v1"
    with pytest.raises(ProviderConfigurationError):
        validate_custom_url("http://models.example/v1")


def test_openai_compatible_adapter_uses_custom_url_and_key(monkeypatch):
    captured = {}

    class FakeStream:
        def __iter__(self):
            yield SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content="Ciao"))])
            yield SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content="!"))])

        def close(self):
            captured["closed"] = True

    class FakeClient:
        def __init__(self, api_key, base_url):
            captured.update(api_key=api_key, base_url=base_url)
            self.chat = SimpleNamespace(completions=self)

        def create(self, **kwargs):
            captured.update(kwargs)
            return FakeStream()

    monkeypatch.setattr(openai, "OpenAI", FakeClient)
    monkeypatch.setattr("orbit_core.providers.keyring.get_password", lambda service, account: (
        "secret-test" if service == "com.orbit.open.endpoint-api-key" and account == "endpoint-1" else None
    ))
    endpoint = {
        "id": "endpoint-1", "provider": "openai_compatible",
        "model_name": "local-model", "base_url": "http://127.0.0.1:1234/v1",
    }
    assert "".join(stream_reply([{"role": "user", "content": "Ciao"}], endpoint)) == "Ciao!"
    assert captured["api_key"] == "secret-test"
    assert captured["base_url"] == "http://127.0.0.1:1234/v1"
    assert captured["stream"] is True
    assert captured["closed"] is True
