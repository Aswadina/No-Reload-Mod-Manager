# GameBanana tab — design

## Why

Getting a mod today means leaving NRMM: find it on GameBanana in a browser, download
the archive, unpack it, drag it into the right group. The user wants to do all of that
from inside NRMM, including finding mods (browse and search) and updating them later.

## Goals

- A new **GameBanana** tab (after Mods) to browse and search mods for the current game.
- One click to download a mod, check it, unpack it and put it in a group.
- Remember where each mod came from, show **Installed** / **Update** on cards, and
  update in one click.
- Look and behave like the rest of NRMM (see "Look" below).

## Non-goals

- Logging in to GameBanana, comments, likes, uploading, or any write action.
- Mods for games NRMM does not manage.
- Browsing anything but mods (no sounds, tools, wips) in version 1.

## Anti-goals

- Anything that overwrites or deletes a user's mod files without them asking.
- Hammering GameBanana (no scraping the site, no background polling loops).
- Large edits to upstream files; the self-update job merges upstream daily.

## What GameBanana gives us (proved by reading the live API, no login needed)

Base: `https://gamebanana.com/apiv11`

- Browse: `GET /Mod/Index?_nPerpage=N&_nPage=P&_aFilters[Generic_Game]=<gameId>&_sSort=...`
  returns `_aMetadata` (`_nRecordCount`, `_nPerpage`, `_bIsComplete`) and `_aRecords`.
- Search: `GET /Util/Search/Results?_sSearchString=...&_idGameRow=<gameId>&_sModelName=Mod&_nPage=P&_nPerpage=N`,
  same record shape.
- A record has `_idRow`, `_sName`, `_sProfileUrl`, `_sVersion`, `_tsDateAdded`,
  `_tsDateModified`, `_tsDateUpdated`, `_bHasFiles`, `_bIsObsolete`, `_aPreviewMedia._aImages[]`
  (`_sBaseUrl` + `_sFile` or `_sFile100/220/530/800`), `_aSubmitter._sName`,
  `_aGame._idRow`, `_aRootCategory`, `_nLikeCount`, `_nViewCount`.
- Details: `GET /Mod/<id>/ProfilePage` adds `_aFiles[]` with `_idRow`, `_sFile`, `_nFilesize`,
  `_tsDateAdded`, `_sDownloadUrl` (`https://gamebanana.com/dl/<fileId>`), `_sMd5Checksum`,
  `_sAvResult`, `_sDescription`, plus `_sText` (HTML description), `_aRequirements`,
  `_bIsWithheld`, `_bIsTrashed`, `_bIsPrivate`.
- Game ids (checked via `/Util/Search/Results?_sModelName=Game`): Genshin Impact **8552**,
  Honkai: Star Rail **18366**, Zenless Zone Zero **19567**, Wuthering Waves **20357**,
  Arknights: Endfield **21842**.
- `_sVersion` is unreliable (one mod said 4.2 while its newest file was v5.0).
  **Update detection must compare the newest file's `_idRow` / `_tsDateAdded`, not the version text.**

Checked, with no answer found: GameBanana's rate limits and rules for automated use. No search
result or documentation mentions them, and the terms page says nothing about API or bot access.
So this is **unknown, not permitted**. Be gentle: 15 results per page, one request at a time,
cache results for the session, no background polling, a plain User-Agent, and on HTTP 429 or
5xx stop and tell the user instead of retrying in a loop.

Not checked yet: how mods behind a content warning behave; the exact category filter parameters.

## How it should work (the parts the user decided are marked; the rest are my calls)

- **Where it appears (user chose):** a fourth tab "GameBanana" (layout A: search bar and
  sort chips on top, a grid of cards like the Mods tab cards, a details dialog on click).
- **Look (user insisted):** match NRMM's real look — pill tab bar, 156.8 x 217.8 cards with
  17px corners and 3px translucent-white borders, accent color for selected, Poppins,
  dialog color `0xFF2B2930` radius 20. Reuse NRMM's widgets and `getAccentColor`.
- **Current game (my call):** the tab uses the game NRMM is currently set to
  (`targetGameProvider`). It shows a short message if that game has no known GameBanana id.
- **Downloading (user chose: "it just goes to the group"):** the details dialog has a
  "Put it in" dropdown. Default (my call): the group currently selected in the Mods tab. The
  list also has "New group". The mod's archive is downloaded to a temp folder, checked against
  `_sMd5Checksum`, unpacked with the existing `SevenZip` class (`lib/utils/archive_manager.dart`),
  unwrapped with the existing `unwrapSingleFolderNesting`, and moved into the group
  with a safe unique folder name. The user then runs Update Mod Data as usual
  (my call: do not auto-run it; show a reminder, as the import button does).
- **Several files (my call):** if a mod has more than one file, the dialog lists them and
  the newest is pre-selected.
- **Remembering the source (my call):** a small file `gbsource.json` inside the mod folder:
  `{ "modId": ..., "fileId": ..., "fileDate": ..., "downloadedAt": ... }`. Same idea as
  `uikey` / `uistate` for UI groups. Moves and renames of the folder keep it.
- **Installed / Update badges (my call):** NRMM scans managed mod folders for `gbsource.json`
  once when the tab opens. A card is **Installed** if its mod id is found, **Update** if the
  newest file id on GameBanana differs from the stored `fileId`.
- **Update (my call):** downloads and unpacks the new file next to the old folder, then
  swaps: the old folder is renamed to `<name>_old` (kept, never deleted), the new one takes
  its place and its `gbsource.json` is updated. The user's own files (icon, group
  position) are carried over by keeping the folder name. If anything fails, the old folder
  stays untouched.
- **Warnings (my call):** if `_sAvResult` is not clean, or the mod is withheld/trashed/private,
  Download is disabled with a short reason.

## Changes made while building (rulings)

- **Tab position:** the tab is last (Keybinds, Mods, Settings, GameBanana), not between Mods and
  Settings. Settings is "tab 2" in about a dozen upstream places; adding at the end avoids
  editing them all. The tab bar grows from 350 to 470 wide.
- **Backup location:** the old folder of an updated mod goes to `<game folder>\NRMM_GB_Backups`
  (next to `Mods`), not `<name>_old` inside the group, because any folder inside a group counts
  as a mod and would show up in NRMM.
- **Card "Update" badge:** compares the mod's `_tsDateUpdated` with the value stored at download.
  GameBanana does not send that date for every mod; then no badge shows and the details dialog
  (which checks the newest file exactly) is the source of truth.
- **Lazy loading:** nothing is requested until the user first opens the tab.
- **Not done:** setting the mod's NRMM icon from the GameBanana picture; auto-running Update Mod Data.

## Left to the builder

- HTTP: the app already has `http` and a shared `httpClient`; use them. Set a plain User-Agent
  such as `NRMM-personal`; do not put the user's email or any personal data in it.
- MD5: `crypto` is not a direct dependency; adding that tiny package or hashing another way is the builder's call.
- Paging, caching of results and images, loading and error states, cancel on tab switch.
- Finding the other games' GameBanana ids (probably a lookup at build time, then a constant).
- Sort and category options.

## Risks

- GameBanana can change the API (it is only partly official). Keep all API code in one file
  so a change is a one-file fix.
- Rate limits are unknown. Keep paging small, no background polling, and cache what we fetch.
- Archives with odd layouts (nested folders, multiple mods in one archive) may not unpack into
  a clean mod folder. Surface this to the user instead of guessing.
- Downloading and running third-party mods is the user's choice; checksum plus GameBanana's
  virus-scan result are the only checks.
