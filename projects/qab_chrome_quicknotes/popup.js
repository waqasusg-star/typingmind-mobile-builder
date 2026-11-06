'use strict';

/**
 * QA Quick Notes — local-only MV3 popup.
 * No host permissions, no network calls, notes stay in chrome.storage.local.
 */

const KEY_NOTES = 'qab_quicknotes_v1';
const KEY_BACKUP = 'qab_quicknotes_backup_v1';
const KEY_CORRUPT = 'qab_quicknotes_corrupt_v1';
const SCHEMA = 1;
const MAX_NOTE_LENGTH = 200;
const MAX_NOTES = 50;

const state = { notes: [], hasBackup: false };

const noteEl = document.getElementById('note');
const saveEl = document.getElementById('save');
const errorEl = document.getElementById('note-error');
const statusEl = document.getElementById('status');
const emptyEl = document.getElementById('empty');
const listEl = document.getElementById('notes');
const restoreEl = document.getElementById('restore');
const countEl = document.getElementById('count');
const composerEl = document.getElementById('composer');

function storageGet(keys) {
  return new Promise((resolve) => {
    chrome.storage.local.get(keys, (items) => resolve(items || {}));
  });
}

function storageSet(items) {
  return new Promise((resolve) => {
    chrome.storage.local.set(items, () => resolve());
  });
}

function storageRemove(keys) {
  return new Promise((resolve) => {
    chrome.storage.local.remove(keys, () => resolve());
  });
}

function normalizeNotes(rawNotes) {
  const notes = [];
  let skipped = 0;
  rawNotes.forEach((candidate) => {
    if (!candidate || typeof candidate !== 'object') {
      skipped += 1;
      return;
    }
    const text =
      typeof candidate.text === 'string' ? candidate.text.trim().replace(/\s+/g, ' ') : '';
    if (!text || text.length > MAX_NOTE_LENGTH) {
      skipped += 1;
      return;
    }
    notes.push({
      id: typeof candidate.id === 'string' && candidate.id ? candidate.id : `n${notes.length + 1}`,
      text,
      createdAt:
        typeof candidate.createdAt === 'number' && Number.isFinite(candidate.createdAt)
          ? candidate.createdAt
          : Date.now(),
    });
  });
  return { notes: notes.slice(-MAX_NOTES), skipped };
}

function validate(raw) {
  const text = (raw || '').trim().replace(/\s+/g, ' ');
  if (!text) {
    return { error: 'Enter a note before saving it.' };
  }
  if (text.length > MAX_NOTE_LENGTH) {
    return {
      error: `Keep the note to ${MAX_NOTE_LENGTH} characters or fewer (currently ${text.length}).`,
    };
  }
  return { text };
}

function setStatus(message, status) {
  statusEl.textContent = message;
  statusEl.dataset.state = status;
  statusEl.hidden = !message;
}

function setError(message) {
  errorEl.textContent = message || '';
  errorEl.hidden = !message;
}

function render() {
  listEl.textContent = '';
  state.notes
    .slice()
    .sort((a, b) => b.createdAt - a.createdAt)
    .forEach((note) => {
      const item = document.createElement('li');
      item.className = 'note';
      item.dataset.id = note.id;

      const text = document.createElement('p');
      text.className = 'note__text';
      text.textContent = note.text;

      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'note__delete';
      remove.textContent = 'Delete';
      remove.setAttribute('aria-label', `Delete note: ${note.text}`);
      remove.addEventListener('click', () => deleteNote(note.id));

      item.append(text, remove);
      listEl.append(item);
    });

  emptyEl.hidden = state.notes.length > 0;
  restoreEl.hidden = !state.hasBackup;
}

async function refreshBackupFlag() {
  const items = await storageGet([KEY_BACKUP]);
  state.hasBackup = typeof items[KEY_BACKUP] === 'string' && items[KEY_BACKUP].length > 0;
}

