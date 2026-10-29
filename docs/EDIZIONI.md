# Sviluppo delle edizioni

Orbit Open è la base delle funzioni condivise: interfaccia, chat, archiviazione locale, provider API e modello locale. Le nuove funzioni comuni si sviluppano e si verificano qui prima di essere portate nell'edizione commerciale.

L'edizione commerciale aggiunge soltanto le integrazioni private e il client ID partner di OpenAI. L'accesso ChatGPT open source con `dynamic_agent_client` resta esclusivo di Orbit Open. Credenziali, token, database, porta locale e Portachiavi delle due edizioni restano separati.

Quando OpenAI approverà il client commerciale, le sue modalità di autenticazione, gli scope e il callback verranno confrontati con i dati assegnati prima dell'attivazione. L'uso del piano ChatGPT richiede un'autorizzazione specifica, distinta dal semplice login. La connessione tramite chiave OpenAI API rimane disponibile in entrambe le edizioni.

Le modalità “Richiedi approvazione” e “Accesso completo” sono oggi preferenze salvate per chat. Verranno applicate dalle future azioni su file, browser e app; non concedono da sole accesso al Mac.
