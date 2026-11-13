# Tasks: release-2-0

The gates run in order. Each task is tagged with where it can run:
- **[Mac]:** needs a Mac, to build, test, render boards, install or run a Mac check;
- **[CI]:** GitHub Actions does it;
- **[Cloud]:** needs only the repository, so a cloud session can do it;
- **[David]:** his decision, or his yes.

**Every push, merge, retarget, ready, review request, tag and release needs David's yes in the current chat turn.**
Keep this file current as work moves; `handoff.md` holds the latest state behind each line.

## 1. Finish the stack
- [x] 1.1 Merge #56, the final audit's fixes (F3, F5, F6, F8, F9) plus #52's two CodeRabbit fixes, into
  `super/brain-6-around` once both Build runners pass. [CI] [David] Merged as 16263d8b.
- [x] 1.2 Request CodeRabbit's re-review of #52. Read it in full, fix or answer every note (the lean rules), and post
  the replies. [David] Its one note was fixed in 418dee32, and the review after that was clean.
- [ ] 1.3 David's Mac checks on the installed combined build, F1 (New note's Return) first. The list is in `handoff.md`.
  [Mac] [David] The stack landed first, on David's yes, so these checks now run on the final install (section 6).
- [x] 1.4 #42: mark it ready and merge it into `development`, with a merge commit. [David] Merged as 70ab4242.
- [x] 1.5 #43: retarget it to `development`, mark it ready and merge it. [David] Merged as a711fece.
- [x] 1.6 #52: the same, once its review is answered and #56 is in. [David] Merged as d7d839d3.
- [x] 1.7 After the stack lands, check that every file the specs cite exists on `development`, and fix any stale
  path. [Cloud] All 48 cited paths exist, except section 4's release notes, which are not written yet.

## 2. Land #3 and bridge the feed
- [ ] 2.1 Catch #3 (`chore/repoint-yanc-kannu`, CONFLICTING) up with `development`, run its gates, and merge it.
  [Mac] [David]
- [ ] 2.2 Confirm who can push to `libinmv/kannu`. Only 2.0.0 final needs it. [David]
- [ ] 2.3 Check that this repository's release secrets still exist (`gh secret list`) before the first tag. [David]

## 3. Version
- [ ] 3.1 Set `MARKETING_VERSION` to 2.0.0, and `CURRENT_PROJECT_VERSION` to 12 for beta.1, in both configurations of
  `Kannu.xcodeproj/project.pbxproj`. [Mac]
- [ ] 3.2 Set the codename in `ReleaseInfo.codename` (`Kannu/models/Constants.swift`), once David picks it (9.1). Add
  its row to `scripts/RELEASE.md`'s Codenames table. [Cloud] [David]
- [ ] 3.3 Before final: set 2.0.0's build to the last beta's plus one. [Mac]

## 4. Notes
- [ ] 4.1 Draft the user-facing 2.0 summary for the top of CHANGELOG's `[2.0.0]`. When the version lands, rename
  `[Unreleased]` to `[2.0.0] - <date> - <codename>`. [Cloud]
- [ ] 4.2 Write `docs/release-notes/2.0.0-beta.1.md`: what testers get, what to try, how to report, and that Sparkle
  will not offer it. [Cloud]
- [ ] 4.3 Write `docs/release-notes/2.0.0.md`. [Cloud]
- [ ] 4.4 Rewrite `ReadMe.md` for the pivot. Keep its install, build and licence facts. [Cloud]
- [ ] 4.5 Decide whether AGENTS.md's "Project overview" takes the 2.0 positioning. It still reads "Watch Your
  Agents" (9.6). [David]

## 5. What's New (recommended; one child PR)
- [ ] 5.1 Write the copy for the window and its three cards, Brain, Tasks and Tags, in English. [Cloud]
- [ ] 5.2 Build the window per `specs/whats-new` and `design.md`. [Mac]
- [ ] 5.3 Add its strings to `Kannu/Localizable.xcstrings` in all 17 languages, with sorted insertion. [Mac or Cloud]
- [ ] 5.4 Rule tests: never before the Terms, never on a fresh install, never during onboarding, and shown once.
  Add a DEBUG board from a fixture. [Mac]
- [ ] 5.5 Gates: full KannuTests, the Debug build, boards before and after, and the hook. Then a Mac check on an
  updated install and on a fresh user account. [Mac] [David]

## 6. Final install and Mac checks
- [ ] 6.1 Build the signed Release app from `development` with everything above, and install it the house way: quit,
  back up, replace, then verify the binary's date and a symbol. [Mac] [David]
