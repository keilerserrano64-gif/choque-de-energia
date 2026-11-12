# Definitivo de Madara Edo — «El juicio del Dios de la Guerra · Tengai Shinsei»

**Cómo se usa:** activa el despertar con **H** (barra de energía llena) y, mientras
dura, pulsa **H** otra vez. Una vez por despertar (lo consume). La CPU también puede usarlo.

Orden fijo (≈27 s): Susanoo Perfecto y tajo → carcajada → primer meteorito → se revela
el segundo → caen los dos → Madara de pie entre las ruinas. Esc lo acorta (aplica los
golpes que falten). Daño total ≈ 48 de 100 a un rival de defensa normal, en tres golpes
que pasan por las reglas normales del combate (`CombatSim.ultimate_hit`).

## Imágenes

No hacen falta imágenes nuevas. Madara usa sus cuadros reales (`charge` 3 para el sello
y la mano al cielo, `intro` 2 brazos cruzados, `special` 1 para el tajo, `victory` 0
para la risa, `idle` al final). El rival usa su propio cuadro `down` al quedar tumbado.
El Susanoo, los meteoritos, el cielo, las explosiones y el ojo Rinnegan se dibujan con
código (pixel art).

## Sonidos

Los de `audio/` son **provisionales** (`python tools/gen_ultimate_audio.py`). Para usar
los tuyos, pon en ESTA carpeta un archivo con el nombre de la tabla y se usará solo:

| Uso | Archivo definitivo (opcional) | Provisional |
|-----|-------------------------------|-------------|
| Música (25 s; silencio en 19,0–19,6 s; golpes en 9, 21 y 23 s) | `Ultimate_Music.ogg` | `audio/musica_definitivo.wav` |
| Sonido amenazante (activación) | `Threat_SFX.ogg` | `audio/amenaza.wav` |
| Aparición del Susanoo | `Susanoo_SFX.ogg` | `audio/susanoo.wav` |
| La espada se alza | `Sword_Raise_SFX.ogg` | `audio/espada_alza.wav` |
| Tajo de la espada | `Sword_Slash_SFX.ogg` | `audio/espada_tajo.wav` |
| **Carcajada de Madara** | `Madara_Laugh.ogg` | `audio/risa.wav` (sintética) |
| Rugido del cielo | `Sky_SFX.ogg` | `audio/cielo.wav` |
| Caída del meteorito | `Meteor_Fall_SFX.ogg` | `audio/meteoro_cae.wav` |
| Primera explosión | `Explosion1_SFX.ogg` | `audio/explosion1.wav` |
| Segunda explosión | `Explosion2_SFX.ogg` | `audio/explosion2.wav` |
| **Frase «¿Esto es todo lo que tenéis?»** | `Madara_Line.ogg` | (sin voz: solo subtítulo) |

Abre el proyecto en el editor una vez tras añadir un archivo para que Godot lo importe.
