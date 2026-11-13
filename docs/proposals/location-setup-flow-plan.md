# Location setup: guided flow — implementation plan

Status: **in progress** (T00–T02 done). Vishnu, 13 Nov 2026.
Go-ahead: given by the manager for the proposal page (reported by Vishnu, 13 Nov 2026). To be recorded in `STATE.md` → *Decisions* as task T01 below.
Proposal with screen mock-ups: https://claude.ai/artifact/Aksmr3FLPxsY6DUQPzgpzv

Everything in "What is true today" was checked in the code on branch `PX-08-T02-next-changes` (which contains `PX-01-T17-invite-flow-fixes` at `e9f2e56`). Section 6 marks what is built.

## 1. Goal

An Enterprise Admin sets up a unit's locations without having to learn "levels", "skeleton" or "placeholder". They describe one real place, name each kind of place, add the rest, and publish. The stored data, the API and the phone app do not change.

## 2. What is true today (checked)

| Fact | Where |
|---|---|
| A new unit gets one `location_hierarchy_version` row and **no levels** | `api/app/repositories/business_units.py:76` |
| Levels are saved as one whole list; the top one is always required; names must differ (case-insensitive); 1–100 characters | `services/locations.py` `set_levels`, `LevelInput` |
| A level that has locations can't be removed or turned off; a new level above existing locations is saved as optional | `set_levels` |
| A place can only be added **under a parent** (`parent_id` is required) | `NewNodes`, `add_nodes` (contract 2.4) |
| So the top place can only be created by the skeleton call, which makes one placeholder per level in use and names the top one after the unit's `facility_name` | `create_skeleton` (contract 2.3) |
| Renaming a place clears its placeholder flag; names are 1–200 characters and unique among siblings | `change_node` (contract 2.5) |
| Publishing is refused only while placeholders are left. **An empty branch is reported but does not block publishing** | `_check`: `can_publish = not published and nodes and placeholders == 0` |
| A technician can scan at the deepest required level or below; the phone uses the same rule | `_check`, `mobile/lib/features/scan/location_pick.dart` |
| The phone shows each level's name as the label of its picker, and reads only the published tree (contract 2.9) | `mobile/lib/features/scan/location_screen.dart` |
| The web forces at least 2 levels; the API accepts 1 | `LevelsEditor.tsx` `save` |
| Web code for this area: 6 files, about 1,160 lines, plus 2 test files (9 page tests, 12 helper tests). API: 9 integration tests in `test_locations.py` | `web/src/features/locations/` |
| No `specs/SPEC-PX-05.md` exists, and no `PX-05` task or commit exists | `specs/`, `STATE.md`, `git log` |
| Design canvases are the source of truth for screens (EA-02 = EA 12, 19) | `CONSTITUTION.md` §0, `docs/design/README.md` |
| Open and therefore **not built**: O-5 (limit on levels), O-19 (restore a deleted location) | `docs/api-contracts.md` |

## 3. Decisions (made by the project's rules)

Rules applied: reuse existing logic and components before adding any; contract first; frozen data model; nothing OPEN is built; no new library without approval; PRD V1 is the baseline; canvases are the source for screens, so a difference must be recorded.

