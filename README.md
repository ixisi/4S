# 🚀 4IM3-SCRIPT Engine

**4IM3-SCRIPT** is a lightweight, high-performance scripting language designed for creating animations, logic flows, interactive widgets, and full video games. It uses a highly readable, pipe-delimited syntax designed for rapid sequencing and state management.

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

## 2. Variables, Arrays & State Management

In **4IM3-SCRIPT**, memory is highly flexible. You can store simple numbers, text strings, complex dictionaries, and dynamic arrays. The engine tracks your state globally, meaning a variable updated in one background thread is instantly readable by another.

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

### Math Shorthands
When you need to quickly modify an existing number (like adding score or taking damage), you can use shorthand operators directly in the value field.

* `++` (Add)
* `--` (Subtract)
* `**` (Multiply)

```text
!var | score | ++150 |+|      -- Adds 150 to the current score
!var | player.hp | --10 |+|   -- Subtracts 10 from the player's HP
```

---

### Working with Arrays (Lists)
Arrays are ordered lists of data, perfect for managing inventories, wave spawn queues, or history logs.

**1. Initialization**
To create a dictionary object, use empty curly-brackets `{}`.
```text
!var | active_users | {} |+|
```
To create an array, use empty brackets `[]`.
```text
!var | active_enemies | [] |+|
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

*Note: Inside the target label, the engine automatically provides two hidden variables: `(_index)` (the numeric position) and `(_key)` (the dictionary name, if applicable).*

---

### Asynchronous State Listeners (`!change`)
Instead of writing a loop that constantly checks if a player's HP has reached 0, you can tell the engine to "watch" a variable in the background. If the variable ever meets your condition, the engine instantly interrupts and triggers a label.

**Syntax:**
```text
!change | variable_to_watch | operator | value_to_check | target_label |+|
```

**Example:**
```text
-- The engine will monitor 'boss.hp'. The exact moment it hits 0, it triggers 'victory_sequence'
!change | boss.hp | <= | 0 | victory_sequence |+|
```

**Stopping a Listener (`!detach`)**
If a game phase ends and you no longer want to watch that variable, you can remove the listener using `!detach`.

```text
-- Stop listening to a specific variable:
!detach | change | boss.hp |+|

-- Stop a listener by the label it triggers:
!detach | change | victory_sequence |+|

