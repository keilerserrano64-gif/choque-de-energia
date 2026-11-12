# Choque de Energía · versión Godot 4

Juego de pelea 2D en pixel art con **Kakashi**, **Naruto**, **Ban**, **Todo**, **Adam** y **Madara**, cada uno con técnica propia, despertar, menú principal,
modo **VS local**, **Arcade**, **VS CPU** y **Entrenamiento**. Es la versión web portada a Godot,
con la actualización del menú, la selección tipo libro con cámara, el temporizador de 99 s,
el mejor de 3 rondas, el bloqueo y el hitstun.

> **Solo Kakashi y sin voces** (10-11-2026): se quitaron los otros ocho luchadores (Brasa, Volt,
> Marea, Cobalto, Espejo, Pedernal, Luma y Ónix) y todas las voces. Los combates son espejo
> (Kakashi contra Kakashi). Hay una copia completa de antes en `../respaldo_antes_solo_kakashi/`.
> Para añadir luchadores nuevos usa el importador (ver más abajo).
>
> Después se importaron **Naruto** (`naruto_hokage.png`, `mapa_naruto.json`; técnica «Esfera espiral»,
> embestida), **Ban** (`ban.png`, `mapa_ban.json`; técnica «Arrebato», tirón a distancia) y **Todo**
> (`todo.png`, `mapa_todo.json`; técnica «Aplauso de intercambio»: aparece junto al rival y le golpea)
> y **Adam** (`adam.png` con `--crop 0,0,1586,2623`, solo la primera copia; `mapa_adam.json`; técnica
> «Ráfaga copiada»: ráfaga de puños de cerca que lanza al rival) y **Madara** (`madara_kai.png` con
> `--bg none --scale 0.5 --alpha 128 --gap -1 --min 24`; `mapa_madara.json`; técnica «Abanico de guerra»:
> ráfaga de largo alcance).
>
> Las hojas originales y los mapas están en `fuentes/` (Godot no la importa: tiene `.gdignore`).

Todo el arte se dibuja con código (rectángulos pixel art, como en el juego web), así que no hay
imágenes que importar. La música y los efectos están en `assets/audio/` como WAV.

## Abrir el proyecto

1. Instala **Godot 4.3 o superior** (versión estándar, no hace falta la de .NET).
2. Abre Godot, pulsa **Importar** y elige el archivo `project.godot` de esta carpeta.
3. La primera vez Godot importa los sonidos y registra las clases. Si ves algún aviso rojo
   en la salida durante esa primera importación, cierra y vuelve a abrir el proyecto.
4. Pulsa **F5** (o el botón ▶) para jugar. La escena principal es `scenes/main_menu.tscn`.

Si tu versión es 4.4 o más nueva, Godot ofrecerá convertir el proyecto: acepta.

## Controles

| Acción | Jugador 1 | Jugador 2 (VS) | Mando |
|---|---|---|---|
| Moverse | A / D | ← / → | Cruceta o stick |
| Saltar | W o Espacio | ↑ | Cruceta ↑ o stick |
| Abajo | S | ↓ | Cruceta ↓ |
| Cubrirse (mantener) | E | Numpad 5 o Ç | LB |
| Correr | Mayús | Numpad 0 o Ñ | RB |
| Puño (combo de puños) | I | Numpad 1 o , | X |
| Patada (combo de patadas) | J | Numpad 6 o M | A |
| Técnica | K | Numpad 2 o . | B |
| Golpe fuerte (puño fuerte o ataque de energía) / remate | L | Numpad 4 o ´ | RT |
| Patada fuerte | S + L | ↓ + Num4 | ↓ + RT |
| Despertar | H | Numpad 3 o - | Y |
| Barrida / antiaéreo | S + J / S + I | ↓ + patada / ↓ + puño | ↓ + A / ↓ + X |
| Agarre | D/A hacia el rival + L | → + Num4 | → + RT |
| Pausa | Esc o P | | Start |

El golpe fuerte (L) usa la imagen de golpe fuerte de cada luchador (puño fuerte o ataque de energía) y ↓ + L, su patada fuerte. **Itachi** es la excepción: su ↓ + L (y el remate de su cadena de patadas) es el **Torbellino de espada**, una técnica con tajos morados (`heavy_kick_name` en `catalog.gd`). Es un solo golpe con la fuerza y el empuje del remate del combo
(85 % del daño), pero tarda más en recuperarse y reinicia el combo. Caminar hacia atrás ya
no bloquea: para cubrirse hay que mantener E.

