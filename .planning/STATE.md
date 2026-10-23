





# Estado do Projeto

## Referência do Projeto

Ver: .planning/PROJECT.md (atualizado em 2026-10-19)

**Valor central:** Tocar a biblioteca local do usuário de forma confiável, com a interface clássica de painéis, e nunca danificar os arquivos dele.
**Foco atual:** Fase 1 - Fundação e Infraestrutura de Teste

## Posição Atual

Fase: 1 de 8 (Fundação e Infraestrutura de Teste)
Plano: 0 de 0 na fase atual
Status: Ready to plan
Última atividade: 2026-10-20 - Roadmap criado

Progresso: [░░░░░░░░░░] 0%

## Métricas de Desempenho

**Velocidade:**
- Planos concluídos: 0
- Duração média: -
- Tempo total: 0 horas

**Por fase:**

| Fase | Planos | Total | Média/Plano |
|------|--------|-------|-------------|
| - | - | - | - |

## Contexto Acumulado

### Decisões

- Camadas horizontais (escolha do usuário), com build demonstrável e app tocando ao fim de cada fase
- Sem sandbox, Developer ID + hardened runtime; acesso a pastas atrás de `LibraryRoot` (registrar na Fase 1)
- Infraestrutura de escrita segura (backup, journal, verificação) entra na Fase 2, antes de qualquer UI do Fixer
- Swift Testing como padrão; plano B: toolchain swift.org ou executável `WineupSelfTests`

### Pendências

Nenhuma ainda.

### Bloqueios/Preocupações

- [VERIFICAR] `swift test` só com Command Line Tools (Fase 1)
- [VERIFICAR] GRDB 7.11.1 compila com CLT e tools 5.9 (Fases 1/2)
- Pesquisa de fase necessária antes de planejar: 2, 3, 6, 7, 8

## Continuidade da Sessão

Última sessão: 2026-10-20
Parou em: Roadmap criado, aguardando aprovação
Arquivo de retomada: Nenhum

## Atualização 2026-10-23 (fora das fases: pedidos diretos do usuário)

Feito e testado (189 testes, conferência visual no app):
- Gerenciador de metadados no estilo Mp3tag: busca por álbum (MusicBrainz, etapa 2 com campos marcáveis e faixas × arquivos por arrasto), procurar capas (Cover Art Archive + iTunes), letras (catálogo principal, reserva NetEase, Musixmatch com token do usuário; a tela não cita fontes), visualizador de .lrc, histórico com desfazer por lote, duplicadas → Lixeira com confirmação, ignorar problemas, colunas técnicas configuráveis.
- Consentimento antes da primeira consulta online (NET-02).
- Player: velocidade em menu (0,5×–3×), atalhos clássicos Z X C V B/setas, modo mini sempre por cima, página do artista (Reproduzir tudo/Embaralhar sem repetir single×álbum), VoiceOver nos controles próprios, arrastar painéis por coluna, janela única sem restauração de sessão de janelas.
- Shazam removido (usuário não quer).

Pendentes conscientes:
- DISC-02 (ordem de capas com imagem da pasta), UI-02 (formato de skin documentado), SYS-04 (assinatura: sem certificado), SYS-05 (conferir versões nos avisos), NET-01 (liga/desliga por provedor; hoje é um consentimento geral), NET-04 (opção de salvar capa ao lado em vez de embutir).
