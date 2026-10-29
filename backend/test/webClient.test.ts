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
    const openItemLink = openPendingItemLink;
    openPendingItemLink = () => {};
    globalThis.client = {
      state, submitItemEditor, submitInlineAdd, submitRename, handleInput, handleAction, apiRequest,
      loadServerHomes, applyAuthResponse, clearSession, refreshAccessToken,
      setItemsFlagged, uploadItemAttachment, signInWithApple, runMutation,
      handleGoogleCredentialResponse, sessionScope, openItemLink, filteredHomes, selectAllMatching, pruneSelection,
      sortItemsForTarget, actionRowsForTarget,
      setSaveHandler: handler => { saveItemFromForm = handler; },
    };
  })();`, context);
  return { client: context.client, context, storage };
}

function documentSearchFixture() {
  const fixture = browserFixture();
  fixture.client.applyAuthResponse(auth('A'));
  fixture.client.state.homes = [{
    id: 'home-A', name: 'Maple House', locations: [
      { id: 'floor', name: 'Main Floor', parentId: null },
      { id: 'office', name: 'Office', parentId: 'floor' },
      { id: 'kitchen', name: 'Kitchen', parentId: 'floor' },
    ], items: [
      {
        id: 'camera', name: 'Camera Bag', locationId: 'office', notes: 'Travel kit',
        serialNumber: 'SN-2048', modelNumber: 'TRVL-42', isFlagged: false,
        properties: [{ key: 'Color', value: 'Blue' }], documents: [
          { name: 'Purchase Receipt.pdf', url: 'https://example.invalid/private-object.pdf?signature=hidden-value' },
          { name: 'Travel Manual.pdf', url: 'https://example.invalid/second.pdf' },
        ],
      },
      { id: 'coffee', name: 'Coffee Filters', locationId: 'kitchen', properties: [], documents: [], isFlagged: true },
      { id: 'legacy', name: 'Old Lamp', locationId: null, properties: [] },
    ],
  }];
  return fixture;
}

test('document name search reveals its item and ancestors without changing saved data', () => {
  const { client } = documentSearchFixture();
  const original = JSON.stringify(client.state.homes);
  for (const query of ['RECEIPT', '  travel manual  ', '.pdf']) {
    client.state.search = query;
    const results = client.filteredHomes();
    assert.equal(results.length, 1);
    assert.equal(results[0].id, 'home-A');
    assert.deepEqual(Array.from(results[0].items, (item: any) => item.id), ['camera']);
    assert.deepEqual(Array.from(results[0].locations, (location: any) => location.id), ['floor', 'office']);
  }
  assert.equal(JSON.stringify(client.state.homes), original);
});

test('document search excludes attachment URLs and supports items without documents', () => {
  const { client } = documentSearchFixture();
  for (const query of ['private-object', 'hidden-value', 'missing document']) {
    client.state.search = query;
    assert.equal(client.filteredHomes().length, 0);
  }
  client.state.search = 'old lamp';
  assert.equal(client.filteredHomes()[0].items[0].id, 'legacy');
});

test('document name matches continue to respect the flagged item filter', () => {
  const { client } = documentSearchFixture();
  client.state.search = 'receipt';
  client.state.flaggedOnly = true;
  assert.equal(client.filteredHomes().length, 0);
  client.state.homes[0].items[0].isFlagged = true;
  const results = client.filteredHomes();
  assert.equal(results.length, 1);
  assert.deepEqual(Array.from(results[0].items, (item: any) => item.id), ['camera']);
  assert.deepEqual(Array.from(results[0].locations, (location: any) => location.id), ['floor', 'office']);
});

test('document search preserves existing field matches and an empty search restores all items', () => {
  const { client } = documentSearchFixture();
  for (const query of ['camera', 'TRAVEL', 'color', 'blue', 'sn-2048', 'trvl-42']) {
    client.state.search = query;
    assert.equal(client.filteredHomes()[0].items[0].id, 'camera');
  }
  client.state.search = ' \n ';
  assert.equal(client.filteredHomes(), client.state.homes);
  assert.equal(client.filteredHomes()[0].items.length, 3);
});

test('a document search cannot retain results after changing accounts', () => {
  const { client } = documentSearchFixture();
  client.state.search = 'receipt';
  assert.equal(client.filteredHomes().length, 1);
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  client.state.search = 'receipt';
  assert.equal(client.filteredHomes().length, 0);
});

test('document filters keep matching items and their ancestor paths without mutating inventory', () => {
  const { client } = documentSearchFixture();
  const original = JSON.stringify(client.state.homes);
  client.state.documentFilter = 'with';
  const withDocuments = client.filteredHomes()[0];
  assert.deepEqual(Array.from(withDocuments.items, (item: any) => item.id), ['camera']);
  assert.deepEqual(Array.from(withDocuments.locations, (location: any) => location.id), ['floor', 'office']);
  client.state.documentFilter = 'without';
  const withoutDocuments = client.filteredHomes()[0];
  assert.deepEqual(Array.from(withoutDocuments.items, (item: any) => item.id), ['coffee', 'legacy']);
  assert.deepEqual(Array.from(withoutDocuments.locations, (location: any) => location.id), ['floor', 'kitchen']);
  assert.equal(JSON.stringify(client.state.homes), original);
  client.state.documentFilter = 'all';
  assert.equal(client.filteredHomes(), client.state.homes);
});

test('home, room and document-name matches cannot bypass the document filter', () => {
  const { client } = documentSearchFixture();
  for (const query of ['maple', 'main floor', 'receipt']) {
    client.state.search = query;
    client.state.documentFilter = 'with';
    assert.deepEqual(Array.from(client.filteredHomes()[0].items, (item: any) => item.id), ['camera']);
  }
  client.state.documentFilter = 'without';
  assert.equal(client.filteredHomes().length, 0);
  client.state.search = 'office';
  assert.equal(client.filteredHomes().length, 0);
});

test('document and flag filters intersect and return an empty result when no item qualifies', () => {
  const { client } = documentSearchFixture();
  client.state.flaggedOnly = true;
  client.state.documentFilter = 'with';
  assert.equal(client.filteredHomes().length, 0);
  client.state.documentFilter = 'without';
  assert.deepEqual(Array.from(client.filteredHomes()[0].items, (item: any) => item.id), ['coffee']);
  client.state.search = 'old lamp';
  assert.equal(client.filteredHomes().length, 0);
});

test('document filter reflects attachment addition and removal in the current saved copy', () => {
  const { client } = documentSearchFixture();
  client.state.documentFilter = 'with';
  client.state.homes[0].items[1].documents = [{ name: 'Receipt.pdf', url: 'https://example.invalid/receipt' }];
  assert.equal(client.filteredHomes()[0].items.length, 2);
  client.state.homes[0].items[0].documents = [];
  assert.deepEqual(Array.from(client.filteredHomes()[0].items, (item: any) => item.id), ['coffee']);
  client.state.homes[0].items[1].documents = [];
  assert.equal(client.filteredHomes().length, 0);
});

test('changing and clearing document filters preserves search and flags', () => {
  const { client } = documentSearchFixture();
  client.state.search = 'receipt';
  client.state.flaggedOnly = true;
  for (const value of ['with', 'without', 'all', 'invalid']) {
    client.handleInput({ target: { id: 'document-filter', value } });
    assert.equal(client.state.documentFilter, value === 'invalid' ? 'all' : value);
    assert.equal(client.state.search, 'receipt');
    assert.equal(client.state.flaggedOnly, true);
  }
});

test('document filter is reset across account changes without retaining another account inventory', () => {
  const { client } = documentSearchFixture();
  client.state.documentFilter = 'with';
  client.clearSession();
  assert.equal(client.state.documentFilter, 'all');
  client.applyAuthResponse(auth('B'));
  assert.equal(client.filteredHomes().length, 0);
  client.state.documentFilter = 'without';
  client.applyAuthResponse(auth('C'));
  assert.equal(client.state.documentFilter, 'all');
});

test('photo filtering composes with documents, search and flags and retains ancestor paths', () => {
  const { client } = documentSearchFixture();
  client.state.homes[0].items[0].photoUrls = ['photo'];
  client.state.photoFilter = 'with';
  client.state.documentFilter = 'with';
  assert.deepEqual(Array.from(client.filteredHomes()[0].items, (item: any) => item.id), ['camera']);
  assert.deepEqual(Array.from(client.filteredHomes()[0].locations, (loc: any) => loc.id), ['floor', 'office']);
  client.state.search = 'maple';
  client.state.photoFilter = 'without';
  assert.equal(client.filteredHomes().length, 0);
  client.state.documentFilter = 'all';
  client.state.flaggedOnly = true;
  assert.deepEqual(Array.from(client.filteredHomes()[0].items, (item: any) => item.id), ['coffee']);
  client.state.homes[0].items[1].photoUrls = ['new-photo'];
  assert.equal(client.filteredHomes().length, 0);
});

test('photo choices clear across accounts and do not erase other active filters', () => {
  const { client } = documentSearchFixture();
  client.state.search = 'maple'; client.state.documentFilter = 'with';
  client.handleInput({ target: { id: 'photo-filter', value: 'without' } });
  assert.equal(client.state.photoFilter, 'without');
  assert.equal(client.state.search, 'maple'); assert.equal(client.state.documentFilter, 'with');
  client.handleInput({ target: { id: 'photo-filter', value: 'invalid' } });
  assert.equal(client.state.photoFilter, 'all');
  client.state.photoFilter = 'with'; client.clearSession();
  assert.equal(client.state.photoFilter, 'all');
  client.state.photoFilter = 'without'; client.applyAuthResponse(auth('B'));
  assert.equal(client.state.photoFilter, 'all');
});

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

function itemLinkFixture() {
  const fixture = browserFixture();
  const { client, context } = fixture;
  const frames: (() => void)[] = [];
  const timers: (() => void)[] = [];
  context.requestAnimationFrame = (callback: () => void) => frames.push(callback);
  context.window.setTimeout = (callback: () => void) => timers.push(callback);
  context.document.querySelectorAll = () => [];
  const item = { id: 'item-A', name: 'Private item A', properties: [], photoUrls: [], documents: [] };
  client.applyAuthResponse(auth('A'));
  client.state.homes = [{ id: 'home-A', items: [item], locations: [] }];
  client.state.homesLoaded = true;
  client.state.pendingItemLink = { homeId: 'home-A', itemId: 'item-A' };
  return { ...fixture, frames, timers };
}

function itemCopyFixture() {
  const fixture = editorFixture();
  const focused: string[] = [];
  fixture.context.document.getElementById = (id: string) => id === 'item-editor-form' ? fixture.form
    : id === 'item-share-link' ? { focus: () => focused.push('focus'), select: () => focused.push('select') } : null;
  const copied: string[] = [];
  fixture.context.navigator = { clipboard: { writeText: async (url: string) => { copied.push(url); } } };
  const copy = () => fixture.client.handleAction({ dataset: { action: 'copy-item-link', homeId: 'home', itemId: 'item' } });
  return { ...fixture, copied, focused, copy };
}

test('copy item link uses the canonical URL and preserves unfinished editor text', async () => {
  const { client, form, copied, copy } = itemCopyFixture();
  await copy();
  assert.deepEqual(copied, ['https://cubbylog.com/items/home/item']);
  assert.equal(client.state.sheet.type, 'itemEditor');
  assert.equal(client.state.sheet.draft.name, form.elements.name.value);
  assert.equal(client.state.sheet.draft.notes, form.elements.notes.value);
  assert.equal(client.state.sheet.itemLinkStatus, 'copied');
  assert.equal(client.state.isSavingItem, false);
});

test('copied item links encode each identifier without changing the host', async () => {
  const { client, context, copied } = itemCopyFixture();
  context.document.getElementById = () => null;
  client.state.homes = [{ id: 'home /?#', items: [{ id: 'item /?#' }] }];
  client.state.sheet = { type: 'itemEditor', homeId: 'home /?#', itemId: 'item /?#' };
  await client.handleAction({ dataset: { action: 'copy-item-link', homeId: 'home /?#', itemId: 'item /?#' } });
  assert.deepEqual(copied, ['https://cubbylog.com/items/home%20%2F%3F%23/item%20%2F%3F%23']);
});

for (const failure of ['unavailable', 'denied']) {
  test(`copy item link offers selected manual-copy text when clipboard is ${failure}`, async () => {
    const { client, context, focused, form, copy } = itemCopyFixture();
    context.navigator = failure === 'unavailable' ? {} : { clipboard: { writeText: async () => { throw new Error('Denied'); } } };
    await copy();
    assert.equal(client.state.sheet.itemLinkStatus, 'manual');
    assert.equal(client.state.sheet.draft.notes, form.elements.notes.value);
    assert.deepEqual(focused, ['focus', 'select']);
    assert.equal(client.state.sheet.copyingLink, false);
  });
}

test('pending clipboard writes ignore repeat clicks and completion after switching sheets', async () => {
  const { client, context, copy } = itemCopyFixture();
  let complete!: () => void;
  let count = 0;
  context.navigator.clipboard.writeText = () => { count++; return new Promise<void>(resolve => { complete = resolve; }); };
  const pending = copy();
  await copy();
  assert.equal(count, 1);
  const nextSheet = { type: 'account' };
  client.state.sheet = nextSheet;
  complete();
  await pending;
  assert.equal(client.state.sheet, nextSheet);
  assert.equal(client.state.sheet.itemLinkStatus, undefined);
});

test('clipboard failure after sign-out does not restore the old item or link field', async () => {
  const { client, context, focused, copy } = itemCopyFixture();
  let reject!: (error: Error) => void;
  context.navigator.clipboard.writeText = () => new Promise<void>((_resolve, fail) => { reject = fail; });
  const pending = copy();
  client.clearSession();
  reject(new Error('Denied'));
  await pending;
  assert.equal(client.state.sheet, null);
  assert.deepEqual(focused, []);
});

test('copy item link ignores an item no longer in the current home', async () => {
  const { client, copied, copy } = itemCopyFixture();
  client.state.homes[0].items = [];
  await copy();
  assert.deepEqual(copied, []);
  assert.equal(client.state.sheet.itemLinkStatus, undefined);
});

test('copy serial number uses the current draft and preserves unsaved edits', async () => {
  const { client, form, copied } = itemCopyFixture();
  form.elements.serialNumber.value = '  DRAFT-0042  ';
  await client.handleAction({ dataset: { action: 'copy-item-serial', homeId: 'home', itemId: 'item' } });
  assert.deepEqual(copied, ['DRAFT-0042']);
  assert.equal(client.state.sheet.draft.serialNumber, '  DRAFT-0042  ');
  assert.equal(client.state.sheet.draft.name, form.elements.name.value);
  assert.equal(client.state.sheet.draft.notes, form.elements.notes.value);
  assert.equal(client.state.sheet.serialCopyStatus, 'copied');
  assert.equal(client.state.isSavingItem, false);
});

test('empty serial numbers do not overwrite the clipboard', async () => {
  const { client, form, copied } = itemCopyFixture();
  form.elements.serialNumber.value = '   ';
  await client.handleAction({ dataset: { action: 'copy-item-serial', homeId: 'home', itemId: 'item' } });
  assert.deepEqual(copied, []);
});

for (const failure of ['unavailable', 'denied']) {
  test(`serial copy selects the draft field when clipboard is ${failure}`, async () => {
    const { client, form, context } = itemCopyFixture();
    const focused: string[] = [];
    Object.assign(form.elements.serialNumber, {
      value: 'DRAFT-0042', focus: () => focused.push('focus'), select: () => focused.push('select'),
    });
    context.navigator = failure === 'unavailable' ? {} : { clipboard: { writeText: async () => { throw new Error('Denied'); } } };
    await client.handleAction({ dataset: { action: 'copy-item-serial', homeId: 'home', itemId: 'item' } });
    assert.equal(client.state.sheet.serialCopyStatus, 'manual');
    assert.equal(client.state.sheet.draft.notes, form.elements.notes.value);
    assert.deepEqual(focused, ['focus', 'select']);
  });
}

test('serial copy ignores repeat clicks and completion after sign-out', async () => {
  const { client, context, form } = itemCopyFixture();
  form.elements.serialNumber.value = 'DRAFT-0042';
  let reject!: (error: Error) => void;
  let count = 0;
  context.navigator.clipboard.writeText = () => { count++; return new Promise<void>((_resolve, fail) => { reject = fail; }); };
  const copy = () => client.handleAction({ dataset: { action: 'copy-item-serial', homeId: 'home', itemId: 'item' } });
  const pending = copy();
  await copy();
  assert.equal(count, 1);
  client.clearSession();
  reject(new Error('Denied'));
  await pending;
  assert.equal(client.state.sheet, null);
});

test('a shared-item link opens the current item after revealing its location', () => {
  const { client, frames, timers } = itemLinkFixture();
  client.openItemLink();
  frames.shift()!();
  client.state.homes[0].items[0].name = 'Latest item name';
  timers.shift()!();
  assert.equal(client.state.sheet.type, 'itemEditor');
  assert.equal(client.state.sheet.draft.name, 'Latest item name');
  assert.equal(client.state.highlightedItemId, '');
});

for (const stage of ['frame', 'timer']) {
  test(`a shared-item link cannot reopen old details after an account switch during its ${stage}`, () => {
    const { client, frames, timers } = itemLinkFixture();
    client.openItemLink();
    if (stage === 'timer') frames.shift()!();
    client.clearSession();
    client.applyAuthResponse(auth('B'));
    (stage === 'frame' ? frames : timers).shift()!();
    assert.equal(client.state.sheet, null);
    assert.equal(client.state.highlightedItemId, '');
    assert.equal(timers.length, 0);
  });
}

test('a shared-item link does not resurrect an item removed before its delayed editor opens', () => {
  const { client, frames, timers } = itemLinkFixture();
  client.openItemLink();
  frames.shift()!();
  client.state.homes[0].items = [];
  timers.shift()!();
  assert.equal(client.state.sheet, null);
  assert.equal(client.state.highlightedItemId, '');
});

test('new navigation cancels a shared-item reveal even when its sheet is closed again', async () => {
  const { client, frames, timers } = itemLinkFixture();
  client.openItemLink();
  frames.shift()!();
  await client.handleAction({ dataset: { action: 'open-account' } });
  await client.handleAction({ dataset: { action: 'close-sheet' } });
  timers.shift()!();
  assert.equal(client.state.sheet, null);
});

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

function transportFixture() {
  const fixture = browserFixture();
  const requests: Array<{ url: string; options: any; resolve: (value: any) => void; reject: (error: Error) => void }> = [];
  fixture.context.fetch = (url: string, options: any) => new Promise((resolve, reject) => {
    requests.push({ url, options, resolve, reject });
  });
  fixture.client.applyAuthResponse(auth('A'));
  return { ...fixture, requests };
}

const auth = (id: string, token = `token-${id}`) => ({ token, refreshToken: `refresh-${id}`, user: { id, name: id } });
const response = (body: unknown, status = 200) => ({ status, ok: status < 400, json: async () => body, text: async () => JSON.stringify(body) });
const nextTurn = () => new Promise(resolve => setImmediate(resolve));

test('an old 401 cannot refresh or retry a mutation as the next signed-in account', async () => {
  const { client, requests } = transportFixture();
  const rejected = assert.rejects(client.apiRequest('PATCH', '/homes/private-A/items/item', { name: 'Private' }), { name: 'StaleSessionError' });
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  requests[0].resolve(response({}, 401));
  await rejected;
  assert.equal(requests.length, 1);
  assert.equal(client.state.token, 'token-B');
  assert.equal(requests[0].options.headers.Authorization, 'Bearer token-A');
});

test('delayed inventory responses cannot restore signed-out private homes', async () => {
  const { client, requests, storage } = transportFixture();
  const rejected = assert.rejects(client.loadServerHomes(), { name: 'StaleSessionError' });
  requests[0].resolve(response({ plan: 'paid' }));
  requests[1].resolve(response([{ id: 'private-A' }]));
  await nextTurn();
  assert.equal(requests.length, 3);
  client.clearSession();
  requests[2].resolve(response({ id: 'private-A', name: 'Private home', items: [], locations: [] }));
  await rejected;
  assert.equal(client.state.homes.length, 0);
  assert.equal(client.state.accountPlan, null);
  assert.equal(storage.has('stuffTrackerMobileWeb.homes'), false);
});

test('a response whose body finishes after sign-out is discarded', async () => {
  const { client, requests } = transportFixture();
  let finishBody!: (value: unknown) => void;
  const rejected = assert.rejects(client.apiRequest('GET', '/homes'), { name: 'StaleSessionError' });
  requests[0].resolve({ status: 200, ok: true, json: () => new Promise(resolve => { finishBody = resolve; }) });
  await nextTurn();
  client.clearSession();
  finishBody([{ id: 'private-A' }]);
  await rejected;
});

test('a stale token refresh cannot restore an old account or clear a newer refresh', async () => {
  const { client, requests } = transportFixture();
  const rejected = assert.rejects(client.refreshAccessToken(), { name: 'StaleSessionError' });
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  const nextRefresh = client.refreshAccessToken();
  requests[0].resolve(response(auth('A', 'late-token-A')));
  await rejected;
  const sharedRefresh = client.refreshAccessToken();
  assert.equal(requests.length, 2);
  assert.equal(client.state.user.id, 'B');
  requests[1].resolve(response(auth('B', 'new-token-B')));
  assert.deepEqual(await Promise.all([nextRefresh, sharedRefresh]), [true, true]);
  assert.equal(client.state.token, 'new-token-B');
});

test('reauthenticating the same account also discards its previous refresh', async () => {
  const { client, requests } = transportFixture();
  const rejected = assert.rejects(client.refreshAccessToken(), { name: 'StaleSessionError' });
  client.applyAuthResponse(auth('A', 'new-sign-in-A'));
  requests[0].resolve(response(auth('A', 'obsolete-A')));
  await rejected;
  assert.equal(client.state.token, 'new-sign-in-A');
});

test('a temporary refresh failure preserves the session and cached inventory', async () => {
  const { client, requests } = transportFixture();
  client.state.homes = [{ id: 'home-A' }];
  const rejected = assert.rejects(client.refreshAccessToken(), /Temporarily unavailable/);
  requests[0].resolve(response({ error: 'Temporarily unavailable' }, 503));
  await rejected;
  assert.equal(client.state.token, 'token-A');
  assert.equal(client.state.refreshToken, 'refresh-A');
  assert.equal(client.state.homes[0].id, 'home-A');
});

test('same-session refresh retries with the rotated token and original mutation identity', async () => {
  const { client, requests } = transportFixture();
  const saving = client.apiRequest('PATCH', '/homes/home/items/item', { name: 'Updated' });
  requests[0].resolve(response({}, 401));
  await nextTurn();
  requests[1].resolve(response(auth('A', 'rotated-A')));
  await nextTurn();
  assert.equal(requests[2].options.headers.Authorization, 'Bearer rotated-A');
  assert.equal(requests[2].options.headers['X-CubbyLog-Mutation-ID'], requests[0].options.headers['X-CubbyLog-Mutation-ID']);
  assert.equal(requests[2].options.body, requests[0].options.body);
  requests[2].resolve(response({ name: 'Updated' }));
  assert.equal((await saving).name, 'Updated');
});

test('an earlier home refresh cannot overwrite a newer home refresh', async () => {
  const { client, requests } = transportFixture();
  const obsolete = assert.rejects(client.loadServerHomes(), { name: 'StaleSessionError' });
  const current = client.loadServerHomes();
  requests[2].resolve(response({ plan: 'paid' }));
  requests[3].resolve(response([{ id: 'latest' }]));
  await nextTurn();
  requests[4].resolve(response({ id: 'latest', name: 'Latest home' }));
  await current;
  requests[0].resolve(response({ plan: 'free' }));
  requests[1].resolve(response([{ id: 'old' }]));
  await obsolete;
  assert.equal(client.state.homes[0].name, 'Latest home');
  assert.equal(client.state.accountPlan.plan, 'paid');
  assert.equal(requests.length, 5, 'obsolete list must not start detail requests');
});

test('optimistic failure rollback cannot restore the previous account cache', async () => {
  const { client, requests, storage } = transportFixture();
  client.state.homes = [{ id: 'home-A', items: [{ id: 'item-A' }] }];
  const rejected = assert.rejects(client.setItemsFlagged('home-A', ['item-A'], true));
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  requests[0].resolve(response({}, 500));
  await rejected;
  assert.equal(client.state.homes.length, 0);
  assert.equal(storage.has('stuffTrackerMobileWeb.homes'), false);
  assert.equal(client.state.user.id, 'B');
});

test('a signed attachment upload finishing after sign-out cannot be adopted', async () => {
  const { client, requests } = transportFixture();
  const rejected = assert.rejects(client.uploadItemAttachment('home-A', 'photo', { name: 'image.png', type: 'image/png', size: 10 }), { name: 'StaleSessionError' });
  requests[0].resolve(response({ uploadUrl: 'https://uploads.invalid/test', fileUrl: 'https://files.invalid/private-A', key: 'private-A', headers: {} }));
  await nextTurn();
  assert.equal(requests[1].options.method, 'PUT');
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  requests[1].resolve(response(null, 200));
  await rejected;
  assert.equal(client.state.isUploadingAttachment, false);
});

test('an old Apple popup cannot replace a newer signed-in account', async () => {
  const { client, context, requests } = transportFixture();
  let completePopup!: (value: unknown) => void;
  client.state.appleClientId = 'qa-client';
  context.window.AppleID = { auth: {
    init: () => {},
    signIn: () => new Promise(resolve => { completePopup = resolve; }),
  } };
  const rejected = assert.rejects(client.signInWithApple(), { name: 'StaleSessionError' });
  client.applyAuthResponse(auth('B'));
  completePopup({ authorization: { id_token: 'old-apple-A' } });
  await rejected;
  assert.equal(requests.length, 0);
  assert.equal(client.state.user.id, 'B');
});

test('Google credentials from an obsolete sign-in screen are ignored', () => {
  const { client, requests } = transportFixture();
  const scope = client.sessionScope();
  client.applyAuthResponse(auth('B'));
  client.handleGoogleCredentialResponse({ credential: 'old-google-A' }, scope);
  assert.equal(requests.length, 0);
  assert.equal(client.state.user.id, 'B');
});

test('an old operation cannot clear a newer account operation loading state', async () => {
  const { client } = transportFixture();
  let finishOld!: () => void;
  let finishNew!: () => void;
  const oldWork = client.runMutation(() => new Promise<void>(resolve => { finishOld = resolve; }));
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  const newWork = client.runMutation(() => new Promise<void>(resolve => { finishNew = resolve; }));
  finishOld();
  await oldWork;
  assert.equal(client.state.isLoading, true);
  finishNew();
  await newWork;
  assert.equal(client.state.isLoading, false);
});

test('a successful sign-in still finalizes its own loading state', async () => {
  const { client } = transportFixture();
  await client.runMutation(() => client.applyAuthResponse(auth('B')));
  assert.equal(client.state.user.id, 'B');
  assert.equal(client.state.isLoading, false);
});

test('an old item save cannot dismiss or unlock a new account editor', async () => {
  const { client, form } = editorFixture();
  let finish!: () => void;
  client.setSaveHandler(() => new Promise<void>(resolve => { finish = resolve; }));
  const saving = client.submitItemEditor(form);
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  const currentSheet = { type: 'itemEditor', draft: { name: 'B draft' } };
  client.state.sheet = currentSheet;
  client.state.isSavingItem = true;
  finish();
  await saving;
  assert.equal(client.state.sheet, currentSheet);
  assert.equal(client.state.isSavingItem, true);
});

test('changing accounts clears the previous account editor and attachment state', () => {
  const { client } = editorFixture();
  client.state.isUploadingAttachment = true;
  client.state.isSavingItem = true;
  client.applyAuthResponse(auth('B'));
  assert.equal(client.state.sheet, null);
  assert.equal(client.state.isUploadingAttachment, false);
  assert.equal(client.state.isSavingItem, false);
});

function inlineAddFixture(kind = 'item') {
  const fixture = transportFixture();
  fixture.client.state.homes = [{ id: 'home-A', items: [], locations: [] }];
  fixture.client.state.adding = { kind, homeId: 'home-A', parentId: null, locationType: 'room' };
  const form = { elements: { name: { value: 'New storage ' } } };
  return { ...fixture, form };
}

for (const kind of ['home', 'location', 'item']) {
  test(`${kind} quick-add retains failed text and replays the same create after an uncertain response`, async () => {
    const { client, requests, form } = inlineAddFixture(kind);
    const saving = client.submitInlineAdd(form);
    const firstBody = requests[0].options.body;
    assert.match(JSON.parse(firstBody).client_id, /^[0-9a-f-]{36}$/);
    requests[0].reject(new TypeError('Connection interrupted'));
    await saving;
    assert.equal(client.state.adding.name, 'New storage ');
    assert.equal(client.state.adding.error, 'Connection interrupted');
    assert.equal(client.state.adding.saving, false);
    // Another refresh may change sibling ordering before retrying the same create.
    client.state.homes[0].items.push({ id: 'other', locationId: null, sortOrder: 0 });
    client.state.homes[0].locations.push({ id: 'other', parentId: null, sortOrder: 0 });
    form.elements.name.value = 'Changed after uncertain create';
    const retry = client.submitInlineAdd(form);
    assert.equal(requests[1].options.body, firstBody);
    assert.equal(client.state.adding.name, 'New storage ');
    requests[1].resolve(response({ id: JSON.parse(firstBody).client_id }));
    await nextTurn();
    requests[2].resolve(response({ isPaid: true }));
    requests[3].resolve(response([]));
    await retry;
    assert.equal(client.state.adding, null);
    assert.equal(client.state.toast, 'Added');
  });
}

test('quick-add only reloads inventory when the create was already confirmed', async () => {
  const { client, requests, form } = inlineAddFixture();
  const saving = client.submitInlineAdd(form);
  requests[0].resolve(response({ id: 'created' }));
  await nextTurn();
  requests[1].resolve(response({ isPaid: true }));
  requests[2].reject(new Error('Refresh interrupted'));
  await saving;
  assert.equal(client.state.adding.error, 'Refresh interrupted');
  assert.equal(client.state.adding.created, true);
  const retry = client.submitInlineAdd(form);
  assert.equal(requests.filter(request => request.options.method === 'POST').length, 1);
  requests[3].resolve(response({ isPaid: true }));
  requests[4].resolve(response([]));
  await retry;
  assert.equal(client.state.adding, null);
});

test('quick-add ignores duplicate submissions and cancellation while saving', async () => {
  const { client, requests, form } = inlineAddFixture();
  const saving = client.submitInlineAdd(form);
  await client.submitInlineAdd(form);
  await client.handleAction({ dataset: { action: 'cancel-add' } });
  assert.equal(requests.length, 1);
  assert.equal(client.state.adding.saving, true);
  requests[0].reject(new Error('Offline'));
  await saving;
  assert.equal(client.state.adding.saving, false);
});

test('quick-add cannot restore its failed draft into a new account', async () => {
  const { client, requests, form } = inlineAddFixture();
  const saving = client.submitInlineAdd(form);
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  client.state.adding = { kind: 'home', name: 'Account B draft', saving: true };
  requests[0].reject(new Error('Old account failure'));
  await saving;
  assert.equal(client.state.adding.name, 'Account B draft');
  assert.equal(client.state.adding.saving, true);
  assert.equal(client.state.adding.error, undefined);
});

test('a confirmed quick-add does not dismiss a different draft opened while it was saving', async () => {
  const { client, requests, form } = inlineAddFixture();
  const saving = client.submitInlineAdd(form);
  await client.handleAction({ dataset: { action: 'start-add', addKind: 'home' } });
  client.state.adding.name = 'Next home draft';
  const newerDraft = client.state.adding;
  requests[0].resolve(response({ id: 'created' }));
  await nextTurn();
  requests[1].resolve(response({ isPaid: true }));
  requests[2].resolve(response([]));
  await saving;
  assert.equal(client.state.adding, newerDraft);
  assert.equal(client.state.adding.name, 'Next home draft');
});


function renameFixture(kind = 'home') {
  const fixture = transportFixture();
  fixture.client.state.homes = [{ id: 'home-A', name: 'Home', icon: null, items: [], locations: [{ id: 'room', name: 'Room' }] }];
  fixture.client.state.sheet = { type: 'rename', kind, homeId: 'home-A', ...(kind === 'location' ? { locationId: 'room' } : {}) };
  return { ...fixture, form: { elements: { name: { value: 'Updated name ' } } } };
}

for (const kind of ['home', 'location']) {
  test(`${kind} rename retains its failed draft and can retry`, async () => {
    const { client, requests, form } = renameFixture(kind);
    const saving = client.submitRename(form);
    assert.equal(new URL(requests[0].url).pathname, kind === 'home' ? '/homes/home-A' : '/homes/home-A/locations/room');
    requests[0].reject(new Error('Offline'));
    await saving;
    assert.equal(client.state.sheet.name, 'Updated name ');
    assert.equal(client.state.sheet.error, 'Offline');
    assert.equal(client.state.sheet.saving, false);
    const retry = client.submitRename(form);
    requests[1].resolve(response({}));
    await nextTurn();
    requests[2].resolve(response({ isPaid: true }));
    requests[3].resolve(response([]));
    await retry;
    assert.equal(client.state.sheet, null);
    assert.equal(client.state.toast, 'Renamed');
  });
}

test('rename ignores duplicate submissions and closing while saving', async () => {
  const { client, requests, form } = renameFixture();
  const saving = client.submitRename(form);
  await client.submitRename(form);
  await client.handleAction({ dataset: { action: 'close-sheet' } });
  assert.equal(requests.length, 1);
  assert.equal(client.state.sheet.saving, true);
  requests[0].reject(new Error('Offline'));
  await saving;
});

test('a late rename cannot dismiss a different sheet', async () => {
  const { client, requests, form } = renameFixture();
  const saving = client.submitRename(form);
  client.state.sheet = { type: 'account' };
  requests[0].resolve(response({}));
  await nextTurn();
  requests[1].resolve(response({ isPaid: true }));
  requests[2].resolve(response([]));
  await saving;
  assert.equal(client.state.sheet.type, 'account');
});

test('an old rename failure cannot affect a new account sheet', async () => {
  const { client, requests, form } = renameFixture();
  const saving = client.submitRename(form);
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  client.state.sheet = { type: 'rename', name: 'Account B draft', saving: true };
  requests[0].reject(new Error('Account A error'));
  await saving;
  assert.equal(client.state.sheet.name, 'Account B draft');
  assert.equal(client.state.sheet.saving, true);
  assert.equal(client.state.sheet.error, undefined);
});

test('rename typing survives unrelated redraws without trimming unfinished text', () => {
  const { client, form } = renameFixture();
  client.handleInput({ target: { closest: (selector: string) => selector === '#rename-form' ? form : null } });
  assert.equal(client.state.sheet.name, 'Updated name ');
});


test('select all uses final matching items in one writable home and clears hidden selections', async () => {
  const { client } = documentSearchFixture();
  client.state.homes[0].role = 'editor';
  client.state.homes[0].items[0].photoUrls = ['photo'];
  client.state.homes.push({ ...client.state.homes[0], id: 'other-home' });
  client.state.selectionMode = true;
  client.state.search = 'travel'; client.state.documentFilter = 'with'; client.state.photoFilter = 'with';
  assert.equal(client.selectAllMatching('home-A'), true);
  assert.deepEqual(Array.from(client.state.selectedItemIds), ['camera']);
  assert.equal(client.selectAllMatching('other-home'), false);
  assert.equal(client.state.selectedHomeId, 'home-A');
  client.state.photoFilter = 'without'; client.pruneSelection();
  assert.equal(client.state.selectedItemIds.size, 0);
  client.state.photoFilter = 'all'; client.state.documentFilter = 'all'; client.state.search = '';
  client.state.flaggedOnly = true;
  client.selectAllMatching('home-A');
  assert.deepEqual(Array.from(client.state.selectedItemIds), ['coffee']);
  await client.handleAction({ dataset: { action: 'clear-selection' } });
  assert.equal(client.state.selectedItemIds.size, 0);
  assert.equal(client.state.selectionMode, true);
  client.state.homes[0].role = 'viewer';
  assert.equal(client.selectAllMatching('home-A'), false);
  assert.equal(client.state.selectedItemIds.size, 0);
});

function itemOrderFixture() {
  const fixture = browserFixture();
  fixture.client.applyAuthResponse(auth('A'));
  const homes = [{ id: 'home-A', name: 'Maple House', role: 'editor', locations: [
    { id: 'floor', name: 'Floor', type: 'floor', parentId: null },
    { id: 'room', name: 'Office', type: 'room', parentId: 'floor' },
    { id: 'box', name: 'Drawer', type: 'container', parentId: 'room' },
  ], items: [null, 'floor', 'room', 'box'].flatMap((locationId, scope) =>
    ['Zebra case', 'adapter', 'Adapter', 'Étagère'].map((name, index) => ({
      id: `${scope}-${index}`, name, locationId, sortOrder: index, quantity: 1,
      isFlagged: index === 0, properties: [], documents: [], photoUrls: [],
    })))
  }, { id: 'home-B', name: 'Other home', role: 'owner', locations: [], items: [
    { id: 'other', name: 'Other item', locationId: null, sortOrder: 9 },
  ] }];
  fixture.client.state.homes = structuredClone(homes);
  const patches: Array<{ path: string; body: any }> = [];
  const reads: string[] = [];
  fixture.context.fetch = async (url: string, options: any) => {
    const pathname = new URL(url).pathname;
    if (options.method === 'PATCH') {
      const body = JSON.parse(options.body);
      patches.push({ path: pathname, body });
      const item = homes[0].items.find(item => pathname.endsWith('/' + item.id));
      if (!item) throw new Error('Unexpected item');
      Object.assign(item, { sortOrder: body.sort_order });
      return response(item);
    }
    reads.push(pathname);
    return response(pathname === '/homes' ? homes : pathname.startsWith('/homes/')
      ? homes.find(home => pathname === `/homes/${home.id}`) : {});
  };
  return { ...fixture, homes, patches, reads };
}

test('item ordering menus disclose the full direct count and exclude viewers and single items', () => {
  const { client } = itemOrderFixture();
  client.state.search = 'Zebra';
  client.state.flaggedOnly = true;
  for (const locationId of [null, 'floor', 'room', 'box']) {
    assert.match(client.actionRowsForTarget({ homeId: 'home-A', locationId }).join(''), /Order All 4 Items by Name/);
  }
  client.state.homes[0].role = 'viewer';
  assert.doesNotMatch(client.actionRowsForTarget({ homeId: 'home-A' }).join(''), /sort-items/);
  assert.doesNotMatch(client.actionRowsForTarget({ homeId: 'home-B' }).join(''), /sort-items/);
});

test('item ordering uses direct items including hidden matches and preserves equal-name order', async () => {
  for (const [scope, locationId] of [null, 'floor', 'room', 'box'].entries()) {
    const { client, patches, homes } = itemOrderFixture();
    const otherItems = structuredClone(homes[0].items.filter(item => item.locationId !== locationId));
    client.state.search = 'Zebra';
    client.state.flaggedOnly = true;
    client.state.documentFilter = 'without';
    client.state.photoFilter = 'without';
    client.state.actionMenu = { homeId: 'home-A', locationId };
    await client.handleAction({ dataset: { action: 'sort-items' } });
    assert.deepEqual(patches.map(patch => patch.path), [1, 2, 3, 0].map(index => `/homes/home-A/items/${scope}-${index}`));
    assert.deepEqual(patches.map(patch => patch.body), [0, 1, 2, 3].map(sort_order => ({ sort_order })));
    assert.deepEqual(homes[0].items.filter(item => item.locationId !== locationId), otherItems);
    assert.equal(homes[1].items[0].sortOrder, 9);
    assert.equal(client.state.actionMenu, null);
    assert.equal(client.state.toast, 'Items ordered by name');
    assert.equal(client.state.search, 'Zebra');
    assert.equal(client.state.flaggedOnly, true);
    const originalOrder = homes[0].items.map(item => item.sortOrder);
    await client.sortItemsForTarget({ homeId: 'home-A', locationId });
    assert.deepEqual(homes[0].items.map(item => item.sortOrder), originalOrder);
  }
});

test('item ordering ignores stale locations, missing homes, viewers, and zero/one item scopes', async () => {
  const { client, patches } = itemOrderFixture();
  for (const target of [null, { homeId: 'missing' }, { homeId: 'home-A', locationId: 'deleted' }, { homeId: 'home-B' }]) {
    await client.sortItemsForTarget(target);
  }
  client.state.homes[0].role = 'viewer';
  await client.sortItemsForTarget({ homeId: 'home-A' });
  assert.equal(patches.length, 0);
});

test('partial ordering waits for late writes, refreshes actual results, and can be retried', async () => {
  const { client, context, patches, homes, reads } = itemOrderFixture();
  const request = context.fetch;
  let finishLate!: () => void;
  let first = true;
  context.fetch = async (url: string, options: any) => {
    if (options.method === 'PATCH' && first) {
      if (url.endsWith('/0-2')) throw new Error('Connection interrupted');
      if (url.endsWith('/0-0')) await new Promise<void>(resolve => { finishLate = resolve; });
    }
    return request(url, options);
  };
  const target = { homeId: 'home-A' };
  client.state.actionMenu = target;
  const pending = client.sortItemsForTarget(target);
  await nextTurn();
  assert.equal(reads.length, 0);
  assert.match(client.actionRowsForTarget(target).join(''), /Ordering Items…/);
  await client.sortItemsForTarget(target);
  assert.equal(patches.length, 2);
  finishLate();
  await pending;
  assert.match(client.state.toast, /Some items could not be ordered/);
  assert.equal(client.state.actionMenu, target);
  assert.equal(client.state.homes[0].items.find((item: any) => item.id === '0-0').sortOrder, 3);
  assert.doesNotMatch(client.actionRowsForTarget(target).join(''), /Ordering Items…/);
  first = false;
  await client.sortItemsForTarget(target);
  assert.equal(client.state.toast, 'Items ordered by name');
  assert.deepEqual(homes[0].items.slice(0, 4).map(item => item.sortOrder), [3, 0, 1, 2]);
});

test('a lost ordering refresh reports the saved result honestly and retry recovers', async () => {
  const { client, context, homes } = itemOrderFixture();
  const request = context.fetch;
  context.fetch = (url: string, options: any) => options.method === 'GET'
    ? Promise.reject(new Error('Offline')) : request(url, options);
  const target = { homeId: 'home-A', locationId: 'room' };
  client.state.actionMenu = target;
  await client.sortItemsForTarget(target);
  assert.match(client.state.toast, /Items were ordered, but could not refresh/);
  assert.equal(client.state.actionMenu, target);
  assert.deepEqual(homes[0].items.slice(8, 12).map(item => item.sortOrder), [3, 0, 1, 2]);
  context.fetch = request;
  await client.sortItemsForTarget(target);
  assert.equal(client.state.toast, 'Items ordered by name');
  assert.equal(client.state.homesLoadError, '');
});

test('late ordering completions cannot refresh or close the next account menu', async () => {
  const { client, context, reads } = itemOrderFixture();
  const request = context.fetch;
  const completions: Array<() => void> = [];
  context.fetch = async (url: string, options: any) => {
    if (options.method === 'PATCH') await new Promise<void>(resolve => completions.push(resolve));
    return request(url, options);
  };
  const pending = client.sortItemsForTarget({ homeId: 'home-A' });
  client.clearSession();
  client.applyAuthResponse(auth('B'));
  const nextMenu = { homeId: 'home-B' };
  client.state.actionMenu = nextMenu;
  completions.forEach(finish => finish());
  await pending;
  assert.equal(reads.length, 0);
  assert.equal(client.state.homes.length, 0);
  assert.equal(client.state.actionMenu, nextMenu);
  assert.notEqual(client.state.toast, 'Items ordered by name');
});
