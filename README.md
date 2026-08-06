# Qmcbedrockmods

Instala `.mcpack` / `.mcaddon` / `.mcworld` / `.zip` de Minecraft Bedrock
(mcpelauncher, Flatpak `io.mrarm.mcpelauncher`) sin pasos manuales: tirás
los archivos en `~/Mods` y corrés el script (o el lanzador de escritorio).

## Uso

```bash
mkdir -p ~/Mods                 # poné ahi los .mcpack/.mcaddon/.mcworld/.zip
~/Qmcbedrockmods/instalar_mods_bedrock.sh
```

También disponible como lanzador de escritorio
(`instalar-mods-bedrock.desktop`).

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
- Actualizar un pack ya instalado a una versión nueva no lo desinstala
  primero (si cambiás el nombre de carpeta del addon entre versiones,
  puede quedar la vieja instalada en paralelo). No detectado como bug
  real todavía, solo una limitación conocida.
