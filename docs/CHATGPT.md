# Accesso con ChatGPT in Orbit Open

Stato: flusso open source implementato. Il consenso, il catalogo modelli e una risposta reale del modello sono stati verificati su un'installazione locale. 21 test Core superati e build Swift release riuscita.

## Connessioni distinte

1. **OpenAI API:** chiave API personale nel Portachiavi. Resta indipendente dall'accesso ChatGPT.
2. **ChatGPT con account:** login OAuth, consenso per usare il piano idoneo, token nel Portachiavi. Modelli letti dal catalogo dell'account e aggiunti alle chat su scelta dell'utente.

La schermata Impostazioni mostra due voci separate. Se l'utente non concede l'uso del piano, Orbit Open mostra l'account collegato ma non aggiunge modelli ChatGPT. Non passa automaticamente a OpenAI API in caso di limite o errore.

## Come funziona

- Al primo accesso il client usa `dynamic_agent_client`, un ID stabile del Mac, callback `127.0.0.1:8766/auth/callback`, `state`, `nonce` e PKCE. Il browser di sistema mostra il consenso OpenAI.
- Il Core controlla `state`, client ID, firma dell'ID token, issuer, audience, scadenza e nonce prima di salvare l'account. Il client ID emesso viene riutilizzato per accessi successivi allo stesso account.
- Access token, refresh token e ID token validato sono salvati nel Portachiavi. Il rinnovo sostituisce insieme access token e refresh token. La disconnessione tenta la revoca remota e rimuove i token locali, conservando l'associazione account/client per un nuovo login.
- I modelli vengono letti da `/v1/models` usando il token OAuth. Le risposte ChatGPT usano la Responses API pubblica con `store=false` e `stream=true`; sono considerate complete solo dopo `response.completed`.
- Il servizio locale disattiva il registro degli URL delle richieste per non scrivere nei log il codice temporaneo ricevuto dal browser nel callback.

## Limiti attuali

- È gestito un account ChatGPT alla volta. La scelta fra più account registrati va ancora sviluppata.
- Ogni nuova installazione richiede il consenso dell'utente nel browser e l'idoneità del suo piano.
- Il browser può rimanere sulla schermata di accesso mentre il Core viene aggiornato: evitare di riavviare il servizio durante un tentativo in corso, perché lo stato di quel tentativo è in memoria.

Fonti: [registrazione e login open source](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), [account e sessioni](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions), [modelli e inferenza](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).
