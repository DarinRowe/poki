# Poki calling guide

Use a known bundle_id for launch_app rather than guessing localized names. Batch launch_app with fill when the task already supplies the text and a single input is expected. Omit field in that case. When a selector is needed, copy its exact observed label or current ref; keep the screen language. Observe before adding navigation whose target is not yet known, such as an assumed new-tab button.

Use fill for text, preserving the user's literal input. Check text_verified and the saved result. sent only means an action was issued. Use list_elements for structure and observe_device or take_screenshot when an image is needed. Use adequate current-screen information already present in a receipt to choose the next step.

After a batch fails, inspect failed_step, remaining_steps and the current screen. Correct only unfinished steps. Observe an unknown outcome before acting again. When a route hands back to the model, continue from the current page while retaining completed actions.

Check the actual field and value when reading requested information. For web tasks, verify both the committed URL and page content. Text in an address editor or a matching title alone is insufficient. Verify new records after leaving edit mode. State which requirements remain unconfirmed.

If simulator input fails, inspect the actual field state before choosing recovery. Repeated observation does not fix input. Use another available method when repeated observation adds no evidence.

Handle system prompts through handle_alert. Specify a purchase button by its exact text only when the task explicitly requests the purchase. For login, verification codes and unlock, use the available tools and locally configured credentials. If no available approach can complete the task, finish_task(success=false) with completed work, the blocker and attempted approaches.
