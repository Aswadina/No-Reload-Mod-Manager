# GameBanana Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (chosen for this project) to implement this plan task-by-task.

**Goal:** A GameBanana tab to browse/search mods for the current game, download one into a group, and update it later.

**Architecture:** All new code in `lib/custom/gb/`. A small API layer (`gb_api.dart`) turns GameBanana JSON into plain Dart objects. `gb_source.dart` remembers where an installed mod came from. `gb_install.dart` downloads, verifies, unpacks and places or swaps a mod. `gb_tab.dart` is the screen. `main.dart` gets a handful of one-line edits to add the tab.

**Tech Stack:** Flutter, Riverpod, `http` (already used), `SevenZip` (`lib/utils/archive_manager.dart`), `crypto` for MD5 (new tiny dependency).

**Spec:** `docs/superpowers/specs/2026-11-04-gamebanana-design.md`

## Global Constraints

- Personal code in `lib/custom/gb/`; upstream edits tiny (`main.dart` tab wiring only).
- API base `https://gamebanana.com/apiv11`; 15 results per page; one request at a time; no background polling; User-Agent `NRMM-personal` (no personal data); on HTTP 429/5xx stop and show a message.
- Game ids: Genshin 8552, HSR 18366, ZZZ 19567, Wuthering Waves 20357, Endfield 21842.
- Sorts accepted by the API (tested): `Generic_Newest`, `Generic_MostLiked`, `Generic_MostDownloaded`, `Generic_LatestUpdated`.
- Update detection uses file ids/dates, never `_sVersion`.
- Never delete user files: an update moves the old folder to a backup folder outside `Mods`, never removes it.
- Look: NRMM's own widgets and `getAccentColor`; cards 156.8 x 217.8, 17px corners, 3px `Color.fromARGB(127,255,255,255)` border, Poppins; dialogs `0xFF2B2930` radius 20.

## Review Focus

- API returns 400/429/500 or garbage JSON: user sees a message, nothing crashes.
- Record with no images, no `_sVersion`, or missing `_tsDateUpdated`: card still renders.
- Download whose MD5 does not match: nothing is installed and the temp file is removed.
- Archive with one wrapper folder vs. loose files vs. several folders: lands as one clean mod folder.
- Update when the download fails: the old mod folder is untouched.

---

### Task 1: API layer
**Files:** Create `lib/custom/gb/gb_api.dart`; Test `test/custom/gb_api_test.dart`; Fixtures `test/fixtures/gb/browse.json`, `profile.json` (real responses).
**Produces:** `GbMod`, `GbPage`, `GbFile`, `GbModDetails`, `GbException(message, statusCode)`, `GbSort` enum with `apiValue`, and `class GbApi(http.Client)` with `browse({gameId, page, sort})`, `search({gameId, query, page})`, `details(id)`.
- [ ] Tests (MockClient serving fixtures): parses browse page (count, names, thumb url from `_sFile530`), tolerates missing fields, parses details (files, md5, download url, blocked flags), builds the exact URL for browse and search, maps 400/429/500 to `GbException`.
- [ ] Implement; commit `feat(gb): API layer`.

### Task 2: Source memory
**Files:** Create `lib/custom/gb/gb_source.dart`; Test `test/custom/gb_source_test.dart`.
**Produces:** `GbSource{modId,fileId,fileDate,modDateUpdated,downloadedAt}` with `toJson/fromJson`; `readGbSource(modPath)`, `writeGbSource(modPath, src)`; `Future<Map<int, InstalledGbMod>> scanInstalled(String managedPath)` (looks one group deep, maps modId to path+source); `bool hasUpdateForCard(InstalledGbMod, GbMod)` (record's `dateUpdated` newer than stored `modDateUpdated`); `bool hasUpdateExact(GbSource, GbModDetails)` (newest file id differs).
- [ ] Tests incl. garbage json reads as null; scan ignores folders without the file. Implement; commit.

### Task 3: Install and update
**Files:** Create `lib/custom/gb/gb_install.dart`; Test `test/custom/gb_install_test.dart`.
**Produces:** `Future<String> installFile({client, details, file, groupPath, tempRoot, extract})` returns the new mod folder path; `Future<String> updateMod({..., existing, backupRoot, carryOverFiles})`. `extract` is injected (`Future<bool> Function(String archive, String outDir)`), default uses `SevenZip`. Placement rule: a single top-level folder with nothing beside it becomes the mod folder (its name); otherwise everything goes into a folder named after the mod (sanitized). Names never overwrite (`_1`, `_2`).
- [ ] Tests (fake extract that writes files): md5 mismatch installs nothing and cleans temp; single-wrapper; loose files; unique name; update swaps and keeps old in backup; failed update leaves old folder untouched; carry-over copies named files.
- [ ] Implement; add `crypto` to `pubspec.yaml`; commit.

### Task 4: The tab
**Files:** Create `lib/custom/gb/gb_tab.dart`; Modify `lib/main.dart` (4th tab: `length: 4`, `_views` lists at ~680/1496/1611, a `SegmentTab`, bar width 350 to 470).
- [ ] Search bar + sort chips + grid of cards (Installed/Update badge) + load more; details dialog with files, "Put it in" dropdown (groups + New group), Download/Update, progress text; game with no id shows a message.
- [ ] `flutter analyze` (no new errors), all tests green; commit.

### Task 5: Wrap up
- [ ] Note the feature in `CLAUDE.md`; run the whole test suite and Pester; report. Merge/push/install only when the user says so.
