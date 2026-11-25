# Entrega final — checklist de la rúbrica

Este documento traduce la *Rúbrica proyecto final* al estado real del repositorio y reúne lo
que falta para publicarlo. Todo lo verificable está enlazado; lo pendiente está marcado como
**PENDIENTE** y depende de datos que solo el equipo puede dar (URL del repositorio, cuentas).

## 1. Checklist de la rúbrica

| Requisito de la rúbrica | Estado | Evidencia |
|---|---|---|
| Repositorio **público** en GitHub | **PENDIENTE**: falta crear el repo y añadir el remoto | instrucciones en §2 |
| Todos los miembros tienen commits | **PENDIENTE**: definir equipo y cuentas | §3 |
| Motor de la lista permitida | **Cumple** — Godot 4.7.2 | `docs/DECISIONS.md` D001 |
| Nivel completo con inicio y final claros | **Cumple** | §4: turno de 00:00 a 06:00, victoria/derrota, rango, reinicio |
| Audio ("el 50 % del juego es el audio") | **Cumple** | §5: 4 stems a 105/118/130/142 BPM, metrónomo, 9 SFX, calibración |
| Sin drogas, sexo, política ni religión | **Cumple** | tono: comedia de lavandería cósmica; sin esas temáticas |
| Demo + sustentación oral | **Preparado** | §6 guion de demo y §7 preguntas de sustentación |
| Que la segunda entrega no difiera de la primera | **Cumple** | mismo GDD y mismo género; `AGENTS.md` §0–§A8 |

## 2. Publicar el repositorio

El checkout local **no tiene remoto configurado**. Con el repositorio ya creado en GitHub:

```bash
cd "$PWD"                       # raíz del proyecto
git remote add origin git@github.com:<usuario>/<repo>.git   # o https://github.com/...
git push -u origin main
git tag -a v1.0-entrega -m "Entrega final: Cosmic Spin Cycle"
git push origin v1.0-entrega
```

Antes de publicar, verificar que el árbol está limpio y la compuerta completa pasa:

```bash
git status --short
export XDG_DATA_HOME="$PWD/.work/xdg/data" \
       XDG_CACHE_HOME="$PWD/.work/xdg/cache" \
       XDG_CONFIG_HOME="$PWD/.work/xdg/config"
./tools/verify_milestones.sh
```

El `.gitignore` excluye `.godot/`, `.work/`, `.worktrees/`, cachés de Python, logs, builds y
basura de sistema; no hay binarios de build ni credenciales en el índice (comprobado con
`git grep`).

## 3. Commits de todos los miembros

La rúbrica exige que **cada miembro** tenga commits. Hoy el historial está firmado por dos
identidades técnicas (`Cosmic Spin Cycle Dev`, `a2-audio`), no por personas. Dos opciones:

1. **Equipo real**: cada miembro clona el repo, configura su identidad y aporta al menos un
   commit real (documentación, arte, una corrección). Ejemplo:
   ```bash
   git clone <url> && cd <repo>
   git config user.name  "Nombre Apellido"
   git config user.email "correo@dominio"
   # editar docs/CREDITS.md o cualquier archivo propio
   git add . && git commit -m "docs(credits): add <nombre> to the team"
   git push
   ```
2. **Autoría individual**: si el proyecto es de una sola persona, se puede reescribir la
   autoría del historial local (aún no publicado) para que GitHub atribuya los commits a la
   cuenta del autor. Es una operación destructiva sobre hashes; debe hacerse **antes** del
   primer push y con respaldo (`git bundle create backup.bundle --all`).

## 4. Nivel completo (inicio → final)

- **Objetivo**: lavar los planetas sucios y entregarlos en la tapa verde antes de las 06:00
  sin que la estabilidad llegue a cero.
- **Inicio**: menú → *Iniciar turno* → prompt de primer arranque (tutorial recomendado) →
  turno a las 00:00 con 98 apariciones planificadas.
