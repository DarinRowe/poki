import { flagOn } from './element-flags.mjs';
import { checkWork, deadline } from './work.mjs';

const normalize = value => (value ?? '').normalize('NFKC').trim().toLocaleLowerCase();
const role = element => (element.role ?? element.type ?? '').replace(/^(?:XCUIElementType|AX)/i, '').toLowerCase();
const named = (element, label) => [element.label, element.text].some(value => normalize(value) === label);
const usable = element => flagOn(element.visible) && flagOn(element.enabled);
const foregroundKey = seen => seen.foreground?.bundle_id || seen.foreground?.pid || null;

async function observe(ctx) {
  try {
    await ctx.settle();
    const seen = await deadline(4500, () => ctx.structure(0));
    return { ...seen, elements: seen.elements.filter(usable) };
  } catch (error) {
    checkWork();
    if (error.name === 'AbortError') throw error;
    return { elements: [] };
  }
}

function percentage(value) {
  if (typeof value !== 'string') return undefined;
  const match = value.normalize('NFKC').trim().match(/^(\d+(?:[.,]\d+)?)\s*[%٪]$/u);
  const percent = match && Number(match[1].replace(',', '.'));
  return match && percent <= 100 ? percent : undefined;
}

function result(reason, instruction, extra = {}) {
  return { isError: true, reason, instruction, sent: false, outcome: 'not_sent', ...extra };
}

function sliderOf(seen, label) {
  const matches = seen.elements.filter(element => named(element, label) &&
    (['slider', 'adjustable'].includes(role(element)) || element.trait_names?.includes('Adjustable')));
  return matches.length === 1 ? matches[0] : undefined;
}

function sliderPoint(box, axis, percent) {
  const inset = Math.min(4, (axis === 'vertical' ? box.height : box.width) / 8);
  const fraction = percent / 100;
  return axis === 'vertical'
    ? { x: box.x + box.width / 2, y: box.y + box.height - inset - fraction * (box.height - 2 * inset) }
    : { x: box.x + inset + (axis === 'right_to_left' ? 1 - fraction : fraction) * (box.width - 2 * inset), y: box.y + box.height / 2 };
}

export async function setSlider(ctx, args, blocked) {
  const label = normalize(args.text);
  if (!label) throw new Error('Provide the exact visible accessibility label of the slider.');
  const before = await observe(ctx);
  if (blocked(before)) return result('blocking_overlay', 'Resolve the overlay before adjusting the slider.');
  const slider = sliderOf(before, label);
  const initial = percentage(slider?.value);
  if (initial === undefined) return result('slider_unconfirmed', 'Find one visible adjustable control with this label and a readable percentage. Expand the control if necessary.');
  let value = initial;
  let sent = false;
  let seen = before;
  const requested = args.percent;
  const receipt = () => ({ sent, requested_percent: requested, previous_percent: initial, actual_percent: value });
  // Float reporting and coarse device steps can round the measured value.
  const tolerance = args.tolerance ?? 3;
  for (let attempt = 0; attempt < 2 && Math.abs(value - requested) > tolerance; attempt++) {
    checkWork();
    const current = sliderOf(seen, label);
    const box = current.frame ?? current;
    if (![box.x, box.y, box.width, box.height].every(Number.isFinite) || box.width < 8 || box.height < 8) break;
    const axis = args.axis ?? (box.height > box.width ? 'vertical' : 'left_to_right');
    let point = percent => sliderPoint(box, axis, percent);
    if (args.track) {
      const { min, max } = args.track;
      const inside = ({ x, y }) => x >= box.x && x <= box.x + box.width && y >= box.y && y <= box.y + box.height;
      if (!inside(min) || !inside(max) || Math.hypot(max.x - min.x, max.y - min.y) < 8 ||
          (attempt && ['x', 'y', 'width', 'height'].some(key => box[key] !== (slider.frame ?? slider)[key]))) {
        if (sent) break;
        return result('slider_track_outside_control', 'Measure both ends of the actual track inside the current slider frame.');
      }
      point = percent => ({ x: min.x + (max.x - min.x) * percent / 100, y: min.y + (max.y - min.y) * percent / 100 });
    }
    const start = point(value), end = point(requested);
    const input = await ctx.input({ op: 'drag', x1: start.x, y1: start.y, x2: end.x, y2: end.y, duration_ms: 350, hold_ms: 180 }, seen);
    if (input.isError || input.stopped || input.sent !== true) return { ...input, sent: sent || input.sent === true, actual_percent: value, value_verified: false };
    sent = true;
    const after = await observe(ctx), found = sliderOf(after, label);
    const observed = percentage(found?.value);
    if (foregroundKey(after) !== foregroundKey(before) || blocked(after) ||
        (slider.object_id && found?.object_id && slider.object_id !== found.object_id) || observed === undefined) {
      return result('slider_readback_unavailable', 'The drag was sent. Inspect the current slider before trying again.',
        { ...receipt(), actual_percent: undefined, value_verified: false, outcome: 'unknown' });
    }
    const improved = Math.abs(observed - requested) < Math.abs(value - requested);
    value = observed;
    seen = after;
    if (!improved) break;
  }
  if (Math.abs(value - requested) <= tolerance) return { ...receipt(), value_verified: true, ...(sent ? {} : { already_set: true }) };
  return result('slider_value_not_reached', 'Inspect the observed value before trying again.',
    { ...receipt(), outcome: sent ? 'partial' : 'not_sent', value_verified: false });
}

