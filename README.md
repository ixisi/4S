# 🚀 4IM3-SCRIPT Engine

**4IM3-SCRIPT** is a lightweight, high-performance scripting language designed for creating animations, logic flows, interactive widgets, and complex runtime simulations. It uses a highly readable, pipe-delimited syntax designed for rapid sequencing and state management.

---

## 1. Core Syntax & Rules

Writing in 4IM3-SCRIPT follows a strict, predictable format. Every instruction you write is a **Command Line**, and the engine reads them sequentially from top to bottom.

### The Command Structure
Every command begins with an exclamation mark (`!`), separates its arguments with a pipe (`|`), and **must** be terminated by the execution trigger (`|+|`). 

**Syntax:**
```text
!command | argument_1 | argument_2 |+|
```

**Example:**
```text
!move | x:500, y:200 | 1s |+|
```
*Note: Spaces around the pipes are completely optional and ignored by the engine, allowing you to format your code for readability.*

### Variable Resolution & Math `(...)`
To read the value of a variable or perform mathematical operations, wrap the expression in parentheses `()`. The engine will evaluate everything inside the parentheses before executing the command.

```text
-- Reading a variable:
!text | Score: (current_score) |+|

-- Performing inline math:
!var | health | (health - 15) |+|
```

### Path Resolution (Dot Notation)
You can easily access nested properties or the real-time attributes of visual sources using dot notation. You can even combine this with the math evaluator.

```text
-- Accessing a dictionary value:
!var | current_state | (player_stats.hp) |+|

-- Accessing a visual source's position:
!var | drop_x | (Enemy1.pos().x) |+|
```

### Math Shorthand Modifiers
For quick variable updates, the engine supports prefix shorthand modifiers directly inside the argument.
* `++` (Add)
* `--` (Subtract)
* `**` (Multiply)

```text
-- These two commands do the exact same thing:
!var | score | (score + 10) |+|
!var | score | ++10 |+|
```

### Comments & Block Skips
To write comments, document your code, or hide entire sections of logic from the main execution loop, wrap them in `-skip-` and `-end-` tags. The engine will completely ignore anything between these tags unless another part of the script explicitly jumps inside.

```text
-skip-
    Any text here is ignored. You can use this for documentation!
    
    !label|hidden_logic |+|
        !log|This command only runs if a thread jumps directly to 'hidden_logic' |+|
        !return |+|
-end-
```

---

## 2. Variables, Arrays & State Management

Memory is highly flexible. You can store simple numbers, text strings, complex dictionaries, and dynamic arrays. The engine tracks your state globally, meaning a variable updated in one background thread is instantly readable by another.

### Defining & Updating Variables (`!var`)
The `!var` command is your primary tool for managing state. If a variable doesn't exist, this command creates it. If it does exist, it overwrites it.

**Syntax:**
```text
!var | variable_name | value |+|
```

**Examples:**
```text
!var | player_name | "Hero" |+|
!var | max_health | 100 |+|

-- Copying one variable to another using the math evaluator:
!var | current_health | (max_health) |+| 
```

### Dictionaries & Dot Notation
You can organize related variables into dictionaries (objects) by using dot notation in the variable name.

```text
-- Creates a "player" dictionary with nested attributes:
!var | player.hp | 100 |+|
!var | player.speed | 15 |+|

-- You can also use dynamic variables as keys inside parentheses:
!var | grid_x | 4 |+|
!var | grid_y | 5 |+|
!var | map.cell_(grid_x)_(grid_y) | "WALL" |+|
```

### Working with Arrays (Lists)
Arrays are ordered lists of data, perfect for managing inventories, wave spawn queues, or history logs.

**1. Initialization**
To create an array, use empty brackets `[]`.
```
!var | active_enemies | [] |+|
-- or dictoniary object
!var | object_data | {} |+|
```

**2. Array Commands**
The engine provides dedicated commands for manipulating array contents safely:
* **`!array.push`**: Adds a value to the very end of the array.
  `!array.push | active_enemies | "Goblin_1" |+|`
* **`!array.pop`**: Removes the *last* item from the array. You can optionally provide a variable name to save the removed item.
  `!array.pop | active_enemies | last_enemy_removed |+|`
