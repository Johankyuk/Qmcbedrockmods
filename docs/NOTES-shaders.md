# Notas — Shaders RenderDragon en Minecraft Bedrock (Linux / mcpelauncher)

Última actualización: 20 sep 2026
Continúa: sesión de julio 2026 (Trinity Launcher)

## Método que funciona (estado actual)

Launcher: Flatpak oficial `io.mrarm.mcpelauncher` (Flathub).
Data root: `~/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher/`
<data_root>/
├── mods/
│ └── libmcpelaunchershadersmod.so ← PLANO, sin subcarpeta
├── shaders/
│ └── *.material.bin ← PLANO, sin subcarpeta
└── games/com.mojang/resource_packs/
└── <nombre-del-pack>/ ← el .mcpack descomprimido completo

Mod: `GameParrot/mcpelauncher-shadersmod` (MIT). **No usar junto con**
`CrackedMatter/mcpelauncher-materialbinloader` — ambos hookean el mismo sistema
de render y se pisan. La guía oficial de CurseForge ahora solo menciona
MaterialBinLoader para Linux, pero el método probado y funcionando en este
setup es shadersmod solo.

Shader: Newb Classic / Newb X Legacy, de `devendrn/newb-x-mcbe`. Descarga
oficial: CurseForge o MCPEDL (GitHub ya no aloja el `.mcpack`, solo el
código fuente).

## Pasos (de cero)

```bash
DATA="$HOME/.var/app/io.mrarm.mcpelauncher/data/mcpelauncher"

# 1. Mod (plano, directo en mods/)
mkdir -p "$DATA/mods"
# bajar release de github.com/GameParrot/mcpelauncher-shadersmod (asset x86_64)
# si viene en .zip, descomprimir y mover el .so suelto a mods/, sin subcarpeta

# 2. Descomprimir el .mcpack (es un zip renombrado)
unzip -q "ruta/al/pack.mcpack" -d /tmp/newb_extraido

# 3. Materials, planos, solo de la raíz (no de subpacks)
mkdir -p "$DATA/shaders"
cp /tmp/newb_extraido/renderer/materials/*.material.bin "$DATA/shaders/"

# 4. Pack completo como resource pack normal (texturas, biomes, fogs)
mkdir -p "$DATA/games/com.mojang/resource_packs/nombre-del-pack"
cp -r /tmp/newb_extraido/* "$DATA/games/com.mojang/resource_packs/nombre-del-pack/"
```

En el juego: Configuración → Almacenamiento → Recursos globales → activar el
pack, subirlo arriba de todo, cerrar y reabrir el juego completo.

## Errores encontrados y su causa

**"No se ve nada, vanilla puro"** — el `.so` del mod quedó en una subcarpeta
dentro de `mods/` en vez de plano. El launcher no escanea subcarpetas
automático salvo que la UI las registre como mods activos por su cuenta, y
eso no pasa si el archivo se puso ahí por terminal.

**Dos entradas duplicadas del mismo shader en "Recursos globales"** — mismo
UUID, dos carpetas con nombre distinto en disco. Pasa si se importó una vez a
mano y otra vez el launcher auto-importó un `.mcpack` descargado desde el
navegador. Identificar la vigente (`grep uuid`/`version` en cada
`manifest.json`), borrar la vieja, resincronizar `shaders/`.

**Texto rojo "Only works with MB Loader / BetterRenderDragon / Hynis" en la
descripción del pack** — disclaimer genérico del autor listando los loaders
oficiales (Android/Windows/iOS). El método Linux/mcpelauncher no está en esa
lista por ser no oficial. No es advertencia de incompatibilidad real.

**`[ModLoader] Loaded 0 mods` al lanzar `mcpelauncher-client` directo** —
pasa si se lanza sin el flag `--mods /ruta`. Ese flag no se auto-detecta; lo
arma la UI según su propio gestor. Para debug real:
```bash
flatpak run --command=mcpelauncher-client io.mrarm.mcpelauncher \
  --game-dir <ruta-version> --data-dir <data-root> --mods <data-root>/mods
```

**Asset equivocado x86 vs x86_64** — GameParrot publica ambos con nombres
casi idénticos. Verificar con `ls | grep -i shadersmod` antes de descomprimir.

## Gotchas generales de la sesión (no específicos de shaders)

- Alias de `ls` (`eza --icons` probablemente) rompe con rutas que llevan `=`.
  Usar `\ls` para el comando real sin alias.
- `set -e` fuera de un subshell cierra la terminal entera si algo falla.
  Envolver siempre en `( set -e; ... )`.
- Verificar `$PWD` antes de `git init` — un `cd` en un bloque separado que no
  corrió deja al siguiente bloque parado en el directorio equivocado.
- CurseForge bloquea fetch automatizado (robots.txt) — los links de descarga
  se abren a mano en el navegador.
- GitHub API sin auth tiene rate limit bajo — para una descarga puntual de
  release alcanza, para exploración pesada (code search) truena rápido.

## Repo

NewbQ fue descartado; su lógica vive en `instalar_mods_bedrock.sh` v6 (ver README).

## Pendiente / no verificado

- No se re-confirmó por log que el ModLoader cargue el `.so` en un lanzamiento
  normal vía UI tras la corrección a `mods/` plano — se validó solo
  visualmente en el juego.
- El wizard de NewbQ nunca se probó de punta a punta en esta máquina (la
  descarga real desde la API de GitHub no se ejecutó en testing).
- Pack de texturas Faithful sigue en pausa (corrupción de render con
  `DRI_PRIME=1` en dGPU NVIDIA vía `horus-gpu-watch`) — heredado de julio.
- Vibrant Visuals sigue no viable (whitelist de GPU no incluye RTX).
