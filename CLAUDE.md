# CLAUDE.md

This is the user's **personal fork** of No Reload Mod Manager (a Flutter Windows
app). They are not contributing upstream. They run their own build, with their
own features, and a self-update job keeps it merged with the original creator's
releases.

## Repos and branches

| Name | What it is |
|---|---|
| `upstream` remote | The original: `https://github.com/Aglglg/No-Reload-Mod-Manager.git`. Read only. |
| `origin` remote | The user's fork: `https://github.com/Aswadina/No-Reload-Mod-Manager.git` |
| `my-version` | **The user's app.** All personal features live here. Feature branches come off it and merge back into it. |
| `main` | Pure mirror of `upstream/main`. Never commit to it or merge into it. |

Keep personal Dart changes in new files under `lib/custom/` where possible, and
keep edits to upstream files small. That keeps future upstream merges free of conflicts.

## The self-update job

Code: `tools/self-update/`. Design: `docs/superpowers/specs/2026-10-11-self-update-pipeline-design.md`.

- Windows scheduled task **`NRMM Self-Update`** runs daily at 04:00, plus as soon
  as possible after a missed run. It runs as the user, only when logged in.
- It works in its own clone at `%LOCALAPPDATA%\NRMM-Builder\repo` and never touches
  this dev folder. The task runs `update.ps1` *from that clone*, so pushing
  `my-version` updates the job itself.
- Each run does the following:
  1. Fetch upstream and origin.
  2. Reset the clone to `origin/my-version`.
  3. Merge the newest upstream **release tag** (`vX.Y.Z`, not `upstream/main`).
  4. If the merged content (git tree hash) matches `state.json`, stop.
  5. Otherwise build with fastforge (`dart pub global run fastforge:main package --platform windows --target exe`).
  6. Push `my-version` and the `main` mirror to origin.
  7. Close the app, install silently, and **always start the app afterwards**.
  8. Show a toast.
- When anything fails (merge conflict, build failure, missing installer), the
  installed app stays as it was, the reason goes to the log, and a toast is shown.
- Files: `%LOCALAPPDATA%\NRMM-Builder\state.json` (last install),
  `logs\yyyy-MM-dd.log` (keeps 30), `update.lock`.
- Installed app: `%APPDATA%\No Reload Mod Manager\No_Reload_Mod_Manager.exe`.
- The app's own upstream auto-updater is switched off. Settings → "Check for
  Updates" shows `lib/custom/self_update_dialog.dart` instead.

### Commands (run from this folder)

| Task | Command |
|---|---|
| Update now | `powershell -ExecutionPolicy Bypass -File tools\self-update\update.ps1` |
| Rebuild even if nothing changed | add `-Force` |
| Merge and build only, no push or install | add `-DryRun` |
| Tests (Pester 3.4: use `Should Be`, not `Should -Be`) | `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tools/self-update/tests -EnableExit"` |
| Register / repair the task | `powershell -ExecutionPolicy Bypass -File tools\self-update\install-task.ps1` |
| Remove the task | `powershell -ExecutionPolicy Bypass -File tools\self-update\uninstall-task.ps1` |
| Task status | `Get-ScheduledTaskInfo -TaskName 'NRMM Self-Update'` |

### When the user asks to "pull the latest changes and update"

1. Fetch upstream tags and say what the newest release is.
2. Run `update.ps1` and report what it logged ("Nothing new", or the version it installed).
3. If it reports a **merge conflict**, resolve it in this dev folder: on
   `my-version`, merge the tag, fix the conflicts, run the tests, and push.
   Then run `update.ps1` again.

### Gotchas

- Scripts must run on **Windows PowerShell 5.1** (no `pwsh`, `&&`, `??`).
- A bad push of `tools/self-update/*` can break the job before it resets its
  clone. To repair it, push the fix, then re-run `install-task.ps1`.
- Running `update.ps1` for real closes the user's mod manager for about 2 minutes. Say
  so before doing it.
