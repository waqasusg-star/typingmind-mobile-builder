# QA Quick Notes (Chrome MV3) 1.0.0

Isolated builder acceptance project: `qab_chrome_quicknotes`.

Local-only Manifest V3 popup. No host permissions, no content scripts, no network calls,
no accounts and no remote code. Notes live in `chrome.storage.local`.

## Features

- Add a short note (max 200 characters, counter, inline validation with focus return).
- Notes list newest first; per-note Delete with an accessible label.
- Empty state, error state, and a polite `role="status"` live region.
- Ctrl/Cmd + Enter saves from the keyboard; visible focus rings.
- Light and dark themes via `prefers-color-scheme` with 40 px controls.
- Storage payload is `{schema:1, notes:[...]}`; the previous good payload is kept as a backup,
  unreadable payloads are moved aside for diagnostics and the popup starts clean with a notice
  and a "Restore last saved copy" action.

## Tests

`tests/extension.test.cjs` exports the reviewed async contract
(`{ context, extensionId, assert }`) and runs in a real isolated Chromium extension context:

1. empty state with no notes;
2. blank-note rejection through the real UI (and no storage write);
3. save through the UI, rendered row, and the actual `chrome.storage.local` payload;
4. persistence after a popup reload;
5. corrupt payload → recovery notice → restore from the kept copy;
6. delete a note and verify the empty state and stored payload.

## Install locally

1. Unzip the extension ZIP.
2. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, select the folder.

## Limits

- Not published to the Chrome Web Store and not reviewed by Google.
- Tested only in Chromium through the builder harness, not in a personal Chrome profile.
- Notes are per-browser-profile; no sync and no export.
