# Qmcbedrockmods

Instala `.mcpack` / `.mcaddon` / `.mcworld` / `.zip` de Minecraft Bedrock
(mcpelauncher, Flatpak `io.mrarm.mcpelauncher`) sin pasos manuales: tirás
los archivos en `~/Mods` (mods/addons/shaders) o en `~/Mundos` (mundos
completos) y corrés el script (o el lanzador de escritorio).

## Uso

### Instalar

```bash
git clone https://github.com/Johankyuk/Qmcbedrockmods.git ~/Qmcbedrockmods
cd ~/Qmcbedrockmods && ./install.sh
```

`install.sh` es idempotente. Copia el script a `~/.local/bin/`, despliega el
lanzador de escritorio con la ruta del `$HOME` real (el repo guarda el
placeholder `HOME/`, nunca una ruta hardcodeada), crea `~/Mods` y `~/Mundos`,
y aborta con `exit 1` si falta `unzip`, `flatpak` o el propio launcher.

### Usar

```bash
# ~/Mods    -> .mcpack/.mcaddon/.zip (addons, shaders) y .mcworld (solo sus packs)
# ~/Mundos  -> .mcworld/.zip que quieras jugar como partida completa
~/.local/bin/instalar_mods_bedrock.sh
```

Para otro flatpak de mcpelauncher (p.ej. Trinity), ambos scripts respetan
`LAUNCHER_APP_ID`:

```bash
LAUNCHER_APP_ID=com.trench.trinity.launcher ./install.sh
```

También disponible como lanzador de escritorio
(`instalar-mods-bedrock.desktop`).

## v6: shaders RenderDragon integrados (fusión con NewbQ)

Ya no hace falta el wizard aparte (NewbQ, descartado):
un shader se tira en `~/Mods` como cualquier otro pack. Si el pack trae
`renderer/materials/*.material.bin` en su raíz, el script además:

