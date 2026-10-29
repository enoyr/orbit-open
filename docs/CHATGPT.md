# Accesso con ChatGPT in Orbit Open

Stato: **da implementare**. Il percorso open source usa la registrazione dinamica descritta da OpenAI; la pubblicazione del codice da sola non realizza il login né garantisce l'idoneità di ogni account.

## Connessioni distinte

1. **OpenAI API**: chiave API personale nel Portachiavi. È già disponibile e rimane indipendente.
2. **ChatGPT con account**: login OAuth e consenso dell'utente per richieste idonee tramite il suo piano ChatGPT. Da sviluppare.

Per il primo accesso OpenAI documenta `client_id=dynamic_agent_client`, un ID stabile dell'host, callback locale su `127.0.0.1`, `state`, `nonce`, PKCE e verifica dell'ID token. Il client ID restituito va conservato per l'account e riutilizzato negli accessi successivi. I token vanno nel Portachiavi. Le autorizzazioni per usare il piano sono distinte dal login; un token d'identità non dà accesso alle risposte dei modelli.

La versione commerciale di Orbit segue il [percorso di richiesta per partner commerciali](https://developers.openai.com/siwc/request-client-id) e non deve riutilizzare la registrazione di Orbit Open.

Fonti: [registrazione open source](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [quickstart](https://developers.openai.com/siwc/quickstart).
