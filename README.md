# 4IM3 Scripting Engine for OBS Studio (v2.0.0)

This engine allows you to write multithreaded, interactive scripts directly inside OBS Studio. This document covers the exact syntax, commands, and variables you need to animate sources, build logic, and control OBS.

## 1. Syntax Rules

Every line of code you write must follow these strict formatting rules:

* **Start and End:** Every command starts with `!` and **must** end with `|+|`.
* **Arguments:** Separated by the pipe symbol `|`.
* **Dynamic Math:** You can wrap arguments in `( )` to evaluate live math or read variables (e.g., `!move|x:(screen.width / 2)|1s|+|\`).
* **Time Formats:** Durations accept `ms` (milliseconds), `s` (seconds), `mi` (minutes), and `hr` (hours).
* **Relative Values:** Use `++` or `--` to add or subtract from a current value (e.g., `!move|x:++50|1s|+|\`).

### The Interrupt Guard `[[ ]]`

You can instantly cancel any time-consuming command (like `!wait` or `!move`) if a variable changes.

* **Format:** `[[Variables_to_Watch]][Optional_Jump_Label] !command |+|`
* **Example:** `[[isHit]][Flinch] !move|x:500|5s |+|`
*(This moves the source over 5 seconds. If the variable `isHit` changes at any point during those 5 seconds, the movement cancels instantly and the script jumps to the `Flinch` label).*

---

## 2. Core Commands

### Flow Control & Logic

* **`!label | Name |+|`** - Creates a marker in your script to jump to.
* **`!jump | Name |+|`** - Instantly moves execution to a label.
* **`!wait | duration |+|`** - Pauses the script (e.g., `!wait|1.5s |+|`).
* **`!call | Name | Optional_Args |+|`** - Jumps to a label, runs it, and then returns to where it left off.
* You can pass temporary local variables: `!call|MyLabel|x:10, y:20 |+|`.
* **`!return |+|`** - Returns from a `!call`. If used outside a call, it ends the current thread.
* **`!if | val1 | operator | val2 | Label | Mode |+|`** - Compares two values (`==`, `!=`, `>`, `<`, `>=`, `<=`).
* If true, it jumps to the Label. If you set `Mode` to `ret`, it performs a `!call` instead of a `!jump`.
* **`!loop |+|`** - Completely resets the script and restarts from the very top.
* **`!then | cmd | args |+|`** - Executes a single command inline.

### Variables & Memory

* **`!var | name | value |+|`** - Sets a local variable.
* **`!gvar | name | value |+|`** - Sets a global variable.
* **`!array.push | array_name | value |+|`** - Adds an item to a list.
* **`!array.pop | array_name | save_var |+|`** - Removes the last item and saves it to a variable.
* **`!array.remove | array_name | value |+|`** - Finds and removes a specific value.
* **`!array.clear | array_name |+|`** - Empties the list.

### Background Threads & Scope

* **`!source | Target1 | Target2... |+|`** - Selects one or multiple OBS sources to manipulate. Leave blank (`!source |+|`) to reset.
* **`!run { code } |+|`** or **`!run | Label |+|`** - Spawns a background thread that runs simultaneously.
* **`!foreach | array_name | item_var | Label |+|`** - Loops through an array, spawning a parallel thread for each item.
* **`!stop | TargetName |+|`** - Kills all background threads attached to a specific source. Use `!stop|all` to kill everything.

### Triggers & Events

* **`!onpress | HotkeyName | PressLabel | ReleaseLabel |+|`** - Triggers a label when a keyboard key is pressed, and another when released.
* **`!change | VarName | Operator | Value | Label |+|`** - Triggers a label automatically when a variable hits a specific value. Omit the operator and value to trigger on *any* change.
* **`!collision | Source1 | Source2 | Label |+|`** - Triggers a label automatically when two sources touch on screen.
* **`!attach | SourceName | Label |+|`** - Instantly launches a thread for a specific source.

---

## 3. Animation & Transformations

* **`!easing | EasingName |+|`** - Sets the default smoothing curve (e.g., `linear`, `quad_out`, `bounce_out`).
* **`!move | properties | duration | easing |+|`** - Moves, scales, or rotates a source.
* *Format:* `x:val, y:val, rot:val, scale.x:val, scale.y:val`.
* *Example:* `!move|x:500, scale.x:2|1s|quad_out |+|`.


* **`!path | control_x,control_y | target_x,target_y | duration | easing |+|`** - Moves a source along a curved trajectory. Argument 1 sets the curve pull (control point), Argument 2 sets the final destination.
* **`!spiral | center_x,center_y | start_radius | rotations | duration | easing |+|`** - Spirals a source inward.
* **`!fade | target_opacity | duration | easing |+|`** - Adjusts visibility (0.0 to 1.0).
* **`!pin | ParentSource | offset_x,offset_y |+|`** - Locks the current source to a parent source's location. Use `!pin|none` to detach.
* **`!delete |+|`** - Deletes the current source from the OBS scene.

---

## 4. OBS Integration

* **`!filter | SourceName | FilterName | PropertyName | TargetValue | Duration |+|`** - Smoothly animates an OBS filter setting (like Blur Size or Color). Omit duration to snap instantly.
* **`!media | SourceName | Action | Value |+|`** - Controls video playback.
* *Actions:* `play`, `pause`, `stop`, `restart`, `seek`.
* *Example:* `!media|MyVideo|seek|10s |+|`.


* **`!media_time | SourceName | SaveVariable |+|`** - Saves the video's current playback time to a variable.
* **`!sound | SourceName | Action | TargetValue | Duration |+|`** - Audio control.
* *Actions:* `play`, `pause`, `stop`, `volume`.
* *Example (Fade audio):* `!sound|BGM|volume|0.5|2s |+|`.


* **`!switch | SceneName |+|`** - Instantly cuts to a new OBS scene.
* **`!transition | SceneName | TransitionType | Duration |+|`** - Changes scenes using an OBS transition (e.g., `Fade`).
* **`!log | Message |+|`** - Prints text to the OBS Script Log.

---

## 5. Visual Effects (VFX)

Quick, pre-built animations.

* **`!shake | intensity | duration |+|`** - Jitters the source.
* **`!camera_shake | intensity | duration |+|`** - Jitters the entire scene.
* **`!glitch | intensity | duration |+|`** - Digital tearing effect.
* **`!rainbow | speed | duration |+|`** - Color cycles (requires an attached Color Filter).
* **`!breathing | speed | duration |+|`** - Gently pulses scale and opacity.
* **`!sway | speed | duration |+|`** - Rocks back and forth (rotation).
* **`!dvd | speed | duration |+|`** - Bounces the source around the screen boundaries.

---

## 6. Predefined Variables & Functions

You can use these directly inside math brackets `( )` anywhere in your script.

### Live Variables

* **`screen.width`**: Width of the OBS canvas.
* **`screen.height`**: Height of the OBS canvas.
* **`tick`**: The time passed since the last frame (useful for custom physics).
* **`pi` / `huge**`: Math constants ($\pi$ and $\infty$).

### @ Functions

* **`@mouse()`**: Returns the cursor position `{x, y}`.
* **`@dist(x1, y1, x2, y2)`**: Calculates distance between points.
* **`@source(Name)` / `!var|my_source|source(name)`**: Gets a source reference.
* **`@clone(auto_delete_bool)`**: Duplicates the targeted source.
* **`@delete()**`: Deletes a source.
* **`@alert(msg)`**: Logs a warning.
* **Standard Math**: `@sin()`, `@cos()`, `@abs()`, `@floor()`, `@ceil()` are all supported natively.
---
## Examples

### 1. The "Ping-Pong" Patrol Loop

This creates a simple, infinite back-and-forth movement loop. 
Perfect for floating enemies, clouds, or moving background elements.

```text
!source|EnemyShip |+|

!label|StartPatrol |+|
    -- Move right by 300 pixels smoothly over 2 seconds
    !move|x:++300|2s|sine_inout |+|
    !wait|2s |+|
    
    -- Move left by 300 pixels
    !move|x:--300|2s|sine_inout |+|
    !wait|2s |+|
    
    -- Loop forever
    !jump|StartPatrol |+|

```

### 2. The Dynamic Health Bar

This snippet shows how to use math inside arguments `( )` to smoothly shrink a UI element based on a variable.

```text
!source|HealthBarFill |+|
!gvar|player_health|100 |+|

-- Call this label whenever the player takes damage
!label|TakeDamage |+|
    -- Subtract 10 from the current health
    !gvar|player_health|--10 |+|
    
    -- Dynamically calculate the scale (e.g., 80 health = 0.8 scale)
    !move|scale.x:(player_health / 100)|300ms|quad_out |+|
    
    -- Briefly flash the health bar red using a color filter
    !filter|HealthBarFill|ColorCorrection|color|0xff0000|100ms |+|
    !filter|HealthBarFill|ColorCorrection|color|0xffffff|200ms |+|
    
    !return |+|

```

### 3. The "Fire & Forget" VFX Thread

Want a magical crystal to pulse and hover in the background while your main script does other things? 
Use `!run` to spin up a parallel thread and drop a VFX macro inside.

```text
!source|MagicCrystal |+|

-- Spawns a background thread that runs independently
!run{
    -- The breathing macro scales and pulses opacity automatically
    -- The '0' duration means it loops infinitely
    !breathing|0.05|0 |+|
}|+|

-- The main script immediately continues down here!
!log|Crystal animation started! |+|

```

### 4. The "Reactive" Enemy (Interrupt Guards)

The enemy will patrol normally, but if the `isHit` variable changes, it will instantly cancel its movement and play a flinch animation.

```text
!source|BossMonster |+|
!gvar|isHit|0 |+|

!label|Patrol |+|
    -- Move for 5 seconds. If 'isHit' changes, abort instantly and jump to [Flinch]!
    [[isHit]][Flinch] !move|x:++500|5s|linear |+|
    [[isHit]][Flinch] !wait|5s |+|
    
    [[isHit]][Flinch] !move|x:--500|5s|linear |+|
    [[isHit]][Flinch] !wait|5s |+|
    
    !jump|Patrol |+|

!label|Flinch |+|
    !shake|20|300ms |+|
    !gvar|isHit|0 |+|  -- Reset the hit state
    !jump|Patrol |+|   -- Go back to patrolling

```

### 5. Follow the Mouse

A tiny script that mathematically glues a source to your live cursor coordinates using the `@mouse()` function.

```text
!source|CustomCursor |+|

!label|FollowLoop |+|
    -- Fetch the mouse X and Y dynamically every frame
    !move|x:(@mouse().x), y:(@mouse().y)|16ms|linear |+|
    
    !wait|16ms |+|
    !jump|FollowLoop |+|

```
