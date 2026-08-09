# MouseLens TestFlight Beta Notes

## What To Test

Please test short screen and window recordings, then review and export from the editor.

Focus areas:

1. Recording starts after countdown and finishes from the floating toolbar.
2. Screen mode records the intended display area.
3. Window mode records the selected window and keeps cursor/zoom aligned with clicks.
4. Editor playback starts immediately after recording.
5. Cursor, click feedback, Auto Zoom, and Manual Zoom align with the real click location.
6. Trim, Zoom Track, background, padding, and corner radius controls behave predictably.
7. Presenter camera bubble can be positioned before recording and remains consistent in preview/export.
8. Exported MP4 matches the editor preview.
9. GIF export works for short trimmed clips.
10. Captions can be generated, edited, previewed, and exported.
11. Cursor styles remain consistent between preview, MP4 export, and GIF export.

## Known Beta Risks

- Window recording should be tested across several apps and display layouts.
- Multi-display setups need extra verification.
- Automatic zoom behavior may still need tuning for very dense click sequences.
- GIF exports are intended for short clips; long GIFs can become large.
- Speech transcription quality depends on macOS speech recognition availability, language, microphone quality, and recording clarity.

## Feedback Requested

Please include:

- macOS version
- Mac model if known
- Screen or Window mode
- Single display or multi-display
- Steps to reproduce
- Whether the issue appears in preview, exported MP4, or both

## Beta Review Notes

MouseLens requires Screen Recording permission to capture video. Microphone permission is optional and only needed when microphone audio or captions are tested. Camera permission is optional and only needed when the presenter camera bubble is enabled. No account is required.