* **`!array.remove`**: Searches the entire array for a specific value and removes it.
  `!array.remove | active_enemies | "Goblin_1" |+|`
* **`!array.clear`**: Instantly wipes the array clean, leaving it empty.
  `!array.clear | active_enemies |+|`

**3. Iterating (`!foreach`)**
To process every item in an array or dictionary, use the `!foreach` command. This will spawn a new, simultaneous background thread at the specified label for *every single item*.

**Syntax:**
```text
!foreach | array_name | iterator_variable_name | target_label |+|
```
*(Note: Inside the target label, the engine automatically provides two hidden variables: `(_index)` for the numeric position and `(_key)` for the dictionary name, if applicable).*

---

## 3. Control Flow & Logic

Your script needs to make real-time decisions and navigate between different blocks of code. **4IM3-SCRIPT** provides a streamlined set of control flow commands to jump around your file, call subroutines, and evaluate mathematical conditions.

### Labels (`!label`)
Labels are the anchors of your script. They do not execute any logic on their own; instead, they act as destinations for other commands to navigate to.
```text
!label | start_sequence |+|
```

### Navigation (`!jump` vs. `!call`)
There are two distinct ways to move to a label depending on whether you are branching your logic permanently or running a subroutine.

* **`!jump` (One-Way Trip):** Instantly aborts the current execution path, moves the thread to the target label, and continues running downward from there.
    ```text
    !jump | start_sequence |+|
    ```

* **`!call` & `!return` (Round Trip):** Acts exactly like a function call. The engine remembers exactly where it came from, jumps to the label, runs the code, and snaps right back to the line immediately following the call when it hits `!return`.
    **Passing Arguments:** You can pass an optional comma-separated map of arguments to the subroutine. These values are temporarily injected into the script's memory scope while the subroutine runs.
    ```text
    -- Call the label and pass down 'amount' and 'critical' values
    !call | take_damage | amount:15, critical:true |+|

    -skip-
    !label | take_damage |+|
        -- The injected arguments are now accessible as variables!
        !var | player_hp | (player_hp - amount) |+|
        !if | critical | == | true | play_heavy_hit_sound |+|
        !return |+|
    -end-
    ```

### Conditional Logic (`!if`)
The `!if` command is your engine's primary decision-maker. It evaluates two values (which can be hardcoded numbers, text, or resolved variables), and if the condition is true, it instantly acts as a `!jump` to a target label.

**Syntax:**
```text
!if | value_1 | operator | value_2 | target_label |+|
```
**Supported Operators:** `==`, `!=`, `>`, `<`, `>=`, `<=`.
*(Pro Tip: If you want an `!if` statement to act as a `!call` (round trip) instead of a one-way `!jump`, add `ret` as an optional 5th argument: `!if | hp | < | 50 | heal_logic | ret |+|`)*

### Fixed Iteration (`!loop`)
Sometimes you need to repeat a specific action an exact number of times without writing complex counter variables and manual `!if` checks. The `!loop` command automatically repeats a target label or an inline code block for the specified number of iterations. 

The engine automatically injects a hidden variable called `(_index)` into the loop's scope so you know which iteration is currently running. All spawned loop threads run perfectly in parallel.

**Syntax:**
```text
!loop | count | target_label |+|
!loop | count | { ... inline code block ... } |+|
```

**Example:**
```text
-- Spawns 5 random coins instantly using an inline block
!source | Master_Coin |+|
!loop | 5 | {
    !var | new_coin | @clone(true) |+|
    !source | new_coin |+|
    !pos | x:(@math.random(100, 1800)), y:-50 |+|
} |+|
```

---

## 4. Asynchronous Threads (Process Management)

Because scripts execute sequentially from top to bottom, writing a continuous loop using standard navigation commands would block the rest of your code from running. The engine solves this by providing a robust asynchronous task system. You can spin up dozens of simultaneous background operations while the main script continues to run freely.

### `!spawn` (Global Threads)
The `!spawn` command is used for **"Fire and Forget"** background logic. It registers a new thread to the background queue and immediately moves on. It does **not** lock onto the currently selected visual source. This makes it perfect for global managers, polling loops, or countdown timers.

```text
!spawn | global_timer_loop |+|
```