En **VS CPU**, **Arcade** y **Entrenamiento** el jugador 1 puede usar también las flechas.
El primer mando controla al J1 y el segundo al J2. Las acciones se registran en
`scripts/autoload/controls.gd`; si creas una acción con el mismo nombre en
*Proyecto > Configuración del proyecto > Mapa de entrada*, se usa la tuya.

## Versión 3: puños, patadas y combos reales

> Desde el 11-11-2026 las teclas del J1 son **I puño · J patada · K técnica · L golpe fuerte**;
> los textos de esta sección ya usan las teclas nuevas.

- **Puños y patadas separados**: si pulsas **I** varias veces solo salen puñetazos
  (jab → directo → gancho → **uppercut** que lanza al rival). Si pulsas **J** varias veces
  solo salen patadas (baja → media → alta → **patada giratoria**). Cada luchador tiene su
  número de golpes por cadena (`punch_combo` y `kick_combo` en `catalog.gd`).
- **Mezclar no rompe el combo**: I, I, J, J = dos puños y dos patadas seguidas.
  **L** a mitad de cualquier cadena la remata (lanzador o remate cruzado).
- **Combos reales**: el aturdimiento de cada golpe cubre la recuperación del siguiente, así que
  una cadena completa no se puede interrumpir. El contador muestra los golpes y el daño total.
- **Reducción de daño (proration)**: a partir del 4.º golpe de un combo cada golpe hace un 8 %
  menos (mínimo 45 %), como en los juegos de lucha actuales. Ajustes en `combo_data.gd`.
- **Malabares**: el uppercut y la patada giratoria lanzan al rival; se le puede seguir
  golpeando en el aire hasta 4 veces.
- **CPU más lista**: piensa combos enteros de puños, patadas o mezclas, y en Desafío/Experto
  solo los continúa si el primer golpe entra.
- **Movimientos de comando**:
  - **↓ + I** uppercut antiaéreo · **↓ + J** barrida (derriba al rival) · **↓ + L** patada fuerte
  - **I o J en el aire**: puño aéreo o patada voladora (uno por salto). Enlazan con un combo al
    aterrizar (salto + patada → I, I, I…).
  - **→ + L pegado al rival**: agarre. Atraviesa la guardia: es la respuesta a quien se cubre
    todo el rato. De lejos, →+L sigue siendo el golpe fuerte.
- **Kakashi** (juego que antes era de Volt):
  - **Salto de umbral (K)** frena justo delante del rival y le golpea si está a tiro, también
    pegado a él. Antes, usado a quemarropa, fallaba y le teletransportaba detrás del rival.
  - **Atrás + K**: esquiva hacia atrás con estela eléctrica; el primer golpe que le llegue en ese
    instante lo atraviesa sin hacer daño («¡ESQUIVA RELÁMPAGO!»). La CPU también la usa.
  - **Arco de ruptura** (despertar) también conecta a quemarropa.
  - Como solo tiene unas pocas imágenes, sus golpes se inclinan para que se lean bien:
    patada baja, patada alta, giro de la patada giratoria, barrida, uppercut y ataques aéreos.
  - Se activa por su técnica (`"special": "volt-step"`), no por el nombre: cualquier luchador
    con esa técnica lo tiene.
- **Contraataque**: si golpeas al rival mientras prepara su golpe, haces un 25 % más de daño
  y queda aturdido más tiempo («¡CONTRAATAQUE!»).
- **Anuncios**: «¡PRIMER GOLPE!», «¡GRAN COMBO!» (5 golpes), «¡COMBO BRUTAL!» (8),
  «¡COMBO LEGENDARIO!» (12) y «¡PERFECTO!» si ganas la ronda sin recibir daño.
- **La CPU** también usa el antiaéreo, la patada voladora, la barrida y el agarre contra
  quien se cubre demasiado.
- **Lista de movimientos** actualizada en la pausa, con la cadena exacta de cada luchador.
- Táctil: botón **v** (abajo) para la barrida y el antiaéreo en móvil.

## Mejora visual (pixel art)

