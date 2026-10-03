# Accessibility behavior and verification

The native exploration canvas normalizes ordinary touch and API20 accessibility hover into the same stable-ID semantic actions as the object list, large buttons and on-screen scanning. A canvas does not hide the entire screen from accessibility. Persistent Library and Stop audio controls remain outside the exploration surface. Coordinate forms and explicit buttons provide alternatives to dragging, zooming and panning gestures.

Settings provide up to 200% text, high contrast, dwell delay, volume, optional vibration, scanning speed and coordination with screen-reader automatic speech. Longer descriptions require an explicit request. Audio is cancelled on foreground loss, mode changes, touch cancellation, interruption and output-device change. Missing vibration is reported without implying that a simulated event was physically felt.

Source review still needs an author who can assess the original or an equivalent accessible reference. A labelled coordinate form does not provide independent access to an undescribed image. An imported author declaration is not accessibility certification.

The reference Oniro6.1 emulator initially has no spoken screen-reader bundle. A native accessibility extension probe, if used, proves event delivery only. It must not be counted as a successful blind-user or full spoken-reader flow. Tests on a supported runtime with a genuine reader must include import, acceptance, tutorial, hover exploration, list navigation, answer selection/submission, pause, exit and resumption, in English and at 200% text.

Physical vibration, headphone removal, simultaneous reader/audio behavior and representative-user usability are separate checks. See `TEST_REPORT.md` for the actual outcomes. No phone hardware was inferred from an emulator's vibrator capability flag.