-- Remove ALL variable watchers in the entire engine:
!detach | change |+|
```

## 3. Control Flow & Logic

To build a game or an interactive widget, your script needs to make real-time decisions and navigate between different blocks of code. **4IM3-SCRIPT** provides a streamlined set of control flow commands to jump around your file, call subroutines, and evaluate mathematical conditions.

### Labels (`!label`)
Labels are the anchors of your script. They do not execute any logic on their own; instead, they act as destinations for other commands to navigate to.
```text
!label | start_game |+|
```

### Navigation (`!jump` vs. `!call`)
There are two distinct ways to move to a label depending on whether you are branching your logic permanently or just running a quick subroutine.

* **`!jump` (One-Way Trip):** Instantly aborts the current execution path, moves the thread to the target label, and continues running downward from there.
    ```text
    !jump | start_game |+|
    ```
* **`!call` & `!return` (Round Trip):** Acts exactly like a function call in traditional programming. The engine remembers exactly where it came from, jumps to the label, runs the code, and the moment it hits a `!return` command, it snaps right back to the line immediately following the `!call`.
    ```text
    !call | update_ui |+|
    !log | The UI was successfully updated! |+|

    -skip-
    !label | update_ui |+|
        !source | ScoreUI |+| 
        !text | SCORE: (score) |+|
        !return |+|  -- Snaps back to the !log command above
    -end-
    ```

### Conditional Logic (`!if`)
The `!if` command is your engine's primary decision-maker. It evaluates two values (which can be hardcoded numbers, text, or resolved variables), and if the condition is true, it instantly acts as a `!jump` to a target label.

**Syntax:**
```text
!if | value_1 | operator | value_2 | target_label |+|
```

**Supported Operators:**

| Operator | Description | Example |
| :--- | :--- | :--- |
| `==` | Equal to | `!if \| game_active \| == \| 0 \| ignore \|+\|` |
| `!=` | Not equal to | `!if \| current_level \| != \| 1 \| ignore \|+\|` |
| `>` | Greater than | `!if \| score \| > \| high_score \| new_record \|+\|` |
| `<` | Less than | `!if \| timer \| < \| 10 \| play_warning_sound \|+\|` |
| `>=` | Greater than or equal to | `!if \| player_y \| >= \| 1080 \| kill_player \|+\|` |
| `<=` | Less than or equal to | `!if \| boss_hp \| <= \| 0 \| boss_defeated \|+\|` |

> **Pro Tip: The `ret` mode**
> If you want an `!if` statement to act as a `!call` (round trip) instead of a one-way `!jump`, you can add `ret` as an optional 5th argument!
> `!if | player_hp | < | 50 | play_heal_animation | ret |+|`


## 4. Asynchronous Threads (Process Management)

Because scripts execute sequentially from top to bottom, writing a continuous loop using standard navigation commands would block the rest of your code from running. **4IM3-SCRIPT** solves this by providing a robust asynchronous task system. You can spin up dozens of simultaneous background operations—like countdown timers, continuous animations, or data polling—while the main script continues to run freely.

To start a background thread, you use either the `!spawn` or `!run` command. While they look similar, they serve completely different architectural purposes.

### `!spawn` (Global & Disconnected Threads)
The `!spawn` command is used for **"Fire and Forget"** background logic. When you use `!spawn`, the engine registers the new thread to the background queue and immediately moves on. 

It does **not** lock onto the currently selected visual source. This makes `!spawn` the perfect tool for global managers, polling loops, countdown timers, or any abstract logic that dictates the overall state of your widget.

**Example (Global Timer):**
```text
!spawn | global_timer_loop |+|
```

### `!run` (Localized & Attached Threads)
The `!run` command is used for **Source-Specific** behaviors. When you use `!run`, the engine captures the *currently active `!source`* and locks that source into the thread's local scope. 

Furthermore, `!run` executes immediately within the current frame until it hits a `!wait` command, making it perfectly synced with visual updates. This makes `!run` the ideal tool for assigning animations, hover effects, or individual physics logic directly to a specific visual element on your screen.

**Example (Attached Animation):**
```text
!source | Alert_Icon |+|
!run | alert_bounce_animation |+|
```

### Targeting Labels vs. Inline Blocks `{ }`
Both `!spawn` and `!run` offer two different ways to define the code they execute: you can either pass the name of a **Label**, or you can write an **Inline Code Block** directly inside curly brackets `{ }`.

**Method A: Targeting a Label**
Best for long, complex logic loops that you might need to call from multiple places.
```text
!spawn | main_clock_logic |+|
!run | floating_animation_logic |+|
```

**Method B: Inline Code Blocks `{ }`**
Best for short, highly localized logic. The engine captures everything inside the brackets and runs it as an anonymous background thread.
```text
-- A global background task using an inline block
!spawn | {
    !label | poll_api |+|
    !fetch | "https://api.example.com/data" | my_data |+|
    !wait | 10s |+|
    !jump | poll_api |+|
} |+|

