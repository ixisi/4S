This README documents the **4IM3-Script** language based on your provided files. It covers the syntax, core commands, all built-in animations, and the available API commands you can access directly.

---

# **4IM3-Script Documentation**

**4IM3-Script** is a custom animation and logic language for OBS Studio sources. It allows you to chain commands, perform math on source properties (like position or scale), and create complex logic loops.

## **I. The Basics**

### **Syntax Structure**

Commands are separated by the sequence separator `|+|`. Arguments inside a command are separated by pipes `|`.

`!command | argument_1 | argument_2 |+| !next_command`

* **`!`**: All commands start with a bang.
* **`|`**: Separator for arguments.
* **`|+|`**: Separator for command blocks (lines).
* **`--`**: Comments. Anything after `--` is ignored (unless it is part of a math operator like `--1`).

### **Variables & Math**

You can use variables (like `screen.width` or `pos.x`) anywhere a number is expected.

* **Dot Notation**: Access properties directly (e.g., `pos.x`, `scale.y`, `bounds.x`).
* **Inline Math**: Wrap equations in parentheses `()`.
* Example: `!move|x:(screen.width / 2 - 100)`


* **Relative Operators**:
* `++`: Add (e.g., `x:++10` moves right 10px).
* `--`: Subtract (e.g., `y:--10` moves up 10px).
* `**`: Multiply.



---

## **II. Core Commands**

These are the fundamental commands for moving sources and controlling the script flow.

| Command | Syntax | Description |
| --- | --- | --- |
| **`!move`** | `!move|axis:val|time` | Moves the source over time. <br>

<br>Ex: `!move|x:500,y:200|1s` |
| **`!wait`** | `!wait|time` | Pauses execution. <br>

<br>Ex: `!wait|500ms` |
| **`!var`** | `!var|name|value` | Sets a variable. <br>

<br>Ex: `!var|start_x|pos.x` |
| **`!if`** | `!if|v1|op|v2|target` | Checks a condition. If true, jumps to a label or runs a function.<br>

<br>Ex: `!if|pos.x|>|1920|RESET` |
| **`!jump`** | `!jump|LABEL_NAME` | Jumps immediately to a specific `!label`. |
| **`!label`** | `!label|NAME` | Marks a spot in the code to jump to. |
| **`!loop`** | `!loop` | Restarts the script from the very first line. |
| **`!log`** | `!log|msg_or_var` | Prints a message or variable value to the OBS Script Log. |

---

## **III. Predefined Animations**

These are built-in effects you can use immediately. Most accept a **duration** (how long to run). If duration is `0` or omitted, they run infinitely until interrupted.

| Animation | Syntax | Description |
| --- | --- | --- |
| **Rainbow** | `!rainbow|speed|duration` | Cycles the source color (gradient) through RGB spectrum.<br>

<br>Ex: `!rainbow|0.5|5s` |
| **Shake** | `!shake|intensity|duration` | Randomly vibrates the source position.<br>

<br>Ex: `!shake|10|1s` |
| **Glitch** | `!glitch|intensity|duration` | Randomly teleports and stretches the source for a digital glitch effect.<br>

<br>Ex: `!glitch|20|200ms` |
| **Breathing** | `!breathing|speed|duration` | Gently pulses scale and opacity.<br>

<br>Ex: `!breathing|0.05|0` (Infinite) |
| **DVD Bounce** | `!dvd|speed|duration` | Bounces the source off the edges of the screen/bounds.<br>

<br>Ex: `!dvd|5|10s` |
| **Sway** | `!sway|speed|duration` | Gently rotates the source back and forth.<br>

<br>Ex: `!sway|0.05|0` |

---

## **IV. Logic Functions (@Functions)**

You can run these inside math equations `()` or execute them directly using `!@name`.

**Usage:**

* **Direct:** `!@alert(Hello World)`
* **In Math:** `!move|x:(@sin(@time()) * 100)`

| Function | Syntax | Description |
| --- | --- | --- |
| **`@random`** | `@random(min, max)` | Returns a random integer between min and max. |
| **`@time`** | `@time()` | Returns the current OS clock time (in seconds). |
| **`@round`** | `@round(val)` | Rounds a number to the nearest integer. |
| **`@sin` / `@cos**` | `@sin(val)` | Returns the Sine/Cosine of a value. |
| **`@min` / `@max**` | `@min(a, b)` | Returns the smaller/larger of two numbers. |
| **`@alert`** | `@alert(msg)` | Logs a warning message to the OBS log. |

*Note: Standard math functions like `floor`, `ceil`, `tan`, `sqrt`, `abs`, `log`, `exp` are also supported.*

---

## **V. API Direct Access (obj_source_t)**

If a command isn't in the "Core Commands" list (like `!scale` or `!rot`), the script falls back to the internal API wrapper (`obj_source_t`). You can call any of these directly.

**Syntax for API calls:**
`!command | argument` OR `!command | key:value, key:value`

### **Transform & Dimensions**

| Command | Arguments | Description |
| --- | --- | --- |
| **`!pos`** | `x:val, y:val` | Instantly sets position. <br>

<br>Ex: `!pos|x:0, y:0` |
| **`!scale`** | `x:val, y:val` | Sets scale factor (1 = 100%). <br>

<br>Ex: `!scale|x:1.5, y:1.5` |
| **`!rot`** | `val` | Sets rotation in degrees. <br>

<br>Ex: `!rot|90` |
| **`!width`** | `val` | Sets width in pixels. <br>

<br>Ex: `!width|1920` |
| **`!height`** | `val` | Sets height in pixels. <br>

<br>Ex: `!height|1080` |
| **`!bounds`** | `x:val, y:val` | Sets the bounding box size (if bounds are enabled). |
| **`!crop`** | `left:v, right:v...` | Crops the source. keys: `top`, `bottom`, `left`, `right`. |
| **`!align`** | `val` | Sets alignment integer (Obs alignment enum). |

### **Visibility & Management**

| Command | Arguments | Description |
| --- | --- | --- |
| **`!hide`** | *(None)* | Hides the source. |
| **`!show`** | *(None)* | Shows the source. |
| **`!remove`** | *(None)* | **Deletes** the scene item from the scene. |

### **Style & Color**

| Command | Arguments | Description |
| --- | --- | --- |
| **`!style.opacity`** | `val` | Sets opacity (0.0 to 1.0). <br>

<br>Ex: `!style.opacity|0.5` |
| **`!style.color`** | `r, g, b` | Sets source color overlay.<br>

<br>Ex: `!style.color|255, 0, 0` |
| **`!style.grad.enable`** | *(None)* | Enables the gradient filter. |
| **`!style.grad.color`** | `r, g, b` | Sets the gradient color. |
| **`!style.grad.dir`** | `val` | Sets gradient direction (degrees). |

---

## **VI. Example Scripts**

**1. Simple Bounce**

```text
!var|bottom|(screen.height - height) |+|
!label|TOP |+|
!move|y:bottom|1s |+|
!move|y:0|1s |+|
!jump|TOP

```

**2. Random Teleport (Chaos)**

```text
!label|CHAOS |+|
!pos|x:@random(0, 1920), y:@random(0, 1080) |+|
!wait|200ms |+|
!jump|CHAOS

```

**3. Rainbow DVD Logo**

```text
!rainbow|0.5|0 |+|   -- Infinite Rainbow
!dvd|5|0 |+|         -- Infinite Bounce

```