| # | Question | Decision | Why |
|---|---|---|---|
| D1 | How is the first real place saved? | **Existing calls only:** levels (2.2) → skeleton (2.3) → rename each place (2.5). No new endpoint, no contract change. | Reuses logic that is already built, tested (9 API tests) and audited. A new "create with names" endpoint would be a second way to do the same thing. Safe to retry: a second skeleton call is refused with 409 (tree not empty), and every call locks the unit's version row, so two admins can't corrupt it. |
| D2 | Empty branch (a building with nothing inside) | **Warn, do not block**, exactly as the API does today. | Blocking would change contracts 2.7 and 2.8 and the publish rule. The mock-up's greyed-out Publish button for this case is **not** built; the button follows the API's `can_publish`. |
| D3 | The "Off" rule | **Kept.** | PRD FR-2.1 defines levels as "required, optional or off", so it cannot be dropped. The guided steps offer required or optional (a checkbox); Off stays where it is today, in the level editor, which "Edit kinds" opens unchanged. |
| D4 | Create-unit label "Facility (top location level)" | **Not changed in this work.** | It is a different screen (EA-01) and was not part of the go-ahead. Raised as a follow-up (section 11). The guided setup shows the same value as "your site", which removes most of the confusion without touching that screen. |
| D5 | Screens differ from canvas EA 12 and EA 19 | **Record it** in `STATE.md` → *Decisions* and in `docs/design/README.md`, with the link to the proposal page, before any code. | Constitution §0: canvases are the source of truth for screens, so the approved difference must be written down. |
| D6 | Drag to move or reorder | **Not built.** | It needs a new library. The existing Move dialog and ↑ ↓ buttons already do this. |
| D7 | Task IDs and spec | `PX-05-T01…`; section 5 is the requirement list. | BC-05 Locations maps to SPEC-PX-05 in the Constitution; no such file or task exists yet. |

One thing still needs a person, not a rule: **confirm the go-ahead in writing** (who, date) so T01 can record it.

## 4. The new flow, screen by screen

The Locations page picks one screen from the unit's saved state. No tabs.

| Saved state | Screen shown |
|---|---|
| No levels, no places | **Guided setup** step 1, then step 2 |
| Levels saved, no places (a unit left half-way under the old screens) | Guided setup, step 1, with the saved kinds already filled in step 2 |
| Places exist, not published | **Working page** |
| Published | Working page, read-only |

### Guided setup
1. **Describe one place.** A row of boxes, biggest to smallest. The first box is filled with the unit's `facility_name`. "+ Add a smaller part" adds a box; ✕ removes one; at least 2 boxes.
2. **Name each kind.** Under each typed place, a box for the kind (Plant, Building, Shop, Bin). "Common setups" buttons fill these from today's presets. A checkbox per middle kind: "Not every … has a …" (saves the level as optional).
3. **Create** (D1): save levels → create skeleton → rename each place to the typed name. Then open the working page.

Checks before sending, so the API never refuses: every box filled; kinds differ from each other (case-insensitive); kind ≤ 100 characters; place ≤ 200 characters.

### Working page
- A banner: "Not published yet", how many things are left to fix, and "Review & publish".
- The list of places with **Kind** and **Status** on every row (Placeholder / Scan here / Needs a … / Ready — already built in T00).
- Row actions as today: add the next kind (named, e.g. "+ Bin"), add several, rename, move, delete.
- "Kinds: Plant › Building › Shop › Bin · Edit kinds" opens today's level editor (`LevelsEditor`, unchanged rules, including Off) in a dialog.
- **Phone preview** beside the list: what a technician picks for the selected place, using the same rule as the phone.

### Publish dialog
- The "can't be undone" warning first.
- Counts by kind ("2 Buildings · 1 Shop · 2 Bins").
- Problems name the place ("Warehouse D has no Bin yet") with "Show me". An empty branch is a warning; only placeholders disable Publish (D2).
- The example path as today.

## 5. Requirements (GIVEN / WHEN / THEN)

