# UI groups (multi-on groups) — design

## Why

Character groups let one mod be on at a time. The user also has UI mods
(Genshin) that must all be on together and be switched individually, from NRMM,
without reloading the game (no F10). Today those mods sit loose in the game's
Mods folder, outside NRMM's managed folder, so NRMM cannot see them.

GameBanana download/update support is a **separate, later project**. It comes after this one.

## Goals

- A new kind of group, "UI group". Each mod in it has its own on/off switch.
  Several can be on at once.
- Toggling takes effect in game with a key press, no reload.
- Import loose mods from the game's Mods folder into a UI group (tick which ones).
- Keep new code in `lib/custom/`; keep edits to upstream files small
  (the self-update job merges upstream releases daily).

## Non-goals

- GameBanana integration.
- Changing how the mod .ini rewriter works (`_checkAndModifySections` and friends).
- Live toggling for mods the rewriter cannot manage (same limits as normal groups).

## Anti-goals

- Anything that needs an F10 reload per toggle.
- Anything that makes upstream merges conflict-prone.
- Breaking existing normal groups.

## How it works (the builder decides details)

- Existing mechanic: the rewriter writes `$managed_slot_id = <modIndex>` into
  each mod ini and gates it on the group's `active_slot`. Slot 0 = None.
  One number per group, so only one mod can be on.
- **UI group trick:** treat each mod in a UI group as its own two-state group
  (slot 0 = off, slot 1 = on). Toggle = the existing select key press with
  that mod's own group number and slot 0 or 1. The rewriter is untouched.
- Cost: each UI mod uses one of the 500 group numbers and needs its own
  `group_N.ini` control file (namespace must be unique per mod).
- Import: a button that lists loose mod folders in the game's Mods folder
  (outside the managed folder), lets the user tick some, and moves them into a UI group folder.
  Moving is safe because the managed folder lives inside Mods, so the game still finds them. (My call.)
- On-disk marker for "this group is a UI group": a small file in the group folder, like the
  other markers NRMM already keeps (my call).

## Step 1: throwaway spike (approved)

Before the full build, prove it with one real UI mod: make one mod behave as its own
two-state group and toggle it in game with no reload. If it fails, stop and come back to the design.

## Left to the builder

- Exact marker file name and how "Update Mod Data" numbers the groups.
- How the carousel and grid tabs draw a UI group (switch per mod).
- Whether the persisted on/off state is read from disk or tracked in memory.

## Risks

- A UI mod with unusual ini sections may not rewrite cleanly (same as today's normal groups).
- The 500-group cap, if the user imports a lot of mods.
