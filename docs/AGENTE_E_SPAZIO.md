# Agente sul computer e spazio affiancato

## Obiettivo

Orbit deve poter lavorare con i contenuti del computer dalla conversazione: trovare e leggere file, crearli o modificarli, organizzare cartelle, consultare siti e mostrare all'utente ciò che sta facendo. Il primo client è macOS; un eventuale client Windows userà lo stesso Core e gli stessi contratti degli strumenti, con adattatori propri per il sistema operativo.

## Strumenti riutilizzabili

- Il Core espone operazioni con input e risultati definiti: ricerca, lettura, scrittura e organizzazione dei file; navigazione e interazione nel browser; successivamente integrazioni con app e documenti.
- Il modello propone un'operazione; il Core controlla permessi e modalità della chat, la esegue tramite l'adattatore del sistema e restituisce il risultato al modello. La schermata mostra stato, esito ed eventuale approvazione.
- “Richiedi approvazione” ferma le azioni esterne finché l'utente non le conferma. “Accesso completo” permette l'esecuzione senza quella pausa, nei limiti dei permessi concessi all'app e al sistema operativo. La modalità salvata oggi è solo una preferenza: va applicata dal Core prima di abilitare gli strumenti.
- Le operazioni devono poter essere annullate quando possibile; quelle distruttive o non reversibili devono essere chiaramente riconoscibili. I risultati di file e siti sono dati da analizzare, non istruzioni da eseguire.

## Spazio affiancato

- La chat rimane visibile a sinistra. Un pannello a destra si apre su richiesta dell'utente o quando un'attività richiede un'anteprima, con divisore trascinabile, pulsanti per chiudere e riaprire e larghezze minime per entrambi i lati.
- Lo stesso contenitore ospita schede di browser, documenti, file e attività. Cambia il contenuto della scheda, non la struttura della finestra. Se lo spazio è stretto, il pannello diventa una vista sovrapposta o una scheda dedicata.
- La conversazione indica quale elemento è aperto nel pannello. L'utente può scegliere un altro elemento senza perdere il punto della chat; la dimensione del pannello viene ricordata.
- La prima versione utile è l'anteprima di un file letto da Orbit. Seguono navigazione browser e modifica dei documenti tramite strumenti appropriati.

## Ordine di realizzazione

1. Contratto degli strumenti, controllo delle approvazioni e registro delle azioni.
2. Lettura e ricerca dei file locali, con anteprima nel pannello.
3. Scrittura e organizzazione dei file, con esito visibile e recupero quando possibile.
4. Browser nello stesso pannello; poi integrazioni con altre app.
