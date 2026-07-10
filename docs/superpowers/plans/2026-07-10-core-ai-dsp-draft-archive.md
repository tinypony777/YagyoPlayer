# Core AI / Music Understanding / DSP Draft Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the frozen Step 3 DSP prototype outside the app target, replace the current Step 3 direction with an iOS 27 Core AI + Music Understanding + bounded DSP Listening Profile concept, and publish the documentation on `main`.

**Architecture:** `Draft/Step3-One-Ear` is a source snapshot copied from `origin/agent/step3-one-ear` at `f639bee`; it is not compiled by the normal XcodeGen project. The canonical product document contains only the product promise and boundaries. A separate provisional plan records confirmed Apple APIs, Mastering-App reference patterns, assumptions, phased delivery, safety gates, and verification requirements.

**Tech Stack:** Markdown, Git, Swift/C/C++ source snapshot, Apple Music Understanding, Apple Core AI, AVFoundation, the existing YagyoPlayer XcodeGen project.

## Global Constraints

- Work from `origin/main` commit `3937c84` or a later fast-forwarded main commit; preserve all existing main changes.
- Store the frozen prototype under repository-root `Draft/Step3-One-Ear`; nothing under `Draft` may be part of the production or test target.
- Snapshot only files present in `origin/agent/step3-one-ear` at `f639bee`; do not claim the Mac-only Task 4 commits are included.
- Preserve libebur128 `COPYING` and `ORIGIN.md` beside its source.
- Do not copy the branch-generated `YagyoPlayer.xcodeproj/project.pbxproj`, build artifacts, FFmpegSwiftSDK, simulator logs, or profiler output.
- Do not add FFmpegSwiftSDK as a dependency or future recommendation.
- Treat Core AI and Music Understanding as iOS 27 beta APIs whose contracts require revalidation against the release SDK.
- Core AI ranks allow-listed, versioned DSP recipe IDs; it must not generate arbitrary DSP nodes, ordering, or unbounded coefficients.
- Original/bypass remains permanently available. No processing is applied before explicit user selection, and failures return to Original.
- The initial product concept is a headphone-route Listening Profile selected from `Original + up to three candidates`, not per-track automatic mastering.
- Music Understanding and Core AI run outside the real-time render callback. The selected deterministic DSP recipe is the only new work in the playback render path.
- Keep YagyoPlayer a local-first music player: no audio upload, no network dependency, and no automatic file modification.
- Use `tinypony777/Mastering-App` only as a design reference; do not add a source or package dependency on that repository.
- Do not use Remote Desktop Commander for implementation or review. It is reserved for later Xcode build, test, and Simulator validation through local Codex.

---

### Task 1: Archive the existing Step 3 prototype outside build targets

**Files:**
- Create: `Draft/Step3-One-Ear/README.md`
- Create: `Draft/Step3-One-Ear/CURRENT_STATE.md`
- Create: `Draft/Step3-One-Ear/Design/2026-07-10-step3-one-ear-design.md`
- Create: `Draft/Step3-One-Ear/Design/2026-07-10-step3-one-ear-plan.md`
- Create: `Draft/Step3-One-Ear/Snapshot/YagyoPlayer/Analysis/*`
- Create: `Draft/Step3-One-Ear/Snapshot/YagyoPlayer/Services/{AudioPlaybackBackend.swift,LegacyAudioPlayerPlaybackBackend.swift,PlaybackController.swift}`
- Create: `Draft/Step3-One-Ear/Snapshot/YagyoPlayerTests/{Analysis,Fixtures,TestSupport}/*`
- Create: `Draft/Step3-One-Ear/Snapshot/YagyoPlayerTests/PlaybackControllerTests.swift`
- Create: `Draft/Step3-One-Ear/Snapshot/Vendor/libebur128/*`
- Create: `Draft/Step3-One-Ear/Snapshot/Integration/project.step3.yml`

**Interfaces:**
- Consumes: Git tree `origin/agent/step3-one-ear^{tree}` at commit `f639bee`.
- Produces: A non-compiling, provenance-recorded prototype snapshot that future work can inspect without reviving the old branch architecture.

- [x] **Step 1: Verify snapshot source and production exclusions**

Run:

```bash
git rev-parse origin/agent/step3-one-ear
git status --short --branch
```

Expected: the first command prints `f639beed71aea7f24d32cb3ce4a23996000ad8d9`; the second shows a clean `main` except for this plan file.

- [x] **Step 2: Copy only the approved source, tests, vendor, design, and integration files**

