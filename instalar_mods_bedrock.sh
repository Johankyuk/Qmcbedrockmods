#!/bin/bash
# Instala .mcpack / .mcaddon / .mcworld / .zip en mcpelauncher (Minecraft
# Bedrock en Linux) - v3
#
# Cambios respecto a v2 (bugs confirmados con casos de prueba reales antes
# de tocar nada):
#
# 1. Un archivo corrupto/invalido ya NO aborta el resto de la corrida.
#    v2 tenia 'set -e' a nivel de todo el script: si 'unzip' fallaba en
#    UN solo archivo (descarga a medias, zip invalido), el script entero
#    moria ahi (exit code no-cero sin catch) y todo lo que venia
#    alfabeticamente despues jamas se procesaba -- sin ningun aviso de
#    que se salteo. Ahora cada archivo se procesa en su propio intento;
#    si falla, se avisa y se sigue con el proximo.
#
# 2. Ya no se pisan mods entre si cuando dos addons distintos usan
#    nombres de carpeta genericos ('BP'/'RP', muy comun en addons reales
#    de MCPEDL/comunidad). v2 usaba el nombre de carpeta TAL CUAL viene
#    adentro del zip como nombre de destino: si dos addons distintos
#    traen ambos una carpeta llamada 'BP', el segundo pisaba al primero
#    en resource_packs/behavior_packs sin ningun error. Ahora el destino
#    siempre lleva el nombre del archivo fuente como prefijo, unico por
#    definicion entre archivos distintos.
#
# 3. Extensiones reconocidas ahora son case-insensitive (.MCADDON,
#    .McPack, etc. -- algunos navegadores/hosting alteran el casing) y
#    se suman .zip (muchos sitios distribuyen un .zip plano sin
#    renombrar) y .mcworld (mundos con el addon incrustado en
#    behavior_packs/ + resource_packs/, tambien muy comun).
#
# 4. Si un archivo no contiene ningun manifest.json reconocible, ahora
#    se avisa explicitamente en vez de terminar en silencio sin instalar
#    nada y sin decir por que.

SRC_DIR="$HOME/Mods"

MCPE_DIR="$HOME/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher/games/com.mojang"
RES_DIR="$MCPE_DIR/resource_packs"
BEH_DIR="$MCPE_DIR/behavior_packs"

if ! command -v unzip &> /dev/null; then
    echo "Falta 'unzip'. Instálalo con: sudo pacman -S unzip  (o tu gestor de paquetes)"
    exit 1
fi

mkdir -p "$RES_DIR" "$BEH_DIR"

shopt -s nullglob
shopt -s nocaseglob   # que .MCADDON, .McPack, etc. tambien matcheen
files=("$SRC_DIR"/*.mcpack "$SRC_DIR"/*.mcaddon "$SRC_DIR"/*.mcworld "$SRC_DIR"/*.zip)
shopt -u nocaseglob

if [ ${#files[@]} -eq 0 ]; then
    echo "No se encontraron archivos .mcpack/.mcaddon/.mcworld/.zip en $SRC_DIR"
    exit 1
fi

ok_count=0
fail_count=0

for file in "${files[@]}"; do
    name=$(basename "$file")
    stem="${name%.*}"
    echo "Procesando: $name"

    tmpdir=$(mktemp -d)

    if ! unzip -oq "$file" -d "$tmpdir" 2>/tmp/unzip-err-$$; then
        echo "  ✗ ERROR: '$name' no es un zip valido (descarga incompleta o corrupta) -- SE SALTEA, sigo con el resto."
        sed 's/^/    /' /tmp/unzip-err-$$
        rm -f /tmp/unzip-err-$$
        rm -rf "$tmpdir"
        fail_count=$((fail_count + 1))
        continue
    fi
    rm -f /tmp/unzip-err-$$

    # Desempaquetar cualquier .mcpack/.mcaddon/.zip anidado adentro (hasta 3 niveles)
    for i in 1 2 3; do
        nested=$(find "$tmpdir" -iname "*.mcpack" -o -iname "*.mcaddon" -o -iname "*.zip")
        [ -z "$nested" ] && break
        while IFS= read -r nfile; do
            [ -z "$nfile" ] && continue
            ndir="${nfile%.*}_extracted"
            mkdir -p "$ndir"
            if ! unzip -oq "$nfile" -d "$ndir" 2>/dev/null; then
                echo "    (aviso: no pude abrir un archivo anidado dentro de $name, lo ignoro)"
            fi
            rm -f "$nfile"
        done <<< "$nested"
    done

    manifests=$(find "$tmpdir" -name "manifest.json")
    if [ -z "$manifests" ]; then
        echo "  ✗ '$name' no tiene ningun manifest.json adentro (no es un addon/pack valido, o es un formato no reconocido) -- SE SALTEA."
        rm -rf "$tmpdir"
        fail_count=$((fail_count + 1))
        continue
    fi

    installed_any=0
    while IFS= read -r manifest; do
        packdir=$(dirname "$manifest")
        inner_name=$(basename "$packdir")

        if [ "$packdir" = "$tmpdir" ]; then
            # Manifest suelto en la raiz del zip (sin subcarpeta): el
            # nombre del archivo ya es unico de por si.
            pack_name="$stem"
        else
            # Prefijo con el nombre del archivo fuente para que dos
            # addons distintos con carpetas internas iguales (BP/RP
            # genericas) nunca se pisen entre si.
            pack_name="${stem}__${inner_name}"
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
        installed_any=1
    done <<< "$manifests"

    rm -rf "$tmpdir"
    if [ "$installed_any" = 1 ]; then
        ok_count=$((ok_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi
done

echo ""
echo "Listo: $ok_count archivo(s) instalado(s), $fail_count con problemas (ver avisos arriba)."
echo "CIERRA Minecraft por completo y vuelve a abrirlo para que detecte los packs."