-- A source-attached animation using an inline block
!source | Notification_Card |+|
!run | {
    !label | slide_in |+|
    !move | y:--100 | 500ms | quad_out |+|
    !wait | 5s |+|
    !move | y:++100 | 500ms | quad_in |+|
    !return |+|
} |+|
```

### Time Delays (`!wait`)
The `!wait` command yields the specific thread it is called inside without freezing the rest of the engine or other active threads. 

It supports explicit time formats:
* `ms` (Milliseconds) - *Default if no unit is provided*
* `s` (Seconds)
* `mi` (Minutes)
* `hr` (Hours)

**Example:**
```text
!wait | 16ms |+|   -- Pauses this thread for ~1 frame
!wait | 2.5s |+|   -- Pauses this thread for 2.5 seconds
```

### Terminating Threads (`!stop`)
Because background loops are often designed to run indefinitely, you must have a way to terminate them when they are no longer needed. The `!stop` command is your internal process manager, allowing you to kill active threads using three distinct targeting methods.

**1. Stop by Label Name (Process Control):** When a thread is started using a label, it is automatically tagged with that label's name. You can stop it globally by referencing that name.
```text
!stop | main_clock_logic |+|
```

**2. Stop by Attached Component (Source Control):** Because `!run` threads are attached to specific visual sources, you can command the engine to kill any active threads associated with that specific visual element.
```text
!stop | Notification_Card |+|
```

**3. The Global Kill Switch:** To instantly terminate every background thread, loop, and async task currently running across the entire script (useful for hard resets or clearing the screen), use the `all` argument.
```text
!stop | all |+|
```

## 5. Component System (Sources, Templates, and Physics)

In **4IM3-SCRIPT**, visual elements are not just static images or text; they are dynamic components. The engine allows you to select these elements, duplicate them by the hundreds, and establish continuous physics rules so they can interact with one another. 

### Targeting Visual Elements (`!source`)
Before you can animate an element, hide it, or duplicate it, you must tell the engine which component you want to manipulate. The `!source` command sets the "Active Target" for the current thread.

Any visual command that follows will automatically apply to this target until you select a new one.

**Syntax:**
```text
!source | element_name |+|
```

**Example:**
```text
!source | Notification_Card |+|
!move | y:++150 | 500ms | quad_out |+|
!fade | 0 | 500ms |+|
```

### Templates and Dynamic Duplication (`!template` & `@clone`)
If you are building a complex widget—like a chat visualizer that drops a new 3D coin every time someone subscribes—you do not want to manually create 100 coin elements beforehand. Instead, you create one master element, tag it as a **Template**, and duplicate it dynamically.

**1. Tagging a Template**
The `!template` command assigns a universal ID to the currently targeted source. 
```text
!source | Master_Coin |+|
!template | coin_prefab |+|
```

**2. Spawning Clones (`@clone`)**
Once you have a master component, you can duplicate it infinitely using the inline `@clone()` macro. Passing `true` into the macro tells the engine to automatically clean up the clone if the script is ever reset.

```text
!source | Master_Coin |+|

-- Create the clone and save its unique memory pointer to a variable
!var | new_coin | @clone(true) |+|

-- Target the new clone and animate it
!source | new_coin |+|
!pos | x:500, y:-100 |+|
!show |+|
```

### Boundary Physics (`!collision`)
You can program elements to react when they physically touch each other on the screen. The `!collision` command sets up a continuous, invisible background monitor that checks the visual boundaries of two components. 

If those boundaries overlap, the engine instantly interrupts and spawns a thread at your specified label.

**Syntax:**
```text
!collision | target_1 | target_2 | target_label |+|
```

**The Power of Templates in Physics:**
You do not have to register a collision for every single duplicated coin. If you use a `template_id` in the `!collision` command, the engine will automatically monitor *every single clone* that shares that ID!

```text
-- If ANY cloned coin touches the 'Donation_Jar' element, run 'coin_collected'
!collision | coin_prefab | Donation_Jar | coin_collected |+|
```

**Identifying the Exact Clone:**
When a collision triggers, the engine needs a way to tell you *which* specific clone hit the target. It does this by automatically injecting two temporary variables into the target label's scope: `(_collider)` and `(_collided_with)`.

```text
-skip-
!label | coin_collected |+|
    -- Target the exact coin that triggered the collision and delete it
    !source | _collider |+| 
    !delete |+|
    
    !var | total_donations | ++1 |+|
    !return |+|
