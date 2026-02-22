
# 4IM3 Animation & Scripting Engine for OBS

**4IM3** is a lightweight, asynchronous 2D animation engine that runs natively inside OBS via Lua. It allows you to write custom, highly performant animations, interactive stream overlays, and even complete 2D mini-games directly onto your OBS canvas without needing external software.

## Features

* **Custom Scripting Syntax:** Easy-to-read, pipe-delimited syntax.
* **True Asynchronous Threading:** Run multiple animations, particle spawners, and logic loops simultaneously without freezing OBS.
* **Scope-Protected Memory:** Professional-grade local and global variable isolation to prevent memory leaks.
* **Event-Driven Architecture:** CPU-friendly `on_change` watchers, hotkeys, and AABB collision detection.
* **Dynamic Math & Interpolation:** Evaluate math equations and object properties dynamically at runtime.

---

## 📖 Syntax Basics

Every command in 4IM3 starts with `!` and ends with the execution delimiter `|+|`. Arguments are separated by pipes `|`.

```text
!command|argument_1|argument_2 |+|
```

### Comments

```text
-- This is a single line comment. It must have its own line.
--[[ 
This is a multi-line block comment.
The engine will perfectly ignore everything in here! 
]]

```

### Dot-Notation & Properties

You can access live properties of your OBS sources directly in your math equations:

```text
!var|player|source(Hero) |+|
!source|health_bar |+|
!pin|player|x:((player.width - width) / 2), y:player.height |+|

```

---

## 📦 Variable & Memory Management

4IM3 utilizes a strict memory model to protect background threads from corrupting the main game state.

* **`!var|name|value`**: Creates or modifies a variable. If inside a `!run` thread, this creates a temporary **Local** variable.
* **`!gvar|name|value`**: Explicitly creates or modifies a **Global** variable across the entire engine.

**Math Operations:**
You can use relative math strings or wrap equations in parentheses.

```text
!var|score|++10 |+|          -- Adds 10 to score
!gvar|health|--1 |+|         -- Subtracts 1 from global health
!var|center_x|(1920 / 2) |+| -- Evaluates the math

```

---

## 🎯 Source Management

Before you can animate an object, you must select it.

| Command | Example | Description |
| --- | --- | --- |
| `!source` | `!source | Hero|+ |
| `@clone` | `!var | clone_id|@clone()|+ |
| `!show` / `!hide` | `!hide|+ | ` |
| `!delete_source` | `!delete_source|+ | ` |

---

## 🎬 Animation & Transformation

4IM3 includes a robust tweening engine.

**`!move | properties | duration | easing`**
Moves, scales, or rotates a source over time.

```text
!move|x:500, y:++50, rot:360|1.5s|quad_out |+|

```

*Supported Easings:* `linear`, `quad_in`, `quad_out`, `quad_inout`, `sine_inout`, `back_out`, `elastic_out`, `bounce_out`.

**`!pos`, `!scale`, `!rot` (Instant Transformations)**
Instantly snaps a source to a value without animation.

```text
!pos|x:960, y:540 |+|
!scale|x:1.5, y:1.5 |+|

```

**Advanced Animations:**

* `!path | cp_x:val, cp_y:val | target_x:val, target_y:val | duration | easing` (Bezier Curves)
* `!spiral | center_x, center_y | start_radius | rotations | duration | easing`
* `!fade | target_opacity | duration | easing`
* `!pin | parent_source | offsets` (Glues one source to another)

---

## 🧠 Logic & Control Flow

Control the flow of your script using loops, jumps, and conditional subroutines.

**Labels & Jumps (Loops)**

```text
!label|MyLoop |+|
    !move|y:++10|1s|sine_inout |+|
    !then|move|y:--10|1s|sine_inout |+|
    !jump|MyLoop |+|

```

**If Statements (`!if | val1 | operator | val2 | TargetLabel | Mode`)**

```text
-- Standard Jump (Leaves the current loop permanently)
!if|health|<=|0|DeathScreen |+|

-- Conditional Subroutine (Requires 'CALL' flag. Will return to this spot!)
!if|score|==|100|PlayCheer|CALL |+| 

```

**`!run{ ... }` (Background Threads)**
Spawns an isolated, asynchronous background thread. Perfect for particle spawners or overlapping animations.

```text
!run{
    !var|particle|@clone() |+|
    !source|particle |+|
    !move|y:1080|2s |+|
    !delete_source |+|
}|+|

```

**`!wait | duration`**
Pauses the current thread.

```text
!wait|0.5s |+|

```

---

## ⚡ Event Listeners (Watchers)

Never use infinite loops to check variables! Use CPU-friendly event listeners.

**`!on_change | variable | [operator] | [value] | LabelName`**
Wakes up and spawns a thread *only* when a variable changes.

```text
!on_change|health|<=|0|GameOver |+|
!on_change|score|UpdateScoreUI |+|

```

**`!onpress | Hotkey_Name | LabelName`**
Registers an OBS Hotkey. When pressed, safely spawns a background thread.

```text
!onpress|Shoot_Key|FireBullet |+|

```

**`!on_collision | source_1 | source_2 | LabelName`**
Fires a background thread when two source bounding boxes overlap.

```text
!on_collision|player|bullet|TakeDamage |+|

```

---

## 🎨 Styling & FX Library

Modify OBS source filters and text properties dynamically.

| Command | Example | Description |
| --- | --- | --- |
| `!text` | `!text|Score: score|+ | ` |
| `!style.color` | `!style.color|255|0|0|+ | ` |
| `!shake` | `!shake|15|0.5s|+ | ` |
| `!glitch` | `!glitch|20|1s|+ | ` |
| `!rainbow` | `!rainbow|0.01|0s|+ | ` |
| `!breathing` | `!breathing|0.05|0s|+ | ` |

---

## 🚀 Quick Example: Particle Spawner

Here is a complete script demonstrating threading, scoping, and cleanup.

```text
!var|base_particle|source(Asteroid) |+|
!source|base_particle |+| !hide |+|

!label|ParticleSpawner |+|
    !run{
        -- 1. Setup Clone
        !source|base_particle |+|
        !var|clone_id|@clone(true) |+|
        !source|clone_id |+|
        
        -- 2. Randomize Start Position
        !pos|x:(math.random(0, 1920 - width)), y:-200 |+|
        !show |+|
        
        -- 3. Dynamic Math Trajectories
        !var|fall_time|(math.random(2, 6)) |+|
        !var|spin|(math.random(-360, 360)) |+|
        
        -- 4. Animate and Clean up
        !move|y:1200, rot:spin|fall_time |+|
        !delete_source |+|
    }|+|
    
    !wait|0.5s |+|
    !jump|ParticleSpawner |+|

```

---

### Installation

1. Add `4IM3-SCRIPT.lua` to your OBS Scripts folder (`Tools -> Scripts`).
2. Select your text file or type your code into the provided Script UI.
3. Click **Execute** and watch your canvas come alive!
