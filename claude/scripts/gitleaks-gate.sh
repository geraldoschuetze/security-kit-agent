#!/usr/bin/env bash
# gitleaks-gate.sh — Hook PreToolUse do Claude Code (camada extra; a defesa
# sem-bypass é o hook nativo do git em ~/.config/git/hooks/pre-commit).
# Bloqueia comandos que fazem `git commit` se o Gitleaks achar segredos staged.
# Exit 2 = bloqueia a ação (o Claude vê o motivo no stderr e corrige).
# Exit 0 = permite.

set -uo pipefail

# Lê o JSON do evento via stdin e extrai o comando bash que será executado.
INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$CMD" ] && exit 0

# --- Matcher robusto -------------------------------------------------------
# Casa uma invocação `git ... (commit|ci)` mesmo com:
#   - alias `git ci`
#   - prefixo de env vars:            FOO=bar git commit
#   - opções globais:                 git -C /path commit  /  git --git-dir=... commit
#   - encadeamento:                   cd x && git commit -m ...  /  a; git commit
# Evita falso-positivo de `git log --grep=commit` (exige (commit|ci) como
# subcomando logo após as opções, não dentro do valor de uma flag).
GIT_COMMIT_RE='(^|[;&|[:space:]])(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*)git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|--[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?|-[A-Za-z]+))*[[:space:]]+(commit|ci)([[:space:]]|$)'

if ! printf '%s' "$CMD" | grep -Eq "$GIT_COMMIT_RE"; then
  exit 0
fi

# Sem gitleaks instalado: não bloqueia, mas avisa (fail-open no Claude porque o
# hook nativo do git é a defesa dura; ainda assim registra o gap).
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[gitleaks-gate] AVISO: gitleaks não instalado — commit prosseguindo SEM verificação de segredos." >&2
  echo "[gitleaks-gate] Rode: bash ~/.claude/scripts/install-tools.sh" >&2
  exit 0
fi

# Escaneia apenas o que está staged (valores redigidos — política zero-persistência).
if ! gitleaks git --pre-commit --staged --no-banner --redact . >/dev/null 2>&1; then
  {
    echo "[gitleaks-gate] COMMIT BLOQUEADO: o Gitleaks encontrou possíveis segredos nos arquivos staged."
    echo "Rode 'gitleaks git --pre-commit --staged --redact .' para ver os achados (valores redigidos)."
    echo "Remova o segredo (use variável de ambiente/secret manager), faça unstage, e tente novamente."
    echo "Se for falso positivo, adicione uma regra em .gitleaksignore com justificativa e data."
  } >&2
  exit 2
fi

exit 0
