# Tasks: add-wispr-meeting-notes

## 1. Reader
- [x] 1.1 `WisprFlowMeetingsStore`: `mode=ro`, never `immutable=1`, schema check, live meetings with a summary, newest first, at most 50
- [x] 1.2 `WisprFlowMeetingsManager`: in memory only, read off the main actor, counts-only log

## 2. Notch and settings
- [x] 2.1 Meetings in the notch's Notes list; Copy only; read-only editor with Open in Wispr Flow
- [x] 2.2 The editor's `persistNote` and `scheduleAutoSave` return before saving a meeting
- [x] 2.3 Brain › Notes › Wispr Flow switch (off by default), with its search entry

## 3. Tests
- [x] 3.1 `WisprFlowMeetingsStoreTests`, against an uncheckpointed WAL database of made-up meetings
- [x] 3.2 `WisprMeetingsNeverStoredRulesTests`, with planted offenders
- [x] 3.3 `openspec validate --all --strict` (0.23.0)
- [ ] 3.4 Archive after merge
