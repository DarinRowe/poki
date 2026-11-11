# Poki keyboard (typing panel)

Poki bundles a keyboard extension that only Poki types through. It is **not a keyboard
for people**: it has no keys. While Poki types it shows "Poki is typing…", a progress
bar and a **Take Over** button; otherwise it shows a short note and **Switch Keyboard**.
The panel is plain SwiftUI on the system keyboard background (glass buttons on iOS 26
and later, bordered buttons on iOS 18), with the system globe key where iOS asks for one.

It is used on the native-services path (no XCTest runner, no automation indicator).
When the panel cannot be used, Poki types plain text with key presses. It pastes only
when the owner has chosen Paste in Advanced.

## Set it up

Poki → Setup lists **Add the Poki Keyboard** with the steps and whether it has answered:

1. Settings → General → Keyboard → Keyboards → Add New Keyboard → **Poki**.
2. Tap Poki in that list and turn on **Allow Full Access**.
3. Keep your usual keyboards, and switch to the Poki keyboard once in any text field.

Full Access is what lets the extension reach the App Group folder it shares with Poki.
The extension has no network code and never touches the clipboard.

## How a `type` goes

1. Poki writes the request (text, clear, hidden) to the shared folder and posts a
   Darwin notification.
2. If the panel is the keyboard in use, it takes the request by renaming the file (so
   only one side can ever own it), writes an acknowledgement, and types.
3. If nothing acknowledges, Poki presses the hardware input-source shortcut (Ctrl+Space)
   on its simulated keyboard, once per installed keyboard at most, and stops at the first
   acknowledgement. iOS hides the on-screen keyboard while a hardware keyboard is attached,
   so after each press the simulated keyboard is also taken away for up to about two
   seconds, long enough for the extension to start cold. **Nothing on the screen is read
   to do this**: the acknowledgement is the only signal. The number of presses that worked
   is remembered and tried in one go next time. A switch that fails is remembered for that
   app for ten minutes, and one more press completes the circle back to the owner's keyboard.
4. If there is still no acknowledgement, Poki withdraws the request (the same rename).
   Plain text (what hardware keys can type) is then typed with key presses. Other text,
   such as Chinese or emoji, is **not entered**, and the answer says why the keyboard was
   not used; the same reason shows on the Setup page. Nothing is pasted unless the owner
   chose Paste (below). A request the panel has taken is never typed again by anything else.
5. The panel types at a person's pace: Latin text a key at a time with longer gaps at
   word starts, Chinese a word at a time, long text faster. It checks its own work from
   the text around the cursor and reports `matched`, `mismatch` or `unknown`. Poki does
   **not** read the screen before or after: no focus wait, no read-back.
6. When the action list ends, Poki asks the panel to leave, and it hands the field back
   to the previous keyboard (**Switch back when finished**). Opened by hand, it leaves
   on its own after a few seconds.

Passwords: a secure field never shows a third-party keyboard, so those are typed with
key presses as before. When a secure field is anywhere on screen the panel's report
carries no text.

## Stopping it

- **Take Over** stops the typing, and Poki pauses for the owner (the same owner-only
  pause as before: the agent cannot dismiss it). The answer is `poki user takeover`.
- Switching keyboards or leaving the field mid-text stops the typing. The answer is
  `poki typing stopped`, delivery unknown: the text is never typed a second time, and
  the agent reads the screen to see what is there.
- A Return that submits the field ends the typing normally. It is not a takeover.

## Settings

Setup → Advanced → Typing:

| Setting | Default | Meaning |
| --- | --- | --- |
| Text Entry | Poki Keyboard | **Poki Keyboard**: as above, never the clipboard. **Paste**: key presses, with a paste for what the keys cannot type (the clipboard is saved and put back); the Poki keyboard is not used, and only then do the clipboard endpoints answer. |
| Switch to It Automatically | on | Step 3 above. Off: the panel is used only when it is already the keyboard in use. |
| Switch Back When Finished | on | Step 6 above. |
| System Pinyin Keyboard for Chinese | off | The earlier engine ([native-ime-testing.md](native-ime-testing.md)). Slower, and it reads the screen while typing. Used only when the panel declines. |

Hold the **Typing** heading for three seconds to show the experimental
**Create routines from user demonstrations** switch (off by default).

## How it is built

- `native/ios-app/KeyboardShared` is the shared code: the mailbox (`KeyboardLink`) and
  the typing itself (`KeyboardTyper`, `KeyboardTypist`). It is a Swift package so its
  tests run on Linux (`swift test` in that folder); the app and the extension compile
  the same sources.
- The mailbox uses atomic file renames only. There are **no file locks**: a lock held
  on a shared-container file when the extension is suspended gets it killed by iOS
  (`0xdead10cc`). Only the extension writes `status.json`.
- `PokiKeyboard/` is the extension: `KeyboardViewController` (the mailbox, the text
  proxy) and `KeyboardPanel` (the SwiftUI view).
- `Poki/Runtime/PokiKeyboardTyping.swift` is the app side; `NativeServicesWDA` answers
  `POST /wda/keys` with `keyboard: true` through it, and PokiCore asks for it when the
  transport says `typesThroughKeyboard`.

## Not yet checked on a device

- That Ctrl+Space from the simulated hardware keyboard reaches a third-party keyboard in
  the rotation on every iOS version. When it does not, the answer says the keyboard did
  not come up.
- That iOS reports the added keyboards to the app (`AppleKeyboards`). When it does not,
  Poki asks the panel only after it has answered once.
- Floating and split keyboards on iPad, and landscape heights.
