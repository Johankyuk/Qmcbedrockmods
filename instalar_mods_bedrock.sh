#!/bin/bash
# Instala .mcpack / .mcaddon / .mcworld / .zip en mcpelauncher (Minecraft
# Bedrock en Linux) - v4
#
# v4: soporte para shaders RenderDragon (Newb y similares) via
# GameParrot's mcpelauncher-shadersmod.
#
# Un shader RenderDragon no es un resource pack comun: junto al
# manifest.json normal trae una carpeta renderer/materials/ con
# archivos *.material.bin en la raiz del pack (los subpacks/ opcionales
# se ignoran a proposito -- son variantes que en Trinity se eligen
# desde un selector que este metodo de carpeta plana no tiene). Ese
# renderer/materials/ no va a resource_packs/ como el resto del pack:
# el mod shadersmod lo lee aparte, en su propia carpeta shaders/ sin
# subcarpetas.
#
# Requiere tener ya instalado libmcpelaunchershadersmod.so en mods/
# (github.com/GameParrot/mcpelauncher-shadersmod) -- eso este script NO
# lo automatiza (es un binario externo, se instala una sola vez a
# mano). Si falta, solo avisa.

SRC_DIR="$HOME/Mods"

# LAUNCHER_APP_ID permite apuntar a otro flatpak de mcpelauncher (p.ej.
# Trinity: com.trench.trinity.launcher) sin tocar el script:
#   LAUNCHER_APP_ID=com.trench.trinity.launcher ./instalar_mods_bedrock.sh
LAUNCHER_APP_ID="${LAUNCHER_APP_ID:-io.mrarm.mcpelauncher}"

APP_DATA_DIR="$HOME/.var/app/$LAUNCHER_APP_ID/data/mcpelauncher"
MCPE_DIR="$APP_DATA_DIR/games/com.mojang"
RES_DIR="$MCPE_DIR/resource_packs"
BEH_DIR="$MCPE_DIR/behavior_packs"
SHADERS_DIR="$APP_DATA_DIR/shaders"
MODS_DIR="$APP_DATA_DIR/mods"

if ! command -v unzip &> /dev/null; then
    echo "Falta 'unzip'. Instálalo con: sudo pacman -S unzip  (o tu gestor de paquetes)"
    exit 1
fi

mkdir -p "$RES_DIR" "$BEH_DIR" "$SHADERS_DIR"

if [ ! -f "$MODS_DIR/libmcpelaunchershadersmod.so" ]; then
    echo "Aviso: no encontré libmcpelaunchershadersmod.so en $MODS_DIR"
    echo "  Sin eso los shaders RenderDragon (Newb y similares) no van a cargar aunque"
    echo "  este script los copie bien. Bajalo de github.com/GameParrot/mcpelauncher-shadersmod"
    echo "  y ponelo en esa carpeta (una sola vez)."
    echo ""
fi

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
shader_count=0

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

        # Shader RenderDragon: renderer/materials/*.material.bin en la
        # raiz de ESTE pack (subpacks/ se ignora a proposito, ver nota
        # arriba). Van aparte, aplanados, a shaders/.
        shader_src="$packdir/renderer/materials"
        if [ -d "$shader_src" ] && compgen -G "$shader_src"/*.material.bin > /dev/null; then
            cp "$shader_src"/*.material.bin "$SHADERS_DIR"/
            n=$(ls "$shader_src"/*.material.bin | wc -l)
            echo "  -> [shader] $n archivo(s) .material.bin copiados a: $SHADERS_DIR"
            shader_count=$((shader_count + 1))
        fi
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
if [ "$shader_count" -gt 0 ]; then
    echo "$shader_count de esos traian shader RenderDragon -- confirma que libmcpelaunchershadersmod.so este en mods/ y activa el pack arriba de todo en Recursos Globales."
fi
echo "CIERRA Minecraft por completo y vuelve a abrirlo para que detecte los packs."