Use `git archive` or an equivalent mechanical Git-tree extraction. Keep the original `YagyoPlayer`, `YagyoPlayerTests`, and `Vendor` relative paths under `Snapshot`. Rename the branch `project.yml` to `Snapshot/Integration/project.step3.yml`. Do not extract `YagyoPlayer.xcodeproj/project.pbxproj`.

- [x] **Step 3: Write archive provenance and status documents**

`README.md` must state:

```markdown
# Step 3 “One Ear” DSP Draft

This directory freezes the abandoned Step 3 prototype for reference. It is outside YagyoPlayer's XcodeGen source roots and is not production code.
```

It must link to `CURRENT_STATE.md`, both files in `Design`, and the new canonical Core AI plan.

`CURRENT_STATE.md` must record:

- base `3937c84` lineage context and snapshot head `f639bee`
- implemented: playback backend seam, vendored libebur128, labeled PCM adapter, EBU R128 wrapper, related tests
- not included: `SilenceDetector`, `OnsetDetector`, `PerceptionDSPCore`, cache, offline pipeline, realtime ring buffer, AVAudioEngine backend
- Mac-only commit identifiers `41bd00e` and `1abf278` are not present in GitHub and are not in this snapshot
- the prototype is frozen by the Core AI + Music Understanding direction and is not assumed reusable as the future playback-effect chain

- [x] **Step 4: Verify the archive is outside targets and complete**

Run:

```bash
rg -n "Draft" project.yml YagyoPlayer.xcodeproj/project.pbxproj
test -f Draft/Step3-One-Ear/Snapshot/Vendor/libebur128/COPYING
test -f Draft/Step3-One-Ear/Snapshot/Vendor/libebur128/ORIGIN.md
test ! -e Draft/Step3-One-Ear/Snapshot/YagyoPlayer.xcodeproj/project.pbxproj
git diff --check
```

Expected: `rg` returns no matches; all three `test` commands succeed; `git diff --check` emits no errors.

- [x] **Step 5: Commit the frozen snapshot**

```bash
git add Draft/Step3-One-Ear docs/superpowers/plans/2026-07-10-core-ai-dsp-draft-archive.md
git commit -m "docs: archive frozen Step 3 DSP draft"
```

### Task 2: Update the canonical product direction

**Files:**
- Modify: `docs/PRODUCT_DIRECTION.md`
- Modify: `docs/DESIGN_NAV.md`
- Modify: `docs/WWDC26-Music-notes.md`

**Interfaces:**
- Consumes: The user-approved Listening Profile concept and Apple iOS 27 beta API facts.
- Produces: A short canonical product promise with no speculative implementation details or stale old-Step-3 claims.

- [x] **Step 1: Replace §4.2 with the new product-level contract**

The section must say that Music Understanding supplies Apple-defined musical analysis, Core AI ranks a few validated DSP recipes, and the user chooses a Listening Profile through loudness-matched comparison with Original. It must explicitly preserve local-first behavior, non-destructive playback, bypass/reset, and normal playback fallback.

- [x] **Step 2: Rewrite Step 3 and the Later section consistently**

Step 3 becomes an iOS 27 capability and feasibility stage rather than a completed custom DSP engine. Its release criteria are: release-SDK capability verification, Original + three bounded candidates, explicit default selection, deterministic DSP, route-safe fallback, and no playback-trust regression. Remove the old requirement to complete custom LUFS + silence + onset + cache in Step 3. Keep MusicUnderstanding out of the old “Later migration” wording because it is now part of the planned direction.

- [x] **Step 3: Correct visual and platform notes**

`DESIGN_NAV.md` must keep the current honest state (`averagePower` only) and describe future attack/silence/pace reactions as Music Understanding or later bounded-analysis inputs, separate from Listening Profile processing. `WWDC26-Music-notes.md` must mark Music Understanding and Core AI as iOS 27 beta APIs and remove the implication that they are an iOS 26 production dependency.

- [x] **Step 4: Verify canonical-document consistency**

Run:

```bash
rg -n "libebur128|FFmpegSwiftSDK|共有 DSP コア|LUFS\+無音\+オンセット|Later — MusicKit / Apple Music / MusicUnderstanding" docs/PRODUCT_DIRECTION.md docs/DESIGN_NAV.md docs/WWDC26-Music-notes.md
git diff --check
```

Expected: the first command returns no stale canonical claims; `git diff --check` emits no errors.

- [x] **Step 5: Commit the canonical direction update**

```bash
git add docs/PRODUCT_DIRECTION.md docs/DESIGN_NAV.md docs/WWDC26-Music-notes.md docs/superpowers/plans/2026-07-10-core-ai-dsp-draft-archive.md
git commit -m "docs: revise Step 3 for iOS 27 intelligence"
```