### `!run` (Localized Threads)
The `!run` command is used for **Source-Specific** behaviors. It captures the *currently active `!source`* and locks that source into the thread's local scope. It executes immediately within the current frame until it hits a `!wait` command, making it perfectly synced with visual updates.

```text
!source | Alert_Icon |+|
!run | alert_bounce_animation |+|
```

### Inline Code Blocks `{ }`
Both `!spawn` and `!run` offer two different ways to define the code they execute: you can either pass the name of a **Label** (as shown above), or you can write an **Inline Code Block** directly inside curly brackets `{ }`.

```text
-- A global background task using an inline block
!spawn | {
    !label | api_poll |+|
    !fetch | "[https://api.example.com/data](https://api.example.com/data)" | my_data |+|
    !wait | 10s |+|
    !jump | api_poll |+|
} |+|
```

### Time Delays (`!wait`)
The `!wait` command yields the specific thread it is called inside without freezing the rest of the engine or other active threads. It supports formats like `ms` (default), `s`, `mi`, and `hr`.

```text
!wait | 16ms |+|   -- Pauses this thread for ~1 frame
!wait | 2.5s |+|   -- Pauses this thread for 2.5 seconds
```

### Terminating Threads (`!stop`)
The `!stop` command is your internal process manager, allowing you to kill active threads using three distinct targeting methods.
1. **Stop by Label Name:** Target the globally tagged label name. (`!stop | timer_loop |+|`)
2. **Stop by Attached Component:** Target the specific visual source locked to a `!run` thread. (`!stop | Alert_Icon |+|`)
3. **The Global Kill Switch:** Instantly terminate every background thread currently running. (`!stop | all |+|`)

---

## 5. Component System (Sources, Templates, and Physics)

Visual elements are dynamic components. The engine allows you to select these elements, duplicate them, manage their lifecycles, and establish continuous physics rules.

### Targeting Visual Elements (`!source`)
The `!source` command sets the "Active Target" for the current thread. Any visual command that follows will automatically apply to this target until you select a new one.

```text
!source | Notification_Card |+|
!move | y:++150 | 500ms | quad_out |+|
```

### Templates and Dynamic Duplication (`!template` & `@clone`)
Instead of manually creating hundreds of elements, you can tag one master element as a **Template** and duplicate it dynamically.

**1. Tagging a Template**
```text
!source | Master_Coin |+|
!template | coin_prefab |+|
```

**2. Spawning Clones (`@clone`)**
Duplicate the master component infinitely using the inline `@clone()` macro. Passing `true` auto-deletes the clone if the script is reset.
```text
!var | new_coin | @clone(true) |+|
!source | new_coin |+|
!pos | x:500, y:-100 |+|
```

### Component Relations: Positional vs. Behavioral
You can link components together in two distinctly different ways. It is critical to understand the difference between pinning physical positions and attaching logical behaviors.

* **`!pin` (Positional Tracking):** Pins the currently targeted source to a parent source. The pinned source will automatically map to the parent's X/Y coordinates on the screen.
    ```text
    -- Syntax: !pin | parent_source | offsets (x:0, y:0) |+|
    !source | Floating_HealthBar |+|
    !pin | Character_Sprite | x:0, y:-50 |+|
    ```

* **`!attach` (Behavioral Tracking):** Attaches a specific logic thread (label) directly to a target source's lifecycle. If the source is ever deleted or destroyed, the attached logic loop is automatically terminated with it. 
    ```text
    -- Syntax: !attach | target_source | label_name |+|
    !source | Enemy_Sprite |+|
    !attach | Enemy_Sprite | enemy_ai_loop |+|
    ```

### Boundary Physics (`!collision`)
The `!collision` command sets up a continuous background monitor that checks the visual boundaries of two components. If those boundaries overlap, the engine instantly spawns a thread at your specified label.

```text
-- Syntax: !collision | target_1 | target_2 | target_label |+|
!collision | coin_prefab | player_prefab | coin_collected |+|
```
*(Note: Inside the target label, the engine injects `(_collider)` and `(_collided_with)` so you can precisely identify which specific clones collided).*

### Memory & Lifecycle Cleanup
* **`!despawn | duration |+|`**: Attaches a timer to the active source. Once the timer runs out, the component is automatically deleted from memory. (`!despawn | 5s |+|`)
* **`!delete |+|`**: Instantly destroys the currently targeted `!source`.
* **`!clones | remove |+|`**: A global cleanup command that instantly searches the engine and deletes every dynamic clone generated.

