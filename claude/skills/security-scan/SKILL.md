---
name: security-scan
description: Executa uma auditoria de segurança completa do projeto (estilo Snyk, mas 100% open source) combinando ferramentas de assinatura — Trivy + OSV-Scanner (SCA/container/IaC/licenças, duas bases de CVE), Semgrep (SAST), Gitleaks (secrets) — COM revisão semântica por raciocínio (authz/lógica/IDOR) que as regras não pegam. Use quando o usuário pedir "scan de segurança", "verificar vulnerabilidades", "auditoria de segurança", "/security-scan" ou antes de releases/deploys.
---

# Security Scan — Auditoria completa de segurança (ferramentas + raciocínio)

Você é o orquestrador de uma auditoria de **segurança da informação (cyber
security)** do repositório atual. O objetivo é replicar — e superar — a
cobertura do Snyk usando ferramentas open source, juntando **duas famílias que
se complementam**:

- **Assinatura/regra** (Trivy + OSV-Scanner, Semgrep, Gitleaks) → cobertura ampla,
  determinística, ótima para CVEs, secrets, IaC e padrões de código inseguro conhecidos.
- **Raciocínio semântico** (subagente `semantic-reviewer`) → o ponto cego das
  regras: autorização quebrada, IDOR, lógica de negócio explorável, fluxo de
  dados perigoso entre arquivos, validação/authz ausente.

Nenhuma das duas basta sozinha. Regra sem raciocínio perde falha de lógica;
raciocínio sem regra perde CVE/secret. Esta skill roda as duas e consolida.

## Escopo — SOMENTE segurança

Trate exclusivamente de segurança da informação: vulnerabilidades exploráveis,
credenciais expostas, misconfigurações de infra, risco de supply chain e falhas
de autorização/lógica. **NÃO** inclua estilo, refatoração, performance ou dívida
técnica. Se notar algo grave fora do escopo, no máximo uma linha em "Observações".

## Modos

- **FULL** (padrão, `/security-scan`) — audita o repositório inteiro. Ferramentas
  varrem tudo; o `semantic-reviewer` mapeia e revisa a superfície security-relevant.
- **DIFF** (`/security-scan diff`) — modo revisão de PR: a parte semântica e o SAST
  focam no diff vs `main` (`git diff main...HEAD`). Rápido para o gate de PR.
- **PATH** (`/security-scan <subdir>`) — restringe o escopo a um subdiretório.

## Pré-checagem (obrigatória)

```bash
command -v trivy osv-scanner semgrep gitleaks
```

Se alguma faltar, avise e ofereça rodar `~/.claude/scripts/install-tools.sh`. NÃO
prossiga silenciosamente sem uma ferramenta — informe qual categoria fica
descoberta. (A revisão semântica não depende de ferramenta externa e roda sempre.)

Sem `osv-scanner` o scan **ainda roda**, mas perde os advisories **sem CVE** —
diga isso explicitamente no relatório em vez de apresentar o resultado como completo.

## Fluxo de execução

Rode as **quatro dimensões em paralelo**. Se o ambiente suportar subagentes
(Claude Code), delegue cada uma ao subagente especializado; se NÃO suportar
(ex.: Gemini CLI, que não tem subagentes), execute cada etapa **você mesmo,
inline**, seguindo a mesma metodologia do agente correspondente.

1. **`sca-scanner`** → dependências (SCA/CVEs), IaC, licenças e container.
   (**Trivy + OSV-Scanner** — duas bases; o agente reconcilia e marca o que só uma
   delas pegou.)
2. **`sast-scanner`** → análise estática do código próprio. (Semgrep)
3. **`secrets-scanner`** → segredos no working tree e no histórico git. (Gitleaks)
4. **`semantic-reviewer`** → revisão por raciocínio: authz/IDOR, lógica de
   negócio, fluxo de dados entre arquivos, validação ausente. Passe o **modo**
   (FULL/DIFF/PATH) e a base do diff no prompt.

DAST (`dast-scanner`, OWASP ZAP) é **opt-in**: só quando o usuário pedir teste
dinâmico E informar a URL de um app rodando. Nunca roda automaticamente.