- [ ] 6.2 David's Mac checks on that install: the checkpoint's list and #56's, both in `handoff.md`. [Mac] [David]

## 7. Ship
- [ ] 7.1 Tag `v2.0.0-beta.1` on the release commit. CI publishes a notarized pre-release, and both appcasts stay
  unchanged. [CI] [David]
- [ ] 7.2 The fix window: fixes land in `development` and ship as `v2.0.0-beta.N` if needed. [Mac] [David]
- [ ] 7.3 Tag `v2.0.0`. CI publishes, and commits the appcast to this repository's `main`. [CI] [David]
- [ ] 7.4 The feed bridge: copy 2.0.0's appcast item into `libinmv/kannu`'s `Updates/appcast.xml`, then read that
  file's raw XML to check it lists 2.0.0. [David]
- [ ] 7.5 Archive this change once 2.0.0 ships:
  `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 archive release-2-0 --yes`. [Cloud]

## 8. Launch video, "A day in the notch" (45 s at 16:9, plus a 15 s cut at 9:16)
The storyboard, shot list and prompts live only on David's Mac, in the untracked `marketing/kannu-2-0-day/`, and are
never committed (David, 2026-11-13). `marketing/` is never staged.
- [ ] 8.1 In a local session, write the storyboard and shot list into `marketing/kannu-2-0-day/`, with one prompt per
  shot, for seven beats from morning to night:
  1. A dark desk; the eye in the notch opens.
  2. Agents running; Brain › Agents full screen.
  3. A ticket lands in Brain › Tasks; typing `#launch @3pm` fills in the tag and the reminder; list-detail.
  4. The timer runs that task; Time to log.
  5. A pinned clipboard snippet; Notes beside the list.
  6. Evening: usage nears its limit, and the sidebar badge shows.
  7. Night: the notch closes like an eye. End card: "Kannu 2.0".

  UI shots are image-to-video from real 2.0 frames (snapshot boards from fixtures, never real data), with the UI held
  still, as the July ad's prompts did. Atmosphere shots (the desk, a day of light) are text-to-video. Higgsfield makes
  the shots only; the cut, captions, music and the day-clock overlay are done in David's editor. [Mac]
- [ ] 8.2 David approves the shot list. [David]
- [ ] 8.3 Render the UI frames the shot list names, as snapshot boards from fixtures. [Mac]
- [ ] 8.4 Authorize the higgsfield MCP through `/mcp`. [David]
- [ ] 8.5 Generate the shots in batches, each on David's yes, because every generation spends credits. [David]
- [ ] 8.6 Assemble the cut, and David signs it off before release day. [David]

## 9. Open decisions (each asked when its step comes up)
- [ ] 9.1 The codename. Horus is recommended: next on the list, and his eye matches the logo and a notch that closes
  like an eye.
- [ ] 9.2 Whether 2.0 adds the What's New window. Recommended: yes, one small child PR.
- [ ] 9.3 Who pushes the `libinmv/kannu` feed bridge.
- [ ] 9.4 Whether 2.0 adds features beyond what is built. If not, "more features" leads the 2.x roadmap.
- [x] 9.5 Where the storyboard and prompts live: on David's Mac only, never committed (David, 2026-11-13). A cloud
  session cannot write there, so the storyboard is a local task (8.1).
- [ ] 9.6 AGENTS.md's "Project overview" and the pivot (4.4, 4.5).
- [ ] 9.7 Whether #55 (Claude hooks no longer hold up a prompt; ready, into `development`) ships in 2.0.
- [ ] 9.8 What happens to `release/1.4.0` and #14 now that 2.0 supersedes 1.4.0.
- [ ] 9.9 Moving OpenSpec to 2.x, which keeps project context in `openspec/config.yaml` and retires this layout.

## 10. Carried over from the redesign (not 2.0 gates unless David makes them one)
- [ ] 10.1 The audit's leftovers:
  - F1 (New note's Return): fix after its Mac check;
  - F2 (looping previews while Brain is unseen): if the Mac check shows a cost;
  - F4 (focus and headings beside the list) and F7 (notch rail recomputes): optional;
  - F10's copy ("Click ›"): with the next strings pass.
- [ ] 10.2 A strings pass:
  - F10's copy;
  - the older wording on Brain's Tasks and Notes pages ("Turn On", "Tag colours");
  - the three wording fixes from #42's second review;
  - onboarding's uncatalogued strings (49 of 77).
- [ ] 10.3 Review follow-ups. Each is in `handoff.md`, with its file and why it waits.
