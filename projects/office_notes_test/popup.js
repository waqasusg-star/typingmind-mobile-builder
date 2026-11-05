'use strict';

// Local-only note storage. No network access, no host permissions.
const NOTE_KEY = 'office_note';

const noteField = document.getElementById('note');
const saveButton = document.getElementById('save');
const statusField = document.getElementById('status');

function getStoredNote() {
  return new Promise((resolve) => {
    chrome.storage.local.get(NOTE_KEY, (items) => {
      const value = items[NOTE_KEY];
      resolve(typeof value === 'string' ? value : '');
    });
  });
}

function setStoredNote(value) {
  return new Promise((resolve) => {
    chrome.storage.local.set({ [NOTE_KEY]: value }, () => resolve());
  });
}

function showStatus(state, message) {
  statusField.textContent = message;
  statusField.dataset.state = state;
}

async function init() {
  noteField.value = await getStoredNote();
  // Marks the field ready so tests can assert on a hydrated popup.
  noteField.dataset.loaded = 'true';
  showStatus('idle', 'Saved locally in this browser only.');
}

saveButton.addEventListener('click', async () => {
  saveButton.disabled = true;
  try {
    await setStoredNote(noteField.value);
    showStatus('saved', 'Note saved locally.');
  } catch (error) {
    showStatus('error', 'Could not save the note locally.');
    console.error('Office Notes Test: failed to save note', error);
  } finally {
    saveButton.disabled = false;
  }
});

init();