---

## 6. Events & Listeners (Interactive Triggers & State Watchers)

The engine uses an event-driven architecture. You register a listener once, and the engine handles the background monitoring, triggering your logic only when the specific event occurs.

### System Hotkeys (`!onpress`)
The `!onpress` command registers a bindable hotkey title into the host system. When the user maps and presses this key, the engine instantly spawns a background thread at your designated label. You can also specify an optional release label.

**Syntax:**
```text
!onpress | hotkey_title | press_label | release_label (optional) |+|
```
**Example:**
```text
!onpress | Trigger_Action | action_start | action_end |+|
```

### State Watchers (`!change`)
The `!change` command allows you to asynchronously monitor any variable in your script. The exact moment your condition is met, it interrupts and executes the target label.

**Method A: Trigger on a Specific Condition**
```text
-- Trigger the sequence exactly when the counter hits 100
!change | item_counter | >= | 100 | goal_reached |+|
```

**Method B: Trigger on ANY Change**
```text
-- Update the UI every single time the variable changes value
!change | current_score | update_ui_label |+|
```

### Removing Listeners & Behaviors (`!detach`)
Leaving background listeners, physics calculations, or lifecycles active when they are no longer needed can cause massive memory leaks or unintended behaviors. 

The `!detach` command is your universal cleanup tool. It allows you to selectively strip specific behaviors from the engine or from a targeted visual source.

**1. Detaching Global Listeners (No active `!source` required):**
* **`onpress`:** Detaches a keyboard shortcut by referencing its target label.
  `!detach | onpress | action_start |+|`
* **`change`:** Detaches a state watcher by the variable it watches, the label it triggers, or all watchers entirely.
  `!detach | change | item_counter |+|` *(By Variable)*
  `!detach | change | goal_reached |+|` *(By Label)*
  `!detach | change |+|` *(Removes ALL active change watchers)*

**2. Detaching Component Behaviors (Requires an active `!source`):**
First, select your target using `!source`, then call `!detach` to strip behaviors off of it.
* **`pin`:** Unlinks the source from its positional parent so it stops following it.
  `!source | Floating_HealthBar |+| !detach | pin |+|`
* **`attach` (or `spawn` / `loop`):** Severs any behavioral logic loops currently bound to the source's lifecycle.
  `!source | Enemy_Sprite |+| !detach | attach |+|`
* **`collision`:** Removes the source from the boundary physics monitor so it no longer triggers collision events.
  `!source | Phantom_Ghost |+| !detach | collision |+|`
* **`emitter`:** Immediately stops a continuous particle system before its duration naturally finishes.
  `!source | Exhaust_Pipe |+| !detach | emitter |+|`
* **`despawn`:** Cancels a scheduled death timer, saving the object from being automatically deleted.
  `!source | PowerUp |+| !detach | despawn |+|`

---

## 7. Animations & Visual Effects

All visual commands apply to the currently active target set by the `!source` command. 

### Instant Property Setters
These commands execute immediately without transition.
* **`!pos | x:VALUE, y:VALUE |+|`**: Instantly snaps to X/Y coordinates.
* **`!scale | x:VALUE, y:VALUE |+|`**: Instantly updates the scale multiplier.
* **`!rot | VALUE |+|`**: Instantly sets the rotation angle in degrees.
* **`!text | VALUE |+|`**: Instantly updates the content of a text element.

### Interpolation (Smooth Animations)
These commands require a duration (e.g., `1s`, `500ms`) and optionally accept an easing type (like `linear`, `quad_out`, `quad_inout`).

* **`!move | properties | duration | easing |+|`**: Animates position, scale, and rotation simultaneously. (`!move | x:500, scale.x:1.5 | 1s | quad_inout |+|`)
* **`!fade | target_opacity | duration | easing |+|`**: Smoothly transitions opacity. (`!fade | 0 | 500ms | linear |+|`)
* **`!path | p1_properties | p2_properties | duration | easing |+|`**: Moves an element along a curved quadratic Bezier trajectory.