- **Escenarios** (`scripts/render/stage_painter.gd`), todos con cielo en degradado tramado y
  elementos animados:
  - **Puerto Brumaria**: luna llena, ciudad con ventanas encendidas, faro con haz giratorio,
    barcos que se mecen, gaviotas, reflejo en el agua y muelle de tablones con farolillos.
  - **Patio del Bastión**: atardecer, torres con tejado, murallas con almenas, estandartes,
    antorchas y público que salta en la grada; suelo de losas.
  - **Rocas Gemelas**: montañas nevadas, dos agujas de roca con cascada, pinos, pájaros y
    niebla; suelo de hierba que se mece y roca.
  - **Falla Carmesí**: luna roja, columnas de humo, ruinas en llamas, grieta de lava que
    late y brasas; suelo agrietado con lava.

### Efectos de combate (pixel art)

- **Chispas de impacto según el golpe**, en la altura real donde pega: estrella para los
  puños, media luna para las patadas, estallido con anillo para remates, agarres y
  lanzadores, y escudo hexagonal al bloquear (`ArenaView._draw_spark`).
- **Polvo**: nube al aterrizar de un salto alto o al caer derribado (con temblor de
  pantalla) y nubecillas detrás de los pies al correr.
- **Estela** de dos copias en los remates (uppercut, patada giratoria, patada alta,
  patada voladora, barrida, agarre).
- **Sombra ovalada** que se encoge y aclara cuando el luchador está en el aire.
- **Luz del escenario** sobre los luchadores: fría en el puerto, cálida en el bastión,
  rojiza en la falla.
- **Despertar**: llamas de energía del color del luchador que suben alrededor del cuerpo.

### Animación

- **Respiración**: de la cintura hacia arriba el cuerpo sube y baja; los pies no se mueven
  del suelo (antes se hundían un poco).
- **Caminar y correr**: zancada más amplia al correr, la pierna que avanza se levanta y el
  torso rebota con cada paso.
- **Rebote al ser derribado**: si cae desde muy alto rebota una vez contra el suelo, con
  polvo y temblor de pantalla.
### Pantallas

- **Transición pixelada** entre pantallas: bloques con borde brillante que tapan la
  pantalla en diagonal y se retiran en el mismo orden (`scripts/ui/components/pixel_wipe.gd`).
- **Presentación VS** antes del primer asalto: fondo partido con los colores de cada
  luchador, líneas de velocidad, retratos que entran desde los lados, nombres, el «VS» que
  golpea en el centro y el escenario (`scripts/fight/vs_splash.gd`). Se acorta con
  «Omitir presentación de ronda».
- **Resultado**: rayos de luz que giran detrás del ganador (en su color) y confeti pixelado.
- El menú principal deja ver mejor los escenarios animados de fondo.

## Importar luchadores desde una hoja de sprites

Herramienta para meter personajes nuevos (o cambiar los sprites de uno) a partir de una hoja
con todos los cuadros juntos. Encuentra Godot sola.

**Con ventana** (doble clic en `tools\importar.bat`, o abre `tools/importador/importador.tscn`
en el editor y pulsa F6):

1. **Abrir…** la hoja y **Analizar hoja**: salen los cuadros numerados (gris = repetido o reflejo).
2. Escribe el **id** (minúsculas, sin espacios), el **nombre** y la **base** de la que copiar
   estadísticas si es nuevo.
3. Elige una **pose** en la lista y haz **clic en sus cuadros en orden** (clic derecho quita).
   La animación se ve abajo, con los pies sobre el suelo.
4. **Aplicar al juego**.

**Por terminal** (desde la carpeta del proyecto):

```
tools\importar.bat --sheet hoja.png --fighter id                 # recorta y numera
tools\importar.bat --sheet hoja.png --fighter id --draft         # borrador del mapa por filas
tools\importar.bat --sheet hoja.png --fighter id --map mapa.json --name "Nombre" --base kakashi --apply
tools\importar.bat --fighter id --apply                          # repetir con lo guardado
tools\importar.bat --help                                        # todas las opciones y poses
```

Qué hace al aplicar:

- Detecta solo si la hoja tiene fondo liso o celdas de color (también admite rejilla fija con
  `--grid 64x64`). El color de las líneas entre celdas solo se borra fuera de ellas, así no se
  come pelo gris o ropa blanca.
- Guarda `assets/fighters/<id>/<id>_sheet.png` solo con los cuadros usados, alineados por los pies.
- Escribe el luchador en `scripts/data/catalog.gd`: si es nuevo, copia las estadísticas de la
  base; si existe, solo cambia sus sprites. Calcula `sprite_height` y `sprite_head` (retratos).
