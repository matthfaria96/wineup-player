---
phase: 01-funda-o-e-infraestrutura-de-teste
plan: 03
subsystem: build/empacotamento
tags: [build, testes, empacotamento, smoke]
requires: [01-01, 01-02]
provides: [build-app com gate de testes, verify-app.sh, smoke-playback.sh]
affects: [scripts/build-app.sh, scripts/verify-app.sh, scripts/smoke-playback.sh, scripts/test.sh]
requirements: [FND-01, FND-02, FND-04]
key-decisions:
  - "build-app.sh roda ./scripts/test.sh antes do build (SKIP_TESTS=1 pula), verify-app.sh após empacotar e smoke-playback.sh no fim (SKIP_SMOKE=1 pula)"
  - "test.sh passa -plugin-path para host/plugins/testing das CLT: sem isso o plugin TestingMacros não é encontrado de forma intermitente/persistente"
metrics:
  tasks: 2
  commits: 3
completed: 2026-10-20
---

# Plano 01-03: Gate de testes, verificação de empacotamento e smoke de reprodução

**Uma linha:** `./scripts/build-app.sh` agora testa, compila, empacota, verifica o `.app` (rpath, frameworks, assinatura, lançamento fora da pasta de build) e confirma que o app toca FLAC, M4A e WAV sem cair.

## O que foi feito

- **Tarefa 1 (`17505d8`):** `build-app.sh` chama `./scripts/test.sh` antes do build, `./scripts/verify-app.sh` depois de empacotar e `./scripts/smoke-playback.sh` no fim. `verify-app.sh` checa o rpath `@executable_path/../Frameworks`, que cada dependência `@rpath` (do binário e dos frameworks aninhados) está embutida, `codesign --verify --deep --strict`, copia o app com `ditto` para um diretório temporário e o lança direto (resolução do dyld) e via `open -n`; imprime "Empacotamento OK".
- **Tarefa 2 (`b651d5d`):** `smoke-playback.sh` gera um seno de 440 Hz com `python3 -I` num `mktemp -d`, converte para FLAC e M4A com `afconvert`, abre o app com cada arquivo, espera 5 s e falha se o processo morrer ou surgir um `Wineup-*.ips` novo; imprime "Reprodução OK (FLAC, M4A, WAV)".

## Verificação

- `./scripts/test.sh`: 9 testes passando.
- `./scripts/verify-app.sh "build/Wineup Player.app"`: "Empacotamento OK", exit 0.
- `./scripts/smoke-playback.sh "build/Wineup Player.app"`: "Reprodução OK (FLAC, M4A, WAV)", exit 0.

## Desvios

1. **[Regra 1 - Bug] Plugin TestingMacros não encontrado (`0adddfa`).** A nova tentativa (`swift test || swift test`) do plano 01-01 deixou de bastar: o erro "plugin for module 'TestingMacros' not found" passou a ocorrer nas duas tentativas. O plugin fica em `usr/lib/swift/host/plugins/testing/`; `test.sh` agora passa `-Xswiftc -plugin-path` para essa pasta (resolvida via `xcrun --find swift`).
2. **[Regra 1 - Bug] Contagem de crash reports no smoke.** Sem nenhum `Wineup-*.ips`, `ls ... | wc -l` falhava e, com `set -euo pipefail`, abortava o script antes de abrir o app. Trocado por `find ... -name "Wineup-*.ips" | wc -l`.
3. **Ambiente:** o executor original parou por disco cheio (ENOSPC) antes de commitar; o orquestrador concluiu e commitou. O disco do usuário está com ~98% de uso — builds repetidos podem falhar por espaço.

## Próximos passos

Fase 1 pronta para verificação. As fases seguintes devem usar `./scripts/build-app.sh` como gate (testes + empacotamento + reprodução).
