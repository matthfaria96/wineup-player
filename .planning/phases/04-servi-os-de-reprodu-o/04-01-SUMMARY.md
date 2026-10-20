---
phase: 04-servi-os-de-reprodu-o
plan: 01
subsystem: playback
tags: [swift, queue, session, gapless]
requires: []
provides:
  - target WineupServices (PlaybackController, SessionStore, SettingsStore)
  - PlaybackQueue pura em WineupCore
  - helpers de teste ServicesFixtures
affects: [04-02, 04-03, 04-04, 04-05]
tech-stack:
  added: []
  patterns: [fila imutavel por valor, shuffle SplitMix64 com semente, sessao JSON em app_setting]
key-files:
  created:
    - Sources/WineupCore/Audio/PlaybackQueue.swift
    - Sources/WineupServices/WineupServices.swift
    - Sources/WineupServices/PlaybackController.swift
    - Sources/WineupServices/SettingsStore.swift
    - Sources/WineupServices/SessionStore.swift
    - Tests/WineupCoreTests/PlaybackQueueTests.swift
    - Tests/WineupServicesTests/SmokeTests.swift
    - Tests/WineupServicesTests/PlaybackControllerTests.swift
    - Tests/WineupServicesTests/SessionStoreTests.swift
    - Tests/WineupServicesTests/Support/ServicesFixtures.swift
  modified:
    - Package.swift
    - Sources/WineupCore/Audio/NextTrackPlanner.swift
key-decisions:
  - "selecting(index:) preserva a ordem embaralhada para a travessia terminar"
requirements-completed: [PLAY-01, PLAY-03]
duration: ~30min
completed: 2026-10-20
---

# Phase 4 Plan 01: Servicos de reproducao Summary

Target WineupServices com fila imutavel (repetir uma/todas, embaralhar por semente), PlaybackController com enfileiramento gapless e sessao persistida em app_setting (session.v1).

## Deviations from Plan

**1. [Rule 1 - Bug] selecting(index:) reembaralhava a fila**
- Trabalho parcial anterior usava `rebuilt` em `selecting`, regenerando shuffleOrder a cada avanco.
- Fix: preserva shuffleOrder/seed. Commit e9de5dc.

**2. [Rule 3 - Blocking] FakeEngine incompleto**
- O protocolo AudioEngine tem currentTime/totalTime/isPlaying (nao listados no plano); adicionados ao FakeEngine.

Restante do trabalho parcial mantido conforme o plano.

## Commits
- e9de5dc Task 1 (target + PlaybackQueue)
- Task 2: PlaybackController
- Task 3: SettingsStore/SessionStore/fixtures

## Verification
`swift build -c release && ./scripts/test.sh` passou (core 14, library 59, services 17 testes).

## Known Stubs
None.

## Self-Check: PASSED