async function load() {
  const items = await storageGet([KEY_NOTES, KEY_BACKUP]);
  state.hasBackup = typeof items[KEY_BACKUP] === 'string' && items[KEY_BACKUP].length > 0;

  const payload = items[KEY_NOTES];
  if (typeof payload !== 'string' || !payload) {
    state.notes = [];
    render();
    return;
  }

  let parsed = null;
  try {
    parsed = JSON.parse(payload);
  } catch (error) {
    parsed = null;
  }

  if (!parsed || parsed.schema !== SCHEMA || !Array.isArray(parsed.notes)) {
    await storageSet({ [KEY_CORRUPT]: payload });
    await storageRemove(KEY_NOTES);
    state.notes = [];
    setStatus(
      'The saved notes could not be read, so a fresh list was started. The unreadable copy was kept for diagnostics.',
      'recovered',
    );
    render();
    return;
  }

  const normalized = normalizeNotes(parsed.notes);
  state.notes = normalized.notes;
  if (normalized.skipped > 0) {
    const label = normalized.skipped === 1 ? 'entry' : 'entries';
    setStatus(
      `Recovered the notes and skipped ${normalized.skipped} damaged ${label}.`,
      'recovered',
    );
  }
  render();
}

async function persist(notes) {
  const items = await storageGet([KEY_NOTES]);
  const current = items[KEY_NOTES];
  if (typeof current === 'string' && current) {
    try {
      const parsed = JSON.parse(current);
      if (parsed && parsed.schema === SCHEMA && Array.isArray(parsed.notes)) {
        await storageSet({ [KEY_BACKUP]: current });
      }
    } catch (error) {
      // Keep the unreadable payload untouched; load() records it for diagnostics.
    }
  }
  await storageSet({ [KEY_NOTES]: JSON.stringify({ schema: SCHEMA, notes }) });
  await refreshBackupFlag();
  render();
}

async function saveNote(event) {
  if (event) event.preventDefault();
  const result = validate(noteEl.value);
  if (result.error) {
    setError(result.error);
    noteEl.focus();
    return;
  }
  setError('');
  const now = Date.now();
  const next = state.notes
    .concat([{ id: `n${now}`, text: result.text, createdAt: now }])
    .slice(-MAX_NOTES);
  state.notes = next;
  await persist(next);
  noteEl.value = '';
  countEl.textContent = '0';
  setStatus('Note saved.', 'saved');
  render();
}

async function deleteNote(id) {
  const next = state.notes.filter((note) => note.id !== id);
  state.notes = next;
  await persist(next);
  setStatus('Note deleted.', 'deleted');
  render();
}

async function restoreBackup() {
  const items = await storageGet([KEY_BACKUP]);
  const backup = items[KEY_BACKUP];
  if (typeof backup !== 'string' || !backup) {
    setStatus('There is no saved copy to restore.', 'error');
    return;
  }
  let parsed = null;
  try {
    parsed = JSON.parse(backup);
  } catch (error) {
    parsed = null;
  }
  if (!parsed || parsed.schema !== SCHEMA || !Array.isArray(parsed.notes)) {
    setStatus('The saved copy is unreadable too, so nothing was restored.', 'error');
    return;
  }
  const normalized = normalizeNotes(parsed.notes);
  state.notes = normalized.notes;
  await storageSet({ [KEY_NOTES]: JSON.stringify({ schema: SCHEMA, notes: state.notes }) });
  await storageRemove(KEY_BACKUP);
  state.hasBackup = false;
  const label = state.notes.length === 1 ? 'note' : 'notes';
  setStatus(`Restored ${state.notes.length} ${label} from the saved copy.`, 'restored');
  render();
}

async function init() {
  noteEl.addEventListener('input', () => {
    countEl.textContent = String(noteEl.value.length);
    if (!errorEl.hidden && noteEl.value.trim()) {
      setError('');
    }
  });
  composerEl.addEventListener('submit', saveNote);
  noteEl.addEventListener('keydown', (event) => {
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
      saveNote(event);
    }
  });
  restoreEl.addEventListener('click', restoreBackup);
  countEl.textContent = '0';

  try {
    await load();
  } finally {
    noteEl.dataset.loaded = 'true';
  }
}

init();
