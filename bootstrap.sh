#!/usr/bin/env bash
# bootstrap.sh — Instala o kit de SEGURANÇA (skills + agentes + scripts +
# hooks) num PC novo, para Claude Code (~/.claude) e Gemini (~/.gemini).
#
# Uso:
#   bash bootstrap.sh              # instala Claude + Gemini + hook git + ferramentas
#   bash bootstrap.sh --no-gemini  # só Claude
#   bash bootstrap.sh --no-tools   # pula instalação de trivy/osv-scanner/semgrep/gitleaks
#
# Segurança: os settings.json deste repo são TEMPLATES sanitizados (sem segredos).
# Segredos reais (JWT, tokens OAuth, credenciais) NUNCA entram no repo — você
# preenche os placeholders (__SET_...__) localmente após o bootstrap.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DO_GEMINI=1; DO_TOOLS=1
for a in "$@"; do case "$a" in --no-gemini) DO_GEMINI=0;; --no-tools) DO_TOOLS=0;; esac; done

CLAUDE="$HOME/.claude"; GEMINI="$HOME/.gemini"; GITHOOKS="$HOME/.config/git/hooks"
say(){ printf '==> %s\n' "$*"; }

# ---------- Claude ----------
say "Instalando skills/agents/scripts de segurança em $CLAUDE"
mkdir -p "$CLAUDE/skills" "$CLAUDE/agents" "$CLAUDE/scripts"
cp -r "$HERE/claude/skills/."   "$CLAUDE/skills/"
cp -r "$HERE/claude/agents/."   "$CLAUDE/agents/"
cp -r "$HERE/claude/scripts/."  "$CLAUDE/scripts/"
chmod +x "$CLAUDE/scripts/"*.sh 2>/dev/null || true

# settings: instala template só se não existir (não sobrescreve o seu, que tem segredos)
install_settings(){  # $1=template  $2=destino
  local tpl="$1" dst="$2"
  if [ -f "$dst" ]; then
    say "JÁ EXISTE $dst — não sobrescrevo. Compare manualmente com $tpl"
  else
    sed "s#__HOME__#$HOME#g" "$tpl" > "$dst"
    say "Instalado $dst a partir do template (preencha placeholders __SET_...__)"
  fi
}
install_settings "$HERE/claude/settings.template.json" "$CLAUDE/settings.json"

# ---------- Gemini ----------
if [ "$DO_GEMINI" = 1 ]; then
  say "Instalando skills em $GEMINI (mesma base de skills)"
  mkdir -p "$GEMINI/skills"
  cp -r "$HERE/claude/skills/." "$GEMINI/skills/"
  install_settings "$HERE/gemini/settings.template.json" "$GEMINI/settings.json"
fi

# ---------- Hook git global sem-bypass ----------
say "Ativando hook git global (bloqueia commit com segredo em qualquer repo)"
mkdir -p "$GITHOOKS"
cp "$HERE/git-hooks/pre-commit" "$GITHOOKS/pre-commit"
chmod +x "$GITHOOKS/pre-commit"
git config --global core.hooksPath "$GITHOOKS"

# ---------- Ferramentas de segurança ----------
if [ "$DO_TOOLS" = 1 ] && [ -f "$CLAUDE/scripts/install-tools.sh" ]; then
  say "Instalando trivy/osv-scanner/semgrep/gitleaks (versões fixas + checksum)"
  bash "$CLAUDE/scripts/install-tools.sh" || say "install-tools falhou — rode manualmente depois"
fi

echo ""
say "Concluído. Próximos passos:"
echo "   1. Garanta ~/.local/bin no PATH (onde as ferramentas de scan são instaladas)."
echo "   2. Abra o Claude Code / Gemini e rode /security-scan num projeto."
