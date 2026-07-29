#!/usr/bin/env bash
# install-tools.sh — Instala as ferramentas do kit de segurança OSS com
# VERSÕES FIXAS e VERIFICAÇÃO DE INTEGRIDADE (checksum SHA256 + cosign quando
# disponível). Substitui o antigo "curl | sh -s latest" sem verificação.
#
# Uso:  bash ~/.claude/scripts/install-tools.sh
# Bump: edite as variáveis *_VERSION abaixo. Se a versão não existir, o
#       download falha de forma barulhenta (fail-closed) — nunca cai em "latest".
#
# Ferramentas: trivy (SCA/IaC/container/licenças), osv-scanner (2ª base de SCA —
#              pega advisory SEM CVE, que o Trivy não indexa), semgrep (SAST via
#              pipx), gitleaks (secrets), e opcional imagem ZAP (DAST).

set -euo pipefail

# ---------------------------------------------------------------- versões fixas
# Verificadas em 2026-07-23 via API de releases. Para atualizar, bump aqui.
TRIVY_VERSION="0.72.0"
GITLEAKS_VERSION="8.30.1"
SEMGREP_VERSION="1.171.0"
OSV_VERSION="2.4.0"          # 2ª base de SCA (OSV.dev) — advisory sem CVE + bun.lock
ZAP_IMAGE="zaproxy/zap-stable:2.15.0"   # opcional (DAST)

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN_DIR"

OS="$(uname -s)"; ARCH="$(uname -m)"
have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }

if [ "$OS" != "Linux" ]; then
  warn "Este script foi calibrado para Linux. No macOS use: brew install trivy gitleaks semgrep"
fi

# sha256 de um arquivo, imprime só o hash
sha256() { sha256sum "$1" | awk '{print $1}'; }

# Verifica $file contra a linha "HASH  nome" dentro de $checksums (match pelo basename exato).
verify_sha() {
  local file="$1" checksums="$2" base got want
  base="$(basename "$file")"
  got="$(sha256 "$file")"
  want="$(awk -v f="$base" '($2==f)||($2=="*"f)||($2=="./"f){print $1; exit}' "$checksums")"
  if [ -z "$want" ]; then warn "checksum de $base não encontrado no arquivo de checksums"; return 1; fi
  if [ "$got" != "$want" ]; then warn "CHECKSUM DIVERGENTE p/ $base"; warn "  esperado: $want"; warn "  obtido:   $got"; return 1; fi
  say "checksum OK: $base"
}

# Verificação cosign keyless (best-effort) via bundle sigstore (.sigstore.json).
verify_cosign_bundle() {
  local checksums="$1" bundle="$2" identity_re="$3"
  if ! have cosign; then warn "cosign ausente — pulando verificação de assinatura (só checksum SHA256)."; return 0; fi
  if [ ! -f "$bundle" ]; then warn "bundle sigstore ausente — pulando cosign."; return 0; fi
  if cosign verify-blob --bundle "$bundle" \
        --certificate-identity-regexp "$identity_re" \
        --certificate-oidc-issuer-regexp '.*' "$checksums" >/dev/null 2>&1; then
    say "cosign OK (assinatura sigstore verificada)"
  else
    warn "cosign FALHOU na verificação da assinatura — abortando por segurança."; return 1
  fi
}

dl() { curl -fsSL --retry 3 -o "$2" "$1"; }

# ------------------------------------------------------------------------ Trivy
install_trivy() {
  if have trivy && trivy --version 2>/dev/null | grep -q "$TRIVY_VERSION"; then
    say "Trivy $TRIVY_VERSION já instalado"; return 0; fi
  say "Instalando Trivy $TRIVY_VERSION..."
  local tarch; case "$ARCH" in x86_64) tarch="Linux-64bit";; aarch64|arm64) tarch="Linux-ARM64";; *) warn "arch $ARCH não mapeada p/ trivy"; return 1;; esac
  local base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"
  local asset="trivy_${TRIVY_VERSION}_${tarch}.tar.gz"
  dl "$base/$asset" "$TMP/$asset"
  dl "$base/trivy_${TRIVY_VERSION}_checksums.txt"   "$TMP/trivy.sums"
  dl "$base/trivy_${TRIVY_VERSION}_checksums.txt.sigstore.json" "$TMP/trivy.sigstore.json" || true
  verify_cosign_bundle "$TMP/trivy.sums" "$TMP/trivy.sigstore.json" 'https://github.com/aquasecurity/trivy.*' || return 1
  verify_sha "$TMP/$asset" "$TMP/trivy.sums" || return 1
  tar -xzf "$TMP/$asset" -C "$TMP" trivy
  install -m 0755 "$TMP/trivy" "$BIN_DIR/trivy"
}

