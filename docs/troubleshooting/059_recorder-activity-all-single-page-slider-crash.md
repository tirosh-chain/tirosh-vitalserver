# TS-059: Recorder Activity All Single-Page Slider Crash

> ID: TS-059  
> Category: macOS Helper / Observability  
> Owner: macOS runtime Helper UI  
> Status: active

## Symptoms

In the macOS Helper app, selecting `All` in a VRecorder activity timeline can terminate the app immediately.

The crash report shows SwiftUI failing while constructing `Slider` in `RuntimeRecordersPanel.activityAllSamplesWindowControl(_:)`.

## Cause

The activity page control always created a `Slider`, even when the `All` activity response had only one page. That produced a non-progressing slider range such as `0...0`. On macOS 26, SwiftUI validates slider normalization during view construction, so disabling the slider after construction does not prevent the precondition failure.

Invalid provider page metadata, such as a page count below `1`, could trigger the same boundary. That state must remain an invalid activity contract instead of being coerced into a usable empty/default page.

## Fix Direction

Render the page slider only when the explicit page count is greater than one. A single-page `All` window still shows its page label, but it does not create a slider.

Validate `All` activity page metadata before building chart display state. If page count or index is invalid, surface an invalid activity timeline message rather than materializing controls from repaired metadata.

## Prevention

SwiftUI controls should only receive valid construction ranges. Disabled state is a presentation affordance, not a way to protect a control from invalid input.

Provider-owned pagination metadata must be consumed explicitly. Do not infer or repair missing, invalid, or failed activity page state in the UI.

## Related Cases

- TS-055
