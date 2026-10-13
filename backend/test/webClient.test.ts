import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

// Run the shipped browser functions, replacing only the DOM renderer and I/O.
function browserFixture() {
  const source = fs.readFileSync(path.resolve(__dirname, '../../web/app.js'), 'utf8');
  const storage = new Map<string, string>();
  const context = vm.createContext({
    crypto: webcrypto,
    window: { location: new URL('http://localhost:8910/') },
    document: { getElementById: () => ({}) },
    localStorage: {
      getItem: (key: string) => storage.get(key) ?? null,
      setItem: (key: string, value: string) => storage.set(key, value),
      removeItem: (key: string) => storage.delete(key),
    },
  });
  vm.runInContext(source.slice(0, source.indexOf('  document.addEventListener("click"')) + `
    render = () => {};
    showToast = message => { state.toast = message; };
    openPendingItemLink = () => {};
    globalThis.client = {
      state, submitItemEditor, handleInput, handleAction, apiRequest,
      loadServerHomes, applyAuthResponse, clearSession, refreshAccessToken,
      setSaveHandler: handler => { saveItemFromForm = handler; },
    };
  })();`, context);
  return { client: context.client, context, storage };
}

function editorFixture() {
  const fixture = browserFixture();
  const item = { id: 'item', name: 'Original', properties: [], photoUrls: [], documents: [] };
  fixture.client.state.homes = [{ id: 'home', items: [item] }];
  fixture.client.state.sheet = { type: 'itemEditor', homeId: 'home', itemId: 'item', draft: item };
  const elements = Object.fromEntries([
    'name', 'icon', 'quantity', 'notes', 'locationId', 'purchaseDate', 'serialNumber',
    'modelNumber', 'warrantyExpiresDate', 'estimatedValue', 'isFlagged',
  ].map(name => [name, { value: '', checked: false }]));
  elements.name.value = 'Changed name';
  elements.notes.value = 'Draft notes with trailing space ';
  elements.quantity.value = '2';
  const form = { dataset: { homeId: 'home', itemId: 'item' }, elements, querySelectorAll: () => [] };
  return { ...fixture, form };
}

test('item save keeps the complete draft on failure and rejects overlapping submissions', async () => {
  const { client, form } = editorFixture();
  let calls = 0;
  let reject!: (error: Error) => void;
  client.setSaveHandler(() => {
    calls++;
    return new Promise((_resolve, fail) => { reject = fail; });
  });
  const saving = client.submitItemEditor(form);
  await client.submitItemEditor(form);
  await client.handleAction({ dataset: { action: 'close-sheet' } });
  assert.equal(calls, 1);
  assert.equal(client.state.isSavingItem, true);
  assert.equal(client.state.sheet.draft.notes, form.elements.notes.value);
  reject(new Error('Temporary outage'));
  await saving;
  assert.equal(client.state.isSavingItem, false);
  assert.equal(client.state.sheet.error, 'Temporary outage');
  assert.equal(client.state.sheet.draft.name, 'Changed name');
  assert.equal(client.state.sheet.draft.quantity, 2);
});

test('a retained item draft can be retried and closes only after success', async () => {
  const { client, form } = editorFixture();
  client.setSaveHandler(() => Promise.reject(new Error('Offline')));
  await client.submitItemEditor(form);
  assert.equal(client.state.sheet.error, 'Offline');
  client.setSaveHandler(() => Promise.resolve());
  await client.submitItemEditor(form);
  assert.equal(client.state.sheet, null);
  assert.equal(client.state.toast, 'Item saved');
});

test('typing updates the item draft without trimming unfinished text before redraws', () => {
  const { client, form } = editorFixture();
  client.handleInput({ target: { closest: () => form } });
  assert.equal(client.state.sheet.draft.notes, 'Draft notes with trailing space ');
  assert.equal(client.state.sheet.draft.name, 'Changed name');
});

test('attachment uploads block item saves until their draft is ready', async () => {
  const { client, form } = editorFixture();
  client.state.isUploadingAttachment = true;
  let calls = 0;
  client.setSaveHandler(() => { calls++; });
  await client.submitItemEditor(form);
  assert.equal(calls, 0);
});
