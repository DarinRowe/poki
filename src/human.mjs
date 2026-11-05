import { execute } from './work.mjs';

// A real macOS dialog is the acknowledgment. A successful notification alone is not.
export async function askHuman(message, seconds = 120) {
    const script = `on run argv
      set promptText to item 1 of argv
      set waitSeconds to (item 2 of argv) as integer
      try
        set response to display dialog promptText with title "Poki MCP" buttons {"取消", "确认"} default button "确认" cancel button "取消" giving up after waitSeconds
        if gave up of response then return "timeout"
        if button returned of response is "确认" then return "done"
        return "cancelled"
      on error number -128
        return "cancelled"
      end try
    end run`;
    const { stdout } = await execute('osascript', ['-e', script, '--', message, String(Math.ceil(seconds))], { timeout: (seconds + 10) * 1000 });
    const status = stdout.trim();
    return { status, completed: status === 'done', message: status === 'done' ? 'The user confirmed the dialog. Inspect the device before continuing.' : 'The user did not confirm completion.' };
}
