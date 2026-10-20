# Phase 1: Fundação e Infraestrutura de Teste - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss; decisões tomadas a partir de .planning/research/SUMMARY.md)

<domain>
## Phase Boundary

O código tem um núcleo testável separado da UI e o projeto prova cedo que testa e empacota com apenas Command Line Tools. Requisitos: FND-01, FND-02, FND-03, FND-04. Sem mudança visível para o usuário: o app continua abrindo e tocando como hoje.

</domain>

<decisions>
## Implementation Decisions

- Targets SwiftPM: começar com `WineupCore` (Foundation puro: modelos, IDs estáveis, portas/protocolos `AudioEngine`, `LibraryStore`, `TagIO`, `MetadataProvider`, tipos `Confidence`, `TagDiff`, journal) e manter o executável `Wineup` com a UI atual; subdividir Audio/Library/Services nas fases seguintes.
- Testes com Swift Testing (`import Testing`), que existe nos CLT; plano B se `swift test` falhar: toolchain swift.org ou executável `WineupSelfTests`. Validar com um `swift test` real logo no primeiro plano.
- IDs estáveis: `TrackID` baseado em UUID (ou hash do caminho) em vez de índice; `MarkColor` sai do domínio (a cor SwiftUI vira extensão na camada de UI).
- Sem sandbox; acesso a pastas atrás de um tipo `LibraryRoot` (registrar em Key Decisions do PROJECT.md).
- Build assinado de teste: manter `scripts/build-app.sh` (ad-hoc) e validar que o `.app` abre fora da pasta de build com frameworks e rpath corretos; assinatura Developer ID/notarização ficam na fase 6.
- `-strict-concurrency=complete` nos targets novos; tools-version 5.9.
- Licença do repositório: um commit externo adicionou LICENSE GPL v3 — manter como está; não alterar nesta fase.

### Claude's Discretion
Demais escolhas de implementação a critério do planejador, guiadas pelos critérios de sucesso do ROADMAP e pelas convenções do código atual.

</decisions>

<code_context>
## Existing Code Insights

- `Sources/Wineup/` — executável único: `Model/` (Track, PlayerState objeto-deus, SampleData), `Audio/` (AudioEngineService com SFBAudioEngine + AVAudioUnitEQ entre sourceNode e mainMixerNode; TrackLoader), `Panels/`, `Components/`, `Layout/`, `Theme/`, `AboutView.swift`.
- `scripts/build-app.sh` embute frameworks LGPL dinâmicos e assina ad-hoc.
- Restrição crítica do SFBAudioEngine: o grafo só pode ser alterado entre `sourceNode` e `mainMixerNode` (fora disso aborta).

</code_context>

<specifics>
## Specific Ideas

Ver `.planning/research/ARCHITECTURE.md` (camadas) e `PITFALLS.md` (testes só com CLT).

</specifics>

<deferred>
## Deferred Ideas

Banco, áudio real e UI ficam para as fases 2–5.

</deferred>