- Añade su estilo en `fighter_animations.gd` (con `"like"`: mismos tiempos que la base).
- Deja `tools/out/<id>_preview.png` (cuadros numerados) y `tools/out/<id>_poses.png` (cada pose
  con sus cuadros) para revisar, y una copia del catálogo anterior en `tools/out/respaldo/`.

**Reconoce la hoja solo**: separa lo que es el personaje de los efectos, letreros, marcos e
ilustraciones (por sus colores) y agrupa sus cuadros en animaciones. `tools/out/<id>_grupos.png`
muestra solo al personaje, una animación por fila y todo a la misma escala, con una pista de lo que
parece cada una (de pie, desplazamiento, tumbado, golpe con alcance…). `--draft` escribe el borrador
del mapa por animaciones con el reposo ya puesto. En la ventana, **Mayús + clic** añade una animación
entera y lo que no es el personaje sale oscurecido. Al aplicar, revisa el mapa y avisa si una pose
usa un efecto o mezcla cuadros de tamaños muy distintos.

**Hojas grandes y detalladas** (importaciones nuevas, detector v2): analiza la hoja en segundos aunque
sea enorme, recorta cada cuadro de la hoja original a tamaño completo y, si el personaje mide más de
200 px de pie, lo reduce con filtro suave. Decide solo si hace falta reducir la hoja, borrar la neblina
transparente o no juntar sprites apretados, y lo dice en el informe. Para desactivarlo: `--no-auto`.
En la ventana, todo está en «Opciones avanzadas». Las importaciones guardadas siguen con su detector,
así sus números de cuadro no cambian.

El mapa es un JSON `{"pose": número o [números]}`. Las poses son las del juego (`idle`, `walk`,
`jump`, `block`, `jab`, `light`, `heavy`, `finisher`, `finisher_impact`, `hurt`, `fall`,
`down`, `special`, `victory`…, o `<golpe>_<fase>` como `jab_anticipate`). Los nombres
habituales se traducen solos (`kick` → `finisher`, `salto` → `jump`, `daño` → `hurt`).
Ajustes opcionales: `"_frame_time": {"walk": 0.08}` (segundos por cuadro), `"_height": 65`
(tamaño en el juego), `"_offset": {"105": [2, -3]}` (mueve un cuadro mal colocado) y
`"_out_scale": 0.5` (tamaño de la hoja final). Si el personaje mira a la izquierda, añade `--flip`.

## Modos

- **Arcade**: un rival por luchador del catálogo (con solo Kakashi, cuatro combates espejo, uno
  por escenario), todos en dificultad Normal; los dos últimos rivales pueden despertar. Si pierdes puedes continuar. Al terminar ganas
  100 monedas extra.
- **VS**: dos jugadores en el mismo teclado o con dos mandos. No se ganan monedas.
- **VS CPU**: eliges tu luchador, el rival, el escenario y la dificultad (Normal por defecto).
- **Entrenamiento**: el rival es un muñeco quieto, la vida se recarga y se ven las cajas de colisión
  (verde = pushbox, rojo = hitbox activa). Se pueden ocultar en Opciones.
- **Tienda de despertares**: cada despertar cuesta 80 monedas y se guarda en el dispositivo.

## Estructura

```
choque_de_energia/
├── project.godot              Configuración (960x540, 60 ticks de física, autoloads)
├── icon.svg
├── assets/audio/              Efectos y música (WAV)
├── scenes/
│   ├── main_menu.tscn         Menú principal + Opciones + Tienda
│   ├── character_select.tscn  Selección tipo libro con cámara
│   ├── stage_select.tscn      Carrusel de escenarios y dificultad
│   └── fight.tscn             Arena, cámara, HUD, táctil, pausa y resultado
├── scripts/
│   ├── autoload/              SaveData, Sfx (audio), Controls (teclas), Router (escenas)
│   ├── data/                  catalog.gd (luchadores, escenarios) y fighter_animations.gd
│   ├── combat/                combat_sim.gd (toda la lógica), fighter_state.gd, player_input.gd
│   ├── render/                fighter_painter.gd, stage_painter.gd, arena_view.gd
│   ├── fight/                 fight.gd, fight_hud.gd, pause_menu.gd, result_panel.gd, touch_controls.gd
│   └── ui/                    menú, selección, escenario, opciones, tienda y componentes
└── tests/test_runner.gd       Pruebas de la lógica de combate
```

