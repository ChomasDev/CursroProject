# Ai-Ando — protocollo WebSocket del roast

L'app macOS apre **una connessione WebSocket per ogni prompt** (URL da env `AIANDO_WS_URL`, es. `ws://localhost:3000/roast`, oppure UserDefaults `wsURL`).
Tutti i messaggi sono **frame di testo JSON**, un messaggio per frame, chiavi in `snake_case`.

## Flusso

1. Il client si connette e manda **un** `roast_request`.
2. Il server risponde con: `stats` (prima possibile) → tanti `delta` / `phrase` → `done`.
3. Dopo `done` (o `error`) il client chiude il socket.

Timeout: se il client non riceve **nessun frame per 20s** chiude e passa al roast mock locale.
Se il server fallisce prima di mandare qualsiasi cosa, l'utente vede comunque il mock.

## Client → server

```json
{
  "type": "roast_request",
  "session_id": "b1f3…",
  "conversation_id": "c9a2…",
  "prompt": "ciao potresti per favore sistemare questo bug che non va il login grazie mille",
  "token_count": 19,
  "model": "claude-4-sonnet"
}
```
`conversation_id` e `model` possono essere `null`. `token_count` è una stima (~4 caratteri/token): se ne hai uno vero, rimandalo in `stats.token_count`.

## Server → client

### `stats` — numeri calcolati dal backend (mai dall'LLM)
```json
{"type":"stats","stats":{
  "similar_count":48213, "token_count":19, "seconds_spent":14,
  "prompts_per_day":60, "hourly_wage":15.5,
  "euro_per_day":3.62, "euro_per_month":79.64,
  "leaderboard_rank":1323, "leaderboard_total":8741, "people_above":1322,
  "leaderboard":[
    {"name":"xX_vibecoder_Xx","tokens":900271,"is_me":false},
    {"name":"tu","tokens":478,"is_me":true}
  ]
}}
```
Campi mancanti = 0 (tollerato), ma meglio mandarli tutti. `people_above` = `leaderboard_rank - 1`.

### `delta` — pezzo di testo da **appendere** a una sezione (streaming token/parola)
```json
{"type":"delta","section":"cloni","text":"No vabbè 💀 questa frase "}
```

### `phrase` — frase completa
```json
{"type":"phrase","section":"invece_potevi","text":"Fare 7 squat. Non li avresti fatti comunque"}
```
- Per `invece_potevi`: **ogni `phrase` è un elemento della lista** (manda 3-4 phrase).
- Per le altre sezioni: `phrase` **sostituisce** il testo della sezione (utile se non fai streaming token per token).

### `done` / `error`
```json
{"type":"done"}
{"type":"error","message":"LLM timeout"}
```

Tipi sconosciuti (es. `{"type":"ping"}`) vengono ignorati. Frame non JSON ignorati.

## Sezioni (`section`)

Stesse chiavi del JSON in `prompts/ai-ando-system-prompt.md`. Ordine consigliato:

| `section` | contenuto |
|---|---|
| `cloni` | quante persone hanno scritto lo stesso prompt |
| `fun_fact_frase` | fun fact inventato sulla frase |
| `soldi_gratis` | € al giorno/mese "a gratis" |
| `invece_potevi` | lista (una `phrase` per elemento) |
| `classifica` | posizione nella classifica Ai-Ando |
| `prompt_migliore` | prompt riscritto |
| `commento_prompt_migliore` | verdetto finale |

## Esempio completo di sessione

```
→ {"type":"roast_request","session_id":"s1","conversation_id":null,"prompt":"ciao sistemami il login","token_count":6,"model":null}
← {"type":"stats","stats":{...}}
← {"type":"delta","section":"cloni","text":"No vabbè 💀 "}
← {"type":"delta","section":"cloni","text":"l'hanno scritta altre 48.213 persone."}
← {"type":"delta","section":"fun_fact_frase","text":"Hai salutato l'AI con 'ciao'…"}
← {"type":"delta","section":"soldi_gratis","text":"Bhe ipotizziamo che fai 60 prompt…"}
← {"type":"phrase","section":"invece_potevi","text":"Bere mezzo spritz"}
← {"type":"phrase","section":"invece_potevi","text":"Guardare 2 TikTok e dimenticarli"}
← {"type":"phrase","section":"invece_potevi","text":"Fare 7 squat"}
← {"type":"delta","section":"classifica","text":"Bhe coglione come sei sei solo 1323°…"}
← {"type":"phrase","section":"prompt_migliore","text":"Il login fallisce: [errore]. Trova la causa in `auth/` e proponi il fix minimo."}
← {"type":"delta","section":"commento_prompt_migliore","text":"Bhe coglione avresti potuto scriverla così…"}
← {"type":"done"}
```

Tip per lo streaming dall'LLM: se l'LLM produce il JSON completo, parsalo in streaming (o chiedi un formato a righe tipo `### cloni` + testo) e inoltra i chunk come `delta` della sezione corrente. Il client gestisce le sezioni in qualsiasi ordine.
