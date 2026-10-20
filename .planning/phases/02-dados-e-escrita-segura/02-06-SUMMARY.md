---
phase: 02-dados-e-escrita-segura
plan: 06
subsystem: app-integration
tags: [library, bootstrap, search, smoke]
requires: [02-01, 02-02, 02-03]
provides: [NAV-01 first-run root, LibraryController adapter, persisted playlist and FTS search in app]
affects: [Sources/Wineup, scripts/smoke-playback.sh]
key-files:
  created:
    - Sources/WineupLibrary/Bootstrap/LibraryBootstrap.swift
    - Tests/WineupLibraryTests/LibraryBootstrapTests.swift
    - Sources/Wineup/Library/LibraryController.swift
  modified:
    - Sources/Wineup/Model/PlayerState.swift
    - Sources/Wineup/WineupApp.swift
    - scripts/smoke-playback.sh
requirements-completed: [NAV-01, LIB-01, LIB-02, LIB-04]
metrics:
  completed: 2026-10-20
---

# Phase 2 Plan 06: Integração da biblioteca no app Summary

LibraryBootstrap (NAV-01, flag `default_root_bootstrapped` em `app_setting`) mais um LibraryController MainActor que liga o banco persistido, a varredura e a busca FTS ao PlayerState, sem refatorar a UI.

## Commits
- d88901e: LibraryBootstrap + 5 testes
- 0ead36d: LibraryController, PlayerState/WineupApp, smoke

## Comportamento
- Primeira abertura: ~/Music vira raiz e a varredura começa; pasta ausente/vazia não gera erro; flag impede re-adição.
- `.task { startLibrary() }` carrega faixas persistidas (substitui SampleData sem tocar) e varre com status "Varrendo biblioteca: x/y".
- Pastas (⌘O/arrastar/onOpenURL) viram raízes; arquivos soltos seguem pelo TrackLoader.
- Busca debounced 150 ms via SearchService; banco indisponível cai no modo antigo.
- `WINEUP_LIBRARY_PATH` sobrescreve o caminho do banco.

## Deviations
1. [Rule 3] `smoke-playback.sh` falhava em silêncio (`set -e`/pipefail) porque `~/Library/Logs/DiagnosticReports` não existe nesta máquina; `find` agora tolera isso.
2. O smoke passa o banco temporário com `open --env WINEUP_LIBRARY_PATH=...` (open não herda o ambiente do shell); verificado manualmente que o banco temporário é criado.
3. Durante a depuração, uma execução do smoke ORIGINAL (via git stash) abriu o app sem o banco temporário e criou `~/Library/Application Support/Wineup/library.sqlite` (varredura somente leitura de ~/Music; nenhum arquivo de música alterado). Removi esse diretório, gerado nesta sessão, para preservar o comportamento de primeira abertura.
4. `LibraryController.init`/`isAvailable` são `nonisolated` para uso no init do PlayerState (não MainActor).

## Gate
`swift build -c release && ./scripts/test.sh && ./scripts/build-app.sh`: build ok, 53 testes passam, empacotamento + "Reprodução OK (FLAC, M4A, WAV)". Sem diretórios WineupTests- restantes; nenhum processo Wineup ativo.

## Known Stubs
Nenhum.

## Self-Check: PASSED
