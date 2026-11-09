import type { SiteCopy } from "./types";

export const copyIt: SiteCopy = {
  ui: {
    navCompare: "Confronto",
    navTechnology: "Tecnologia",
    navAlternatives: "Alternative",
    navGuides: "Guide",
    navDownload: "Scarica",
    navGitHub: "GitHub",
    download: "Scarica per Mac",
    downloadSub: "Gratis · macOS 14+ · Apple silicon e Intel · 7,5 MB",
    viewSource: "Codice sorgente su GitHub",
    readMore: "Continua a leggere",
    faqTitle: "Domande frequenti",
    updated: "Aggiornato il",
    languageName: "English",
    skipToContent: "Vai al contenuto",
    footerTagline: "Un foglio di calcolo gratuito e open source per Mac. Nativo, leggerissimo e compatibile con Excel.",
    footerLicense: "Foglio è software libero, distribuito con doppia licenza MIT e Apache-2.0.",
    footerTrademark:
      "Excel è un marchio di Microsoft Corporation. Numbers è un marchio di Apple Inc. Google Sheets (Fogli Google) è un marchio di Google LLC. LibreOffice è un marchio di The Document Foundation. Foglio è un progetto indipendente, non affiliato né approvato da nessuna di queste aziende.",
    notFoundTitle: "Questo foglio è vuoto",
    notFoundText: "La pagina che cercavi non esiste o è stata spostata. Prova dalla home page o da una delle guide.",
    backHome: "Torna alla home page",
    yes: "Sì",
    no: "No",
    partial: "In parte",
  },

  meta: {
    home: {
      title: "Foglio: foglio di calcolo gratis per Mac, compatibile Excel",
      description:
        "Foglio è un foglio di calcolo gratis per Mac, open source. Apre e salva file Excel xlsx, ~500 funzioni, nativo e leggero: 7,5 MB. Nessun account.",
      ogTitle: "Foglio — il foglio di calcolo gratuito, nativo e open source per Mac",
    },
    compare: {
      title: "Foglio vs Excel, Numbers, LibreOffice e Fogli Google",
      description:
        "Confronto onesto tra fogli di calcolo per Mac: prezzo, dimensioni, velocità, file xlsx, macro, tabelle pivot, collaborazione e privacy. Con le fonti.",
    },
    technology: {
      title: "Come è fatto Foglio: Swift, AppKit e Rust | Foglio",
      description:
        "Dentro Foglio: un'app nativa Swift/AppKit con un motore in Rust (un fork di IronCalc). Perché pesa 7,5 MB, si apre in 0,24 s e ricalcola così in fretta.",
    },
    download: {
      title: "Scarica Foglio per Mac: foglio di calcolo gratis | Foglio",
      description:
        "Scarica Foglio 1.0, foglio di calcolo gratuito per macOS 14 o successivi. App universale per Apple silicon e Intel, immagine disco da 7,5 MB.",
    },
    alternatives: {
      title: "Alternative a Excel, Numbers e Fogli Google su Mac | Foglio",
      description:
        "Cerchi un'alternativa a Excel, Numbers, LibreOffice Calc o Fogli Google sul Mac? Guide oneste su quando Foglio fa per te e quando invece no.",
    },
    guides: {
      title: "Guide ai fogli di calcolo su Mac: xlsx, xls e CSV | Foglio",
      description:
        "Guide pratiche per il Mac: aprire file Excel e CSV senza Excel, sistemare caratteri strani e colonne sbagliate, usare le formule in italiano e altro.",
    },
  },

  home: {
    eyebrow: "Gratis · Open source · Nativo per macOS",
    h1: "Il foglio di calcolo gratis per Mac che apre i tuoi file Excel",
    subtitle:
      "Foglio è un'app Mac piccola, veloce e nativa per i fogli di calcolo di tutti i giorni. Apre e salva `.xlsx`, apre `.xls`, `.ods` e `.csv`, conosce circa 500 funzioni di Excel e non costa nulla: niente abbonamento, niente account, niente pubblicità.",
    badges: [
      "Gratis per sempre, MIT / Apache-2.0",
      "7,5 MB di download, si apre in 0,24 s",
      "Nativo Swift/AppKit, niente Electron",
      "Nessun account, nessuna telemetria",
    ],
    statLabels: {
      download: "Dimensione del download",
      launch: "Dall'avvio alla prima finestra",
      memory: "Memoria con un foglio vuoto",
      open100k: "Aprire un xlsx da 100.000 righe",
      recalc: "Modifica e ricalcolo di 300.000 formule",
      price: "Prezzo, per sempre",
    },
    featuresTitle: "Tutto quello che serve per i fogli di tutti i giorni",
    featuresIntro:
      "Foglio copre il lavoro che la maggior parte delle persone fa davvero con un foglio di calcolo: elenchi, bilanci familiari, fatture, report, file Excel ricevuti da altri. Si usa come Excel e si comporta come un'app Mac.",
    features: [
      {
        icon: "file",
        title: "Apre i file Excel",
        text: "Legge e scrive `.xlsx` con formattazione, grafici, immagini, note e convalida dati. Apre anche `.xls`, `.xlsb`, `.xlsm`, `.ods`, `.csv` e `.tsv`.",
      },
      {
        icon: "function",
        title: "~500 funzioni di Excel",
        text: "SOMMA.PIÙ.SE, CERCA.X, FILTRO, LET, LAMBDA, date, testo, statistica e finanza. 191 delle 195 funzioni verificate danno gli stessi risultati di Excel.",
      },
      {
        icon: "globe",
        title: "Formule in italiano",
        text: "Su un Mac in italiano scrivi `=SOMMA(A1:A10)` o `CERCA.VERT` con il `;` e la virgola decimale, come in Excel. I file restano Excel standard.",
      },
      {
        icon: "bolt",
        title: "Veloce anche sui file grandi",
        text: "Una cartella da 100.000 righe e 300.000 formule si apre in 1,1 s e dopo una modifica si ricalcola in 16 ms, grazie al ricalcolo incrementale.",
      },
      {
        icon: "feather",
        title: "Piccolo e leggero",
        text: "7,5 MB di download, 19 MB installato, circa 58 MB di memoria con un foglio vuoto e 0 % di CPU quando è inattivo. Le ventole restano zitte.",
      },
      {
        icon: "apple",
        title: "Una vera app per Mac",
        text: "Scritto in Swift e AppKit: Apri recenti, pannelli nelle finestre, modalità scura, Stampa ed Esporta PDF, zoom con le dita, scorciatoie di Excel per Mac.",
      },
      {
        icon: "chart",
        title: "Grafici e immagini",
        text: "Grafici a colonne, barre, linee, torta, anello, area e dispersione, salvati nel file `.xlsx`. Inserisci, ritaglia e comprimi immagini; anche le vecchie clip art EMF/WMF.",
      },
      {
        icon: "filter",
        title: "Strumenti per i dati",
        text: "Ordina, Filtro automatico, Trova e sostituisci, Rimuovi duplicati, Testo in colonne, elenchi a discesa, formattazione condizionale e un pivot leggero (Riepiloga per).",
      },
      {
        icon: "lock",
        title: "Privato per natura",
        text: "Niente account, pubblicità o statistiche d'uso. Foglio non si collega a Internet di sua iniziativa: i tuoi file restano sul tuo Mac.",
      },
    ],
    speedTitle: "Così leggero che ti dimentichi di averlo",
    speedIntro:
      "Foglio non contiene un browser, una macchina virtuale Java o un framework multipiattaforma. Per questo si scarica in pochi secondi e si apre prima che tu muova il mouse.",
    speedNote:
      "Valori di Foglio misurati su un MacBook Air M4 (16 GB), macOS 27, Foglio 1.0, novembre 2026: mediana di più prove, memoria rilevata con `footprint`. Le dimensioni delle altre app sono quelle indicate dai rispettivi store e pagine di download a novembre 2026.",
    freeTitle: "Gratis, e resta gratis",
    freeText: [
      "Foglio non ha un prezzo, una prova a tempo, un abbonamento o una versione a pagamento. Non serve un Apple Account, un account Microsoft o un account Google per usarlo, e non c'è pubblicità.",
      "Il codice sorgente è su [GitHub](https://github.com/Acid236/foglio) con licenza MIT e Apache-2.0: chiunque può leggerlo, compilarlo, migliorarlo o crearne una versione propria. I tuoi fogli sono normali file `.xlsx` che si aprono in Excel, Numbers, LibreOffice e Fogli Google: nessun vincolo.",
    ],
    compareTitle: "Come si confronta",
    compareText:
      "Excel ha più funzioni, Fogli Google ha la collaborazione in tempo reale, Numbers ha modelli bellissimi. Foglio è l'opzione gratuita, leggera e nativa che apre bene i file Excel. Leggi il [confronto completo](/compare/), compresi i punti in cui vincono gli altri.",
    techTitle: "Fatto come dovrebbe essere fatta un'app per Mac",
    techText:
      "Un'interfaccia Swift/AppKit con una griglia su misura, sopra un motore di calcolo in Rust (un fork migliorato di IronCalc) collegato come semplice libreria statica. Scopri [come è fatto Foglio](/technology/) e perché questo lo rende piccolo e veloce.",
    formatsTitle: "Apre i file che ti mandano",
    formatsText:
      "`.xlsx` e `.xlsm` da Excel, i vecchi `.xls` e i binari `.xlsb`, `.ods` da LibreOffice, e `.csv` / `.tsv` con riconoscimento automatico di codifica, separatore e virgola decimale. Salva in `.xlsx`, esporta in CSV e PDF. Leggi le guide su come [aprire file xlsx su Mac senza Excel](/guides/open-xlsx-on-mac-without-excel/), [aprire i vecchi file .xls](/guides/open-xls-on-mac/) e [aprire file CSV su Mac](/guides/open-csv-on-mac/).",
    alternativesTitle: "Arrivi da un'altra app?",
    alternativesText:
      "Note oneste per chi arriva da [Excel per Mac](/alternatives/excel-for-mac/), [Numbers](/alternatives/numbers/), [LibreOffice Calc](/alternatives/libreoffice/) o [Fogli Google](/alternatives/google-sheets/), compreso quando conviene continuare a usarli. Le trovi tutte nella pagina delle [alternative](/alternatives/).",
    ctaTitle: "Provalo con i tuoi fogli di calcolo",
    ctaText:
      "Sono 7,5 MB e non costa nulla. Foglio 1.0 è una prima versione: mentre lo provi, tieni una copia di backup dei file importanti.",
    faq: [
      {
        q: "Foglio è davvero gratis?",
        a: "Sì. Nessun prezzo, nessun periodo di prova, nessun abbonamento, nessun acquisto in-app e nessuna pubblicità. Foglio è software open source con licenza MIT e Apache-2.0.",
      },
      {
        q: "Foglio apre e salva i file Excel?",
        a: "Sì. Legge e scrive `.xlsx` con formattazione, grafici, immagini, note, convalida dati e formattazione condizionale. Apre anche `.xls`, `.xlsb`, `.xlsm` e `.ods`, oltre ai file di testo CSV e TSV. Salva in `.xlsx` ed esporta in CSV e PDF.",
      },
      {
        q: "Può sostituire completamente Microsoft Excel?",
        a: "Per i fogli di tutti i giorni spesso sì. Per alcuni lavori no: Foglio non esegue macro (VBA), non ha vere tabelle pivot (offre il più semplice *Riepiloga per*), ignora forme e SmartArt e non apre file protetti da password. Il [confronto](/compare/) elenca tutte le differenze.",
      },
      {
        q: "Su quali Mac funziona?",
        a: "Su qualsiasi Mac con macOS 14 Sonoma o successivo, sia Apple silicon sia Intel. È un'unica app universale.",
      },
      {
        q: "Perché macOS dice che Foglio è di uno sviluppatore non identificato?",
        a: "Foglio 1.0 non è firmato con un Apple Developer ID a pagamento, quindi la prima volta macOS chiede conferma. Su macOS 15 o successivi vai in Impostazioni di Sistema ▸ Privacy e sicurezza e fai clic su **Apri comunque**; su macOS 14 fai clic destro sull'app e scegli **Apri**. La [pagina di download](/download/) spiega ogni passaggio.",
      },
      {
        q: "Foglio raccoglie dati o richiede un account?",
        a: "No. Nessun account, nessun accesso, nessuna statistica d'uso, nessuna telemetria. Foglio non apre connessioni di rete di sua iniziativa: apre una pagina web solo quando fai clic su un collegamento ipertestuale in una cella.",
      },
      {
        q: "Posso scrivere le formule in italiano?",
        a: "Sì. Foglio segue la lingua e la regione del Mac: su un Mac in italiano scrivi `=SOMMA(A1:A10;B2)`, `SE` o `CERCA.VERT` con il punto e virgola e la virgola decimale, esattamente come in Excel in italiano. Nei file le formule vengono salvate nella forma standard inglese, così si aprono correttamente ovunque. Funziona anche in tedesco, spagnolo e francese. Trovi i nomi tradotti nella [tabella delle funzioni in italiano e inglese](/guides/excel-functions-italian-english/).",
      },
      {
        q: "Foglio è un'app finita?",
        a: "Foglio 1.0 gestisce dall'inizio alla fine i fogli di tutti i giorni ed è coperto da 69 test automatici dell'interfaccia, ma è una prima versione. Tieni un backup dei file importanti e segnala i problemi su [GitHub](https://github.com/Acid236/foglio/issues).",
      },
    ],
  },

  compare: {
    h1: "Foglio a confronto con Excel, Numbers, LibreOffice e Fogli Google",
    intro: [
      "Non esiste il foglio di calcolo migliore in assoluto per Mac: esiste quello adatto a ciò che fai. Questa pagina mette Foglio accanto alle quattro app tra cui gli utenti Mac scelgono più spesso, ed è volutamente onesta: dove un'altra app è migliore, la tabella lo dice.",
      "In breve: **Excel** è il più completo e il più costoso; **Numbers** è gratuito ed elegante ma converte i file Excel; **LibreOffice Calc** è gratuito e potente ma pesante e non è un'app Mac nativa; **Fogli Google** è gratuito e collaborativo ma vive nel browser e richiede un account Google. **Foglio** è gratuito, open source, leggerissimo e nativo, e modifica direttamente i file `.xlsx`, con meno funzioni avanzate di Excel.",
    ],
    tableTitle: "Confronto punto per punto",
    tableNote:
      "Prezzi e funzionalità verificati sulle pagine ufficiali dei produttori a novembre 2026 (fonti in fondo); i prezzi sono quelli di listino in Italia, IVA inclusa, e possono cambiare. I valori di Foglio sono misurati su un MacBook Air M4, macOS 27, Foglio 1.0.",
    sections: [
      {
        heading: "Quale scegliere?",
        body: ["Scegli lo strumento in base al lavoro, non al marchio. Quasi tutti usano solo una piccola parte di ciò che queste app sanno fare."],
        bullets: [
          "**Scegli Foglio** se vuoi un'app gratuita, veloce e riservata che apra e salvi file Excel sul Mac senza account né abbonamenti.",
          "**Scegli Excel** se usi macro (VBA), Power Query, vere tabelle pivot, grafici avanzati, o devi riprodurre al millimetro i file della tua azienda.",
          "**Scegli Numbers** se crei documenti che devono essere belli da vedere, soprattutto per te, e vivi nell'ecosistema Apple, iPhone e iPad compresi.",
          "**Scegli LibreOffice Calc** se ti serve un'app gratuita con tabelle pivot, macro e moltissime funzioni, e non ti pesa un'app grande e non nativa.",
          "**Scegli Fogli Google** se più persone modificano lo stesso foglio contemporaneamente e lavorare nel browser con un account Google non è un problema.",
        ],
      },
      {
        heading: "Dove vince Foglio",
        body: [
          "Foglio è di gran lunga l'app più piccola del confronto: 7,5 MB di download contro centinaia di megabyte o qualche gigabyte delle alternative desktop. Mostra una finestra pronta in 0,24 s, usa circa 58 MB di memoria con un foglio vuoto e resta a 0 % di CPU quando è inattivo.",
          "È gratuito senza condizioni, open source e funziona completamente offline senza account. A differenza di Numbers modifica i file `.xlsx` senza convertirli, e su un Mac in italiano scrivi le formule con gli stessi nomi di Excel in italiano: `SOMMA`, `SE`, `CERCA.VERT`.",
        ],
      },
      {
        heading: "Dove vincono gli altri",
        body: [
          "Excel è molto più completo: macro, Power Query, vere tabelle pivot, molti più tipi di grafico, ed è il riferimento per qualsiasi file Excel. Anche LibreOffice ha tabelle pivot e macro, oltre a un livello di disegno e molti più formati di importazione ed esportazione. Fogli Google offre la migliore collaborazione in tempo reale e funziona su qualsiasi dispositivo con un browser. Numbers ed Excel hanno app per iPhone e iPad; Foglio esiste solo per Mac.",
          "Foglio 1.0 è la prima versione di un piccolo progetto open source, mentre le grandi suite hanno decenni di rifinitura alle spalle. Se un file è importante, tienine una copia.",
        ],
      },
    ],
    faq: [
      {
        q: "Qual è la migliore alternativa gratuita a Excel su Mac?",
        a: "Dipende da cosa ti serve. Foglio è l'opzione gratuita più leggera che modifica direttamente i `.xlsx`. LibreOffice Calc è l'app desktop gratuita più completa. Fogli Google è il migliore per lavorare in gruppo. Numbers è già installato e gratuito, ma converte i file Excel nel proprio formato. La nostra [rassegna dei fogli di calcolo gratis per Mac](/guides/free-spreadsheet-apps-for-mac/) presenta altre opzioni.",
      },
      {
        q: "Foglio supporta le macro o VBA?",
        a: "No. Foglio apre i file `.xlsm` ma non ne esegue le macro. Se il tuo lavoro dipende da VBA, usa Microsoft Excel; anche LibreOffice ne esegue una parte.",
      },
      {
        q: "Foglio ha le tabelle pivot?",
        a: "Non ancora vere tabelle pivot. *Riepiloga per* crea un foglio di riepilogo aggiornato automaticamente con formule SOMMA.PIÙ.SE e CONTA.PIÙ.SE, che basta per i pivot più semplici. Excel, LibreOffice, Numbers e Fogli Google hanno tutti le tabelle pivot.",
      },
      {
        q: "Più persone possono modificare un file di Foglio contemporaneamente?",
        a: "No. Foglio è un'app desktop pensata per una persona alla volta. Per lavorare insieme in tempo reale sono più adatti Fogli Google o Excel con OneDrive.",
      },
      {
        q: "I prezzi delle altre app sono aggiornati?",
        a: "Sono stati verificati sulle pagine dei produttori a novembre 2026 e sono prezzi di listino italiani. I prezzi cambiano nel tempo: controlla i link alle fonti prima di acquistare.",
      },
    ],
  },

  technology: {
    h1: "Come è fatto Foglio, e perché è così piccolo e veloce",
    intro: [
      "Molte app moderne si portano dietro una copia di un browser, una macchina virtuale Java o un grande framework multipiattaforma. Foglio non contiene nulla di tutto questo. È un'app Mac nativa in Swift e AppKit, con il motore di calcolo scritto in Rust e collegato direttamente all'app.",
      "Questa pagina spiega l'architettura due volte: prima a parole semplici, poi con abbastanza dettagli perché uno sviluppatore possa orientarsi nel [codice sorgente](https://github.com/Acid236/foglio).",
    ],
    sections: [
      {
        heading: "In parole semplici",
        body: [
          "Immagina Foglio diviso in due parti. Quella che vedi (finestre, menu, la griglia di celle) è scritta con gli strumenti di Apple, quindi ha l'aspetto e il comportamento di tutte le altre app del Mac. Quella che fa i conti (legge i file, interpreta le formule, ricalcola) è un motore separato scritto in Rust, un linguaggio che produce programmi molto veloci e compatti.",
          "Le due parti comunicano attraverso un'interfaccia piccola e semplice. In mezzo non c'è nient'altro: nessun browser nascosto, nessuna macchina virtuale, nessun runtime da scaricare. Ecco perché l'intera app pesa 7,5 MB, si apre in 0,24 s e usa circa 58 MB di memoria con un foglio vuoto.",
        ],
      },
      {
        heading: "L'app per Mac: Swift e AppKit",
        body: [
          "L'interfaccia è scritta in Swift con AppKit, il framework su cui si basano il Finder e gran parte delle app di sistema. I documenti sono veri documenti macOS: Apri recenti, Salva con nome, Ripristina, Duplica, pannelli nelle finestre, schermo intero, modalità scura, stampa ed Esporta PDF funzionano come ti aspetti.",
          "Il foglio è una griglia `NSView` disegnata su misura, non un controllo tabella standard. Chiede al motore solo le celle visibili, in blocchi pronti da disegnare: così lo scorrimento resta fluido anche su fogli con centinaia di migliaia di righe. Anche grafici, immagini e barra della formula sono disegnati dall'app.",
          "Foglio contiene inoltre un proprio lettore di metafile EMF e WMF, il formato di immagini vettoriali dei vecchi documenti Office (clip art, equazioni MathType, diagrammi Visio incollati). Immagini che altre app Mac mostrano come riquadri vuoti vengono disegnate correttamente e salvate senza modifiche.",
        ],
      },
      {
        heading: "Il motore: Rust e un IronCalc migliorato",
        body: [
          "Le formule vengono interpretate e calcolate da [IronCalc](https://github.com/ironcalc/IronCalc), un motore per fogli di calcolo open source in Rust. Foglio usa un fork migliorato di IronCalc 0.9.1, con ogni modifica segnalata e documentata nel repository.",
          "Il fork aggiunge il **ricalcolo incrementale**: quando modifichi una cella vengono ricalcolate solo le formule che dipendono da essa, non l'intera cartella. Su una cartella da 100.000 righe e 300.000 formule una modifica richiede 16 ms; un ricalcolo completo 64 ms.",
          "Aggiunge anche le **ricerche indicizzate**. Il primo CERCA.VERT, CONFRONTA o CERCA.X su un intervallo lo legge una volta e costruisce un indice; le ricerche successive sono un singolo accesso all'indice. 1.000 CERCA.VERT esatti su 10.000 righe sono passati da 1.703 ms in IronCalc originale a 1,3 ms nel fork di Foglio. Il fork corregge inoltre una dozzina di funzioni, tanto che 191 delle 195 funzioni della verifica di compatibilità danno gli stessi risultati di Excel in ogni caso di prova.",
        ],
        bullets: [
          "I vecchi `.xls`, i binari `.xlsb` e gli `.ods` di LibreOffice vengono letti con [calamine](https://github.com/tafia/calamine), un lettore veloce scritto in Rust.",
          "I file CSV e TSV passano da un importatore in Rust che riconosce la codifica del testo, il separatore e il separatore decimale.",
          "Le formule scritte in italiano, tedesco, spagnolo o francese vengono tradotte nella forma standard inglese di Excel prima di essere salvate.",
        ],
      },
      {
        heading: "Il ponte: una semplice interfaccia C",
        body: [
          "Il motore in Rust viene compilato come libreria statica ed espone una piccola interfaccia C (`foglio_core.h`): aprire e salvare un file, modificare una cella, restituire un blocco di celle visibili. Swift la chiama direttamente tramite un bridging header. Nessun binding generato, nessun framework, nessun messaggio tra processi: una chiamata al motore costa più o meno quanto una normale chiamata di funzione.",
        ],
      },
      {
        heading: "Niente progetto Xcode",
        body: [
          "Foglio si compila con due comandi: `cargo` costruisce la libreria Rust e `swiftc` compila l'app e la collega. Uno script produce un'app universale per Apple silicon e Intel e la impacchetta in un'immagine disco con `hdiutil`, lo strumento di Apple. Servono gli Xcode Command Line Tools e Rust; Xcode completo non è necessario.",
          "Meno strati significa meno cose che possono rompersi, compilazioni più rapide e un progetto che chiunque può leggere da cima a fondo.",
        ],
      },
      {
        heading: "Testato con tastiera e mouse veri",
        body: [
          "Foglio ha 69 test dell'interfaccia che usano l'app reale con eventi di tastiera e mouse reali: scrivere formule, riempire intervalli, ordinare, annullare, salvare e riaprire file. Gli importatori di file e il motore di calcolo hanno le proprie suite di test in Rust, e una modalità speciale confronta ogni ricalcolo incrementale con un ricalcolo completo.",
        ],
      },
      {
        heading: "Perché tutto questo rende Foglio piccolo e veloce",
        body: [
          "Un'app Electron contiene una copia completa del browser Chromium, di solito ben oltre 100 MB prima ancora di fare qualcosa. Una suite Java o multipiattaforma porta con sé il proprio runtime e il proprio toolkit grafico. Foglio contiene solo il proprio codice e usa i framework già presenti su ogni Mac.",
          "Il motore in Rust è compilato con l'ottimizzazione completa in fase di link e senza simboli di debug. Il risultato è un'app universale di circa 19 MB su disco, 7,5 MB come download compresso, che a riposo usa lo 0 % della CPU.",
        ],
      },
    ],
    faq: [
      {
        q: "Foglio è un'app Electron o web?",
        a: "No. È un'app AppKit nativa scritta in Swift. Al suo interno non c'è alcun motore di browser.",
      },
      {
        q: "Funziona in modo nativo su Apple silicon?",
        a: "Sì. Foglio è un'app universale con codice nativo sia per Apple silicon (arm64) sia per Intel (x86_64).",
      },
      {
        q: "Posso compilare Foglio da solo?",
        a: "Sì. Installa gli Xcode Command Line Tools e Rust, poi esegui `scripts/build.sh`. Il [README](https://github.com/Acid236/foglio#building-from-source) riporta i comandi esatti.",
      },
      {
        q: "Le modifiche a IronCalc sono disponibili per tutti?",
        a: "Il fork è open source con le stesse licenze di IronCalc; ogni modifica è segnalata da un commento `Foglio fork:` e descritta in `third_party/README.md`, così può essere esaminata e riutilizzata.",
      },
    ],
  },

  download: {
    h1: "Scarica Foglio per Mac",
    intro: [
      "Foglio 1.0 è gratuito. Un'unica immagine disco universale funziona su ogni Mac con macOS 14 Sonoma o successivo, sia Apple silicon sia Intel.",
      "È una prima versione: gestisce dall'inizio alla fine i fogli di tutti i giorni, ma tieni un backup dei file importanti.",
    ],
    steps: [
      {
        title: "Scarica l'immagine disco",
        text: "Fai clic sul pulsante di download per scaricare `Foglio-1.0.dmg` (7,5 MB) dalla pagina delle release del progetto su GitHub.",
      },
      {
        title: "Trascina Foglio in Applicazioni",
        text: "Apri l'immagine disco e trascina l'icona di Foglio sul collegamento ad Applicazioni lì accanto. Poi espelli l'immagine disco.",
      },
      {
        title: "Aprilo la prima volta",
        text: "La prima volta macOS chiede conferma, perché Foglio non è firmato con un Apple Developer ID a pagamento. Trovi i passaggi qui sotto: va fatto una sola volta.",
      },
      {
        title: "Apri i tuoi fogli di calcolo",
        text: "Fai doppio clic su un file `.xlsx` e scegli Foglio da Apri con, oppure trascina i file sull'icona di Foglio nel Dock.",
      },
    ],
    gatekeeperTitle: "“Sviluppatore non identificato”: come aprire Foglio la prima volta",
    gatekeeperText: [
      "Foglio 1.0 ha una firma ad-hoc e non è firmato e autenticato (notarizzato) con un account sviluppatore Apple a pagamento, quindi Gatekeeper non può garantirlo e la prima apertura mostra un avviso. È normale per i piccoli progetti open source, e puoi leggere ogni riga del [codice sorgente](https://github.com/Acid236/foglio) o compilare l'app da solo.",
      "**macOS 15 Sequoia o successivi:** fai doppio clic su Foglio e chiudi l'avviso. Apri **Impostazioni di Sistema ▸ Privacy e sicurezza**, scorri fino al messaggio su Foglio e fai clic su **Apri comunque**, poi conferma con la password o il Touch ID.",
      "**macOS 14 Sonoma:** in Applicazioni fai clic destro (o Ctrl-clic) su Foglio, scegli **Apri**, poi fai clic su **Apri** nella finestra di dialogo.",
      "Da quel momento Foglio si apre normalmente, come qualsiasi altra app.",
    ],
    requirementsTitle: "Requisiti",
    requirements: [
      "macOS 14 Sonoma o successivo",
      "Mac con Apple silicon o Intel (app universale)",
      "Circa 19 MB di spazio su disco",
      "Nessun account e nessuna connessione a Internet necessari",
    ],
    sourceTitle: "Preferisci compilarlo da solo?",
    sourceText: [
      "Foglio è open source con licenza MIT e Apache-2.0. Con gli Xcode Command Line Tools e Rust installati, `scripts/build.sh` crea la stessa app universale dal codice sorgente in pochi minuti, senza Xcode.",
      "Note di rilascio, versioni precedenti e segnalazioni sono su [GitHub](https://github.com/Acid236/foglio/releases). Vuoi sapere come funziona? Leggi la pagina sulla [tecnologia](/technology/).",
    ],
    faq: [
      {
        q: "Il download è sicuro?",
        a: "L'immagine disco è generata dal codice sorgente pubblico e pubblicata nella pagina delle release del progetto su GitHub. L'avviso di macOS compare perché l'app non è notarizzata con un account Apple a pagamento, non perché sia stato rilevato qualcosa al suo interno.",
      },
      {
        q: "Come aggiorno Foglio?",
        a: "Foglio non cerca aggiornamenti da solo, perché non si collega a Internet. Scarica la nuova versione da questa pagina o dalle release su GitHub e sostituisci l'app in Applicazioni.",
      },
      {
        q: "Come si disinstalla?",
        a: "Trascina Foglio da Applicazioni al Cestino. I tuoi fogli di calcolo sono normali file e restano dove li hai salvati.",
      },
      {
        q: "Posso impostare Foglio come app predefinita per i file xlsx?",
        a: "Sì. Seleziona un file `.xlsx` nel Finder, scegli Archivio ▸ Ottieni informazioni, seleziona Foglio in **Apri con** e fai clic su **Modifica tutto…**.",
      },
      {
        q: "Esiste una versione per iPhone, iPad, Windows o Linux?",
        a: "No. Foglio è solo per Mac. Il motore in Rust è multipiattaforma, ma l'interfaccia è scritta in AppKit.",
      },
    ],
  },

  alternativesIndex: {
    h1: "Alternative a Excel, Numbers, LibreOffice e Fogli Google per Mac",
    intro: [
      "Ogni pagina spiega cosa guadagni e cosa perdi passando a Foglio da un'app specifica, con una sezione dedicata a quando conviene continuare a usare quella che hai già. Per istruzioni passo passo, leggi le [guide](/guides/).",
    ],
  },
  guidesIndex: {
    h1: "Guide ai fogli di calcolo su Mac",
    intro: [
      "Risposte pratiche ai problemi più comuni con i fogli di calcolo sul Mac: aprire file Excel e CSV senza Excel, sistemare caratteri strani e colonne sbagliate, scrivere le formule in italiano. Ogni guida indica anche come fare senza Foglio. Arrivi da un'altra app? Leggi le [alternative](/alternatives/).",
    ],
  },
};
