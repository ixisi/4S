# 4IM3 Scripting Engine for OBS Studio (v2.0.0)

A highly advanced, multithreaded Lua scripting engine built directly for OBS Studio. 4IM3 transforms OBS from a simple broadcasting tool into a dynamic, logic-driven environment capable of running games, complex cinematic automations, and interactive stream widgets.

## ✨ Key Features
* **Multithreaded Execution:** Spawn parallel background tasks that execute simultaneously without locking up the OBS UI.
* **"Read-Through" Memory Model:** True lexical scoping. Background threads capture local loop variables while maintaining live access to global states.
* **Delta-Time Physics:** Framerate-independent animations guarantee smooth scaling, moving, and fading regardless of stream FPS.
* **Total OBS Dominion:** Manipulate Scene Items, Filters, Audio Sources, Media Timelines, and Scene Transitions directly from your scripts.
* **Built-in VFX Library:** Instantly trigger complex visual effects like glitches, screen shakes, and rainbow cycles with a single command.

---

## 🚀 Installation
1. Download `4IM3-SCRIPT-2.0.0.lua`.
2. Open OBS Studio.
3. Navigate to **Tools > Scripts**.
4. Click the **+** icon and add the Lua file.
5. Use the provided script text box to write your logic, or link to an external text file.

---

## 📖 Syntax Overview
The engine uses a strict, highly parsable command syntax:
`!command_name | argument_1 | argument_2 |+|`

* Every command starts with `!`
* Arguments are separated by `|`
* Every line **must** end with the execution terminator `|+|`

### The Universal Time Parser
Any command requiring a duration accepts highly readable time formats. The engine standardizes them automatically:
* `500ms` (Milliseconds)
* `2.5s` (Seconds)
* `1mi` (Minutes)
* `0.5hr` (Hours)

### Easing Library
For animations like `!move` or `!fade`, the engine supports the following curves:
`linear`, `quad_in`, `quad_out`, `quad_inout`, `sine_inout`, `back_out`, `elastic_out`, `bounce_out`

---

## 🛠️ Command Reference

### 1. Variables & Logic
* `!var|name|value |+|` - Creates/updates a local variable. Supports relative math (`++1`, `--1`).
* `!gvar|name|value |+|` - Creates/updates a global game-state variable.
* `!if|val1|operator|val2|TargetLabel |+|` - Conditional logic. Jumps to `TargetLabel` if true.
* `!label|Name |+|` - Defines a jump point in the script.
* `!jump|Name |+|` - Instantly moves execution to a label.
* `!call|Name |+|` - Executes a label and returns.
* `!return |+|` - Ends the current execution block.
* `!include|filepath |+|` - Imports and executes an external script file.

### 2. Arrays & Multithreading
* `!array.push|array_name|value |+|` - Adds an item to a specific array.
* `!array.pop|array_name|save_var |+|` - Removes the last item and optionally saves it.
* `!array.remove|array_name|value |+|` - Finds and deletes a specific value from the array.
* `!array.clear|array_name |+|` - Empties the array.
* `!foreach|array_name|item_var|LabelName |+|` - Iterates through an array, spawning a parallel thread for each item.
* `!run{ ... }|+|` - Spawns a parallel background thread with a frozen snapshot of local variables.
* `!stop |+|` - Kills all background tasks immediately.
* `!wait|duration |+|` - Pauses the current thread for the specified time.
* `!loop |+|` - Restarts the current execution block from the beginning.
* `!then |+|` - Chains execution (waits for previous async tasks to finish).

### 3. Events & Listeners
* `!onpress|HotkeyName|Label |+|` - Listens for a specific keyboard shortcut.
* `!change|VariableName|Label |+|` - Triggers a label when a variable's value changes.
* `!collision|SourceA|SourceB|Label |+|` - Triggers a label when two sources overlap.

### 4. Source Control & Transformations
* `!source|SourceName |+|` - Targets an OBS source for subsequent commands.
* `!delete|SourceName |+|` - Completely deletes a source from OBS.
* `!move|x:val, y:val|duration|easing |+|` - Smoothly translates a source.
* `!fade|opacity_level|duration|easing |+|` - Transitions opacity (0 to 100).
* `!pin|parent_source|offsets |+|` - Glues a source to another (e.g., `!pin|Hero|x:0, y:20`).
* `!attach|target_source|label_name |+|` - Binds a source to a specific script label.
* `!path|control_x,control_y|target_x,target_y|duration|easing |+|` - Moves a source along a set of coordinates.
* `!spiral|x,y|radius|rotations|duration|easing |+|` - Moves a source in a spiral pattern.

### 5. Advanced OBS Control (Media, Audio, Scenes, Filters)
* `!filter|Target|FilterName|Prop|Val|duration |+|` - Instantly snaps or smoothly tweens an OBS filter property.
* `!media|SourceName|play/pause/stop/seek |+|` - Controls video timelines.
* `!media_time|SourceName|save_var |+|` - Reads current video playback time into a local variable.
* `!sound|SourceName|action_or_volume|val|duration |+|` - Triggers audio or fades volume.
* `!switch|SceneName |+|` - Instantly hard-cuts to a new scene.
* `!transition|SceneName|TransitionType|duration |+|` - Fades/Swipes to a new scene.

### 6. Visual Effects (VFX) Library
Instant macro animations for targeted sources.
* `!shake|intensity|duration |+|`
* `!camera_shake|intensity|duration |+|`
* `!glitch|intensity|duration |+|`
* `!rainbow|speed|duration |+|`
* `!breathing|speed|duration |+|`
* `!dvd|speed|duration |+|`
* `!sway|speed|duration |+|`

### 7. Utility
* `!log|message |+|` - Prints a message/variable to the OBS script log.

---
Great catch—those are essential for building responsive layouts and time-based logic. The `screen` variable allows you to calculate positions relative to the canvas size, while `tick` is perfect for creating custom oscillations or timing events.

Here is the updated **Predefined Variables & Functions** section to include those additions:

---

### **7. Predefined Global Variables**

These variables are updated every frame by the engine and can be used in any math expression or command.

* **`screen.width` / `screen.height**`: Returns the current base resolution of your OBS canvas.
* **`tick`**: Delta Time. Use this to ensure physics-based calculations remain consistent regardless of framerate.

---

## ⚡ Predefined Functions (`@`)
Dynamic keywords used inside arguments to fetch real-time data or perform instant engine actions. Standard math functions (e.g., `math.random`) are completely supported.

* **`@clone(auto_delete_bool)`**: Creates an exact duplicate of the currently targeted source.
* **`@source(Name)`**: Returns the internal reference of a source.
* **`@dist(x1, y1, x2, y2)`**: Calculates the distance between two points.
* **`@mouse()`**: Returns the current mouse coordinates.
* **`@alert(msg)`**: Triggers a system/OBS alert popup.

---

## 🎮 Example: The Object Pool
Here is an example of creating parallel asteroids that read their own local frozen IDs while listening to a global game state.

```text
!gvar|is_playing|1 |+|
!array.clear|asteroid_pool |+|

!var|spawn_count|5 |+|
!label|GeneratePool |+|
    !var|new_rock|@clone(true) |+|
    
    !run{
        !source|new_rock |+| 
        !move|y:1200|5s|linear |+|
        
        -- Threads can safely access their frozen 'new_rock' variable 
        -- while simultaneously reading the live global 'is_playing' state!
        !if|is_playing|==|0|StopRock |+|
    }|+|
    
    !array.push|asteroid_pool|new_rock |+|
    !var|spawn_count|--1 |+|
    !if|spawn_count|>|0|GeneratePool |+|
