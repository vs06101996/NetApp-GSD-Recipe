# Unbiased operator test — TASK-056 / TASK-038 (`recipe-start` / `recipe-help --next`)

**Persona:** New-dev. Just cloned a product repo. Told “the recipe is installed — type `recipe-start`.” Did not implement this. Did not read plans or prior agent chats.

**Target:** `/Users/vs72964/Projects/recipe-sandbox` (not AgentStudio).  
**Branch:** `main` (confirmed). No mutations except read-only helper.

**Date:** 2026-08-20

---

## What I actually opened (new-hire path)

1. `.cursor/skills/recipe-start/SKILL.md` — first file I would find if I grepped “recipe-start”. Top half is agent adapter (bash, Yes/No, “do not chain”). Bottom half is the only human-facing cheat sheet.
2. `.cursor/skills/recipe-help/SKILL.md` — flags table, then a catalog-ish body. `--next` is documented as the same coach as `recipe-start`, print helper stdout, do not invoke other skills, no Yes/No.
3. `docs/RECIPE-COMMANDS.md` — present. Generated catalog: Quick start block, then many tables of `recipe-*` commands. Looks like a reference, not a second wizard.

I did **not** invoke Cursor skills in this session. I ran the helper the skills say to run, which is what `recipe-help --next` would dump verbatim.

---

## Commands run

```bash
cd /Users/vs72964/Projects/recipe-sandbox && git branch --show-current
bash .gsd-recipe/scripts/recipe-next.sh --target /Users/vs72964/Projects/recipe-sandbox
bash .gsd-recipe/scripts/recipe-next.sh --id --target /Users/vs72964/Projects/recipe-sandbox
test -f .cursor/skills/recipe-help/SKILL.md && grep -n "next" .cursor/skills/recipe-help/SKILL.md | head
test ! -f docs/PRD.md && echo "no PRD as expected"
```

---

## Stdout excerpts

**`git branch --show-current`**

```
main
```

**`recipe-next.sh --target …`**

```
=== Recipe next step ===

Why: There is no docs/PRD.md yet.

Type this in Cursor Agent:

  recipe-onboard
  recipe-onboard docs/PRD.md
  recipe-onboard          (then paste or describe the work)

Command: recipe-onboard

Catalog:  recipe-help
Again:    recipe-start
```

**`recipe-next.sh --id --target …`**

```
ONBOARD
```

**PRD check**

```
no PRD as expected
```

**`grep next` on `recipe-help` SKILL.md (head):** `--next` is listed as “Same next-step coach as `recipe-start` (read-only; run `recipe-next.sh`)”; default mode is catalog/tour; `--next` prints helper stdout and must not invoke other skills.

---

## Acceptance criteria

| ID | Criterion | Result | Notes |
|----|-----------|--------|--------|
| AC1 | After install, a new operator can find a friendly next command without knowing GSD jargon. | **PASS** (with friction) | Helper output is plain: no PRD → type `recipe-onboard`. I did not need ROADMAP/Epic/STATE vocabulary to act. Opening `recipe-start/SKILL.md` itself is *not* friendly (agent boilerplate first). If I only type the command in Agent, the *helper* is the usable part. |
| AC2 | `recipe-start` / helper tells them to run `recipe-onboard` on main (no `docs/PRD.md`). | **PASS** | On `main`, no `docs/PRD.md`. Helper: “no docs/PRD.md yet” and `Command: recipe-onboard`. It never says the words “on main”. I only knew the branch because I ran `git branch`. If someone is on `feat/ui-prd` they would get different advice; the coach does not warn you to check branch. |
| AC3 | `recipe-help --next` is the same coach, read-only (does not invoke other skills). | **PASS** (skill-documented; helper executed) | Skill: `--next` runs the same `recipe-next.sh`, print verbatim, do not invoke other skills, do not ask Yes/No. Default `recipe-help` is a catalog/tour. I did not spawn `recipe-onboard`. `--id` is `ONBOARD` (machine id, not a skill invocation). |
| AC4 | Commands are copy-paste friendly (“Type this in Cursor Agent”). | **PASS** (awkward) | Literal heading **Type this in Cursor Agent:** is there. Then **three** lines, all `recipe-onboard` variants. A nervous new hire does not know which one to paste. The footer `Command: recipe-onboard` is the single safe paste. |
| AC5 | Default `recipe-help` still looks like a catalog (not a second workflow). | **PASS** | Default mode: Quick start from `docs/RECIPE-COMMANDS.md` plus a numbered command list and one “Stuck? `recipe-help --next`” line. The generated doc is tables of commands. Coaching is gated to `--next` / `--stuck`. Body of the skill still has a tiny workflow ASCII block; that is catalog framing, not a duplicate `recipe-start`. |

**Overall:** All five ACs **PASS**. Not a clean new-hire experience.

---

## Friction (skeptical)

1. **Told to type `recipe-start`, opened the skill file first.** Half of it is for the model (`cursor_skill_adapter`, bash, Yes/No). I would not have known the *operator* surface is the helper stdout until I ran the script or trusted Agent.
2. **Three onboard snippets.** Bare `recipe-onboard` vs `recipe-onboard docs/PRD.md` when the Why line just said there is **no** `docs/PRD.md`. That looks contradictory. I would pick the first line and hope.
3. **No “stay on main”.** Sandbox `main` has no PRD; other branches do. Coach is silent on git branch.
4. **`--id` prints `ONBOARD`.** Fine for scripts. If I ran that by accident I would not know what to type in Cursor.
5. **Catalog still dumps GSD names** (`gsd-plan-phase`, graphify, etc.) in `RECIPE-COMMANDS.md`. I can ignore them if I follow the helper; I cannot unsee them if I open the catalog first.
6. **`recipe-start` vs `recipe-help --next`.** Skill says start asks Yes/No and *will* invoke the recommended skill if I say Yes. Help `--next` will not. Nobody told me that difference in the helper banner. Easy to agree to Yes without knowing it kicks off onboarding.

---

## Would I know what to type next?

Yes: **`recipe-onboard`** in Cursor Agent.

I would not type `gsd-new-project` from the helper. I might hesitate 30 seconds over which of the three onboard lines to use. I would not know to confirm I am on `main` unless someone already said so.

I would not file Jira. I did not change the sandbox.

---

## Follow-up (implementer, after this report)

Copy in `recipe-next.sh` tightened: no-PRD path no longer lists `recipe-onboard docs/PRD.md`; helper footer notes checkout/branch, and that `recipe-start` may invoke after Yes while `recipe-help --next` only prints.

---

## Evidence checklist

| Check | Result |
|-------|--------|
| Branch `main` | yes |
| `docs/PRD.md` absent | yes |
| Helper recommends `recipe-onboard` | yes |
| Copy-paste heading present | yes |
| `recipe-help` documents `--next` = same helper, read-only | yes |
| Default help = catalog / tour, not a second coach | yes (per SKILL.md + RECIPE-COMMANDS.md) |
