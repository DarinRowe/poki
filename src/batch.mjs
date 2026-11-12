import { checkWork, phase, stopped, stoppingReason } from './work.mjs';
import { managementTools } from './coordination.mjs';
import { definitions } from './tools.mjs';
import { closestTo } from './interaction.mjs';
import { flagOn } from './element-flags.mjs';

const json = value => ({ type: 'text', text: JSON.stringify(value) });
const receipt = value => ({ type: 'text', text: JSON.stringify(value, null, 2) });
export const offDevice = new Set(['wait', 'list_devices', 'poki_mcp_status', 'request_human_action']);
export const changesDevice = new Set(['select_device', 'start_simulator', 'shut_down_simulator']);
// Clients show tools under a prefixed name, and models copy it into a step.
export const stepTool = tool => tool.replace(/^mcp__poki-mcp__/, '');
// A step's stop_reason that ends the run, for batch_commands and run_code alike. An ordinary error
// and a touch with no observed change are left to the caller: stop_on_error, or the script.
export const stopsRun = reason => Boolean(reason) && reason !== 'error' && reason !== 'no_change';

export function invalidStep(command) {
  if (command.tool === 'batch_commands' || command.tool === 'run_code') return 'Nested batches are not supported, and neither is run_code.';
  if (managementTools.has(command.tool)) return 'Call device management tools outside a batch.';
  const definition = definitions.find(([name]) => name === command.tool);
  if (!definition) {
    const closest = closestTo(command.tool, definitions.map(([name]) => name));
    return `Unknown tool: ${command.tool}.${closest.length ? ` Did you mean ${closest.join(', ')}?` : ''}`;
  }
  const schema = definition[2], parsed = schema.safeParse(command.arguments ?? {});
  if (parsed.success) return null;
  const issues = parsed.error.issues.map(issue => `${issue.path.join('.') || 'arguments'}: ${issue.message}`).join('; ');
  return `Invalid arguments for ${command.tool}: ${issues}. It accepts: ${Object.keys(schema.shape ?? {}).join(', ')}.`;
}

function actionReceipt(result) {
  const block = result.content.find(item => item.type === 'text');
  try { return JSON.parse(block?.text) ?? {}; } catch { return {}; }
}

function advice(reason, step, outcome) {
  const earlier = step > 1 ? `Steps 1-${step - 1} already ran; do not repeat them.` : 'No earlier step ran.';
  if (outcome === 'not_sent') return `${earlier} Fix step ${step} using the current screen and continue with the unattempted steps.`;
  if (reason === 'no_change') return `${earlier} Step ${step} was sent and no change was observed. Verify its effect before deciding whether to retry it or continue with the unattempted steps.`;
  return `${earlier} Verify what step ${step} actually did before deciding whether to retry it or continue with the unattempted steps.`;
}

