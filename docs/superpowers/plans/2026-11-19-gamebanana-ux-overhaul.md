# GameBanana tab: UX overhaul plan

Builds on `docs/superpowers/specs/2026-11-04-gamebanana-design.md` (the tab as shipped).
This plan only changes how the tab looks and feels, plus the small API pieces it needs.

## What is wrong today

From your feedback and from reading the code I wrote:

1. **No way to narrow results.** Only 4 sort buttons. No category filter.
2. **Pictures are tiny.** The details dialog is a fixed 680 x 340 box. The main picture is about 230 px wide. You cannot enlarge it.
3. **"Put it in" is a plain dropdown of group names.** No icons, no search, no hint which group fits, and "New group" has no name.
4. **After a download you must run Update Mod Data yourself.** NRMM does not even say where the mod went.
5. **Downloads block the dialog.** Text status only: no percentage, no cancel, no browsing meanwhile.
6. **Update discovery is weak.** The "Update" badge only shows when GameBanana sends an updated date, and there is no "what needs updating" view.
7. **Mature content is shown with no control.** In Genshin, 10 of the 15 most-liked mods carry content ratings, and GameBanana hides their images by default. NRMM shows them. This matters in a game overlay.
8. **Cards say very little.** No category, no age, no download count. A spinner instead of placeholders while loading.
9. **Descriptions lose their formatting.** Links, lists and credits are stripped. No license, no requirements, no changelog, no "open on GameBanana".
10. **Nothing is remembered.** Sort, filters and last-used group reset every time.

## What GameBanana gives us (checked live)

- **Categories:** `GET /Mod/Categories?_idGameRow=<game>&_sSort=a_to_z&_bShowEmpty=false` returns the top categories with counts. Genshin has 7: Skins 12,644, Other/Misc 226, UI 213, Objects 194, Gadget 52, Waverider 11, Cutscenes 1.
- **Filtering:** add `_aFilters[Generic_Category]=<id>` to the browse call. It works for top categories and for sub-categories (tested with Entities/NPCs: 89 results).
- **Sub-categories:** every result names its sub-category and id. Skins has only 3 and UI has 4. But there is **no per-character category**: about 95% of Genshin mods are Skins, so a category filter alone barely narrows them.
- **Mature content:** each result has `_bHasContentRatings` and `_sInitialVisibility` (`hide` for rated mods).
- **Mod page extras:** category, tags, credits, license checklist, requirements, download/view/like counts, update count.
- **Changelog:** `GET /Mod/<id>/Updates` lists update posts (name, date, text). Checked.
- **Not found:** an endpoint that lists a category's sub-categories. We only learn them from results.

## The new experience

Layouts are described in words. Before building each screen I will show a mockup built from NRMM's own theme (not generic boxes), as agreed.

### Browse screen
- **Top row:** search box with a clear (x) button, a sort dropdown, and a small "mature content" switch (Hide / Blur / Show).
- **Second row, "Find mods for":** one chip per group you already have in NRMM (Raiden, Hu Tao, Furina…). Clicking one searches GameBanana for that character. This is the fix for the character problem, and it uses what NRMM already knows about you.
- **Third row, categories:** All, then GameBanana's categories with counts (Skins, UI, Objects…). Picking Skins or UI shows its sub-categories as smaller chips.
- **Segments:** Browse, Installed (count), Updates (count, orange when above zero). Installed and Updates only list mods that came from GameBanana.
- **Cards:** same look as your mod cards. Add a small category tag, "3d ago", download count, and a clear Installed / Update badge. Rated mods are blurred with an "18+" note until you click to reveal (if set to Blur).
- **Loading:** placeholder cards instead of a spinner, images fade in, and the result count shows ("484 mods").
- **Remembered per game:** sort, category, mature setting.

### Details dialog (large)
- Fills most of the window instead of a fixed small box.
- **Left:** one big picture with next/previous arrows, a strip of thumbnails below. Click the picture to open a **full-screen viewer**: arrow keys to move, Esc or click outside to close, mouse wheel to zoom, drag to pan.
- **Right:** title, author, category, tags, counts (downloads, likes, views, updated), then tabs: **About** (formatted text with working links, lists, bold), **Files** (each file with size, date, note, "newest" label), **Changelog**, **Credits and license**.
- **Open on GameBanana** button for anything we do not show.

### "Put it in" picker (replaces the dropdown)
- A panel with a search box and a list of rows: group icon, group name, number of mods, a "UI group" badge where it applies.
- **Suggested** group pinned on top with the reason ("name matches Raiden", or "UI mods go in your UI group"). It uses the mod name, its category, and the group names. UI-category mods suggest a UI group, which links this feature to the UI groups work.
- Then **Recent**, then everything else.
- **New group** opens a small form: name, and type (Character group or UI group). No more nameless groups.
- It remembers your last choice per category.

### Install experience
- Downloads run **in the background**. The dialog can close, and you keep browsing.
- A small progress chip in the tab header shows percent and a cancel button.
- When done: a toast with **Set up now** (opens the existing Update Mod Data dialog for you) and **Show in Mods** (jumps to that group).

### Updates
- The **Updates** segment checks your installed GameBanana mods one at a time (spaced out, cached for a few hours). It never runs in the background.
- Each row shows old vs new file, the changelog text, and an **Update** button. **Update all** at the top.
- The tab bar shows a small count badge when updates are waiting.
- Old versions stay in the backup folder; add a **Restore previous version** action.

### Polish
- Keyboard: arrows and Enter in the grid, Esc closes dialogs. Works with the existing E/Q tab keys.
- Clear error screens with "Try again", an offline message, and an "Open in browser" fallback.
- Works at small window sizes (the app minimum is 750 wide).

## Build order (three releases, each usable on its own)

**Release 1: what you asked for first**
1. API: categories, category filter, mature fields, richer mod and details data, tests on real fixtures.
2. Browse screen: filter rows, "Find mods for" chips, sort dropdown, remembered settings, placeholder loading, mature setting, richer cards.
3. Details dialog: large layout, gallery, full-screen viewer, formatted About, Files, Credits and license.
4. "Put it in" picker with suggestions, search and named new group.

**Release 2: friction and updates**
5. Background downloads with progress and cancel.
6. Set up now / Show in Mods after install.
7. Installed and Updates segments, changelog, Update all, tab badge, restore previous version.

**Release 3: polish**
8. Keyboard navigation, error and offline states, small-window layout, accessibility labels.
9. Final review pass against the real app.

Each release: tests green, `flutter analyze` clean for new code, I show you the screens as in-app-look mockups first, you check it in your real app before I go further.

## Decisions I need from you

1. **Mature content default.** Blur with click-to-reveal (my pick), Hide completely, or Show everything as today?
2. **After a download:** a "Set up now" button (my pick), set up automatically every time, or leave it manual?
3. **Tab position.** Keep GameBanana last (today), or move it between Mods and Settings? Moving it means editing about a dozen upstream spots and risks merge conflicts. I would keep it last.

## Risks and what is not yet verified

- **Facts proved:** category list, category and sub-category filtering, the changelog endpoint, and the mature-content flags all work against the live API.
- **Guesses:** that "Find mods for" using your group names gives good results. Search is by name, so a group called "Mavuika - Nord Express" may need trimming to the character name.
- **Needs testing:** how it feels in the real app. I have not seen the screens running; your feedback is my evidence. I will rely on you for visual checks after each release.
- **Rate limits are still unknown.** The new features add requests (categories once per game, the update check once per installed mod). All are spaced out, cached and user-triggered.
- **The Updates check can be wrong** if GameBanana lists files oddly. The exact check (newest file id and date) stays the source of truth.
