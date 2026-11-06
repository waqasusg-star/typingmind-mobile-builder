'use strict';

/**
 * Real Chromium behaviour test for QA Quick Notes.
 *
 * Runs against the installed extension popup in an isolated browser context:
 * empty state, validation, save + persistence through chrome.storage.local,
 * corrupt-payload recovery, restore from the kept copy, and delete.
 */

const KEY_NOTES = 'qab_quicknotes_v1';
const KEY_BACKUP = 'qab_quicknotes_backup_v1';
const SAMPLE_NOTE = 'Call the forwarder about the Dammam booking.';
const RESTORED_NOTE = 'Recovered note from the kept copy.';

function buildAsserts(assert) {
  const source =
    assert && (typeof assert === 'object' || typeof assert === 'function') ? assert : {};

  const fail = (message, actual, expected) => {
    if (expected === undefined) {
      throw new Error(message || 'Assertion failed');
    }
    throw new Error(
      `${message || 'Assertion failed'}: received ${JSON.stringify(actual)}, expected ${JSON.stringify(
        expected,
      )}`,
    );
  };

  return {
    ok(value, message) {
      if (typeof source.ok === 'function') return source.ok(value, message);
      if (!value) fail(message || 'Expected a truthy value');
    },
    equal(actual, expected, message) {
      if (typeof source.equal === 'function') return source.equal(actual, expected, message);
      if (typeof source.strictEqual === 'function') return source.strictEqual(actual, expected, message);
      if (actual !== expected) fail(message || 'Values are not equal', actual, expected);
    },
  };
}

function clearStorage(page) {
  return page.evaluate(
    () => new Promise((resolve) => chrome.storage.local.clear(() => resolve(null))),
  );
}

function writeStorage(page, items) {
  return page.evaluate(
    (payload) => new Promise((resolve) => chrome.storage.local.set(payload, () => resolve(null))),
    items,
  );
}

function readStorage(page, key) {
  return page.evaluate(
    (storageKey) =>
      new Promise((resolve) => {
        chrome.storage.local.get(storageKey, (items) => {
          resolve(Object.prototype.hasOwnProperty.call(items, storageKey) ? items[storageKey] : null);
        });
      }),
    key,
  );
}

module.exports = async function ({ context, extensionId, assert }) {
  const check = buildAsserts(assert);
  check.ok(
    typeof extensionId === 'string' && extensionId.length > 0,
    'A real extension id is required to open the popup',
  );

  const popupUrl = `chrome-extension://${extensionId}/popup.html`;
  const popup = await context.newPage();

  try {
    await popup.goto(popupUrl);
    await popup.locator('h1', { hasText: 'QA Quick Notes' }).waitFor({ state: 'visible' });

    await clearStorage(popup);
    await popup.reload();

    const note = popup.locator('#note[data-loaded="true"]');
    await note.waitFor({ state: 'attached' });

    // 1. Empty state
    check.equal(await popup.locator('#empty').isVisible(), true, 'Empty state is visible with no notes');
    check.equal(
      (await popup.locator('#empty').textContent()).trim(),
      'No notes yet. Add your first note above.',
      'Empty state explains what to do next',
    );
    check.equal(await popup.locator('li.note').count(), 0, 'No note rows are rendered');

    // 2. Validation
    await note.fill('    ');
    await popup.locator('#save').click();
    await popup.locator('#note-error').waitFor({ state: 'visible' });
    check.equal(
      (await popup.locator('#note-error').textContent()).trim(),
      'Enter a note before saving it.',
      'Blank note is rejected with guidance',
    );
    check.equal(await popup.locator('li.note').count(), 0, 'Blank note is not stored');
    check.equal(await readStorage(popup, KEY_NOTES), null, 'Blank note writes nothing to storage');

    // 3. Saving through the real UI
    await note.fill(SAMPLE_NOTE);
    await popup.locator('#save').click();
    await popup.locator('#status[data-state="saved"]').waitFor({ state: 'attached' });

    check.equal(await popup.locator('li.note').count(), 1, 'Saved note appears once');
    check.equal(
      (await popup.locator('li.note .note__text').first().textContent()).trim(),
      SAMPLE_NOTE,
      'Saved note text is rendered',
    );
    check.equal(await popup.locator('#empty').isVisible(), false, 'Empty state hides after saving');
    check.equal(await note.inputValue(), '', 'Composer clears after saving');

    const stored = await readStorage(popup, KEY_NOTES);
    const parsed = JSON.parse(stored);
    check.equal(parsed.schema, 1, 'Storage payload carries the schema version');
    check.equal(parsed.notes.length, 1, 'Storage payload holds one note');
    check.equal(parsed.notes[0].text, SAMPLE_NOTE, 'Storage payload holds the note text');

    // 4. Persistence across a popup reload
    await popup.reload();
    await popup.locator('#note[data-loaded="true"]').waitFor({ state: 'attached' });
    check.equal(await popup.locator('li.note').count(), 1, 'Note survives a popup reload');
    check.equal(
      (await popup.locator('li.note .note__text').first().textContent()).trim(),
      SAMPLE_NOTE,
      'Reloaded note keeps its text',
    );

    // 5. Corrupt payload recovery and restore
    await writeStorage(popup, {
      [KEY_NOTES]: 'not-json-at-all',
      [KEY_BACKUP]: JSON.stringify({
        schema: 1,
        notes: [{ id: 'b1', text: RESTORED_NOTE, createdAt: 1 }],
      }),
    });
    await popup.reload();
    await popup.locator('#note[data-loaded="true"]').waitFor({ state: 'attached' });
    await popup.locator('#status[data-state="recovered"]').waitFor({ state: 'attached' });

    check.equal(await popup.locator('li.note').count(), 0, 'Unreadable payload does not render notes');
    check.equal(await popup.locator('#restore').isVisible(), true, 'Restore action is offered');
    check.equal(
      await readStorage(popup, KEY_NOTES),
      null,
      'Unreadable payload is removed so the app can start clean',
    );

    await popup.locator('#restore').click();
    await popup.locator('#status[data-state="restored"]').waitFor({ state: 'attached' });
    check.equal(await popup.locator('li.note').count(), 1, 'Restore brings the kept note back');
    check.equal(
      (await popup.locator('li.note .note__text').first().textContent()).trim(),
      RESTORED_NOTE,
      'Restored note keeps its text',
    );

    // 6. Deleting the last note
    await popup.locator('li.note button.note__delete').first().click();
    await popup.locator('#status[data-state="deleted"]').waitFor({ state: 'attached' });
    check.equal(await popup.locator('li.note').count(), 0, 'Delete removes the note row');
    check.equal(await popup.locator('#empty').isVisible(), true, 'Empty state returns after deleting');

    const afterDelete = await readStorage(popup, KEY_NOTES);
    check.equal(JSON.parse(afterDelete).notes.length, 0, 'Storage reflects the deletion');
  } finally {
    await popup.close();
  }
};
