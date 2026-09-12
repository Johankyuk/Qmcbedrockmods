#!/bin/bash
# install.sh — despliega Qmcbedrockmods en la maquina actual.
# Idempotente: se puede correr las veces que haga falta.
# Sin 'set -e' a proposito: los avisos opcionales no deben matar la corrida.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_APP_ID="${LAUNCHER_APP_ID:-io.mrarm.mcpelauncher}"

echo "== Dependencias =="
if ! command -v unzip &>/dev/null; then
  echo "ERROR: falta 'unzip'. Instalalo con: sudo pacman -S unzip" >&2; exit 1
fi
if ! command -v flatpak &>/dev/null; then
  echo "ERROR: falta 'flatpak'." >&2; exit 1
fi
if ! flatpak info "$LAUNCHER_APP_ID" &>/dev/null; then
  echo "ERROR: el flatpak $LAUNCHER_APP_ID no esta instalado." >&2
  echo "       flatpak install flathub $LAUNCHER_APP_ID" >&2
  exit 1
fi

echo "== Script a ~/.local/bin =="
mkdir -p "$HOME/.local/bin" || exit 1
install -m 755 "$REPO_DIR/instalar_mods_bedrock.sh" \
               "$HOME/.local/bin/instalar_mods_bedrock.sh" || exit 1
[ -x "$HOME/.local/bin/instalar_mods_bedrock.sh" ] || {
  echo "ERROR: el script no quedo ejecutable en ~/.local/bin" >&2; exit 1; }

echo "== Lanzador de escritorio =="
# greetd lanza niri via PAM, sin el systemd user manager: ~/.local/bin NO
# esta en el PATH heredado. Por eso el Exec debe ser ruta absoluta, no
# depender del PATH.
APPS_DIR="$HOME/.local/share/applications"
DESKTOP="$APPS_DIR/instalar-mods-bedrock.desktop"
mkdir -p "$APPS_DIR" || exit 1
cp "$REPO_DIR/instalar-mods-bedrock.desktop" "$DESKTOP" || exit 1
sed -i "s|=HOME/|=$HOME/|g" "$DESKTOP" || exit 1
if grep -q '=HOME/' "$DESKTOP"; then
  echo "ERROR: placeholder HOME/ sin sustituir en $DESKTOP" >&2; exit 1
fi
if ! grep -q "^Exec=$HOME/.local/bin/instalar_mods_bedrock.sh$" "$DESKTOP"; then
  echo "ERROR: el Exec desplegado no apunta al script esperado" >&2
  grep '^Exec=' "$DESKTOP" >&2; exit 1
fi
command -v update-desktop-database &>/dev/null && \
  update-desktop-database "$APPS_DIR" &>/dev/null

echo "== Carpetas de entrada =="
# ~/Mods y ~/Mundos son intencionalmente distintas: un .mcworld en Mods
# aporta solo sus packs embebidos; en Mundos se importa como partida.
mkdir -p "$HOME/Mods" "$HOME/Mundos" || exit 1

echo "== Shaders (opcional) =="
SHADERSMOD="$HOME/.var/app/$LAUNCHER_APP_ID/data/mcpelauncher/mods/libmcpelaunchershadersmod.so"
if [ -f "$SHADERSMOD" ]; then
  echo "shadersmod presente."
else
  echo "AVISO: falta libmcpelaunchershadersmod.so en mods/."
  echo "       Los shaders RenderDragon no van a cargar hasta instalarlo a mano:"
  echo "       github.com/GameParrot/mcpelauncher-shadersmod"
fi

echo ""
echo "Listo. Deja tus archivos en ~/Mods (addons) o ~/Mundos (partidas) y corre:"
echo "  ~/.local/bin/instalar_mods_bedrock.sh"
echo "o abre 'Instalar Mods Bedrock' desde el launcher."
