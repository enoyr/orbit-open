# Roadmap di Orbit Open

Questa pagina raccoglie le funzioni concordate per l'edizione Open. Le nuove funzioni condivise si sviluppano qui; l'edizione commerciale potrà poi derivarle mantenendo credenziali e integrazioni separate.

La chat mostra già quando Orbit prepara una risposta e quando la sta scrivendo progressivamente. Questi stati non espongono il ragionamento interno del modello. Un primo percorso permette già di scegliere un file testuale o PDF, mostrarlo nel pannello affiancato e inviarne il contenuto al modello con approvazione. Restano da costruire la ricerca autonoma, gli altri strumenti e i loro stati specifici.

## Prossimi passi

1. **File e azioni sul computer.** Dopo la lettura dei file scelti dall'utente, aggiungere ricerca autonoma, creazione, modifica e organizzazione dei file; poi browser e altre app. Applicare le modalità “Richiedi approvazione” e “Accesso completo” anche alle azioni future, mostrando le operazioni nella pagina Attività. Partire da macOS e mantenere l'interfaccia degli strumenti riutilizzabile per un futuro client Windows. [Disegno della funzione](AGENTE_E_SPAZIO.md).
2. **Spazio affiancato alla chat.** Il primo pannello ridimensionabile mostra già il file scelto. Estenderlo a browser, altri documenti, anteprime e risultati del lavoro. [Disegno dell'interfaccia](AGENTE_E_SPAZIO.md).
3. **Allegati e contenuti locali.** Aggiungere documenti e immagini alla chat, conservarli sul Mac e renderli disponibili ai modelli compatibili. Costruire la base della Libreria per ritrovarli.
4. **Azioni sui messaggi.** Quando il puntatore passa su un messaggio, mostrare una barra discreta con Copia e Ascolta. Aggiungere data e ora del messaggio in forma compatta, con il dettaglio completo al passaggio del puntatore. Valutare la lettura automatica delle risposte come preferenza disattivabile. Rendere i controlli accessibili anche da tastiera e VoiceOver.
5. **Voce.** Prima lettura ad alta voce delle risposte e dettatura dei messaggi; poi una modalità di conversazione vocale continua, con interruzione, ripresa e indicazione chiara di quando il microfono è attivo. Prevedere un percorso locale per il futuro uso senza Internet.
6. **Distribuzione.** Installer, aggiornamenti e gestione semplice del servizio locale; in seguito, più account ChatGPT sulla stessa installazione.
7. **Immagini, fase finale.** Generare e modificare immagini dalla chat, mostrarle nella conversazione e salvarle in Libreria. Usare un generatore dedicato scelto nelle impostazioni, indipendente dal modello testuale. La connessione OpenAI API può usare l'API immagini; la connessione al piano ChatGPT tramite Sign in with ChatGPT non supporta attualmente la generazione di immagini.
8. **Video, dopo le immagini.** Usare lo stesso schema di contenuti e provider per avviare generazioni video, mostrarne avanzamento ed errori, conservare e riprodurre i file finali. Trattare la generazione come lavoro asincrono, senza bloccare la chat. Valutare provider API e locali in base alle capacità disponibili.

Le funzioni qui elencate sono pianificate, non già disponibili nell'app. Per le capacità e i limiti delle connessioni OpenAI fare riferimento alla documentazione ufficiale: [immagini](https://developers.openai.com/api/docs/guides/image-generation), [video](https://developers.openai.com/api/docs/guides/video-generation), [limiti di Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
