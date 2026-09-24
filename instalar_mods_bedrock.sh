#!/bin/bash
# Instala .mcpack / .mcaddon / .mcworld / .zip en mcpelauncher (Minecraft
# Bedrock en Linux) - v6
#
# v6: fusion con NewbQ -- instalacion de shaders RenderDragon de punta a
# punta, sin wizard aparte.
#
# Si un pack trae renderer/materials/*.material.bin en su raiz, se trata
# como shader y ademas del import normal como resource pack se hace:
#   1. Loader: si falta mods/libmcpelaunchershadersmod.so se baja UNA vez
#      de GameParrot/mcpelauncher-shadersmod (asset exacto segun uname -m)
#      y se deja PLANO en mods/. Si estaba metido en una subcarpeta de
#      mods/ (donde el juego no lo carga) se mueve a la raiz.
#   2. Materials: los .material.bin viejos de shaders/ se respaldan y se
#      sacan antes de copiar los nuevos -- nunca dos shaders mezclados.
#      Solo los de la raiz de renderer/materials/, nunca subpacks/.
# NO se usa MaterialBinLoader (CrackedMatter): hookea lo mismo que
# shadersmod y se pisan. Si aparece en mods/ solo se avisa.
#
# Tambien en v6, para TODOS los packs (no solo shaders): antes de copiar
# se busca por UUID del header del manifest si ya hay una version
# instalada (aunque la carpeta tenga otro nombre). Si la hay, se mueve a
# <data_root>/qmc-respaldos/<fecha>/ en vez de quedar duplicada en
# "Recursos globales". Nada se borra: todo lo reemplazado va a respaldo.
#
# Data root: se autodetecta entre Flatpak oficial, Trinity y nativo
# (en ese orden de preferencia). Se puede forzar con:
#   LAUNCHER_APP_ID=com.trench.trinity.launcher ./instalar_mods_bedrock.sh
#   DATA_ROOT=/ruta/a/mcpelauncher ./instalar_mods_bedrock.sh
#
# v5: importa mundos completos desde ~/Mundos.
#
# Un .mcworld en ~/Mods se sigue tratando como hasta ahora: solo se
# extraen los packs embebidos (behavior_packs/resource_packs), pensado
# para addons que alguien distribuyo empaquetados como mundo. Un
# .mcworld en ~/Mundos en cambio SI se importa como mundo jugable
# completo a minecraftWorlds/ -- son dos carpetas con intenciones
# distintas a proposito, no un descuido.
#
# Un mundo real (a diferencia de un addon) no tiene manifest.json en la
# raiz -- tiene level.dat. Eso es lo que se usa para detectar si un
# archivo de ~/Mundos es un mundo valido, sin importar si el zip lo
# empaqueto con level.dat en la raiz o adentro de una subcarpeta con el
# nombre del mundo (ambos formatos existen en descargas reales).
#
# Si ya existe un mundo con el mismo nombre de carpeta destino, NO se
# pisa: se renombra a "<nombre>.bak.<timestamp>" antes de copiar el
# nuevo, para no perder partidas guardadas por una reimportacion.

SRC_DIR="$HOME/Mods"
WORLDS_SRC_DIR="$HOME/Mundos"

SHADERSMOD_REPO="GameParrot/mcpelauncher-shadersmod"
SHADERSMOD_SO="libmcpelaunchershadersmod.so"

# Resolucion del data root: DATA_ROOT explicito > LAUNCHER_APP_ID
# explicito > autodeteccion > Flatpak oficial por defecto.
DATA_ROOTS_POSIBLES=(
    "$HOME/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher"
    "$HOME/.var/app/com.trench.trinity.launcher/data/mcpelauncher"
    "$HOME/.local/share/mcpelauncher"
)
if [ -n "${DATA_ROOT:-}" ]; then
    APP_DATA_DIR="$DATA_ROOT"
elif [ -n "${LAUNCHER_APP_ID:-}" ]; then
    APP_DATA_DIR="$HOME/.var/app/$LAUNCHER_APP_ID/data/mcpelauncher"