Aguarde as quatro retornarem antes de consolidar.

## Consolidação do relatório + histórico (métricas)

Depois que todas retornarem, salve o histórico versionado em `.security/history/`
na raiz do projeto (crie se não existir):

1. Relatório timestampado: `.security/history/security-report-<YYYYMMDD-HHMMSS>.md`.
2. Métricas em JSON: `.security/history/security-metrics-<YYYYMMDD-HHMMSS>.json`:
   ```json
   {"timestamp":"<ISO8601>",
    "sca":{"critical":0,"high":0,"medium":0,"low":0,
           "sources":{"both":0,"osv_only":0,"trivy_only":0},
           "trivy_db_date":"<ISO8601 do UpdatedAt>"},
    "sast":{"critical":0,"high":0,"medium":0,"low":0},
    "secrets":{"real":0,"placeholders":0},"iac":{"critical":0,"high":0,"medium":0},
    "semantic":{"real":0,"toreview":0},"dast":{"high":0,"medium":0,"low":0},
    "verdict":"🔴|🟡|🟢"}
   ```
3. Atualize/gere `security-report.md` na raiz (aponta para o último do histórico).
4. **Tendência:** leia o `security-metrics-*.json` anterior (se houver) e reporte a
   variação por severidade (↑ novos / ↓ resolvidos) no Resumo executivo.

Estrutura do relatório (markdown):

```markdown
# Relatório de Segurança — <nome do projeto> — <data>  (modo: FULL|DIFF|PATH)

## Resumo executivo
- Total de achados por severidade: CRITICAL / HIGH / MEDIUM / LOW
- Veredito: 🔴 BLOQUEAR DEPLOY | 🟡 ATENÇÃO | 🟢 OK
- Top 3 riscos mais urgentes (uma linha cada)

## 1. Dependências e CVEs (SCA)
| Pacote | Versão | ID (CVE/GHSA) | Fonte | Severidade | Versão corrigida | Alcance |
> Fonte = `ambos` · `só OSV` · `só Trivy`. Alcance = o caminho vulnerável é
> exercitado pelo projeto? Dep transitiva com caminho morto é higiene, não urgência.

## 2. Código próprio — padrões (SAST)
| Arquivo:linha | Regra | CWE / OWASP Top 10 | Severidade | Descrição curta |

## 3. Código próprio — lógica & autorização (revisão semântica)
| Arquivo:linha | Classe | CWE / OWASP | Severidade | Cenário de exploração | Correção |
> Aqui vão as falhas que só o raciocínio pega: IDOR, authz ausente, lógica de negócio.

## 4. Segredos expostos
| Arquivo | Tipo de segredo | Commit (se histórico) |
⚠️ NUNCA transcreva o valor do segredo no relatório — apenas tipo e local.

## 5. Infraestrutura como código (IaC)
| Arquivo | Check | Severidade | Correção sugerida |

## 6. Licenças
Apenas licenças problemáticas (copyleft forte em contexto proprietário etc.)

## 7. DAST (apenas se o app estiver rodando e o usuário pedir)
| URL / endpoint | Alerta ZAP | Severidade | Correção sugerida |

## Tendência (vs. scan anterior)
| Categoria | Antes | Agora | Δ |

## Plano de remediação priorizado
Lista numerada: o que corrigir primeiro e como (comandos/upgrades concretos).
```

## Cross-validação (regra + raciocínio)

Ao consolidar, cruze as duas famílias — é aí que está o ganho da junção:

- Achado do SAST que o `semantic-reviewer` confirma explorável (data-flow real)
  → **sobe** de severidade; sinalize "confirmado por revisão semântica".
- Achado do SAST que a revisão semântica mostra mitigado (sanitização a montante)
  → **desce** para o apêndice de falsos positivos, com a justificativa.
- Achado semântico que também bate numa regra → cite ambos; não duplique a linha.

## Quando o usuário traz um achado de scanner comercial (Snyk, Dependabot…)

Acontece muito: *"apareceram 2 HIGH no meu Snyk"*. Antes de sair corrigindo,
**reproduza o achado contra a árvore real**. Ordem:

1. **Peça o ID e o pacote** (print ou texto). Sem isso você caça no escuro — e o
   seu scan pode achar outra coisa e você confundir as duas. Se o seu resultado
   não bate com o que o usuário reportou, **diga isso em voz alta** em vez de
   assumir que são os mesmos achados.
2. **Confira o lockfile**, não o `package.json`. Vários scanners comerciais
   resolvem a árvore a partir do manifesto + registry e **ignoram `overrides` /
   `resolutions` / `pnpm.overrides`** — então reportam como vulnerável uma
   transitiva que o lockfile já fixou numa versão corrigida. Sintoma clássico:
   *"No remediation path available"* numa dep que você já sobrescreveu.
3. **Confira a árvore instalada.** O oposto também ocorre: o lockfile está
   correto, mas sobrou cópia obsoleta em `node_modules/<pkg>/node_modules/…` de
   uma instalação anterior que não foi podada. Compare o `mtime` com a data do
   commit do fix. Nesse caso o scanner comercial está certo e os seus (que leem o
   lockfile) estão errados.
4. **Confira como o artefato de produção é construído.** Se o Dockerfile faz
   install limpo a partir do lockfile, o resíduo local não chega em produção — o
   risco é só na máquina de dev. Diga isso explicitamente.
5. **Advisory sem CVE** é do OSV, não do Trivy. Se o ID reportado não tem CVE,
   confirme no `osv.json`; se nem lá aparecer, é base proprietária do fornecedor e
   você só consegue avaliar pela descrição — **diga que não conseguiu reproduzir**
   em vez de declarar falso positivo.

Conclua sempre com **qual das duas leituras está certa e por quê**, e nunca feche
como "falso positivo" sem mostrar a evidência (versão no lock, mtime, estágio do
Dockerfile).

## Regras de priorização

- CRITICAL/HIGH com fix disponível → topo, sempre.
- Segredo ativo → CRITICAL, independente da ferramenta.
- Falha de authz/IDOR com caminho confirmado → CRITICAL/HIGH mesmo sem CVE.
- Vulnerabilidade sem fix → listar, marcar "monitorar".
- **Advisory sem CVE (só OSV) NÃO é de segunda classe** — trate pelo CVSS, como
  qualquer outro. A ausência de CVE diz respeito ao processo de atribuição de ID,
  não à gravidade.
- **Severidade divergente entre as bases** → use a maior e diga de onde veio.
- Falsos positivos óbvios (teste/fixtures) → apêndice, não misturar com reais.

## Veredito final

- 🔴 se houver qualquer CRITICAL, segredo válido/ativo, falha de authz explorável,
  ou HIGH com exploit conhecido.
- 🟡 se houver HIGH sem fix, falha semântica "a revisar" relevante, ou vários MEDIUM.
- 🟢 caso contrário.

## Baseline para projetos legados + triagem de ignores

Em bases legadas com muito ruído, foque no que é NOVO:
- **Semgrep:** `--baseline-commit <sha>` reporta só achados após o commit.
- **Revisão semântica:** use o modo DIFF.
- **Trivy/Gitleaks:** use os arquivos de ignore, com disciplina.

**Regra de ignore (obrigatória):** toda entrada em `.trivyignore` /
`osv-scanner.toml` / `.semgrepignore` / `.gitleaksignore` deve ter comentário com
**justificativa + data de expiração**. No OSV o ignore é TOML e já tem campo
próprio de expiração — use-o:
```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2026-10-01
reason = "sem fix upstream; caminho vulneravel nao exercitado (dep dev-only)"
```
```
# CVE-2025-XXXX — sem fix upstream; não explorável (dep dev-only). Revisar em 2026-10-01.
CVE-2025-XXXX
```
Entradas expiradas voltam a aparecer na triagem — não são "para sempre".

## Ofereça em seguida (não faça sem confirmar)

1. Corrigir upgrades de dependência simples (patch/minor).
2. Aplicar fixes triviais sugeridos pelo Semgrep / pela revisão semântica.
3. Adicionar achados aceitos aos arquivos de ignore com justificativa + expiração.
