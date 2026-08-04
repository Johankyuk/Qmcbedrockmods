#!/bin/bash
# Instala .mcpack / .mcaddon en mcpelauncher (Minecraft Bedrock en Linux) - v2
set -e

SRC_DIR="$HOME/Mods"

MCPE_DIR="$HOME/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher/games/com.mojang"
RES_DIR="$MCPE_DIR/resource_packs"
BEH_DIR="$MCPE_DIR/behavior_packs"

if ! command -v unzip &> /dev/null; then
    echo "Falta 'unzip'. Instálalo con: sudo apt install unzip"
    exit 1
fi

mkdir -p "$RES_DIR" "$BEH_DIR"

shopt -s nullglob
files=("$SRC_DIR"/*.mcpack "$SRC_DIR"/*.mcaddon)

if [ ${#files[@]} -eq 0 ]; then
    echo "No se encontraron archivos .mcpack/.mcaddon en $SRC_DIR"
    exit 1
fi

for file in "${files[@]}"; do
    name=$(basename "$file")
    echo "Procesando: $name"

    tmpdir=$(mktemp -d)
    unzip -oq "$file" -d "$tmpdir"

    # Desempaquetar cualquier .mcpack/.mcaddon/.zip anidado adentro (hasta 3 niveles)
    for i in 1 2 3; do
        nested=$(find "$tmpdir" \( -iname "*.mcpack" -o -iname "*.mcaddon" -o -iname "*.zip" \))
        [ -z "$nested" ] && break
        while IFS= read -r nfile; do
            [ -z "$nfile" ] && continue
            ndir="${nfile%.*}_extracted"
            mkdir -p "$ndir"
            unzip -oq "$nfile" -d "$ndir"
            rm -f "$nfile"
        done <<< "$nested"
    done

    while IFS= read -r manifest; do
        packdir=$(dirname "$manifest")
        pack_name=$(basename "$packdir")

        if [ "$packdir" = "$tmpdir" ]; then
            pack_name="${name%.*}"
        fi

        # Prioridad: si tiene módulo "resources"/"client_data" -> resource pack
        # si tiene "data"/"script" -> behavior pack
        if grep -Eq '"type"[[:space:]]*:[[:space:]]*"(resources|client_data)"' "$manifest"; then
            dest="$RES_DIR/$pack_name"
            type="resources"
        elif grep -Eq '"type"[[:space:]]*:[[:space:]]*"(data|script)"' "$manifest"; then
            dest="$BEH_DIR/$pack_name"
            type="data/script"
        else
            dest="$RES_DIR/$pack_name"
            type="desconocido (asumido resource)"
        fi

        mkdir -p "$dest"
        cp -r "$packdir"/* "$dest"/
        echo "  -> [$type] copiado a: $dest"
    done < <(find "$tmpdir" -name "manifest.json")

    rm -rf "$tmpdir"
done

echo ""
echo "Listo. CIERRA Minecraft por completo y vuelve a abrirlo para que detecte los packs."