# --------------------------------------------------------------------- Gitleaks
install_gitleaks() {
  if have gitleaks && gitleaks version 2>/dev/null | grep -q "$GITLEAKS_VERSION"; then
    say "Gitleaks $GITLEAKS_VERSION já instalado"; return 0; fi
  say "Instalando Gitleaks $GITLEAKS_VERSION..."
  local garch; case "$ARCH" in x86_64) garch="x64";; aarch64|arm64) garch="arm64";; *) warn "arch $ARCH não mapeada p/ gitleaks"; return 1;; esac
  local base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"
  local asset="gitleaks_${GITLEAKS_VERSION}_linux_${garch}.tar.gz"
  dl "$base/$asset" "$TMP/$asset"
  dl "$base/gitleaks_${GITLEAKS_VERSION}_checksums.txt" "$TMP/gl.sums"
  verify_sha "$TMP/$asset" "$TMP/gl.sums" || return 1
  tar -xzf "$TMP/$asset" -C "$TMP" gitleaks
  install -m 0755 "$TMP/gitleaks" "$BIN_DIR/gitleaks"
}

# ---------------------------------------------------------------------- Semgrep
install_semgrep() {
  if have semgrep && semgrep --version 2>/dev/null | grep -q "$SEMGREP_VERSION"; then
    say "Semgrep $SEMGREP_VERSION já instalado"; return 0; fi
  say "Instalando Semgrep $SEMGREP_VERSION (pipx, versão fixa)..."
  if have pipx; then
    pipx install "semgrep==${SEMGREP_VERSION}" --force
  elif have pip3; then
    pip3 install --user "semgrep==${SEMGREP_VERSION}" || pip3 install --user --break-system-packages "semgrep==${SEMGREP_VERSION}"
    say "(garanta que ~/.local/bin está no PATH)"
  else
    warn "Instale pipx (recomendado) para o Semgrep: python3 -m pip install --user pipx"
    return 1
  fi
}

# ------------------------------------------------------------------ osv-scanner
# 2ª base de SCA. NÃO é redundante com o Trivy: o Trivy indexa por CVE
# (NVD/GHSA/distro) e não enxerga advisory sem CVE atribuído; o OSV indexa por ID
# de advisory (OSV.dev) e pega esses casos. Também tem parsers de lockfile mais
# amplos — inclui `bun.lock`, que o Trivy não lê.
install_osv() {
  if have osv-scanner && osv-scanner --version 2>/dev/null | grep -q "$OSV_VERSION"; then
    say "osv-scanner $OSV_VERSION já instalado"; return 0; fi
  say "Instalando osv-scanner $OSV_VERSION..."
  local oarch; case "$ARCH" in x86_64) oarch="amd64";; aarch64|arm64) oarch="arm64";; *) warn "arch $ARCH não mapeada p/ osv-scanner"; return 1;; esac
  local base="https://github.com/google/osv-scanner/releases/download/v${OSV_VERSION}"
  local asset="osv-scanner_linux_${oarch}"
  dl "$base/$asset" "$TMP/$asset"
  dl "$base/osv-scanner_SHA256SUMS" "$TMP/osv.sums"
  verify_sha "$TMP/$asset" "$TMP/osv.sums" || return 1
  install -m 0755 "$TMP/$asset" "$BIN_DIR/osv-scanner"
}

# ------------------------------------------------------------------------- main
install_trivy    || warn "Trivy falhou"
install_gitleaks || warn "Gitleaks falhou"
install_semgrep  || warn "Semgrep falhou"
install_osv      || warn "osv-scanner falhou — o SCA fica sem a 2ª base (advisory sem CVE)"

echo ""
say "Verificação final:"
for t in trivy semgrep gitleaks osv-scanner; do
  if have "$t"; then printf '   ✅ %s (%s)\n' "$t" "$($t --version 2>/dev/null | head -n1)"; else printf '   ❌ %s\n' "$t"; fi
done
echo ""
say "DAST (opcional): a imagem ZAP é puxada sob demanda pelo dast-scanner:"
echo "   docker pull ${ZAP_IMAGE}"
echo ""
say "Pronto. Garanta que ${BIN_DIR} está no PATH e rode /security-scan no projeto."
