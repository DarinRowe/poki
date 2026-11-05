import { screenIdentity } from '../src/screen-identity.mjs';

const MAX_SCROLL_STEP_MILLISECONDS = 180_000;

export class StepDeadline {
  constructor(seconds, expired, record = () => {}) {
    if (!Number.isFinite(seconds) || seconds <= 0 || seconds > 2147483) throw new Error('Step timeout must be a positive number of seconds.');
    this.seconds = seconds;
    this.expired = expired;
    this.record = record;
    this.step = 0;
  }

  start(reason = 'start') {
    if (this.ended || this.suspended) return;
    const elapsed = this.startedAt === undefined ? 0 : Date.now() - this.startedAt;
    this.scrollRemainingMilliseconds = reason === 'scroll_progress'
      ? this.scrollRemainingMilliseconds - elapsed : MAX_SCROLL_STEP_MILLISECONDS;
    this.recordElapsed(reason);
    this.remainingMilliseconds = reason === 'scroll_progress'
      ? Math.min(this.seconds * 1000, this.scrollRemainingMilliseconds) : this.seconds * 1000;
    this.resume();
  }

  suspend() {
    if (this.ended || this.suspended) return;
    this.remainingMilliseconds -= Date.now() - this.startedAt;
    this.scrollRemainingMilliseconds -= Date.now() - this.startedAt;
    this.recordElapsed('answer_submitted');
    this.suspended = true;
    clearTimeout(this.timer);
  }

  resume() {
    if (this.ended) return;
    this.suspended = false;
    this.startedAt = Date.now();
    clearTimeout(this.timer);
    this.timer = setTimeout(() => { this.recordElapsed('timeout'); this.ended = true; this.expired(); }, Math.max(0, this.remainingMilliseconds));
  }

  advance(step) {
    if (this.ended || step <= this.step) return;
    this.start('step_advanced');
    this.step = step;
  }

  observe(receipt, action) {
    if (this.ended) return false;
    let observed = false;
    if (['scroll', 'swipe'].includes(action?.tool) && changedScroll(receipt)) {
      this.start('scroll_progress');
      observed = true;
    }
    for (const screen of screens(receipt)) {
      const page = screenIdentity(screen);
      if (!page) continue;
      if (this.page && page.id !== this.page && navigates(action)) this.start('new_page');
      this.page = page.id;
      this.pageTitle = page.title;
      observed = true;
    }
    return observed;
  }

  recordElapsed(reason) {
    if (this.startedAt === undefined) return;
    this.record({ step: this.step, page: this.pageTitle ?? null, startedAt: new Date(this.startedAt).toISOString(), endedAt: new Date().toISOString(), elapsedMilliseconds: Date.now() - this.startedAt, endReason: reason });
    this.startedAt = undefined;
  }

  stop() { this.recordElapsed('task_finished'); this.ended = true; clearTimeout(this.timer); }
}

function changedScroll(receipt) {
  if (!receipt || receipt.isError || receipt.stopped) return false;
  if (Array.isArray(receipt.content)) return receipt.content.some(item => {
    if (item.type !== 'text') return false;
    try { return changedScroll(JSON.parse(item.text)); } catch { return false; }
  });
  return receipt.sent === true && receipt.screen_change_verified === true && receipt.screen_changed === true;
}

function navigates(action) {
  if (!action) return false;
  if (action.tool === 'batch_commands') return navigates(action.arguments.commands.findLast(command =>
    !['poki_mcp_status', 'get_foreground_app', 'list_apps', 'take_screenshot', 'observe_device', 'list_elements'].includes(command.tool)));
  if (['fill', 'type_text'].includes(action.tool)) return action.arguments?.submit === true;
  if (action.tool === 'press_key') return ['return', 'enter'].includes(action.arguments?.key);
  return ['launch_app', 'tap', 'tap_text', 'go_back'].includes(action.tool);
}

function screens(receipt) {
  if (!receipt || typeof receipt !== 'object') return [];
  if (Array.isArray(receipt.content)) return receipt.content.flatMap(item => {
    if (item.type !== 'text') return [];
    try { return screens(JSON.parse(item.text)); } catch { return []; }
  });
  if (receipt.screen) return screens(receipt.screen);
  return Array.isArray(receipt.elements) || Array.isArray(receipt.text) ? [receipt] : [];
}