-end-
```

### Memory Cleanup (`!delete` & `!clones`)
When you generate components dynamically, you must destroy them when they are no longer needed to free up memory.

* **`!delete |+|`**: Instantly destroys the currently targeted `!source`. This completely wipes the element from the screen and the engine's memory.
* **`!clones | remove |+|`**: A global cleanup command. It instantly searches the entire engine and deletes every dynamic clone that has been generated, leaving only your original master templates intact.


## 6. Events & Listeners (Interactive Triggers & State Watchers)

To build truly interactive widgets or reactive UI elements, your script needs to respond to things happening in real-time. Instead of writing heavy, continuous loops that constantly check for updates, **4IM3-SCRIPT** uses an event-driven architecture. 

You register a listener once, and the engine handles the background monitoring, instantly triggering your logic only when the specific event occurs.

### Keyboard Inputs (`!onpress`)
The `!onpress` command integrates directly with OBS Studio's native Hotkey system. Instead of hardcoding a specific key (like "Spacebar" or "V"), this command registers a custom Hotkey Title into your OBS settings. 

When the user presses the key they bound to that title, the engine instantly spawns a background thread at your designated label. You can also specify a second label to trigger the moment the user releases the key.

**Syntax:**
```text
!onpress | hotkey_title | press_label | release_label (optional) |+|
```

**How to use it:**
1. Write the `!onpress` command in your script.
2. Run the script in OBS.
3. Open **OBS Settings -> Hotkeys**, search for your `hotkey_title`, and assign your preferred physical keyboard key to it!

**Example (A Push-to-Talk Indicator):**
```text
-- Creates an OBS Hotkey named "Toggle_Microphone_UI"
!onpress | Toggle_Microphone_UI | show_mic | hide_mic |+|

-skip-
!label | show_mic |+|
    !source | Mic_Icon |+| 
    !fade | 100 | 200ms | quad_out |+|
    !return |+|

!label | hide_mic |+|
    !source | Mic_Icon |+| 
    !fade | 0 | 200ms | quad_in |+|
    !return |+|
-end-
```
*Note: If you only want an action to happen on the initial press, you can leave the release label blank (e.g., `!onpress | Jump_Action | jump_logic | |+|`).*

### State Watchers (`!change`)
The `!change` command allows you to asynchronously monitor any variable in your script. The engine watches this data point in the background, and the exact moment your condition is met, it interrupts and executes the target label.

This is incredibly useful for progress bars, goal counters, or complex state machines.

**Method A: Trigger on a Specific Condition**
Use this when you want to trigger logic only when a variable crosses a specific threshold.
```text
-- Syntax: !change | variable | operator | value | target_label |+|

-- Trigger the celebration sequence exactly when the sub goal hits 100
!change | subscriber_count | >= | 100 | sub_goal_reached |+|
```

**Method B: Trigger on ANY Change**
If you omit the operator and value, the engine will trigger the target label *every single time* the variable updates, regardless of its new value.
```text
-- Syntax: !change | variable | target_label |+|

-- Update the visual text widget every time the score variable changes
!change | current_score | update_score_ui |+|
```

### Removing Listeners (`!detach`)
Leaving listeners active when they are no longer needed can lead to unintended behavior (e.g., a keyboard shortcut triggering an animation for a widget that is currently hidden). 

The `!detach` command allows you to selectively strip listeners from the engine's memory.

**Removing Keyboard Shortcuts (`onpress`)**
You can detach a hotkey by specifying the label it is attached to.
```text
-- Stop the hotkey from triggering the microphone labels
!detach | onpress | show_mic |+|
```

**Removing State Watchers (`change`)**
You can detach a watcher by referencing either the variable it is monitoring OR the label it triggers.
```text
-- Stop watching the score variable entirely:
!detach | change | current_score |+|

