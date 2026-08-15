import { buildPresetActions, findPreset } from './preset-scenes.js';
import { decorateEntities, resolveDevices } from './scene-device-resolver.js';

const expectedState = (service) => service === 'turn_off' ? 'off'
  : ['turn_on', 'lock'].includes(service) ? (service === 'lock' ? 'locked' : 'on') : null;

export class SceneEngine {
  constructor({ loadSnapshot, loadSettings, loadTags, callService, verifyState, saveExecution, setHomeMode }) {
    Object.assign(this, { loadSnapshot, loadSettings, loadTags, callService, verifyState, saveExecution, setHomeMode });
  }

  async run({ userId, homeId, sceneId, confirmed = false }) {
    const preset = findPreset(sceneId);
    if (!preset) throw Object.assign(new Error('Готовая сцена не найдена'), { statusCode: 404 });
    const startedAt = new Date();
    const [snapshot, settings, tags] = await Promise.all([
      this.loadSnapshot(userId), this.loadSettings(userId, sceneId), this.loadTags(userId),
    ]);
    const entities = decorateEntities(snapshot.entities, tags);
    const plan = buildPresetActions(sceneId, settings).flatMap((definition) => {
      const targets = resolveDevices(entities, definition.selector);
      if (!targets.length && !definition.optional) return [{ definition, entity: null }];
      return targets.map((entity) => ({ definition, entity }));
    });
    const results = [];
    for (const step of plan) {
      const { definition, entity } = step;
      if (!entity) {
        results.push({ status: 'skipped', reason: 'matching_devices_not_found' });
        continue;
      }
      if (!entity.available) {
        results.push({ entityId: entity.entity_id, name: entity.name, status: 'skipped', reason: 'unavailable' });
        continue;
      }
      if (entity.tags?.includes('protected') && definition.service === 'turn_off') {
        results.push({ entityId: entity.entity_id, name: entity.name, status: 'skipped', reason: 'protected' });
        continue;
      }
      if (definition.confirmation && !confirmed) {
        results.push({ entityId: entity.entity_id, name: entity.name, status: 'confirmation_required', reason: 'sensitive_action' });
        continue;
      }
      const expected = expectedState(definition.service);
      if (expected && entity.state === expected) {
        results.push({ entityId: entity.entity_id, name: entity.name, status: 'success', reason: 'already_in_state' });
        continue;
      }
      try {
        await this.callService(userId, entity.domain, definition.service, entity.entity_id, definition.data);
        const verified = expected ? await this.verifyState(userId, entity.entity_id, expected, 5000) : true;
        results.push({ entityId: entity.entity_id, name: entity.name, status: verified ? 'success' : 'failed', reason: verified ? null : 'verification_timeout' });
      } catch (error) {
        results.push({ entityId: entity.entity_id, name: entity.name, status: 'failed', reason: error.message });
      }
    }
    const successful = results.filter((item) => item.status === 'success').length;
    const failed = results.filter((item) => item.status === 'failed').length;
    const needsConfirmation = results.some((item) => item.status === 'confirmation_required');
    const status = needsConfirmation ? 'confirmation_required'
      : failed || results.some((item) => item.status === 'skipped') ? (successful ? 'partial' : 'failed') : 'success';
    const modeChanged = successful > 0 || status === 'success';
    if (modeChanged) await this.setHomeMode(userId, preset.mode);
    const report = { sceneId, name: preset.name, homeId, status, mode: modeChanged ? preset.mode : null, startedAt, finishedAt: new Date(), results };
    await this.saveExecution(userId, report);
    return report;
  }
}