| ID | Requirement |
|---|---|
| R1 | GIVEN a unit with no levels WHEN the EA opens Locations THEN step 1 shows with the first box filled with the unit's facility name. |
| R2 | GIVEN step 1 with fewer than 2 filled boxes WHEN Next is pressed THEN it stays and says what is missing. |
| R3 | GIVEN step 2 WHEN two kinds have the same name (any letter case) THEN Create is refused with a message, before anything is sent. |
| R4 | GIVEN valid steps 1 and 2 WHEN Create is pressed THEN contract 2.2 gets the kinds in order (optional where ticked), 2.3 is called once, and 2.5 is called once for every place, the top one included, with the typed name. A rename is what clears the placeholder flag, so it is sent even when the name is unchanged. |
| R5 | GIVEN a rename fails during Create WHEN the page reloads THEN the working page shows, with the unrenamed places marked Placeholder, and an error message. |
| R6 | GIVEN places exist WHEN the EA opens Locations THEN the working page shows (no tabs), with a status on every row. |
| R7 | GIVEN a place is selected THEN the phone preview shows one picker per kind in use below the top, with that place's path, and says whether a technician can scan there. |
| R8 | GIVEN "Edit kinds" WHEN a kind is added, renamed, removed or reordered THEN contract 2.2 is called with the whole list and the API's refusals are shown as messages. |
| R9 | GIVEN the publish dialog THEN the irreversible warning is first, counts use kind names, and each empty branch is named. |
| R10 | GIVEN a published unit THEN the working page is read-only and says why. |
| R11 | Everything the old screens could do is still possible: quick start, add one or several (up to 50), choose what goes inside when a kind can be skipped, rename, move, delete with confirmation, search, publish. |

## 6. Tasks

Each task: tests first, ≤ 5 files, ≤ 200 changed lines, its own PR. Web only unless stated. Grade A2 (BC-05).

| ID | Task | Files | Needs |
|---|---|---|---|
| T00 | **Done** (`2ed97f0`): Status column shows a status on every row; shared `canScanAt` and `rowStatus` rules | `locationTree.ts`, `locationTree.test.ts`, `LocationTreeView.tsx` | — |
| T01 | **Done** (`9db1a0c`): Record D1–D7 in `STATE.md`; note the canvas difference in `docs/design/README.md` | 2 docs | decisions |
| T02 | **Done**, split for the size rule. T02a (`fbbf03d`): which screen to show, step 1's start values, the checks; plus an API test proving a same-name rename clears the placeholder flag. T02b: the 2.2 body, the renames, the phone-preview data | `guideRules.ts` (new, keeps these rules apart from the tree helpers; first named `setupGuide.ts`, renamed in T03 because it clashed with `SetupGuide.tsx` on case-insensitive file systems), `guideRules.test.ts`, `api/tests/integration/test_locations.py` | T01 |
| T03 | Guided setup, step 1 and step 2 (new component `SetupGuide.tsx`) | `SetupGuide.tsx`, its test | T02 |
| T04 | Create sequence 2.2 → 2.3 → 2.5 with the failure path (R4, R5); Locations page chooses the screen and drops the tabs | `LocationsPage.tsx`, `SetupGuide.tsx`, `api/locations.ts`, tests | T03 |
| T05 | Working page: banner with things to fix, "Kinds … · Edit kinds", named add buttons, remove "skeleton" wording | `LocationTreeView.tsx`, `LocationsPage.tsx`, tests | T04 |
| T06 | "Edit kinds" dialog: today's `LevelsEditor` shown inside a `Dialog`. Its rules and its Required / Optional / Off choice are not rewritten | `LevelsEditor.tsx`, `LocationTreeView.tsx`, tests | T05 |
| T07 | Phone preview (new component `PhonePreview.tsx`) on the working page | `PhonePreview.tsx`, `LocationTreeView.tsx`, tests | T02, T05 |
| T08 | Publish dialog: warning first, counts by kind, named problems, "Show me" | `PublishDialog.tsx`, `LocationsPage.tsx`, tests | T05 |
| T09 | Clean-up and proof: remove unused code and old texts; full web suite; manual end-to-end run (section 8); update `docs/handover.md` | ≤ 5 files | all |

New components (`SetupGuide`, `PhonePreview`) are needed because nothing existing fits; all other UI reuses `Dialog`, `ConfirmDialog`, `DataTable`, `TextField`, `SelectField`, `Badge`, `Button`, `Alert`, `Card`. No new library.

**Reuse, so there is one copy of each rule**
- Kinds are sent as the existing `LevelInput[]`; "Common setups" are the existing `presets`.
- Add one / add several, rename, move and delete stay in the existing `NodeDialogs` (with `rangeNames`, the sibling-name check and the Idempotency-Key per dialog).
- "Can a technician scan here" has one rule, `canScanAt`, used by the Status column and the phone preview; it mirrors the API's publish check and the phone's picker.
- Publish keeps using the API's `can_publish`; the web adds no rule of its own.

