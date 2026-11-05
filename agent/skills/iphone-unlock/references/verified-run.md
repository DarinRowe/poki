# Standard iPhone wireless unlock verification

On 2026-11-05, after the user authorized the unlock and provided the passcode, one iPhone17,1 (iOS 27.3) was operated over Wi-Fi. The logical screen size was 402×874, in portrait, with a six-digit numeric passcode. This record contains no passcode, device identifier, or notification content.

## Observations

- Calling keypad input six separate times: all six receipts returned sent, and the screenshot showed only three dots.
- A script that opened a separate native touch connection for each digit took 11.8 seconds to send, and the phone stayed on the Lock Screen afterwards.
- Entering the passcode page and tapping six digits within one connection: a version with shorter waits showed only five dots.
- In a new media session, skipping Home and tapping directly did not complete the unlock.
- Finally, entering the passcode page within one session, waiting for it to settle, and tapping continuously: a screenshot confirmed the phone returned to the previous app, and the user then confirmed the unlock succeeded.

These results support keeping the session and wait order of the successful run. They do not on their own prove the underlying cause of the missed inputs.

## Order of the successful run

| Step | Verified parameters |
| --- | --- |
| Start a media session for display 1 | Wait 1000 ms |
| Send Home | Hold 80 ms, wait 2000 ms after release |
| Connect to the touch service | Wait 1000 ms |
| Six coordinate taps | Hold each 150 ms, wait 450 ms after release |
| Keep the input connection open | Wait another 1000 ms, then close input and the media session |
| Check | Screenshot shows the Lock Screen dismissed, and the user confirmed success |

The six taps and the final wait measured about 4.6 seconds. That excludes finding the device, connecting, entering the passcode page, and the final screenshot. Only one complete successful run on this one device has been verified. There is no evidence across models, for the first unlock after a restart, on Duo, or for a batch success rate.

The skill's helper keeps the order of this successful run, and adds a readable coordinate configuration, hidden passcode input, and input validation. The build and validation results for the final packaged version are listed in the pull request. They do not count as additional successful runs on a physical device.
