# Source provenance

Poki Agent runs from this repository. It does not import files from Poki App.

| Files | Source | Adaptation |
| --- | --- | --- |
| `task-runner.mjs`, `routes.mjs`, `fast/` | poki-app `9972d34` | Local paths, English text, pi session and transport events |
| `verify-result.mjs` | poki-app `9b1c24d` | pi session, independent completion and route-learning gate |
| Batch launch handling | poki-app `9b1c24d` | Retained version-3 route behavior from `9972d34` |
| `pi-session.mjs`, `poki-client.mjs`, `prompts/call-draft.md` | Poki development snapshot based on `6ad0d4c1dcfee2ca814785d624ec3cf4cf7409e7`, copied 2026-11-05 | Local paths, English text, configurable OpenAI access and service tier |

The copied implementation was uncommitted in its source workspace. Benchmark transcripts, credentials, sessions and application build products are not distribution dependencies.

Physical-device adaptation retains a verified launch PID when native accessibility omits the bundle ID. Read-only navigation routes use observed page headings and back buttons for intermediate page checks; changing charge estimates do not identify a page. Final result conditions still verify the requested field.

Luma acceptance exposed a native Header button sharing its label with a city card. Route selectors retain the observed Header trait, and result checks retain page headers. Initial task context is stored and matched exactly; mid-task steering still prevents learning. The MCP structured-receipt change `cd3e4c8` was inspected but not copied: these Luma runs did not use batch calls or lack structured observations.

Version-5 routes retain navigation anchors and a verified result plan, with no saved answer text. Action results check their postconditions without a model. Fixed fields require a unique selector and a nonempty current value. Lists retain unique section boundaries and a row shape learned from the first verified answer; changed rows are read from the current screen. If that list structure cannot be matched, one tool-free pi response selects current fields. Older routes must be learned again. These result readers are local Agent changes.

The Agent sends compact element records to the execution model while retaining the full observation for route learning and independent verification. Runtime status and foreground checks remain internal. Action receipts include the existing fresh observation, so completion does not require a duplicate read when that receipt proves the result.

Poki code in this repository is licensed under AGPL-3.0-only. See `THIRD_PARTY_NOTICES.md` for third-party notices.

The BlueBubbles adapter uses the documented [REST API](https://docs.bluebubbles.app/server/developer-guides/rest-api-and-webhooks) and the upstream [message router](https://github.com/BlueBubblesApp/bluebubbles-server/blob/master/packages/server/src/server/api/http/api/v1/routers/messageRouter.ts). Its scoped `where` query also works with the installed BlueBubbles Server 1.9.12. That version returns a bare HTTP 404 for a nonexistent `chatGuid` because its early return does not send a response; the adapter uses bound `chat.guid` and `handle.id` filters instead. No BlueBubbles server code is bundled.

## Telegram source

`telegram-source.mjs` ports the relevant logic from the supplied `hermes-telegram.py` and `hermes-base.py` snapshots of [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), received on 2026-11-05. The supplied snapshots do not identify an upstream commit, so this provenance does not claim one. Hermes is MIT-licensed, copyright 2025 Nous Research. The supplied license is retained verbatim in [licenses/hermes-MIT.txt](licenses/hermes-MIT.txt).

| Supplied source | Ported behavior | Adaptation |
| --- | --- | --- |
| `hermes-telegram.py`, `_handle_text_message`, `_start_polling_mode`, `_cold_boot_drop_pending`; `hermes-base.py`, `_is_sender_authorized` | Poll updates, gate sender before task dispatch, skip initial pending history | Official Bot API HTTP calls in Node.js, required numeric user allowlist, private chats only, persistent offsets; active webhooks fail startup without deletion |
| `hermes-base.py`, `truncate_message`, `_prefix_within_utf16_limit` | UTF-16 length budget, newline/space split, no surrogate split | Plain text with exact whitespace retention; no Markdown fences, formatting fallback or chunk indicators |
| `hermes-base.py`, `_send_with_retry`; `hermes-telegram.py`, `_send_chunks`, `_classify_send_exception` | Bounded backoff, server retry delay, no replay of delivered chunks, uncertain timeout handling | Two retries per request, 30-second inline retry cap, static errors keep credentials out of logs; read-only calls may retry network failures |
| `hermes-telegram.py`, `send_or_update_status`, `_edit_markdown_or_plain` | Remember status message ID, edit progress, tolerate not-modified, replace missing/uneditable status | One status ID per conversation and task; handoff prompts and final results get new messages |

Python Telegram Bot, media handling, Markdown rendering, group topics, plugin authorization callbacks and Hermes's general gateway are not runtime dependencies of Poki Agent. The task interface remains `MessageRunner` and `PhoneTask`.

The execution prompts in `prompts/system.md` and `prompts/pi-app.md` are now written for Poki's local acknowledgement, step deadline and tool behavior. The former human-handoff prompt and its separate license have been removed. The iPhone unlock skill and native helper originate in this repository at `5134e1a`; the Agent host adds stdin-only credential transport and screenshot verification.
