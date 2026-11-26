# Addendum al GDD — sistemas añadidos durante M9

Extiende `docs/GDD.pdf` **sin sustituirlo**. La numeración continúa desde §8 del documento
original; cada sección indica a qué apartado extiende. Cuando hay conflicto, el PDF sigue
siendo la fuente y este addendum el registro de la decisión (ver `docs/DECISIONS.md`).

Autor del GDD original: Juan Camilo Valencia. Implementación y sistemas añadidos:
**Juan Pablo Ante Suárez (2140132)**. Este adendo documenta lo que el equipo implementó
después del prototipado, no un cambio de visión.

Estado: **§9–§17 implementados**.

---

## 9. Amenazas ambientales (extiende §2.5 y §3.2)

### 9.1 Principio

El turno original solo castigaba decisiones del jugador: si jugabas bien, no podías perder.
Para que el tejido cósmico sea una amenaza real y no un contador de errores, el nivel emite
**una amenaza por compás como máximo**, **anunciada en el compás** y **resuelta en un beat**.
Esquivar usa el mismo reloj que lanzar, así que el ritmo gobierna ambas cosas.

### 9.2 Catálogo vigente

| Amenaza | Desde | Forma de peligro | Daño |
|---|---|---|---|
| **Fuga de vacío** | Fase 1 | Disco de 72 px con campo gravitatorio de 170 px | −4/−6/−8 según dificultad |
| **Micrometeorito** | Fase 2 | Impacto en área de 56 px, golpea en el beat | −4/−6/−8 |

El **arco de pelusa** y el **bolsillo de gravedad** están implementados y testeados pero
**fuera de rotación** hasta que su arte esté a la altura (D058). Reactivarlos es una línea en
`HazardPlanner.enabled_kinds()`.

### 9.3 Reglas de aparición

- Rejilla de 32 px dentro del **cuadro delimitado por los centros de las cuatro lavadoras**;
  nunca en las columnas laterales ni detrás de las cintas.
- Prohibido: cintas (+24 px), lavadoras y trituradoras (+12 px), ducto de entrega (90 px),
  borde de la sala (40 px).
- Al menos 120 px de la amenaza anterior y **24 px del jugador**.
- Sin amenazas en los primeros 30 s ni durante el tutorial.

### 9.4 Aviso y resolución

Aviso de **3 beats** (TRANQUILO) o **2 beats** (ESTÁNDAR/CAÓTICO); nunca menos de 2, porque
a 142 BPM un beat son 423 ms. El anillo se contrae durante el aviso y, al golpear, se
convierte en una onda expansiva: el área de daño está pintada desde el primer frame.

### 9.5 Esquiva

Salir de la zona dentro de ±`WINDOW_PERFECT_S` del golpe paga **+25 puntos** y alivia el
índice de vacío. Salir antes es seguro pero no paga. Quedarse cuesta estabilidad.

### 9.6 La fuga de vacío como pozo gravitatorio

| Propiedad | Valor |
|---|---|
| Duración del campo | 3 beats |
| Radio de gravedad | 170 px |
| Arrastre sobre Pip | 155 px/s en el centro, caída lineal a 0 |
| Velocidad de Pip dentro del radio de daño | 55 % |
| Daño sostenido | un tick cada 0.5 s mientras siga dentro (i-frames de 1.0 s) |
| Planetas | fuerza de 780 px/s² × masa, misma caída |
| Núcleo | 30 px: un planeta a ≥120 px/s que lo cruza **se traga** (−3 estabilidad) |
| Núcleo de galaxia | no se traga (pieza única de la Carga Final) |

El arrastre se aplica como desplazamiento, no como velocidad: el rozamiento de marcha borraba
la fuerza en pocos frames (D055). Un lanzamiento que cruza el pozo se curva y puede fallar el
tiro; cuanto más cerca pasa, más se desvía.

---

## 10. Índice de Vacío (extiende §2.3 y §2.4)

Segunda barra, 0–100, **no letal**. Sube sola y salta con los errores de ritmo; baja al
entregar limpio y al esquivar a tiempo. Al llenarse provoca un **colapso parcial** y vuelve a
55, no a 0: la deuda sigue visible.

| Evento | Δ |
|---|---|
| Paso del tiempo (fases 1→4) | +0.30 / +0.45 / +0.60 / +0.75 por segundo |
| Entrega limpia | −10 |
| Esquiva perfecta | −4 |
| MISS de ritmo | +8 |
| Lavadora equivocada | +6 |
| Colapso | amenazas al doble durante 8 / 10 / 12 s, luego vuelve a 55 |

Se dibuja como una tira de 4 px en el borde inferior de la cinta de objetivo, para no añadir
otra placa al HUD.