function galleryOf(seen) {
  // The gallery exposes its own blank system application root and both a sheet and search field.
  // An app with a search page must never qualify.
  const root = seen.elements.find(element => role(element) === 'application');
  const system = seen.foreground?.bundle_id === 'com.apple.springboard' ||
    (!seen.foreground?.bundle_id && seen.foreground?.pid && root && !normalize(root.label));
  const search = seen.elements.filter(element => role(element) === 'searchfield');
  const sheet = seen.elements.some(element => ['sheet', 'dialog'].includes(role(element)) ||
    role(element) === 'button' && ['sheet grabber', '工作表抓取条', '工作表抓取條'].includes(normalize(element.label)));
  const controls = seen.elements.filter(element => role(element) === 'button' &&
    ['control', '控件', '控制项', '控制項'].includes(normalize(element.value)));
  return system && search.length === 1 && (sheet || controls.length) ? { controls } : undefined;
}

export async function addControl(ctx, args, fill) {
  const label = normalize(args.text);
  if (!label) throw new Error('Provide the exact visible name of the control to add.');
  let seen = await observe(ctx), gallery = galleryOf(seen);
  if (!gallery) return result('control_gallery_unconfirmed', 'Open Control Center editing and choose Add a Control, then retry from the gallery.');
  let matches = gallery.controls.filter(control => named(control, label));
  if (!matches.length) {
    const typed = await fill({ text: args.text, submit: false });
    if (typed.isError || typed.stopped || typed.text_verified !== true) return result('gallery_search_unverified',
      'The control search could not be verified. Inspect the gallery before selecting a result.', { search_sent: typed.sent === true });
    seen = await observe(ctx);
    gallery = galleryOf(seen);
    matches = gallery?.controls.filter(control => named(control, label)) ?? [];
  }
  if (matches.length !== 1) return result('control_not_unique', 'Select one exact control from the visible gallery results.');
  const box = matches[0].frame ?? matches[0];
  if (![box.x, box.y, box.width, box.height].every(Number.isFinite) || box.width <= 0 || box.height <= 0)
    return result('control_position_unavailable', 'Observe the visible control before trying again.');
  const input = await ctx.input({ op: 'tap', x: box.x + box.width / 2, y: box.y + box.height / 2, duration_ms: 50 }, seen);
  if (input.isError || input.stopped || input.sent !== true) return input;
  const after = await observe(ctx);
  const installed = !galleryOf(after) && foregroundKey(after) === foregroundKey(seen) &&
    after.elements.some(element => role(element) === 'button' && named(element, label));
  if (installed) return { sent: true, added: true, verified: true };
  return result('control_add_unverified', 'The selection was sent. Check the Control Center layout before trying again.',
    { sent: true, verified: false, outcome: 'unknown' });
}
