# Orbit Open

Orbit Open è un assistente personale per macOS in fase iniziale di sviluppo. Comprende un'app SwiftUI, un Core locale in Python/FastAPI e dati in PostgreSQL nativo. È prevista anche un'edizione commerciale distinta, con modalità di distribuzione da definire separatamente.

## Stato attuale

- Chat e cronologia locali, con indicatore di preparazione, risposta progressiva, stato di scrittura e selezione della connessione.
- Titolo ricavato dalla prima frase del primo messaggio, con rinomina ed eliminazione dal pulsante che compare passando sulla chat nella barra laterale. Markdown con codice e tabelle, icona per copiare sotto ogni messaggio, copia dei blocchi di codice e grafici a barre da blocchi `chart` JSON. La modalità di accesso scelta per ogni chat è conservata in PostgreSQL; gli strumenti per file e browser non sono ancora collegati.
- Connessioni tramite chiave API OpenAI, chiave API Claude, endpoint personalizzato o Ollama locale.
- Chiavi API nel Portachiavi macOS; token locale per le richieste fra app e Core.
- Dati e credenziali separati da Orbit Commercial: database `orbit_open`, porta `8766`, token in `Orbit Open` e voci dedicate nel Portachiavi.
- Pagine Libreria e Attività ancora in preparazione.
- L'accesso con account ChatGPT usa il [percorso open source documentato da OpenAI](https://developers.openai.com/siwc/token-sharing-open-source/sign-in): registrazione dinamica, consenso nel browser, token nel Portachiavi e catalogo modelli dell'account. Su un'installazione locale sono stati verificati consenso, catalogo e una risposta reale del modello. OpenAI API continua a funzionare separatamente.

## Requisiti e avvio dello sviluppo

- macOS 15 o successivo, Swift 6, Python 3.12 o successivo, PostgreSQL locale.
- Crea un database PostgreSQL `orbit_open` accessibile dal tuo account macOS.
- Nel percorso `02_Sorgenti/core`, crea un ambiente virtuale e installa il pacchetto: `python3 -m venv .venv && .venv/bin/pip install -e '.[test]'`.
- Inizializza il database: `ORBIT_DATABASE_URL='postgresql:///orbit_open' .venv/bin/python -m orbit_core.init_db`.
- Avvia il Core: `ORBIT_DATABASE_URL='postgresql:///orbit_open' .venv/bin/uvicorn orbit_core.main:app --host 127.0.0.1 --port 8766`.
- In `02_Sorgenti/macOS/OrbitApp`, esegui `python3 build_app.py`. La build resta nella cartella di progetto; per installarla in `~/Applications` aggiungi `--install`.

Il primo avvio usa la connessione demo locale, senza chiamate a modelli. Le connessioni reali vanno configurate nelle impostazioni. La chiave API non è inclusa nel repository.

## Struttura

- `02_Sorgenti/core`: Core API, migrazioni SQL e test.
- `02_Sorgenti/macOS/OrbitApp`: app SwiftUI, risorse e script di build.
- `docs`: note tecniche pubbliche.

Le funzioni concordate per i prossimi sviluppi, comprese voce, immagini e video, sono raccolte nella [roadmap](docs/ROADMAP.md).

Orbit Open è la base di sviluppo delle funzioni comuni. L'edizione commerciale sarà derivata mantenendo soltanto integrazioni e configurazioni private in un livello separato. Non deve importare o riutilizzare il client ID o i token ottenuti tramite un'installazione open source. La build di sviluppo non ha ancora installer, aggiornamenti automatici o gestione di più account ChatGPT.

## Licenza e marchi

Il codice originale di Orbit Open è distribuito sotto [Apache License 2.0](LICENSE). Copyright 2026 Massimiliano Stefanelli. Il simbolo OpenAI incluso in `Resources/OpenAI.png` appartiene a OpenAI ed è usato soltanto per identificare la connessione al suo servizio; non è concesso con la licenza Apache. L'uso del simbolo deve rispettare le [linee guida OpenAI](https://openai.com/brand/). Il nome e il marchio Orbit sono trattati separatamente dalla licenza del codice.