-- Stop the sub goal listener by referencing its target label:
!detach | change | sub_goal_reached |+|

-- The Nuclear Option: Remove ALL active watchers in the script:
!detach | change |+|
```


## 7. Animations & Visual Effects

In **4IM3-SCRIPT**, all visual commands and animations are applied to the currently active target set by the `!source` command. Once a source is targeted, you can instantly snap it to new properties, smoothly animate it over time, or apply continuous visual effects.

### Instant Property Setters
Sometimes you don't need a smooth transition; you just need an element to instantly appear in a new location or display new text. These commands execute immediately.

* **`!pos | x:VALUE, y:VALUE |+|`**: Instantly snaps the element to the specified X and Y coordinates.
* **`!scale | x:VALUE, y:VALUE |+|`**: Instantly updates the scale multiplier (e.g., `x:2.0` doubles the width).
* **`!rot | VALUE |+|`**: Instantly sets the rotation angle in degrees.
* **`!text | VALUE |+|`**: Instantly updates the content of a text element (supports variable injection).

**Example:**
```text
!source | PlayerScore_Text |+|
!pos | x:100, y:50 |+|
!text | SCORE: (current_score) |+|
```

### Interpolation (Smooth Animations)
To smoothly transition an element over time, use the interpolation commands. These commands require a duration (e.g., `1s`, `500ms`) and optionally accept an easing type (like `linear`, `quad_out`, `quad_inout`) to make the movement feel natural.

**1. The `!move` Command**
The most versatile animation tool. It allows you to animate position, scale, and rotation simultaneously.
```text
-- Syntax: !move | properties | duration | easing |+|
!source | Notification_Card |+|
!move | x:500, y:200, scale.x:1.5 | 1s | quad_inout |+|
```

**2. The `!fade` Command**
Smoothly transitions the opacity of the targeted element.
```text
-- Syntax: !fade | target_opacity | duration | easing |+|
!fade | 0 | 500ms | linear |+|
```

**3. The `!path` Command**
Moves an element along a curved trajectory by defining an intermediate control point (`p1`) and a final destination (`p2`).
```text
-- Syntax: !path | p1_properties | p2_properties | duration | easing |+|
!path | x:300, y:100 | x:600, y:500 | 2s | quad_out |+|
```

### Parenting & Anchoring (`!pin`)
If you want an element to permanently follow another element (like a health bar floating above an enemy), you can use the `!pin` command. The targeted source becomes the "child" and locks onto the "parent," automatically matching its movements.

```text
-- Syntax: !pin | parent_source | offset_properties |+|

!source | Enemy_HealthBar |+|
!pin | Enemy_Sprite | x:0, y:-50 |+|
```
*(To unpin an element, use `!pin | none |+|`)*

### Built-in Visual Effects
The engine includes several pre-programmed effects that you can trigger with a single line of code. These run independently for the specified duration.

* **`!foreground | R | G | B |+|`**: Washes the element with a specific color by targeting its color-add attributes. Perfect for damage flashes (e.g., `!foreground | 255 | 0 | 0 |+|` for pure red). Use `0|0|0` to reset it.
* **`!shake | intensity | duration |+|`**: Violently shakes the targeted element.
* **`!camera_shake | intensity | duration |+|`**: Shakes the entire scene.
* **`!glitch | intensity | duration |+|`**: Applies erratic position and scale stuttering.
* **`!rainbow | speed | duration |+|`**: Cycles an RGB color gradient across the element.
* **`!breathing | speed | duration |+|`**: Applies a gentle, continuous scale-pulsing effect.
* **`!dvd | speed | duration |+|`**: Applies native physics to bounce the element infinitely within the screen boundaries.
* **`!sway | speed | duration |+|`**: Applies a gentle pendulum rotation.
* **`!spiral | center_coords | radius | rotations | duration |+|`**: Spirals the element mathematically around a center point (e.g., `!spiral | x:960, y:540 | 500 | 2 | 2s |+|`).


## 8. Utility & Built-in Macros (`@`)

While standard commands control the flow and visual state of your script, **4IM3-SCRIPT** also provides a suite of Utility Commands and Inline Macros to help you debug, manage media, and crunch numbers dynamically.

### Utility Commands (`!`)
These commands provide specialized functions outside of standard logic and animation.

**1. Debugging (`!log`)**
When building complex logic, you often need to see what value a variable currently holds. The `!log` command prints messages directly to the script's internal log window. It fully supports variable injection.
```text
-- Syntax: !log | message |+|
!log | The player's current health is: (player_hp) |+|
```

**2. Media Control (`!media`)**
Control video or animated media elements natively. 
* **Actions:** `play`, `pause`, `restart`, `stop`, `seek` (seek requires a time value like `5s`).
```text
-- Syntax: !media | target_name | action | value (optional) |+|
!media | Intro_Video | restart |+|
!media | Background_Loop | seek | 10s |+|
```

**3. Audio Control (`!sound`)**
Control audio elements and smoothly fade their volume over time.
* **Actions:** `play`, `pause`, `stop`, `volume`
```text
-- Syntax: !sound | target_name | action | value | duration |+|

