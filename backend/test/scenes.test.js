import assert from 'node:assert/strict';
import test from 'node:test';
import { SceneEngine } from '../src/scenes/scene-engine.js';

const entity = (entityId, state = 'on', extra = {}) => ({
  entity_id: entityId,
  id: entityId,
  name: entityId,
  domain: entityId.split('.')[0],
  state,
  available: true,
  attributes: {},
  capabilities: ['turn_on', 'turn_off'],
  tags: [],
  ...extra,
});

const harness = ({ entities, tags = {}, verify = true, callError = null }) => {
  const calls = [];
  const reports = [];
  const modes = [];
  const engine = new SceneEngine({
    loadSnapshot: async () => ({ rooms: [], entities }),
    loadSettings: async () => ({}),
    loadTags: async () => tags,
    callService: async (...args) => { calls.push(args); if (callError) throw callError; },
    verifyState: async () => verify,
    saveExecution: async (_, report) => reports.push(report),
    setHomeMode: async (_, mode) => modes.push(mode),
  });
  return { engine, calls, reports, modes };
};

test('away scene never switches off protected devices', async () => {
  const h = harness({
    entities: [entity('switch.fridge'), entity('light.hall')],
    tags: { 'switch.fridge': ['protected', 'high_power'] },
  });
  await h.engine.run({ userId: 'u', homeId: 'h', sceneId: 'preset_away' });
  assert.equal(h.calls.some((call) => call[3] === 'switch.fridge'), false);
  assert.equal(h.calls.some((call) => call[3] === 'light.hall'), true);
});

test('unavailable devices produce partial result without a service call', async () => {
  const h = harness({ entities: [entity('light.hall'), entity('light.kitchen', 'unavailable', { available: false })] });
  const report = await h.engine.run({ userId: 'u', homeId: 'h', sceneId: 'preset_away' });
  assert.equal(report.status, 'partial');
  assert.equal(h.calls.length, 1);
  assert.equal(report.results.find((item) => item.entityId === 'light.kitchen').reason, 'unavailable');
});

test('verification timeout is reported as a failed action', async () => {
  const h = harness({ entities: [entity('light.hall')], verify: false });
  const report = await h.engine.run({ userId: 'u', homeId: 'h', sceneId: 'preset_away' });
  assert.equal(report.status, 'failed');
  assert.equal(report.results[0].reason, 'verification_timeout');
});

test('service failure does not stop the remaining execution plan', async () => {
  let count = 0;
  const h = harness({ entities: [entity('light.one'), entity('light.two')] });
  h.engine.callService = async (...args) => { h.calls.push(args); count += 1; if (count === 1) throw new Error('offline'); };
  const report = await h.engine.run({ userId: 'u', homeId: 'h', sceneId: 'preset_away' });
  assert.equal(report.status, 'partial');
  assert.equal(h.calls.length, 2);
});

test('sensitive lock action requires explicit confirmation', async () => {
  const h = harness({ entities: [entity('light.hall'), entity('lock.front')], tags: { 'lock.front': ['entrance_lock'] } });
  const report = await h.engine.run({ userId: 'u', homeId: 'h', sceneId: 'preset_away' });
  assert.equal(report.results.find((item) => item.entityId === 'lock.front').status, 'confirmation_required');
  assert.equal(h.calls.some((call) => call[3] === 'lock.front'), false);
});

test('vacation scene succeeds when optional lock and climate are absent', async () => {
  const h = harness({ entities: [entity('light.hall')] });
  const report = await h.engine.run({ userId: 'u', homeId: 'h', sceneId: 'preset_vacation', confirmed: true });
  assert.equal(report.status, 'success');
  assert.deepEqual(h.modes, ['VACATION']);
});