else
    encontrados=()
    for r in "${DATA_ROOTS_POSIBLES[@]}"; do
        [ -d "$r" ] && encontrados+=("$r")
    done
    if [ ${#encontrados[@]} -eq 0 ]; then
        APP_DATA_DIR="${DATA_ROOTS_POSIBLES[0]}"
    else
        APP_DATA_DIR="${encontrados[0]}"
        if [ ${#encontrados[@]} -gt 1 ]; then
            echo "Aviso: hay ${#encontrados[@]} instalaciones de mcpelauncher, uso la primera:"
            printf '    %s\n' "${encontrados[@]}"
            echo "  Para otra: DATA_ROOT=/ruta/a/mcpelauncher $0"
            echo ""
        fi
    fi
fi
echo "Data root: $APP_DATA_DIR"
echo ""

MCPE_DIR="$APP_DATA_DIR/games/com.mojang"
RES_DIR="$MCPE_DIR/resource_packs"
BEH_DIR="$MCPE_DIR/behavior_packs"
SHADERS_DIR="$APP_DATA_DIR/shaders"
MODS_DIR="$APP_DATA_DIR/mods"
WORLDS_DEST_DIR="$MCPE_DIR/minecraftWorlds"
# Fuera de games/com.mojang a proposito: el juego no ve lo que hay aca.
BACKUP_DIR="$APP_DATA_DIR/qmc-respaldos/$(date +%Y%m%d-%H%M%S)"

# UUID del header de un manifest.json. Se aplana el archivo y se toma el
# primer uuid dentro del bloque "header" (el header no tiene objetos
# anidados, asi que cortar en la primera } alcanza). Si no se encuentra
# ahi, primer uuid del archivo.
pack_uuid() {
    local plano u
    plano=$(tr -d '\n\r' < "$1")
    u=$(printf '%s' "$plano" | grep -o '"header"[^}]*' | grep -o '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1)
    [ -z "$u" ] && u=$(printf '%s' "$plano" | grep -o '"uuid"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1)
    printf '%s' "$u" | sed 's/.*"\([^"]*\)"$/\1/' | tr 'A-Z' 'a-z'
}

# Mueve a respaldo cualquier pack ya instalado (en resource_packs/ o
# behavior_packs/) con el mismo UUID, y tambien la carpeta destino si ya
# existe, para que la copia nueva quede limpia y sin duplicados.
retirar_previos() {
    local uuid="$1" dest="$2" d m u
    for d in "$RES_DIR"/*/ "$BEH_DIR"/*/; do
        d="${d%/}"
        [ -d "$d" ] || continue
        m="$d/manifest.json"
        if [ "$d" = "$dest" ]; then
            :
        elif [ -n "$uuid" ] && [ -f "$m" ]; then
            u=$(pack_uuid "$m")
            [ "$u" = "$uuid" ] || continue
        else
            continue
        fi
        local sub
        sub=$(basename "$(dirname "$d")")
        mkdir -p "$BACKUP_DIR/$sub"
        if mv "$d" "$BACKUP_DIR/$sub/" 2>/dev/null; then
            echo "  (version previa '$(basename "$d")' movida a respaldo: $BACKUP_DIR/$sub/)"
        fi
    done
}

# Garantiza el loader shadersmod PLANO en mods/. Se ejecuta a lo sumo una
# vez por corrida y solo si algun pack resulto ser shader.
shadersmod_revisado=0
shadersmod_ok=0
asegurar_shadersmod() {
    [ "$shadersmod_revisado" = 1 ] && return
    shadersmod_revisado=1
    mkdir -p "$MODS_DIR"

    if compgen -G "$MODS_DIR/*[mM]aterial[bB]in[lL]oader*" > /dev/null; then
        echo "  ! Aviso: hay MaterialBinLoader en $MODS_DIR -- choca con shadersmod."
        echo "    Sacalo de ahi si el shader no carga o el render se rompe."
    fi

    if [ -f "$MODS_DIR/$SHADERSMOD_SO" ]; then
        shadersmod_ok=1
        return
    fi

    # Caso visto en la practica: el .so dentro de una subcarpeta de mods/
    # (pantalla vanilla, el juego no lo carga). Se sube a la raiz.
    local anidado
    anidado=$(find "$MODS_DIR" -mindepth 2 -name "$SHADERSMOD_SO" -type f 2>/dev/null | head -n 1)
    if [ -n "$anidado" ]; then
        mv "$anidado" "$MODS_DIR/$SHADERSMOD_SO"
        echo "  -> [loader] $SHADERSMOD_SO estaba en una subcarpeta, movido plano a $MODS_DIR"
        shadersmod_ok=1
        return
    fi

    local maquina arch
    maquina=$(uname -m)
    case "$maquina" in
        x86_64|amd64)  arch="x86_64" ;;
        i?86)          arch="x86" ;;
        aarch64|arm64) arch="arm64-v8a" ;;
        armv7*|armhf)  arch="armeabi-v7a" ;;
        *)
            echo "  ✗ [loader] arquitectura '$maquina' no soportada por shadersmod -- el shader no va a renderizar."
            return
            ;;
    esac

    if ! command -v curl &> /dev/null; then
        echo "  ✗ [loader] falta 'curl' para bajar shadersmod (sudo pacman -S curl)."
        echo "    O bajalo a mano: github.com/$SHADERSMOD_REPO/releases -> shadersmod-android-$arch.zip"
        return
    fi

    # URL directa al asset con nombre EXACTO: 'x86' nunca puede traer
    # 'x86_64' ni al reves, y no depende del rate limit de la API.
    local url="https://github.com/$SHADERSMOD_REPO/releases/latest/download/shadersmod-android-$arch.zip"
    local tmp so
    tmp=$(mktemp -d)
    echo "  -> [loader] bajando shadersmod-android-$arch.zip (una sola vez)..."
    if ! curl -fsSL -o "$tmp/mod.zip" "$url"; then
        echo "  ✗ [loader] fallo la descarga ($url) -- el shader no va a renderizar hasta instalarlo."
        rm -rf "$tmp"
        return
    fi
    if ! desempacar "$tmp/mod.zip" "$tmp/x" 2>/dev/null; then
        echo "  ✗ [loader] el zip descargado esta corrupto."
        rm -rf "$tmp"
        return
    fi
    so=$(find "$tmp/x" -name "$SHADERSMOD_SO" -type f | head -n 1)
    [ -z "$so" ] && so=$(find "$tmp/x" -name '*.so' -type f | head -n 1)
    if [ -z "$so" ]; then
        echo "  ✗ [loader] no hay ningun .so dentro del zip descargado."
        rm -rf "$tmp"
        return
    fi
    cp -f "$so" "$MODS_DIR/$SHADERSMOD_SO"
    rm -rf "$tmp"
    echo "  -> [loader] instalado: $MODS_DIR/$SHADERSMOD_SO"
    shadersmod_ok=1
}

# Deja en shaders/ SOLO los materials de este shader: los anteriores se
# mueven a respaldo antes de copiar, para no mezclar dos shaders.
instalar_materials() {
    local src="$1" n
    mkdir -p "$SHADERS_DIR"
    if compgen -G "$SHADERS_DIR/*.material.bin" > /dev/null; then
        mkdir -p "$BACKUP_DIR/shaders"
        mv -f "$SHADERS_DIR"/*.material.bin "$BACKUP_DIR/shaders/"
        echo "  (materials del shader anterior movidos a respaldo: $BACKUP_DIR/shaders/)"
    fi
    cp "$src"/*.material.bin "$SHADERS_DIR"/
    n=$(find "$src" -maxdepth 1 -name '*.material.bin' | wc -l)
    echo "  -> [shader] $n archivo(s) .material.bin copiados planos a: $SHADERS_DIR"
}

# Descomprime $1 en $2. unzip devuelve 1 en simples advertencias (p.ej.
# zips armados en Windows con "\" como separador): eso NO es un fallo,
# los archivos quedan extraidos igual. Solo >1 es error real. Despues se
# da permiso de escritura al usuario sobre todo lo extraido: hay packs
# que traen archivos/carpetas de solo lectura dentro del zip, y sin esto
# el rm -rf del temporal falla (basura en /tmp) y los packs copiados
# quedan de solo lectura en resource_packs/.
desempacar() {
    local rc
    unzip -oq "$1" -d "$2"
    rc=$?
    chmod -R u+rwX "$2" 2>/dev/null
    # Algunas versiones de unzip no convierten "\" y dejan archivos
    # llamados literalmente 'RP\manifest.json': se rearman como rutas.
    local f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$2"/}"
        rel="${rel//\\//}"
        mkdir -p "$2/$(dirname "$rel")"
        mv -f "$f" "$2/$rel"
    done < <(find "$2" -depth -name '*\\*' -type f -print0)
    [ "$rc" -le 1 ]
}

if ! command -v unzip &> /dev/null; then
    echo "Falta 'unzip'. Instálalo con: sudo pacman -S unzip  (o tu gestor de paquetes)"
    exit 1
fi

mkdir -p "$RES_DIR" "$BEH_DIR" "$SHADERS_DIR" "$WORLDS_DEST_DIR"

shopt -s nullglob
shopt -s nocaseglob   # que .MCADDON, .McPack, etc. tambien matcheen
files=("$SRC_DIR"/*.mcpack "$SRC_DIR"/*.mcaddon "$SRC_DIR"/*.mcworld "$SRC_DIR"/*.zip)
world_files=("$WORLDS_SRC_DIR"/*.mcworld "$WORLDS_SRC_DIR"/*.zip)
shopt -u nocaseglob

if [ ${#files[@]} -eq 0 ] && [ ${#world_files[@]} -eq 0 ]; then
    echo "No se encontraron archivos .mcpack/.mcaddon/.mcworld/.zip en $SRC_DIR"
    echo "ni archivos .mcworld/.zip en $WORLDS_SRC_DIR"
    exit 1
fi

ok_count=0
fail_count=0
shader_count=0

if [ ${#files[@]} -eq 0 ]; then
    echo "No se encontraron archivos .mcpack/.mcaddon/.mcworld/.zip en $SRC_DIR (se saltea esta parte)."
    echo ""
fi

for file in "${files[@]}"; do
    name=$(basename "$file")
    stem="${name%.*}"
    echo "Procesando: $name"

    tmpdir=$(mktemp -d)

    if ! desempacar "$file" "$tmpdir" 2>/tmp/unzip-err-$$; then
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
            if ! desempacar "$nfile" "$ndir" 2>/dev/null; then
                echo "    (aviso: no pude abrir un archivo anidado dentro de $name, lo ignoro)"
            fi
            rm -f "$nfile"
        done <<< "$nested"
    done

    # subpacks/ son variantes de un pack, nunca packs sueltos.
    manifests=$(find "$tmpdir" -name "manifest.json" -not -path "*/subpacks/*")
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

        retirar_previos "$(pack_uuid "$manifest")" "$dest"
        mkdir -p "$dest"
        cp -r "$packdir"/. "$dest"/
        echo "  -> [$type] copiado a: $dest"
        installed_any=1

        # Shader RenderDragon: renderer/materials/*.material.bin en la
        # raiz de ESTE pack (subpacks/ se ignora a proposito). Ademas del
        # import normal de arriba necesita loader + materials planos.
        shader_src="$packdir/renderer/materials"
        if [ -d "$shader_src" ] && compgen -G "$shader_src"/*.material.bin > /dev/null; then
            if [ "$shader_count" -gt 0 ]; then
                echo "  ! Aviso: otro shader en la misma corrida -- este reemplaza al anterior en shaders/."
            fi
            asegurar_shadersmod
            instalar_materials "$shader_src"
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

world_ok_count=0
world_fail_count=0

if [ ${#world_files[@]} -eq 0 ]; then
    echo "No se encontraron archivos .mcworld/.zip en $WORLDS_SRC_DIR (se saltea importacion de mundos)."
else
    echo ""
    echo "--- Importando mundos desde $WORLDS_SRC_DIR ---"
    for file in "${world_files[@]}"; do
        name=$(basename "$file")
        stem="${name%.*}"
        echo "Procesando mundo: $name"

        tmpdir=$(mktemp -d)

        if ! desempacar "$file" "$tmpdir" 2>/tmp/unzip-world-err-$$; then
            echo "  ✗ ERROR: '$name' no es un zip valido (descarga incompleta o corrupta) -- SE SALTEA, sigo con el resto."
            sed 's/^/    /' /tmp/unzip-world-err-$$
            rm -f /tmp/unzip-world-err-$$
            rm -rf "$tmpdir"
            world_fail_count=$((world_fail_count + 1))
            continue
        fi
        rm -f /tmp/unzip-world-err-$$

        # Un mundo real tiene level.dat (a diferencia de un addon, que
        # tiene manifest.json). Puede venir en la raiz del zip o adentro
        # de una subcarpeta -- se busca hasta 3 niveles de profundidad.
        level_dat=$(find "$tmpdir" -maxdepth 3 -iname "level.dat" | head -n 1)
        if [ -z "$level_dat" ]; then
            echo "  ✗ '$name' no tiene level.dat adentro (no es un mundo valido) -- SE SALTEA."
            rm -rf "$tmpdir"
            world_fail_count=$((world_fail_count + 1))
            continue
        fi
        worldroot=$(dirname "$level_dat")

        dest="$WORLDS_DEST_DIR/$stem"
        if [ -e "$dest" ]; then
            backup="${dest}.bak.$(date +%s)"
            mv "$dest" "$backup"
            echo "  (ya existia un mundo con ese nombre, respaldado en: $backup)"
        fi

        mkdir -p "$dest"
        cp -r "$worldroot"/* "$dest"/
        echo "  -> [mundo] copiado a: $dest"
        world_ok_count=$((world_ok_count + 1))

        rm -rf "$tmpdir"
    done
fi

echo ""
echo "Listo: $ok_count archivo(s) instalado(s), $fail_count con problemas (ver avisos arriba)."
if [ "$shader_count" -gt 0 ]; then
    echo "$shader_count pack(s) con shader RenderDragon."
    if [ "$shadersmod_ok" = 1 ]; then
        echo "  Loader OK. En el juego: Configuracion -> Almacenamiento -> Recursos globales,"
        echo "  activa el pack del shader y subilo ARRIBA DE TODO."
    else
        echo "  ✗ Sin loader shadersmod en mods/: el shader NO va a verse (ver errores arriba)."
    fi
fi
if [ ${#world_files[@]} -gt 0 ]; then
    echo "Mundos: $world_ok_count importado(s), $world_fail_count con problemas."
fi
if [ -d "$BACKUP_DIR" ]; then
    echo "Respaldos de lo reemplazado: $BACKUP_DIR"
fi
echo "CIERRA Minecraft por completo y vuelve a abrirlo para que detecte los packs y mundos."
