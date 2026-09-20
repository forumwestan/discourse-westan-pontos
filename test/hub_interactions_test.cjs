const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const source = fs.readFileSync(path.join(__dirname, '../assets/javascripts/discourse/components/westan-points/hub.gjs'), 'utf8');
const code = source.split('<template>')[0].replace(/^import .*;$/gm, '').replace(/@(?:tracked|action|service)\s*/g, '').replace('export default class WestanPointsHub', 'this.Hub = class WestanPointsHub') + '}';
let requests = [], transport, search;
const context = vm.createContext({
  Component: class { constructor(args) { this.args = args; } willDestroy() {} },
  crypto: { randomUUID }, Intl, console,
  ajax: async (...args) => { requests.push(args); return transport(...args); },
  userSearch: (...args) => search(...args),
  extractError: error => error.jqXHR?.responseJSON?.errors?.join(' ') || error.message,
  popupAjaxError: () => { throw new Error('Unexpected popup'); },
  window: { confirm: () => { throw new Error('Transfer must not use window.confirm'); } },
});
vm.runInContext(code, context);
const member = { id: 2, username: 'Andreza', name: 'Andreza', avatar_template: '/avatar/{size}.png' };
const event = { preventDefault() {} };
function hub() {
  const instance = new context.Hub({ model: { wallet: { balance: 100 } } });
  instance.currentUser = { id: 1, username: 'Igor', admin: true };
  instance.transferDraft = { username: 'Andreza', amount: '20', description: ' Obrigado! ' };
  instance.selectedRecipient = member;
  requests = [];
  return instance;
}

(async () => {
  let instance = hub();
  instance.submitTransfer(event);
  assert.equal(instance.transferStep, 'review');
  assert.equal(requests.length, 0, 'review must never send points');
  assert.equal(instance.reviewedTransfer.description, 'Obrigado!');
  instance.cancelTransfer();
  assert.equal(instance.transferStep, 'form');
  assert.equal(instance.transferDraft.amount, '20');
  instance.selectedRecipient = null;
  instance.submitTransfer(event);
  assert.equal(instance.transferStep, 'form');
  assert.match(instance.transferMessage, /Selecione/);

  instance = hub();
  instance.submitTransfer(event);
  let resolvePost;
  transport = (url) => url.endsWith('/transfer') ? new Promise(resolve => { resolvePost = resolve; }) : { wallet: { balance: 80 } };
  const sending = instance.confirmTransfer();
  await instance.confirmTransfer();
  assert.equal(requests.length, 1, 'double click must not issue two POSTs');
  resolvePost({ wallet: { balance: 80 } });
  await sending;
  assert.equal(instance.transferStep, 'success');
  assert.equal(instance.wallet.balance, 80);
  instance.newTransfer();
  assert.equal(instance.transferStep, 'form');
  assert.equal(instance.selectedRecipient, null);

  instance = hub();
  instance.submitTransfer(event);
  transport = () => { throw { jqXHR: { status: 0 } }; };
  await instance.confirmTransfer();
  const key = requests[0][1].data.request_id;
  assert.equal(instance.transferStep, 'error');
  assert.equal(instance.transferUncertain, true);
  instance.cancelTransfer();
  assert.equal(instance.transferStep, 'error', 'unknown outcome must be retried with same request id');
  transport = url => url.endsWith('/transfer') ? { wallet: { balance: 80 } } : { wallet: { balance: 80 } };
  await instance.confirmTransfer();
  assert.equal(requests[1][1].data.request_id, key);
  assert.equal(instance.transferStep, 'success');

  instance = hub();
  instance.submitTransfer(event);
  transport = url => { if (url.endsWith('/transfer')) return { wallet: { balance: 80 } }; throw new Error('history offline'); };
  await instance.confirmTransfer();
  assert.equal(instance.transferStep, 'success', 'history refresh failure must not negate completed transfer');
  assert.match(instance.transferRefreshWarning, /concluída/);

  instance = hub();
  instance.submitTransfer(event);
  transport = () => { throw { jqXHR: { status: 422, responseJSON: { errors: ['Saldo insuficiente.'] } } }; };
  await instance.confirmTransfer();
  assert.equal(instance.transferMessage, 'Saldo insuficiente.');
  assert.equal(instance.transferUncertain, false);
  instance.cancelTransfer();
  assert.equal(instance.transferStep, 'form');

  instance = hub();
  const pending = {};
  search = ({term}) => new Promise(resolve => { pending[term] = resolve; });
  const first = instance.searchRecipients('An');
  const second = instance.searchRecipients('Nar');
  pending.Nar([{ id: 3, username: 'Naruto' }, {id:1,username:'Igor'}]);
  await second;
  pending.An([member]);
  await first;
  assert.equal(instance.recipientResults.length, 1);
  assert.equal(instance.recipientResults[0].username, 'Naruto', 'stale searches must not replace newer results');
  instance.recipientKeydown({ key: 'Enter', preventDefault() {} });
  assert.equal(instance.selectedRecipient.username, 'Naruto');
  assert.equal(instance.recipientSearchOpen, false);
  instance.updateTransfer({ target: {dataset:{field:'username'},value:''} });
  assert.equal(instance.selectedRecipient, null);

  instance = new context.Hub({ model: { can_manage: true, admin: { rewards: [] } }, configMode: true });
  instance.currentUser = { admin: true };
  transport = () => ({ can_manage: true, admin: { rewards: [] } });
  await instance.refresh();
  assert.equal(requests.at(-1)[0], '/westan/pontos/admin/config');
  assert.equal(instance.isConfigPage, true);
  instance.currentUser = {};
  assert.equal(instance.isConfigPage, false);
  console.log('PASS: inline review/cancel/success/error, selection, stale search, double-click, idempotent retry, refresh failure and config access.');
})().catch(error => { console.error(error); process.exitCode = 1; });
