'use strict';

/**
 * Real Chromium behavior test for Office Notes Test.
 *
 * Opens the installed popup in an isolated extension context, saves a note
 * through the actual UI, reloads the popup and asserts the note persisted
 * through chrome.storage.local.
 */

const NOTE_KEY = 'office_note';
const SAMPLE_NOTE = 'Restock printer paper and blue pens before Friday.';

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
      if (typeof source.ok === 'function') {
        return source.ok(value, message);
      }
      if (!value) {
        fail(message || 'Expected a truthy value');
      }
    },
    equal(actual, expected, message) {
      if (typeof source.equal === 'function') {
        return source.equal(actual, expected, message);
      }
      if (typeof source.strictEqual === 'function') {
        return source.strictEqual(actual, expected, message);
      }
      if (actual !== expected) {
        fail(message || 'Values are not equal', actual, expected);
      }
    },
  };
}

function clearStorage(page) {
  return page.evaluate(
    () =>
      new Promise((resolve) => {
        chrome.storage.local.clear(() => resolve(null));
      }),
  );
}

function readStoredNote(page) {
  return page.evaluate(
    (storageKey) =>
      new Promise((resolve) => {
        chrome.storage.local.get(storageKey, (items) => {
          resolve(
            Object.prototype.hasOwnProperty.call(items, storageKey) ? items[storageKey] : null,
          );
        });
      }),
    NOTE_KEY,
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
    // 1. Open the real popup page.
    await popup.goto(popupUrl);
    await popup
      .locator('h1', { hasText: 'Office Notes Test' })
      .waitFor({ state: 'visible' });
    check.ok(
      (await popup.locator('#note').count()) === 1,
      'Popup should render a single note textarea',
    );
    check.ok(
      (await popup.locator('#save').count()) === 1,
      'Popup should render the Save button',
    );

    // 2. Start from deterministic empty local storage.
    await clearStorage(popup);
    await popup.reload();

    const hydratedNote = popup.locator('#note[data-loaded="true"]');
    await hydratedNote.waitFor({ state: 'attached' });
    check.equal(
      await hydratedNote.inputValue(),
      '',
      'Popup should open with an empty note when nothing is stored',
    );

    // 3. Save a note through the real UI.
    await hydratedNote.fill(SAMPLE_NOTE);
    check.equal(
      await hydratedNote.inputValue(),
      SAMPLE_NOTE,
      'Textarea should hold the typed note before saving',
    );

    await popup.locator('#save').click();
    await popup.locator('#status[data-state="saved"]').waitFor({ state: 'attached' });

    check.equal(
      await readStoredNote(popup),
      SAMPLE_NOTE,
      'Clicking Save should write the note to chrome.storage.local',
    );

    // 4. Reload the popup and assert persistence.
    await popup.reload();
    await popup
      .locator('h1', { hasText: 'Office Notes Test' })
      .waitFor({ state: 'visible' });

    const reloadedNote = popup.locator('#note[data-loaded="true"]');
    await reloadedNote.waitFor({ state: 'attached' });

    check.equal(
      await reloadedNote.inputValue(),
      SAMPLE_NOTE,
      'Saved note should be restored into the textarea after a popup reload',
    );
    check.equal(
      await readStoredNote(popup),
      SAMPLE_NOTE,
      'chrome.storage.local should still hold the saved note after a reload',
    );
  } finally {
    await popup.close();
  }
};
