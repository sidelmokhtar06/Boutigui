<!-- BEGIN:flutter-agent-rules -->

# Flutter + Supabase, pas de framework web

Ce dépôt est une application **Flutter** (Dart, `pubspec.yaml`) avec
Supabase comme backend. Il n'y a ni Node, ni `node_modules/`, ni Next.js,
ni Tailwind. Toute consigne héritée parlant de Next.js ou de classes
Tailwind ne s'applique pas ici.

Contraintes de version qui ont déjà coûté du temps :

- Flutter 3.27.4 / Dart 3.13.1 — `google_fonts` a été retiré entièrement
  le 15 septembre 2026 faute de version compatible (voir `core/theme.dart`).
  Vérifier la compatibilité avant d'ajouter la moindre dépendance.
- Les migrations SQL se collent à la main dans l'éditeur SQL de Supabase,
  dans l'ordre listé par `supabase/AGENTS.md`. Aucun outil de migration.

<!-- END:flutter-agent-rules -->

## Read Before Anything Else

Read in this exact order before any implementation:

1. `AGENTS.md` — root project context, maintained by `/audit` and `/sync`. This is the source of truth for the codebase itself.
2. context/project-overview.md
3. context/architecture.md
4. context/ui-tokens.md
5. context/ui-rules.md
6. context/ui-registry.md
7. context/code-standards.md
8. context/library-docs.md
9. context/build-plan.md
10. context/progress-tracker.md
11. `docs/specs/<relevant-spec>.md` — if the current feature has an approved spec from `/architect`, read it too. `/develop` won't proceed on a load-bearing feature without one.

If `AGENTS.md` doesn't exist yet, run `/audit` before anything else — everything downstream assumes it's there.

## Rules That Never Change

- Never use hardcoded hex values in widget code — every colour comes from `AppTheme` in `lib/core/theme.dart`
- Update `progress-tracker.md` and `ui-registry.md` after every feature — this is manual; no installed skill does it for you
- Before any third-party library — load its installed skill first, then read `context/library-docs.md` for project-specific rules
- If `/develop` reports a load-bearing decision is unmade, or no spec covers what's needed — stop and run `/architect` first. Never guess at an undecided architectural choice.
- If the same problem persists after one corrective prompt — stop immediately and run `/debug`
- Run `/sync` as the last step after any change is complete, before starting the next feature

## Available Skills

From [jsmastery-pro/skills](https://github.com/jsmastery-pro/skills) — install with the command at the bottom of this file.

- `/scope` — turn a product idea into a living, coarse scope in `docs/scope/`. Run before `/architect` on a new feature area.
- `/architect` — before any complex feature, page, or tech-stack decision. Asks deep questions, recommends an answer, writes a build spec to `docs/specs/`.
- `/develop` — build a feature, page, or API from an approved spec. Stops and routes to `/architect` if something load-bearing is undecided.
- `/check verify` — after `/develop`. Drives the real app and proves behavior against the spec.
- `/check review` — before a PR. Runs a code review on a different model than wrote the code.
- `/debug` — when something breaks or behaves unexpectedly and the cause isn't obvious. Reproduce → localize → hypothesize → fix → verify.
- `/test` — after implementing or changing a feature. Writes the test suite for what changed.
- `/document pr | changelog | release-note | postmortem` — writes the human-facing prose about a finished change.
- `/audit` — bootstraps or refreshes `AGENTS.md` on a greenfield project or an area with missing docs (`/audit src/auth`).
- `/sync` — last step after a change is complete. Updates `AGENTS.md`, reconciles scope, flags specs the change made stale.

## Context files

- [supabase/AGENTS.md](supabase/AGENTS.md): SQL run order, RLS gotchas, and the four patch files the code names but the repo lacks
- [lib/services/AGENTS.md](lib/services/AGENTS.md): the Supabase data layer, its conventions and its silent failure modes

## Installing the Skills

Run once at the project root (your own terminal or Claude Code session — not here), then restart Claude Code:

```bash
# Installs into .claude/skills/ of the current project, for Claude Code
npx skills@latest add jsmastery-pro/skills -a claude-code

# Generic .agents/skills, read by Codex and other agents
npx skills@latest add jsmastery-pro/skills
```