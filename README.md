# 4IM3-Script Documentation

**4IM3-Script** is a high-performance, compiled animation language for OBS Studio. It transforms text commands into native Lua closures, allowing for **instant logic execution**, parallel background tasks, and complex procedural animations at 60+ FPS.

---

## **I. The Engine**

### **1. Compiled Architecture**
Unlike standard scripts that read text line-by-line, 4IM3-Script **compiles** your code when you save.
* **Instant Logic:** Commands like `!var`, `!if`, and math `()` run instantly (0ms). The script only pauses when it hits a `!wait` or a movement command.
* **Batch Processing:** You can run hundreds of logic checks in a single frame without lag.

### **2. Syntax Basics**
`!command | arg1 | arg2 |+| !next_command`

* **`!`**: Command prefix.
* **`|`**: Argument separator.
* **`|+|`**: Line separator.
* **`--`**: Comments (ignored by compiler).

---

## **II. Core Commands**

### **Flow Control & Logic**
| Command | Syntax | Description |
| :--- | :--- | :--- |
| **`!wait`** | `!wait\|time` | Pauses the script for a duration. <br>Ex: `!wait\|500ms` |
| **`!var`** | `!var\|name\|val` | Sets a variable. Supports math. <br>Ex: `!var\|mid\|((screen.width - width)/2)` |
| **`!if`** | `!if\|v1\|op\|v2\|TARGET` | Jumps to a `!label` OR runs a `!@func` if true. <br>Ex: `!if\|pos.x\|>\|1920\|@reset()` |
| **`!jump`** | `!jump\|LABEL` | Instantly moves execution to a label. |
| **`!label`** | `!label\|NAME` | Marks a location in the code. |
| **`!loop`** | `!loop` | Jumps back to line 1. |
| **`!log`** | `!log\|msg` | Prints text/variables to the OBS Script Log. |

### **Movement & Animation**
| Command | Syntax | Description |
| :--- | :--- | :--- |
| **`!move`** | `!move\|axis:val\|time` | Interpolates position/scale/rotation. <br>Ex: `!move\|x:500, y:200\|1s` |
| **`!easing`** | `!easing\|type` | Sets the curve for `!move`. <br>Options: `linear`, `sine_inout`, `back_out`, `quad_in`. |

### **Multitasking (Parallelism)**
| Command | Syntax | Description |
| :--- | :--- | :--- |
| **`!run`** | `!run\|cmd\|args...` | Spawns a **background task**. Runs in parallel with main script. <br>Ex: `!run\|rainbow\|0.5\|0` |
| **`!stop`** | `!stop` | Kills all active background tasks. |

---

## **III. Logic & Math**

### **1. Variables & Access**
* **Source Props:** `pos.x`, `width`, `rotation`, `scale.y`.
* **Environment:** `screen.width`, `screen.height`.
* **Custom:** Any variable created with `!var`.

### **2. Advanced Math**
* **Nested Parentheses:** Supported natively. <br>`!var | center | ((screen.width - 200) / 2)`
* **Relative Operators:** <br>`x:++100` (Add), `y:--50` (Sub), `scale:**2` (Multiply).

### **3. The Function Registry (`@Functions`)**
Use these inside math `()` or execute them directly via `!@name`.

| Function | Syntax | Description |
| :--- | :--- | :--- |
| **`@random`** | `@random(min, max)` | Returns random integer. |
| **`@dist`** | `@dist(x1,y1, x2,y2)` | Returns distance between two points. |
| **`@time`** | `@time()` | Returns current OS time (seconds). |
| **`@sin` / `@cos`** | `@sin(val)` | Trigonometry helpers. |
| **`@alert`** | `@alert(msg)` | Logs a message (Execution version of `!log`). |

**Usage Examples:**
* `!move | x:(@sin(@time()) * 100) | 1s`
* `!if | @random(1,100) | > | 50 | WINNER`
* `!@alert(System Ready)`

---

## **IV. Animation Presets**

Built-in effects. Duration `0` = Infinite.

| Preset | Syntax | Description |
| :--- | :--- | :--- |
| **Rainbow** | `!rainbow\|spd\|dur` | Cycles color through RGB spectrum. |
| **Shake** | `!shake\|amp\|dur` | Random position vibration. |
| **Glitch** | `!glitch\|amp\|dur` | Digital stutter/stretch effect. |
| **Breathing** | `!breathing\|spd\|dur` | Smooth scale/opacity pulse. |
| **DVD** | `!dvd\|spd\|dur` | Bounces off screen edges. |
| **Sway** | `!sway\|spd\|dur` | Gentle rotation back and forth. |

---

## **V. Direct API Access**

If a command isn't a preset, the engine searches the source object directly.
* **Multi-Arg Support:** `0,255,0` is auto-split.
* **Dot-Notation:** `style.grad.color` automatically walks the object tree.

| Target | Command Syntax |
| :--- | :--- |
| **Position** | `!pos\|x:0, y:0` |
| **Scale** | `!scale\|x:1, y:1` |
| **Rotation** | `!rot\|90` |
| **Dimensions** | `!width\|1920` / `!height\|1080` |
| **Cropping** | `!crop\|left:10, right:10` |
| **Opacity** | `!style.opacity\|0.5` |
| **Color** | `!style.color\|255, 0, 0` |
| **Gradient** | `!style.grad.enable` <br> `!style.grad.color\|255,0,255` |
| **Visibility** | `!hide` / `!show` |

---

## **VI. Example Scripts**

### **1. The "Elastic Magnetic Orb"**
*Demonstrates High-Performance Logic, Math, and Easing.*

```text
-- [[ SETUP ]]
!stop |+|
!run|breathing|0.05|0 |+|
!style.grad.enable |+|

!label|WAIT |+|
-- 1. Drift to Center (Single-line math)
!easing|sine_inout |+|
!move|x:((screen.width - width)/2), y:((screen.height - height)/2)|2s |+|
!wait|@random(1000, 2000) |+|

-- 2. Zap to Random Location
!easing|back_out |+|
!move|x:@random(0, (screen.width-width)), y:@random(0, (screen.height-height))|300ms |+|
!shake|10|300ms |+|

!jump|WAIT
