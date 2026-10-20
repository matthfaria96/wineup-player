---
phase: 01-funda-o-e-infraestrutura-de-teste
plan: 02
subsystem: core
tags: [track-id, domain]
requirements-completed: [FND-01, FND-03]
completed: 2026-10-20
---

# Phase 1 Plan 2: TrackID estável

Track, TrackID (UUID), MarkColor (sem Color) e Clock agora vivem no WineupCore, com TrackList (removing/neighbor com wrap-around) e TrackID.seed determinístico. O app usa `TrackID?` em currentID/selectedID; a cor de MarkColor é extensão na UI; TrackRow recebe `index` de exibição.

## Commits
- feat: Track, TrackID estável, MarkColor e Clock no WineupCore (testes: 6 novos)
- refactor: app Wineup usa o núcleo e TrackID estável

## Deviations
None - plano executado como escrito (testes e implementação no mesmo commit em vez de RED/GREEN separados).

## Verification
`swift build -c release` OK; `./scripts/test.sh` exit 0 (9 testes).

## Known Stubs
None.

## Self-Check: PASSED
