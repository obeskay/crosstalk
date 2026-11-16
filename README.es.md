<div align="center">

<img src="assets/banner-es.jpg" alt="crosstalk — Antigravity como par no bloqueante para Claude Code" width="100%">

Consulta a un segundo modelo sin quedarte viendo el spinner. Conserva el hilo entre llamadas. Manda la respuesta a la sesión que de verdad la necesita.

[![License: MIT](https://img.shields.io/badge/License-MIT-black.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-2.1.224%2B-black)](https://code.claude.com/docs)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity-agy-black)](https://antigravity.google)

[English](README.md) · Español · [中文](README.zh-CN.md)

</div>

<p align="center">
  <img src="docs/media/ask.gif" alt="Una terminal con dos llamadas de crosstalk en el mismo hilo y luego crosstalk stats" width="100%">
  <br>
  <sub>Una sesión real: dos llamadas en el mismo hilo y luego <code>stats</code>. Las esperas del modelo están recortadas; la salida es literal.</sub>
</p>

---

## El problema

El puente Claude→Gemini habitual es **bloqueante**. Claude invoca `agy` y entonces todos esperan — tú, el modelo, la terminal — mientras un segundo modelo se lee un repo durante cuatro minutos. Delegar algo que te cuesta cuatro minutos de reloj no es delegar. Es una llamada a herramienta lenta.

crosstalk cambia la forma de la interacción, no la plomería:

- **No bloqueante.** La llamada se lanza en segundo plano. Claude sigue trabajando y recibe aviso cuando termina. La respuesta llega como interrupción que atiendes, no como espera que aguantas.
- **Con hilo.** Cada llamada puede retomar una conversación de Gemini con nombre, así que el seguimiento no vuelve a explicar el problema desde cero.
- **Enrutable.** Claude Code 2.1.224 agregó mensajería entre sesiones. crosstalk la usa: la respuesta puede aterrizar en la sesión que la necesita, no en la que resultó preguntar.
- **Con cuentas claras.** Cada llamada registra lo que costó. `stats` te dice cuánto trabajo sacaste de tu contexto de Claude.

## Cómo se compara

El trabajo previo es real y vale la pena — esto no lo reemplaza todo.

| | crosstalk | [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code) | [claude-code-agy-CLI-skill](https://github.com/SafeMantella/claude-code-agy-CLI-skill) |
|---|---|---|---|
| Delegación | no bloqueante | subagente bloqueante | bloqueante |
| Continuidad de conversación | hilos con nombre, retomados | por invocación | por invocación |
| Ruteo entre sesiones | sí, vía `SendMessage` | — | — |
| Contabilidad de tokens | ledger + `stats` | — | — |
| Ruteo de modelos por etapa del SDLC | — | sí | — |

Si lo que quieres es ruteo de modelos opinado a lo largo del ciclo de vida, usa `antigravity-for-claude-code`; es buen proyecto y hace algo que crosstalk ni intenta. Usa crosstalk cuando lo que quieres es un par al que puedas preguntarle sin detenerte.

## Instalación

```
/plugin marketplace add obeskay/crosstalk
```
```
/plugin install crosstalk@crosstalk
```

Son dos prompts separados — si los pegas juntos, la instalación no funciona.

O usa la skill sin el plugin: copia `skills/crosstalk/` a `~/.claude/skills/`. El script viaja dentro del directorio de la skill, así que esa copia es toda la instalación.

En cualquier caso, **abre una sesión nueva después** — Claude Code carga las skills al iniciar sesión.

## Requisitos

- **Claude Code 2.1.224+** para la mensajería entre sesiones. Las versiones anteriores siguen teniendo delegación no bloqueante e hilos; sólo el ruteo la necesita. macOS y Linux — la mensajería no está en Windows nativo.
- **[Antigravity CLI](https://antigravity.google)** (`agy`) en el `PATH`, con sesión iniciada.
- **`python3` o `node`** para leer el JSON de `agy`. Uno de los dos ya está en tu máquina.

## Uso

No lo invocas tú. Le pides a Claude:

```
pregúntale a Gemini si este retry puede cobrar doble
```
```
consigue una segunda opinión del plan de migración, no te esperes
```
```
que Gemini barra el repo buscando URLs hardcodeadas y le avise a la sesión de mi otra terminal
```

Directo, si lo prefieres:

```bash
crosstalk.sh ask "¿Este retry cobra doble en 429?" --thread pagos
crosstalk.sh ask "¿Y en 503?" --thread pagos   # se acuerda
crosstalk.sh stats
crosstalk.sh threads
crosstalk.sh reset pagos
```

Banderas: `--thread NOMBRE`, `--model M`, `--effort low|medium|high`, `--timeout DUR` (default `10m`).

## Cómo funciona

```
   tu sesión de Claude                          Antigravity
  ┌────────────────────┐                     ┌───────────────┐
  │  skill crosstalk   │  llamada en 2° plano│  agy -p       │
  │                    │ ──────────────────► │  --output-    │
  │  sigue trabajando ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │    format json│
  │                    │ ◄────────────────── │               │
  └─────────┬──────────┘   avisa al terminar └───────────────┘
            │                                        ▲
            │ SendMessage                            │ --conversation <id>
            ▼                                        │
  ┌────────────────────┐                    ┌────────┴────────┐
  │  tu otra sesión    │                    │ estado del hilo │
  │  de Claude         │                    │ (local, plano)  │
  └────────────────────┘                    └─────────────────┘
```

`agy -p --output-format json` devuelve `conversation_id`, `status`, `response` y `usage`. crosstalk guarda el id de conversación por nombre de hilo y lo devuelve con `--conversation` en la siguiente llamada, que es lo que abarata el seguimiento. Todo lo demás es superficie documentada de Claude Code: Bash en segundo plano para lo no bloqueante, `ListAgents` y `SendMessage` para el ruteo.

El estado vive en `$XDG_STATE_HOME/crosstalk` (`~/.local/state/crosstalk`). Dos cosas: ids de conversación y un ledger JSONL de lo que costó cada llamada. Se cambia con `CROSSTALK_STATE_DIR`. No se manda nada a ningún lado salvo a `agy`.

## Limitaciones

Dichas de frente, porque descubrirlas solo es peor:

- **Gemini arranca en frío.** No ve tus ediciones sin commitear, ni tu conversación, ni el plan que acabas de acordar. Los prompts tienen que sostenerse solos. Es propiedad de invocar un CLI aparte, no algo que crosstalk pueda tapar.
- **El ruteo entre sesiones necesita que la función esté activa.** Viene encendida por default en macOS y Linux desde 2.1.224, pero una sesión receptora puede retener o rechazar mensajes (`crossSessionInbound`), y algunos proveedores no la ofrecen. Verifica con `/list-agents`.
- **Los hilos son locales.** Los ids de conversación están en tu máquina. Otra máquina son otros hilos.
- **El ledger cuenta los tokens de Gemini, no tu ahorro.** Te dice cuánto trabajo se movió. Lo que habrías gastado haciéndolo en Claude no lo puede medir ninguno de los dos CLIs.

## Contribuir

Issues y PRs bienvenidos. Respeta el alcance: esto es un puente, no un framework. Si un cambio agrega una dependencia, tiene que ganársela.

## Licencia

MIT — ver [LICENSE](LICENSE).

Sin afiliación con Anthropic ni Google. Antigravity y Gemini son productos de Google; Claude Code es de Anthropic.