---

## 11. Dificultad (extiende §2.5)

Tres presets persistentes en `user://settings.cfg`, elegibles en Opciones.

| Perilla | TRANQUILO | ESTÁNDAR | CAÓTICO |
|---|---|---|---|
| Amenazas por compás | 0.25 | 0.5 | 1.0 |
| Beats de aviso | 3 | 2 | 2 |
| Daño por impacto | −4 | −6 | −8 |
| I-frames | 1.2 s | 1.0 s | 0.8 s |
| Intervalo de spawn × | 1.15 | 1.0 | 0.9 |
| Índice de vacío × | 0.7 | 1.0 | 1.35 |
| Ventanas rítmicas × | 1.15 | 1.0 | 0.95 |
| Colapso | 8 s | 10 s | 12 s |

ESTÁNDAR es ×1.0 en spawn y ventanas: la simulación de 480 s sigue dando exactamente 98
apariciones y todas las medidas del repositorio siguen siendo válidas.

---

## 12. Récords del jugador (extiende §2.2 y §4.3)

Tres tablas independientes, **top 10 por dificultad**, persistidas en `user://records.json`
(archivo propio para que *Restablecer* no borre los récords).

Cada entrada: puntos, rango, precisión, combo máximo, entregadas, semilla, fecha y dificultad.
Orden: puntos desc, precisión desc, el turno más antiguo primero. Se mostrará el top de la
dificultad jugada en la pantalla final y una pantalla de récords desde el título.

La pantalla de récords cuelga del título (← → cambia de dificultad, ESC vuelve) y la
pantalla final añade una línea con el puesto alcanzado o `FUERA DEL TOP 10`. `best_score` y
`best_rank` se conservan por compatibilidad con el título.

---

## 13. Tipografía y legibilidad (extiende §4.2)

La escala original (56/40/28/20/16/14/12/10) dejaba el HUD en 12 px y las captions en 10 px,
con el reloj como el elemento más grande. Nueva escala: **56/40/28/22/18/16/14/12**, con la
estabilidad y el combo por encima del reloj en jerarquía. El texto del HUD se mantiene en una
sola familia (Silkscreen) y una sola tinta por intención.

---

## 14. Mezcla de audio (extiende §1.8 y §7.1)

- Bus **Loops** (−10 dB) para las máquinas y la cinta; **limiter** en Master (−3/−1 dB) para
  que cuatro lavadoras, una explosión y la alarma nunca clipeen.
- **Ducking** de la música: −3 dB / 120 ms en un PERIODO perfecto y −4 dB / 150 ms en un
  impacto de amenaza.
- El loop de cada lavadora es posicional (`AudioStreamPlayer2D`), así que las cuatro máquinas
  se separan en estéreo por su posición en la sala.

## 15. Octava compuerta del tutorial (extiende §4.3 y §5.1)

Tras «entrega en la tapa» el tutorial añade **ESQUIVA EL VACÍO**: una fuga de vacío inocua se
abre bajo Pip con 6 s de aviso y la compuerta se concede al salir del radio. No hace daño
(las amenazas están desactivadas en modo tutorial) y enseña el sistema nuevo sin riesgo.

## 16. Exportación (extiende §1.9 y §7.2)

Presets **Linux** y **Windows Desktop** con el PCK embebido en el binario. `build/` queda
fuera de git. El filtro de exportación deja fuera tests, fuentes de arte y documentación,
pero **incluye `art/palette.json`**, que el juego lee en runtime.

## 17. Estado de este addendum

| Sección | Estado | Evidencia |
|---|---|---|
| §9 Amenazas | Implementado | `HazardPlanner`, `HazardDirector`, `Hazard`, 718 tests |
| §9.6 Pozo gravitatorio | Implementado | tests de arrastre, freno, tick y tragarse planetas |
| §10 Índice de Vacío | Implementado | `VoidIndex`, barra en el HUD, tests de umbrales |
| §11 Dificultad | Implementado | `Config.DIFFICULTY_*`, Opciones, persistencia |
| §12 Récords | Implementado | `Leaderboard`, `RecordsScreen`, `records.json` |
| §13 Tipografía | Implementado | `UITheme`, capturas a 1280×720 |
| §14 Mezcla de audio | Implementado | `Settings` (Loops, limiter, ducking), `test_audio_buses` |
| §15 Tutorial, 8 compuertas | Implementado | `TutorialSteps`, `TutorialDirector`, tests de flujo |
| §16 Exportación | Implementado | `export_presets.cfg`, `build/linux`, `build/windows` |

Todo lo planificado para M9 queda implementado. Pendiente solo la publicación final del
repositorio y la sustentación.