-- Smoothly fade the music volume to 50% over 2 seconds:
!sound | Background_Music | volume | 0.5 | 2s |+|
```

**4. Data Fetching (`!fetch`)**
Make asynchronous HTTP requests to retrieve external data (like a web API) without freezing the script. The engine automatically parses JSON responses and saves them to your specified variable.
```text
-- Syntax: !fetch | URL | save_variable |+|

!fetch | "https://api.example.com/stats" | my_api_data |+|
!wait | 2s |+|
!log | The fetched score is: (my_api_data.score) |+|
```

---

### Inline Macros (`@`)
Unlike standard commands (which start with `!`), Macros start with an `@` symbol and are used *inside* your commands or math equations. Macros are evaluated instantly, and their resulting value is injected directly into your command before it runs.

**1. The Clone Macro (`@clone`)**
Used to dynamically duplicate the currently active component. It returns a unique memory pointer that you can save to a variable.
* **Argument:** `true` (auto-delete on script reset) or `false` (persist permanently).
```text
!source | Enemy_Template |+|
!var | new_enemy | @clone(true) |+|
!source | new_enemy |+|
!show |+|
```

**2. Advanced Math (`@math`)**
The engine exposes a full suite of mathematical functions. You can use these to generate randomness, clamp values, or calculate complex geometry.
* **`@math.random(min, max)`**: Generates a random integer.
* **`@math.max(a, b)` / `@math.min(a, b)`**: Returns the highest or lowest of two values (perfect for clamping health bars).
* **`@math.floor(val)` / `@math.ceil(val)`**: Rounds numbers down or up.
* **`@math.sin(val)` / `@math.cos(val)`**: Trigonometry functions for circular movement.

```text
-- Spawn an enemy at a random X coordinate between 100 and 1800:
!var | random_x | (@math.random(100, 1800)) |+|
!pos | x:(random_x), y:-50 |+|

-- Clamp the player's health so it never exceeds 100:
!var | player_hp | (@math.min(100, player_hp + 20)) |+|
```

**3. Spatial & Physics Macros**
* **`@dist(x1, y1, x2, y2)`**: Instantly calculates the distance in pixels between two coordinates.
* **`@mouse()`**: Captures the user's live desktop cursor position. Returns a dictionary with `.x` and `.y` values.
* **`@mass(component_name, density)`**: Calculates the simulated mass of an element based on its physical width and height.

```text
-- Make an element follow the mouse cursor:
!label | mouse_tracker |+|
    !var | mx | (@mouse().x) |+|
    !var | my | (@mouse().y) |+|
    !pos | x:(mx), y:(my) |+|
    !wait | 16ms |+|
    !jump | mouse_tracker |+|
```