`CombatSim` no depende de nodos: es la traducción de `game.js`. Si quieres cambiar el balance,
casi todo está en `scripts/data/catalog.gd` (velocidad, daño, defensa, combos, enfriamientos).

### Añadir un luchador

Lo más fácil es el importador (ver «Importar luchadores desde una hoja de sprites»). A mano:

1. Copia una entrada de `FIGHTERS` en `scripts/data/catalog.gd` y cambia `id`, nombre, colores y valores.
2. Añade su estilo en `ANIMATION_STYLES` de `scripts/data/fighter_animations.gd`.
3. Si su técnica es nueva, añade un caso en `_release_special()` de `combat_sim.gd`
   y su tiempo de carga en `SPECIAL_CHARGE_FRAMES`.
4. La selección coloca sola a los luchadores del catálogo (hasta 9 casillas, `FIGHTER_SLOTS`
   en `scripts/ui/character_select.gd`).

### Luchadores con imágenes

Kakashi usa cuadros de una hoja de sprites: `assets/fighters/kakashi/kakashi_sheet.png`, declarados
en su entrada de `catalog.gd` (`sprites`, `sprite_anchor`, `sprite_height`, `sprite_head`). Las
estelas y rayos extra se hacen en código.

Para añadir otra pose, pon la imagen (128x128, mirando a la derecha y con los pies abajo)
en el diccionario `sprites` con una de estas claves: `attack`, `light`, `heavy`, `finisher`,
`<ataque>_<pose>` (p. ej. `light_impact`), `block`, `jump`, `walk`, `run`,
`run_alt`, `charge`, `special`, `hurt`, `fall`, `down`, `victory`, `intro`. Añade también
su punto de anclaje en `sprite_anchor` (el píxel del centro del cuerpo a la altura de los
pies). Las que falten usan `stance` o `idle`. En vez de una imagen puedes poner una lista de
cuadros (se repite en bucle) y su velocidad en `sprite_frame_time`.
Lo mismo sirve para cualquier otro luchador: con añadir `sprites` a su entrada deja de
dibujarse con rectángulos.

### Combos, buffer y estados (`scripts/data/combo_data.gd`)

Mecánicas portadas del sistema de combate de un proyecto de lucha en Unity (solo la lógica;
nada de su arte ni de sus personajes), reescritas dentro de `CombatSim`:

- **Árbol de combos**: I abre una cadena (I → I → I… hasta el remate de cada luchador).
  L la cierra en cualquier punto: **I → L = Lanzador** (lanza al rival para seguir golpeándolo
  en el aire) y **I → I → L = Remate cruzado** (remate más fuerte). L sin cadena es el golpe
  fuerte de siempre. Cada luchador puede tener sus ramas propias con `combo_branches` en `catalog.gd`.
- **Buffer de entrada**: I, J o L pulsados durante otro golpe (o durante la pausa de impacto) se
  guardan 0,3 s y salen solos en cuanto el golpe se puede cancelar.
- **Golpe en el aire = derribo**: quien recibe un golpe saltando cae y queda derribado.
- **Invulnerable al levantarse** del suelo.
- **Bloqueo en el aire** (mantener E saltando).
- **Guardia firme**: bloquear un golpe cuerpo a cuerpo aturde al atacante un instante y lo
  empuja hacia atrás (los proyectiles no).

### Shaders de las animaciones pesadas

Están en `shaders/` y usan el lenguaje de shaders de Godot (GLSL ES 3.0 con algunos
añadidos; Godot lo traduce a GLSL). Funcionan con el renderizador Compatibilidad y en Web.

- `fighter_fx.gdshader`: se aplica a la capa de cada luchador (`ArenaView`). En el despertar,
  al cargar una técnica y en remates o golpes fuertes añade venas de energía y un contorno
  eléctrico (el contorno solo en luchadores con imágenes), y un destello en el instante del golpe.
  `ArenaView._update_fighter_shader()` decide la intensidad.