### Built-in Visual Effects
These run independently for the specified duration.
* **`!foreground | R | G | B |+|`**: Washes the element with a specific RGB color.
* **`!shake | intensity | duration |+|`**: Violently shakes the targeted element.
* **`!camera_shake | intensity | duration |+|`**: Shakes the entire scene.
* **`!glitch | intensity | duration |+|`**: Applies erratic position and scale stuttering.
* **`!rainbow | speed | duration |+|`**: Cycles an RGB color gradient across the element.
* **`!breathing | speed | duration |+|`**: Applies a gentle, continuous scale-pulsing effect.
* **`!dvd | speed | duration |+|`**: Applies native physics to bounce the element infinitely within boundaries.
* **`!sway | speed | duration |+|`**: Applies a gentle pendulum rotation.
* **`!spiral | center_coords | radius | rotations | duration |+|`**: Spirals the element mathematically around a center point.

### Particle Systems (`!emitter`)
The `!emitter` command turns the currently active source into a continuous particle spawner, spraying out clones of a target template.
```text
-- Syntax: !emitter | template_id | max_count | interval_ms | callback_label |+|
!source | Exhaust_Pipe |+|
!emitter | smoke_prefab | 50 | 50ms | move_smoke_up |+|
```

### Scene Control (`!transition` & `!switch`)
Your script can act as an automated visual director, managing the active visual state and controlling transitions.
* **`!transition | transition_name | duration |+|`**: Sets the active visual transition type and speed (e.g., Fade, Swipe).
* **`!switch | scene_name |+|`**: Instantly changes the live visual output to the specified scene configuration.

---

## 8. Utility & Built-in Macros (`@`)

### Utility Commands (`!`)
* **`!log | message |+|`**: Prints messages directly to the script's internal log window. Fully supports variable injection.
* **`!media | target_name | action | value |+|`**: Controls video or animated media natively. Actions include `play`, `pause`, `restart`, `stop`, `seek`.
* **`!sound | target_name | action | value | duration |+|`**: Controls audio elements and volume fading. Actions include `play`, `pause`, `stop`, `volume`.
* **`!fetch | URL | save_variable |+|`**: Makes an asynchronous HTTP request, parses the JSON/text response, and saves it to a variable without freezing the script.

### Inline Macros (`@`)
Macros are evaluated instantly inside your commands or math equations.
* **`@clone(true/false)`**: Dynamically duplicates the active component and returns a unique memory pointer.
* **`@math.random(min, max)`**: Generates a random integer.
* **`@math.max(a, b)` / `@math.min(a, b)`**: Returns the highest or lowest of two values.
* **`@math.floor(val)` / `@math.ceil(val)`**: Rounds numbers down or up.
* **`@math.sin(val)` / `@math.cos(val)`**: Trigonometry functions for circular math.
* **`@dist(x1, y1, x2, y2)`**: Calculates the pixel distance between two coordinates.
* **`@mouse()`**: Captures the live global cursor coordinates (returns a dictionary with `.x` and `.y`).
* **`@mass(component_name, density)`**: Calculates the simulated mass of an element based on its dimensions.

---

## 9. Advanced Engine Features (Pre-Processor & Execution Guards)

### The Pre-Processor (`!include`)
The `!include` command is evaluated *before* your script runs. It takes the contents of an external text file and injects it directly into your main script, allowing for modular, multi-file architectures.
```text
-- Syntax: !include | path/to/your/file.txt |+|
!include | scripts/ui_logic.txt |+|
```

### Material Guards (`<<material>>`)
By prefixing a command with a **Material Guard** (like `<<solid>>`), you register that visual source into the engine's native Rigid Body Collision Solver. If two `<<solid>>` objects intersect, the engine physically pushes them apart so they cannot pass through one another.
```text
<<solid>> !source | Wall |+|
```

### Interrupt Guards (`[[ ... ]]`)
An **Interrupt Guard** allows you to attach a specific variable watcher to a single, long-running command (like a long `!wait` or `!move`). If the watched variable triggers, the engine instantly aborts that specific command and jumps to your specified label.
```text
-- Syntax: [[variable_to_watch]][target_label] !command | args |+|

-- Wait 5 seconds, but abort and jump to 'interrupted' if 'stun_active' triggers
[[stun_active]][interrupted] !wait | 5s |+|
```