1. **Loader:** si falta `mods/libmcpelaunchershadersmod.so`, lo baja una
   sola vez de
   [GameParrot/mcpelauncher-shadersmod](https://github.com/GameParrot/mcpelauncher-shadersmod)
   (asset exacto según `uname -m`: x86_64, x86, arm64-v8a, armeabi-v7a) y
   lo deja **plano** en `mods/`. Si estaba en una subcarpeta de `mods/`
   (donde el juego no lo carga), lo sube a la raíz.
2. **Materials:** mueve a respaldo los `.material.bin` del shader
   anterior y copia planos a `shaders/` solo los de la raíz de
   `renderer/materials/` (nunca `subpacks/`). Nunca quedan dos shaders
   mezclados.
3. **Resource pack:** el pack completo se importa como siempre (texturas,
   biomes, fogs).

**Cambio de shader con confirmación:** si ya hay un shader activo y el
pack nuevo es otro, antes de copiar nada el script pregunta:

```
  ¿Cambiar de shader?
    Activo ahora: Newb Aero
    Nuevo:        Newb Classic  (newb-classic.mcpack)
  Usar el nuevo? [s/N]:
```

Con `N` (default) el pack nuevo se omite entero y el activo queda
intacto. Reinstalar el mismo shader no pregunta. Sin terminal (p.ej.
corrido desde otro script) se conserva el activo. El nombre del activo
se guarda en `shaders/.qmc-shader-activo`; si falta, se deduce
comparando `shaders/` contra los resource packs instalados.

No se usa `CrackedMatter/mcpelauncher-materialbinloader`: hookea lo mismo
que shadersmod y se pisan. Si aparece en `mods/`, solo se avisa.

Después, en el juego: Configuración → Almacenamiento → Recursos globales →
activar el shader, subirlo **arriba de todo**, cerrar el juego por completo
y reabrir.

### Reinstalar sin duplicados (todos los packs)

Antes de copiar un pack se busca por el `uuid` del `header` de su
`manifest.json` si ya hay una versión instalada, aunque su carpeta tenga
otro nombre. Si la hay, se mueve a
`<data_root>/qmc-respaldos/<fecha>/` — ya no aparece dos veces en
Recursos globales. Nada se borra.

### Data root autodetectado

En orden: Flatpak oficial (`io.mrarm.mcpelauncher`), Trinity
(`com.trench.trinity.launcher`), nativo (`~/.local/share/mcpelauncher`).
Forzar uno: `LAUNCHER_APP_ID=...` o `DATA_ROOT=/ruta/a/mcpelauncher`.

## v5: importar mundos completos desde `~/Mundos`

`~/Mods` y `~/Mundos` son carpetas separadas a propósito, no un
descuido:

- Un `.mcworld` en **`~/Mods`** se sigue tratando como en v4: solo se
  extraen los packs (`behavior_packs`/`resource_packs`) que trae
  embebidos. Pensado para addons que alguien distribuyó empaquetados
  como mundo — el mundo en sí no se toca.
- Un `.mcworld` (o `.zip`) en **`~/Mundos`** se importa como mundo
  jugable completo a `minecraftWorlds/`.

La detección de mundo válido es por `level.dat` (a diferencia de un
addon, que tiene `manifest.json`), sin importar si el zip lo empaquetó
con `level.dat` en la raíz o adentro de una subcarpeta con el nombre
del mundo — ambos formatos existen en descargas reales, se buscan
hasta 3 niveles de profundidad.

Cada mundo se procesa de forma independiente (un `.mcworld` corrupto
no frena los demás) y si ya existe un mundo con el mismo nombre de
carpeta destino, no se pisa: se respalda como
`<nombre>.bak.<timestamp>` antes de copiar el nuevo, para no perder
partidas guardadas por una reimportación.

Probado con: mundo con `level.dat` en la raíz del zip, mundo con
`level.dat` en subcarpeta, extensión en mayúsculas, archivo corrupto,
reimportación de un mundo ya existente (confirma backup), y un `.zip`
de addon puesto por error en `~/Mundos` (se rechaza por no tener
`level.dat`).

## v3: bugs reales que tenía v2, confirmados con casos de prueba antes de tocar nada

1. **Un archivo corrupto mataba todo lo que venía después.** v2 tenía
   `set -e` global: si `unzip` fallaba en un solo archivo (descarga a
   medias, zip inválido), el script entero moría ahí y todo lo que
   seguía alfabéticamente después nunca se procesaba — sin ningún aviso
   de que se saltearon. Ahora cada archivo se procesa en su propio
   intento; si falla, se avisa y se sigue con el resto.

2. **Dos addons distintos con carpetas internas genéricas (`BP`/`RP`,
   muy común en addons reales) se pisaban entre sí en silencio.** v2
   usaba el nombre de carpeta tal cual venía adentro del zip como
   nombre de destino en `resource_packs/`/`behavior_packs/`. Si el
   segundo addon instalado también traía una carpeta llamada `BP`, pisaba
   al primero sin ningún error — el primero desaparecía sin aviso. Ahora
   el destino siempre lleva el nombre del archivo fuente como prefijo
   (`ModX__BP`, `ModY__BP`), único por definición entre archivos
   distintos.

3. **Extensiones no reconocidas.** v2 solo miraba `.mcpack`/`.mcaddon`
   en minúsculas exactas en la raíz de `~/Mods`. Ahora:
   - Case-insensitive (`.MCADDON`, `.McPack`, etc. — algunos
     navegadores/hosting alteran el casing).
   - Se suma `.zip` plano (muchos sitios de addons distribuyen así, sin
     que el usuario lo renombre).
   - Se suma `.mcworld` (mundos con el addon incrustado en
     `behavior_packs/`/`resource_packs/`, también muy común en
     descargas de la comunidad — el script solo extrae los packs
     embebidos, no importa el mundo en sí).

4. **Fallos silenciosos.** Si un archivo no tenía ningún
   `manifest.json` adentro (formato no reconocido, zip vacío, etc.), v2
   no decía nada — simplemente no instalaba nada para ese archivo. Ahora
   avisa explícitamente cuál archivo falló y por qué, y al final cuenta
   cuántos se instalaron bien vs. cuántos tuvieron problemas.

Los 4 puntos se probaron con 6 archivos de prueba armados a mano
(addon estándar, dos addons con carpetas `BP`/`RP` genéricas
colisionando, extensión en mayúsculas, `.zip` plano, `.mcworld`, y un
archivo corrupto) antes de aplicar el fix, y de nuevo después para
confirmar que los 10 UUIDs de los 5 addons válidos sobreviven intactos
y el corrupto se saltea sin frenar el resto.

## Fuera de alcance (a propósito)

- Detección de dependencias entre packs (`dependencies` en el
  manifest) — no se valida, se instala igual.
- Subpacks de shaders (`no_fog`, `no_wave`, etc.): no hay selector en
  este método de carpeta plana, se instala la variante base.
