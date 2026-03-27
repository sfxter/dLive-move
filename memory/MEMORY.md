# Memory Index

- [feedback_version_field.md](feedback_version_field.md) — DirectlyRecallStatus requires version field at msg[0x1c] = 10 after FillGetStatus
- [feedback_typeb_objects.md](feedback_typeb_objects.md) — Type B data objects (DigitalAtten, StereoImage, Delay, DirectOutput) require direct field access, not GetStatus/SetStatus which hang offline
- [project_movechannel_status.md](project_movechannel_status.md) — Move Channel feature: what works, techniques used, remaining work (inserts, stereo, patching)
- [feedback_reverse_engineering_approach.md](feedback_reverse_engineering_approach.md) — Fastest way to find dLive objects: disassemble MIDI handler first, find instances in gRegistryRouter table, skip blind memory scanning
- [feedback_ui_refresh_patterns.md](feedback_ui_refresh_patterns.md) — UI refresh master guide: always use the app's own code path (CSV import, MIDI handler, scene recall) instead of low-level notification methods. Covers all patterns, what works, what fails, and why.