// A batch is one queued operation, so its steps share a device lookup. A touch is compared with the
// screen before it when a later step depends on that (see Devices.checksStep); the screen itself is
// read back once, after the last step.
export async function runBatch(ctx, args) {
  const commands = args.commands.map(command => {
    const tool = stepTool(command.tool);
    const supportsVerification = definitions.find(([name]) => name === tool)?.[2].shape?.verify;
    return { ...command, tool, ...(args.verify === false && supportsVerification ? { arguments: { verify: false, ...command.arguments } } : {}) };
  });
  const unverified = commands.some(command => command.arguments?.verify === false);
  const stopOnError = args.stop_on_error !== false;
  const invalid = stopOnError ? commands.findIndex(invalidStep) : -1;
  if (invalid >= 0) {
    const error = invalidStep(commands[invalid]);
    return { isError: true, content: [json({ step: invalid + 1, tool: commands[invalid].tool, isError: true, elapsed_ms: 0 }), { type: 'text', text: error }, receipt({ completed_steps: 0, stop_reason: 'error', failed_step: { step: invalid + 1, ...commands[invalid], error }, remaining_steps: commands, recovery: { outcome: 'not_started', step: invalid + 1, unattempted_steps: commands }, next: 'Nothing ran. Fix the failed step and send the whole batch again.' })] };
  }
  const blocks = [];
  let stopReason, failed = false, ran = 0, failure, failureOutcome, unchanged, finalInput;
  ctx.inBatch = true;
  try {
    for (const [index, command] of commands.entries()) {
      const started = performance.now();
      ctx.batchStep = { next: commands[index + 1], stopOnError };
      let result, dispatchStarted = false;
      const previousInput = ctx.lastInputAt;
      try {
        checkWork();
        const problem = invalidStep(command);
        if (problem) throw new Error(problem);
        dispatchStarted = true;
        result = await ctx.dispatch(command.tool, command.arguments ?? {});
      } catch (error) {
        result = { isError: true, content: [{ type: 'text', text: error.message }] };
        if (stopped(error)) stopReason = stoppingReason(error);
      }
      ran++;
      blocks.push(json({ step: ran, tool: command.tool, isError: Boolean(result.isError), elapsed_ms: Math.round(performance.now() - started) }), ...result.content);
      // A fill that typed the wrong text is an ordinary failure: stop_on_error decides, not this block.
      // A touch with no observed change may still have worked. The batch pauses only to hold back the steps
      // written for the screen it should produce, so with none left, or when the caller allows it, it goes on.
      const reason = result._meta?.stop_reason;
      const data = actionReceipt(result);
      const inputOccurred = ctx.lastInputAt !== previousInput;
      finalInput = !result.isError && inputOccurred && data.sent === true && data.outcome !== 'unknown' &&
        (args.return_observation === true || command.arguments?.return_observation === true);
      if (reason === 'no_change') { if (stopOnError && ran < commands.length) { stopReason = reason; unchanged = { step: ran, ...command }; } }
      else if (stopsRun(reason)) stopReason = reason;
      if (result.isError) {
        failed = true;
        const selectorRefused = !inputOccurred && ['fill', 'tap_text'].includes(command.tool) &&
          /No visible element matches|Requested field is not visible/.test(result.content[0]?.text ?? '');
        failureOutcome = data.outcome === 'unknown' || reason === 'unknown' ? 'verify' :
          !dispatchStarted || data.outcome === 'not_sent' || data.sent === false || selectorRefused ? 'not_sent' : 'verify';
        failure = { step: ran, ...command, error: result.content.find(block => block.type === 'text')?.text };
        if (!stopReason && stopOnError) stopReason = 'error';
      } else failure = undefined;
      if (stopReason) break;
      if (changesDevice.has(command.tool)) ctx.resolved = undefined;
    }
  } finally { ctx.inBatch = false; ctx.batchStep = undefined; }
  const summary = unverified ? { verified: false } : {};
  // Reading a simulator that a step just shut down would boot it again.
  const last = commands.slice(0, ran).findLast(command => !offDevice.has(command.tool));
  if (last && last.tool !== 'shut_down_simulator') {
    // dispatch restores both when this batch ends.
    if (last.arguments?.device) { ctx.requested = last.arguments.device; ctx.resolved = undefined; }
    const structured = finalInput && !stopReason && !failed && last === commands[ran - 1];
    const { screen, stop_reason, receipt_id, input_completed_at, post_action_observation } = await phase('batch_readback',
      () => ctx.readback(undefined, { once: unverified && !structured, structured }));
    stopReason ??= stop_reason;
    summary.screen = screen;
    if (!stopReason && post_action_observation) Object.assign(summary, {
      sent: true, receipt_id, input_completed_at, post_action_observation,
    });
  }
  if (stopReason) {
    if (failure) {
      const unattempted = commands.slice(ran);
      Object.assign(summary, { failed_step: failure,
        remaining_steps: stopReason === 'unknown' ? unattempted : commands.slice(failure.step - 1),
        recovery: { outcome: failureOutcome, step: failure.step, unattempted_steps: unattempted },
        next: advice(stopReason, failure.step, failureOutcome) });
      if (failureOutcome === 'not_sent' && stopReason === 'error' && failure.tool === 'fill' &&
          summary.screen?.source === 'accessibility' && !summary.screen.stale && !summary.screen.partial && !summary.screen.prompt &&
          /No visible element matches|Requested field is not visible/.test(failure.error ?? '')) {
        const fields = (ctx.seen?.elements ?? []).filter(element => flagOn(element.visible) && /^(?:AX|XCUIElementType)?(?:Secure)?(?:TextField|TextArea|TextView|SearchField)$/i.test(element.type ?? element.role ?? ''))
          .map(element => element.identifier || element.label || element.placeholder);
        if (fields.length === 1 && fields[0]) {
          const { field: _field, ref: _ref, x: _x, y: _y, ...rest } = failure.arguments ?? {};
          summary.next_commands = [{ tool: 'fill', arguments: { ...rest, field: fields[0] } }, ...commands.slice(failure.step)];
          summary.next = `The current visible text field is ${JSON.stringify(fields[0])}. If this is the intended field, run next_commands with that exact label. No text was entered by the failed fill. Earlier completed steps, including launch_app, need not run again.`;
        }
      }
    }
    else if (unchanged) Object.assign(summary, { unchanged_step: unchanged, remaining_steps: commands.slice(ran),
      recovery: { outcome: 'verify', step: ran, unattempted_steps: commands.slice(ran) }, next: advice(stopReason, ran, 'verify') });
    else Object.assign(summary, { remaining_steps: commands.slice(ran), next: `Work stopped (${stopReason}). Check the current screen before continuing.` });
  }
  return { ...(failed || stopReason ? { isError: true } : {}), content: [...blocks, receipt({ completed_steps: ran, stop_reason: stopReason ?? null, ...summary })] };
}
