# Personal build with automatic upstream updates

Date: 2026-10-11

## Goal

Run a personal version of No Reload Mod Manager on this PC, with my own
features, that keeps pulling in changes from the original repo
(`Aglglg/No-Reload-Mod-Manager`), rebuilds itself, and reinstalls itself
without me doing anything. Windows only, for one user, no public releases.

## Branches

| Branch | Purpose |
|---|---|
| `upstream` (remote) | The original creator's repo. Read only. |
| `main` | Pure copy of `upstream/main`. Never edited by hand. |
| `my-version` | My app. Starts from `Reorder-groups`. Features branch off it and merge back into it. |

## One-time changes in `my-version`

1. **Turn off the built-in updater.** `lib/main.dart` points the updater at
   the original creator's appcast. Remove the `setFeedURL` /
   `setScheduledCheckInterval` calls. In `lib/tabs/settings_tab.dart`, the
   "check for updates" button stops calling `autoUpdater.checkForUpdates()`
   and shows a short message saying updates are handled by the self-update
   task instead.
2. **Add the update script** at `tools/self-update/`. The original repo never
   touches this folder, so it never causes merge conflicts.

## The update job

A PowerShell script (`tools/self-update/update.ps1`) run by Windows Task
Scheduler.

- **Schedule:** daily at 04:00, plus "run as soon as possible if a run was
  missed". It runs as the current user, only when logged in (needed to relaunch
  the app and show notifications).
- **Separate working copy:** a dedicated clone at
  `%LOCALAPPDATA%\NRMM-Builder\repo`. The dev folder
  (`C:\Users\Aswad\No-Reload-Mod-Manager`) is never touched by the job.
- **State:** `%LOCALAPPDATA%\NRMM-Builder\state.json` stores the commit that was
  last installed. Logs go to `%LOCALAPPDATA%\NRMM-Builder\logs\<date>.log`,
  and only the last 30 logs are kept.
- **Lock:** a lock file stops two runs from overlapping.

Steps:

1. Fetch `upstream` and `origin` (my fork).
2. Check out `my-version` and reset it to `origin/my-version`. This is the
   job's own clone, so nothing is lost.
3. Merge `upstream/main` into `my-version`.
   - If there's a conflict: abort the merge, notify "Update needs a manual
     merge", and stop.
4. If the resulting commit equals the last installed commit, stop (nothing new).
5. Build: make sure fastforge is installed (`dart pub global activate
   fastforge`), then run `fastforge package --platform windows --target exe`.
   - If the build fails, or the installer is missing: notify, stop. Nothing is
     pushed or installed.
6. Push `my-version` to `origin`, and push `upstream/main` to `origin/main`.
   If the push fails, log it and carry on, since the push is only a backup.
7. Close the mod manager (`No_Reload_Mod_Manager.exe`), run the installer with
   `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`, and wait for it to finish.
8. Relaunch the app from the install folder (`%APPDATA%\No Reload Mod
   Manager\No_Reload_Mod_Manager.exe`). The installer skips its own launch
   step when it runs silently.
9. Save the commit to `state.json` and show a Windows toast notification:
   "Updated to <version> (<short commit>)".

Same app ID and install folder as the official installer, so the new build
installs over the existing one and keeps settings and mods.

**Flags:**
- `-DryRun`: steps 1–5 only (merge and build), with no push, no install, and
  no state update.
- `-Force`: rebuild even if the commit hasn't changed.

**Setup helpers:**
- `tools/self-update/install-task.ps1` registers the scheduled task.
- `tools/self-update/uninstall-task.ps1` removes it.
- First run of `update.ps1` creates the clone and adds the `upstream` remote
  if they're missing.
- One-time setup in the dev folder: add the `upstream` remote, create
  `my-version` from `Reorder-groups`, and push it to `origin`. The job reads
  `origin/my-version`, so it must exist before the first run.

## Error handling

Any failure leaves the currently installed app untouched, writes the reason to
the log, and shows a toast with that reason. Running the job again after
fixing the problem (for example, resolving a merge conflict in the dev folder
and pushing `my-version`) picks up where it left off.

## Testing

1. Run `update.ps1 -DryRun`. It should merge the 79 upstream commits and build
   an installer.
2. Run `update.ps1` by hand. Check that the installed version in Windows Apps
   matches the build, that the app reopens, that drag-to-reorder groups works,
   and that the settings "check for updates" button shows the new message.
3. Run `update.ps1` again. It should exit with "nothing new".
4. Register the scheduled task and trigger it once from Task Scheduler.

## Out of scope

GitHub Actions builds, public releases, code signing, and multiple users or
PCs.
