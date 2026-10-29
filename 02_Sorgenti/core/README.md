# Orbit Open Core API — primo incremento

Richiede Python 3.12+ e PostgreSQL nativo. Usa un database locale dedicato `orbit_open`. La connessione via socket può usare l'identità macOS. La password non va salvata nel progetto.

```sh
python3 -m venv .venv
.venv/bin/pip install -e .
ORBIT_DATABASE_URL='postgresql:///orbit_open' .venv/bin/python -m orbit_core.init_db
ORBIT_DATABASE_URL='postgresql:///orbit_open' .venv/bin/uvicorn orbit_core.main:app --host 127.0.0.1 --port 8766
```

API attuale: stato, capacità del provider, conversazioni, messaggi con risposta SSE e stato/salvataggio/rimozione della chiave OpenAI nel Portachiavi. Il valore della chiave non viene mai restituito dall'API. Il servizio richiede `X-Orbit-Token`, generato con permessi privati in `~/Library/Application Support/Orbit Open/core-token`; l'app legge lo stesso token. Le migrazioni SQL numerate si applicano con `python -m orbit_core.init_db`.

Per installare il servizio che parte al login: `.venv/bin/python install_service.py`. Ogni nuova chat usa inizialmente `demo`: salva messaggi e mostra una risposta di prova, senza chiamare alcun modello. Gli endpoint OpenAI e Ollama si aggiungono dalle impostazioni nell'app e si selezionano per chat. Per OpenAI occorre una chiave API separata, letta dal Portachiavi con servizio `com.orbit.open.openai-api-key`; la schermata per inserirla è presente nelle Impostazioni. Ollama deve essere installato a parte e il modello deve già essere presente.

Per verificare: `ORBIT_DATABASE_URL='postgresql:///orbit_open' .venv/bin/pytest -q`.