### Task 3: Write the provisional Core AI / Music Understanding / DSP plan

**Files:**
- Create: `docs/CORE_AI_MUSIC_UNDERSTANDING_DSP_PLAN.md`

**Interfaces:**
- Consumes: Apple Music Understanding and Core AI documentation, plus bounded safety/reference patterns from `tinypony777/Mastering-App`.
- Produces: A provisional, implementable architecture plan that separates confirmed APIs from hypotheses and does not authorize runtime implementation yet.

- [x] **Step 1: Record facts, assumptions, and non-goals separately**

Confirmed facts must include iOS 27 beta availability, `MusicUnderstandingSession` input/result boundaries, Core AI `.aimodel` on-device inference, and the need for a developer-supplied model. Assumptions must include headphone-route scoping, app-owned feature caching, preference-vector persistence, and the initial recipe catalog. Non-goals must include arbitrary AI-generated chains, per-track automatic mastering, audio upload, destructive export, and FFmpeg adoption.

- [x] **Step 2: Define the bounded data flow and component contracts**

Document this exact logical flow:

```text
Local audio
  -> MusicUnderstandingAdapter + bounded DSP feature extractor
  -> FeatureSnapshot
  -> CoreAISuggestionProvider
  -> SuggestionValidator
  -> Versioned DSPRecipeCatalog
  -> Original + up to three loudness-matched previews
  -> explicit user selection
  -> ListeningProfileStore
  -> deterministic DSP runtime
```

The plan must state that Core AI returns recipe ranking scores/IDs, not executable graphs. The validator rejects unknown, duplicate, non-finite, incompatible, or out-of-version outputs and falls back to Original.

- [x] **Step 3: Incorporate Mastering-App reference lessons without coupling**

Reference the useful patterns by path and repository link: structured advisor protocol, layered fallback, user preference deltas, schema validation/clamping, proposal safety layer, deterministic parameter snapshot, preview-before-commit flow, bypass, and verification evidence. Explicitly reject copying the 11-stage mastering chain, cloud LLM providers, free-form parameter JSON, export loudness targeting, and mastering-specific automatic correction.

- [x] **Step 4: Define phased delivery and release gates**

Phases must be: release-SDK capability spike; deterministic DSP catalog and preview without AI; Music Understanding adapter and cache; Core AI ranker; explicit Listening Profile persistence; playback integration; real-device release gate. Tests must cover validator fail-closed behavior, bypass transparency, loudness-matched switching, route changes, interruption/seek/background regression, render-thread allocations/locks, battery/thermal behavior, offline operation, and accessibility.

- [x] **Step 5: Verify document contracts and links**

Run:

```bash
rg -n "Confirmed|Assumption|Non-goal|Original|MusicUnderstandingSession|\.aimodel|SuggestionValidator|DSPRecipeCatalog|Mastering-App|FFmpeg" docs/CORE_AI_MUSIC_UNDERSTANDING_DSP_PLAN.md
rg -n "https://developer.apple.com/documentation/(musicunderstanding|coreai)" docs/CORE_AI_MUSIC_UNDERSTANDING_DSP_PLAN.md
git diff --check
```

Expected: all required concepts and both Apple documentation families are present; `git diff --check` emits no errors.

- [x] **Step 6: Commit the provisional plan**

```bash
git add docs/CORE_AI_MUSIC_UNDERSTANDING_DSP_PLAN.md
git commit -m "docs: plan Core AI listening profiles"
```

### Task 4: Review, verify, and publish main

**Files:**
- Review: all files changed by Tasks 1–3

**Interfaces:**
- Consumes: The reviewed Task 1–3 commit series on local `main`, including review-follow-up commits.
- Produces: A verified, pushed `origin/main` with the old prototype archived and the new direction documented.

- [x] **Step 1: Run independent subagent review**

The reviewer must check source provenance, target exclusion, licensing files, Apple API accuracy, confirmed-vs-hypothetical labeling, music-player scope, Mastering-App reference accuracy, and internal links.

- [x] **Step 2: Run final local verification**

```bash
git status --short --branch
git diff origin/main...HEAD --check
git diff --name-status origin/main...HEAD
rg -n "Draft" project.yml YagyoPlayer.xcodeproj/project.pbxproj
```

Expected: only the intended commits are ahead of `origin/main`; diff check is clean; no production project file references `Draft`.

- [ ] **Step 3: Push the explicitly requested main branch**

```bash
git push origin main
```

Expected: `origin/main` advances to local `HEAD` without force.
