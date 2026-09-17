# LEAF

React 19 + TypeScript vocabulary notebook. The original requirements are in `../readme.md`.

## Run locally

Node.js 22.13 or newer is required.

```sh
npm install
npm run dev
```

Open the Local URL printed by the server (normally http://localhost:3000).

```sh
npm test
npm run typecheck
npm run build
```

## Multiple examples and synonyms

Use the add buttons in the word editor to register multiple examples (each with its own translation) and synonyms. Each entry can be edited or removed separately. Word details and flashcards show all examples. Existing saved words and old CSV files remain readable. New CSV exports add `examples_json` and `synonyms_json` columns to preserve all entries, including quotes, commas and line breaks. These columns take precedence over the legacy single-value columns when importing.

## Data

Words and quiz history are saved to this browser's localStorage. They persist across browser restarts. Different devices, browsers, and site origins have separate storage. Clearing site data removes this notebook. CSV export backs up words and review scheduling, but not the event history. Export regularly before moving or clearing browser data.

CSV accepts UTF-8 with English or Korean headers. Required columns: `word` (영단어/단어), `meaning` (의미/뜻). Optional: `example` (예시/예문), `translation` (예시 뜻/예문 뜻), `synonyms` (유의어), `memo` (메모). Exports also retain favorite, level, due, and created. Imports skip case-insensitive duplicate words and blank required fields. Quoted commas and multiline cells are supported. Spreadsheet formulas are escaped during export for safe opening.

Correct answers schedule reviews after 1, 3, 7, 14, 30, then 60 days. Incorrect answers return after 10 minutes. Level 4 and above counts as familiar. Each session includes up to 20 shuffled words. Multiple choice requires at least two distinct meanings. Typing ignores surrounding whitespace and case. Flashcard answers use self-assessment.

The initial notebook is empty; sample vocabulary can be added explicitly. No accounts or cloud synchronization are required. Pronunciation uses the browser's speech synthesis and installed voices.