- **Final**: a las 06:00 se evalúa la estabilidad; la pantalla final muestra rango S/A/B/C,
  lavadas, entregadas, precisión, combo máximo, puntos y semilla. La derrota llega si la
  estabilidad toca 0 (o si una lavadora averiada no se atiende).
- **Reinicio**: `REPETIR` en menos de 0,5 s, con la misma semilla; `NUEVA SEMILLA` genera otro
  turno. No hay callejones sin salida.
- **Tutorial**: 7 pasos sobre el nivel real, omitible y repetible; persiste en
  `user://settings.cfg`.

## 5. Audio

- Cuatro stems CC0 adaptados a **105 / 118 / 130 / 142 BPM** con offset de primer beat conocido
  (`assets/audio/music.json`), bus `Music`.
- **Metrónomo** audible (clic por beat, acento en el compás) y anillo de beat en la tapa verde.
- Nueve SFX CC0 (agarre, lanzamiento, lavadora, entrega, explosión, alarma, UI, cinta,
  shredder), buses `SFX` y `UI`.
- Calibración de latencia de 10 s persistida (`docs/CALIBRATION.md`).
- Volumen, música y efectos ajustables desde *Opciones*.

## 6. Guion de demo (6–8 minutos)

1. **0:00** — Menú sobre el diorama vivo: jerarquía, foco con teclado/mando, ambiente.
2. **0:30** — *Iniciar turno* por primera vez → prompt de tutorial → hacer el tutorial
   (moverse, agarrar, lanzar, ritmo, color correcto, mantener E, entregar).
3. **3:00** — Turno real: mostrar el anillo de beat, el clic, la cinta, el holo de la lavadora,
   un lanzamiento PERFECTO (`+2 combo`), una entrega y el multiplicador.
4. **4:30** — Riesgo: lanzar a la lavadora equivocada → `¡ATASCADA!`, −12, 10 s averiada;
   hold E para estabilizar una turbulenta.
5. **5:30** — `F1` para saltar a fase 3 (o esperar el rampa): cintas más rápidas, más presión,
   reasignación de lavadoras.
6. **6:30** — `F1` hasta 06:00 → pantalla final con rango; `REPETIR` (instantáneo).
7. **7:00** — Cierre: arquitectura, pruebas (668), determinismo por semilla, accesibilidad.

## 7. Sustentación oral: preguntas probables

- **¿Cómo se sincroniza el ritmo?** `BeatConductor` deriva el tiempo del reloj de audio
  (posición + mezcla − latencia − calibración − offset del stem); la evaluación ocurre en
  `_input()`, no en `_physics_process()`.
- **¿Por qué las ventanas son ±90/±170 ms?** Se ampliaron tras pruebas: la versión estricta
  (±65/±130) no era perceptible sin experiencia en juegos de ritmo.
- **¿Qué hace único el bucle?** Leer color+patrón, elegir lavadora, lanzar al ritmo, mantener E
  para estabilizar, entregar; el combo multiplica puntos y el riesgo de romper una máquina.
- **¿Cómo se garantiza que no es injugable?** Un bot E2E (`tools/playtest_bot.gd`) juega el
  nivel real y es una compuerta de `verify_milestones.sh`; la cadencia se ajustó con sus
  mediciones (de 197 a 98 apariciones).
- **¿Accesibilidad?** Glifo+color, movimiento reducido, escala de HUD, mando y teclado, tutorial
  omitible, sin información solo por audio.

## 8. Limitaciones conocidas (honestidad para la sustentación)

- 60 FPS en la mediana (12,8 ms) en llvmpipe; no hay margen en picos de explosión.
- La prueba de comprensión con 5 personas está especificada pero no ejecutada.
- El balance final (M9) y los presets de exportación de Windows quedan fuera de esta entrega.
- El tutorial tiene 7 pasos y ~2:30 de duración; puede alargarse si el jugador se detiene.