## 7. What does not change

- Data model: no table or column.
- API and contracts: none. The 9 API tests in `test_locations.py` must still pass untouched.
- Phone app: none. It reads the published tree (2.9), whose shape is the same.
- Not built here: drag and drop (D6), restore a deleted location (O-19, open), a limit on levels (O-5, open), editing after publish (not V1), the create-unit label (D4).

## 8. How it is tested

- **Helpers:** unit tests for every rule in T02 (screen choice, validation, request building, preview).
- **Screens:** component tests for R1–R11, with the API hooks mocked as `LocationsPage.test.tsx` does today. The 9 existing page tests are kept or rewritten one for one so no behaviour loses its test.
- **Gates on every PR:** `npm run typecheck`, `lint`, `format:check`, `test`; 80% coverage on changed lines; diff ≤ 300 lines.
- **Coverage gap:** the web project has no coverage tool installed (`@vitest/coverage-*` is missing), so the 80% rule can't be measured for web code yet. Adding it is a new dependency and needs approval. Until then, every exported rule has its own tests.
- **Manual end-to-end, on a fresh unit:**
  1. Create unit "Plant 04 — Coatings", with "Plant 04" in the Facility field.
  2. Step 1: Plant 04 › Building C › Paint Shop › Bin 07. Step 2: Plant › Building › Shop (not always) › Bin. Create.
  3. Working page shows the 4 places, none marked Placeholder; Bin 07 says "Scan here".
  4. Add Bin 08, add "Warehouse D" (shows "Needs a Bin"), add several Bin 01–03 inside it.
  5. Edit kinds: rename "Shop" to "Area"; check that "Bin" cannot be removed (it has places).
  6. Publish; the page becomes read-only.
  7. On the phone, as a technician of that unit: the picker shows Building → Area → Bin and a scan can be placed at Bin 07.
- **Old half-set-up units:** open a unit that has levels but no places, and one with placeholders left; both must open on the right screen (section 4 table).

## 9. Risks

| Risk | Handling |
|---|---|
| Create is several calls, not one (D1); a failure can leave placeholders | R5: the working page shows them and they can be renamed there. Tested. |
| A typed place has the same name as its placeholder (kind "Bin", place "Bin"; or the top place, which the skeleton already names after the unit) | Skipping the rename would leave the placeholder flag set and block publishing. R4 sends the rename for every place; T02 tests this case. Proven by the API test `test_renaming_a_placeholder_to_its_own_name_clears_the_flag` (T02a). |
| The canvas and the app differ (Constitution §0) | D5 recorded in `STATE.md` before coding. |
| Units set up half-way under the old screens | Section 4 table; tested in section 8. |
| A half-set-up unit has a level that is Off | The skeleton makes no place for an Off level, so the guided steps show boxes only for levels in use and send the Off level back unchanged. T02 tests this case. |
| Task size limits | Tasks are split so each stays within 5 files and 200 lines; split further if one grows. |
| Very large trees | The list loads and draws every place of a unit at once, as it does today; this work does not change that and adds no extra requests per row. How it behaves with thousands of places has **not been measured**. T09 measures it with a seeded large tree and reports the result. |
| Audit log | Create writes one "levels saved", one "placeholders created" and one "renamed" entry per place. These are true records of what happened; no audit code changes. |

## 10. Order of work

T01 → T02 → T03 → T04 → T05 → (T06, T07, T08 in any order) → T09. T00 can be committed now.

## 11. Follow-ups (not part of this work)

- Create-unit screen: the label "Facility (top location level)" reads like a level but is the name of the top place. Needs a canvas decision (EA-01).
- Empty branches: decide whether publishing should be blocked (contracts 2.7, 2.8).
- A `specs/SPEC-PX-05.md` file, so later tasks have a spec to cite.