- `screen_fx.gdshader` + `scripts/render/screen_fx.gd`: capa de pantalla completa entre la arena y
  el HUD. Onda expansiva desde el punto del impacto, aberración cromática, "impact frame" a dos
  tonos en los golpes más brutales y K.O. desaturado con viñeta. La simulación anota los momentos
  en `CombatSim.vfx_events` y `Fight._play_vfx_events()` los pasa al shader.
  El nodo se oculta cuando no hay efectos, así que no gasta GPU el resto del tiempo.
- Se pueden desactivar en **Opciones → Efectos de pantalla**.

### Cambiar el arte por sprites dibujados a mano

Todo el dibujo de personajes está en `FighterPainter.draw_body()`. Puedes sustituirlo por un
`AnimatedSprite2D` por luchador usando los mismos nombres de animación (`idle`, `walk`, `run`,
`jump`, `block`, `light`/`heavy`/`finisher`, `charge`, `special`, `hurt`, `fall`, `getup`,
`victory`, `intro`). `ArenaView.fighter_animation()` ya te dice qué animación y qué cuadro tocan.

## Exportar

1. *Editor > Administrar plantillas de exportación* > **Descargar e instalar**.
2. *Proyecto > Exportar* > **Añadir…** y elige la plataforma:
   - **Windows / Linux / macOS**: no necesita nada más. Exporta a la carpeta `export/`.
   - **Web**: funciona con el renderizador Compatibilidad, que ya está configurado.
     Súbelo a un servidor HTTPS (por ejemplo itch.io).
   - **Android**: instala el JDK 17 y el SDK de Android y configúralos en *Editor > Configuración
     del editor > Exportar > Android*. Los controles táctiles aparecen solos en pantallas táctiles.

## Pruebas

Después de abrir el proyecto una vez en el editor:

```
godot --headless --path . -s res://tests/test_runner.gd
```

Comprueban el catálogo, las animaciones, el hitstun, los derribos, el salto por encima del rival,
el bloqueo, el mejor de 3, el temporizador, los controles de VS, el entrenamiento, la técnica
y el juego de Kakashi, el importador y una simulación larga.

## Diferencias con la versión web

- La lógica corre a 60 ticks fijos por segundo (antes dependía de la frecuencia del monitor).
- En VS ya no se aplican al J2 el daño y la velocidad de la dificultad de la CPU.
- Nuevo modo Arcade con escalera de rivales y modo Entrenamiento funcional.
- Cámara con zoom al despertar y al final de la ronda, cámara lenta en el K.O. y barra de vida
  con daño retardado.
- Los escenarios tienen detalles animados (olas, estandartes, niebla y brasas).
- Soporte de mandos.
- Los botones táctiles tienen posición fija (en la web se podían arrastrar).

## Hojas de sprites (un PNG con todos los cuadros)

Un luchador puede usar una hoja de sprites en vez de un PNG por pose. En `catalog.gd`,
cada cuadro se escribe como `"ruta.png#x,y,ancho,alto"` (lo recorta `scripts/data/sprite_sheet.gd`).

Para preparar la hoja (quitar el fondo, encontrar los cuadros e igualarlos):

```
godot --headless --path . -s res://tools/slice_sheet.gd -- --sheet ruta/hoja.png --fighter id
```

1. Abre `tools/out/<id>_preview.png`: cada cuadro sale enmarcado en rojo y numerado.
2. Escribe un `mapa.json` con los números de cada pose, por ejemplo
   `{"idle": [0, 1, 2, 3], "walk": [4, 5, 6, 7], "jab": 8, "block": 12, "hurt": 14}`.
3. Vuelve a lanzar con `--map mapa.json`: imprime el bloque `"sprites"`, `"sprite_anchor"` y
   `"sprite_height"` para pegar en la entrada del luchador.

La hoja limpia se guarda en `assets/fighters/<id>/<id>_sheet.png`, con todos los cuadros en celdas
del mismo tamaño y los pies abajo al centro. Opciones: `--bg #rrggbb` si el fondo no es el
de la esquina, `--cells auto` si cada cuadro va en una celda de color (p. ej. fucsia) separada
de las demás por líneas o huecos de otro color (p. ej. gris), `--grid 64x64` o
`--grid-cols 8 --grid-rows 4` (con `--offset X,Y` y `--spacing X,Y`) si la hoja viene en rejilla fija, `--gap` para juntar piezas sueltas
y `--min` para ignorar textos y motas. Las claves de pose son las que ya admite el catálogo
(idle, stance, walk, run, jump, block, jab, cross, hook, uppercut, special, hurt, fall, victory…).
