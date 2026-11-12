# Intro cinematográfica de Madara Edo — recursos

La intro (`scenes/intros/madara_edo_intro.tscn`) se reproduce sola antes del asalto 1
cuando Madara Edo está en el combate (no en Entrenamiento ni con «Saltar intros»
activado en Opciones). Se puede saltar con Enter / J / Esc.

## Imágenes

No hace falta ninguna imagen nueva: usa los cuadros reales de
`assets/fighters/madara_edo/madara_edo_sheet.png` que ya están en el catálogo:

| Fase | Cuadro |
|------|--------|
| Aparición | `intro` 0 (silueta), 1 (se materializa) y 2 (armadura, brazos cruzados) |
| Sharingan | `charge` 3 (sello de mano junto a la cara) |
| Chakra | `special` 0 (se agacha) e `intro` 2 (se yergue) |
| Pose final | `intro` 3, 4 y 5, y después `idle` |

El humo, el polvo, el aura de chakra, las ondas, los rayos, el ojo con el Sharingan
y la tarjeta del nombre se dibujan con código (pixel art), así que no hay archivos
de imagen provisionales.

## Sonidos

Los sonidos de `audio/` son **provisionales**, sintetizados con
`python tools/gen_intro_audio.py`. Para usar los tuyos, pon en ESTA carpeta un
archivo con el nombre de la tabla. Si existe, se usa en vez del provisional, sin
tocar código:

| Uso | Archivo definitivo (opcional) | Provisional |
|-----|-------------------------------|-------------|
| Música épica (12 s, crece y golpea a los 9 s) | `Intro_Music.ogg` | `audio/musica_intro.wav` |
| Viento (fase 1) | `Wind_SFX.ogg` | `audio/viento.wav` |
| Humo / aparición | `Smoke_SFX.ogg` | `audio/humo.wav` |
| Activación del Sharingan | `Sharingan_SFX.ogg` | `audio/sharingan.wav` |
| Liberación de chakra | `Chakra_SFX.ogg` | `audio/chakra.wav` |
| Onda expansiva | `Wave_SFX.ogg` | `audio/onda.wav` |

Abre el proyecto en el editor una vez después de añadir un archivo para que Godot lo importe.
