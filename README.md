# 4IM3-SCRIPT 2.3.0

4IM3-SCRIPT is a small language hosted by a single OBS Lua script. A program can control OBS scene sources, draw into an engine-owned pixel renderer or GPU 3D renderer, read input, run animations, and schedule work. You write **4IM3-SCRIPT commands**, not Lua, for ordinary programs.

This doc explains the language syntax, commands, values, units, and runtime behavior. Start with the tutorial, then use the [command reference](#command-reference) and [units](#units-and-coordinate-systems) while writing programs.

## Contents

- [Install and run](#install-and-run)
- [First program](#first-program)
- [Language syntax](#language-syntax)
  - [Assigning command results](#assigning-command-results)
- [Values, expressions, and tables](#values-expressions-and-tables)
- [Control flow and functions](#control-flow-and-functions)
  - [Conditions and loops](#inline-conditions-and-loops)
  - [Functions](#functions)
- [Units and coordinate systems](#units-and-coordinate-systems)
- [Drawing and animation](#drawing-and-animation)
  - [Renderer fields](#renderer-creation-fields)
  - [Canvas fields and drawing](#pixel-canvas)
  - [Packed data and sprites](#packed-data-and-sprites)
  - [Sprite animations](#sprite-animations)
  - [3D objects, imports, and animation](#real-3d-renderer)
  - [Camera-view textures and clipping planes](#camera-view-textures-and-clipping-planes)
  - [Shaders](#shader-renderer)
- [Input and timing](#input-and-timing)
- [Event handlers](#event-handlers)
- [3D physics](#3d-physics)
- [Sources and OBS](#sources-and-obs)
- [Tasks and workers](#tasks-and-workers)
- [Connection messaging](#connection-messaging)
- [TCP networking](#tcp-networking)
- [Command reference](#command-reference)
- [Advanced syntax and compatibility](#advanced-syntax-and-compatibility)
- [Less obvious behavior](#less-obvious-behavior)
- [Troubleshooting](#troubleshooting)

## Install and run

1. In OBS, open **Tools → Scripts**, add `4IM3-SCRIPT-2.3.0.lua`, and leave it loaded. OBS must have Lua scripting available. The engine registers two source types: **4IM3 Pixel Renderer** and **4IM3 Shader Renderer**.
2. Choose **OUTPUT: FILE** and select a UTF-8 `.txt` or `.4im3` program, or choose **OUTPUT: TEXT** and paste commands. **OUTPUT: INPUT** is a one-line input. Press **Execute** to compile and start the program. Loading the engine by itself does not execute the program field.
3. Look at the active OBS scene for graphics. Use **Help → Log Files → View Current Log** for `!log`, validation errors, and stack traces.
4. Set **Script work budget per tick (ms)** between 1 and 20 if needed; the default is 6. This is a cap on script work per OBS tick, **not** a game FPS setting. A program that needs a new picture each frame should use `!wait | frame |+|`.

Pressing **Execute** again resets program variables, tasks, functions, sprite definitions, and canvas buffers. `!save` values stored in OBS settings can be loaded on a later run. Relative resource paths follow the selected output mode:

| Output mode | Base folder for relative paths |
| --- | --- |
| **FILE** | The folder containing the selected entry program, such as `main.txt`. |
| **TEXT / INPUT** | The folder containing the engine Lua file. |

This applies to model import, texture, model save/load/export, shader, module,
and top-level include paths. Absolute paths are unchanged. Nested includes are
relative to the included file that contains them; referenced model buffers and
textures remain relative to the model file. The base folder is captured when
you press Execute and stays fixed until the next Execute. For example,
`path:"models/object.glb"` in File mode refers to a `models` folder beside the
selected entry program.

## First program

Paste this into **OUTPUT: TEXT** and press **Execute**. It creates its own renderer source in the current scene, draws one frame, and writes a message to the OBS log:

```text
!renderer | create | name:HelloView | kind:pixel | width:640 | height:360 |+|
!canvas | create | name:HelloView | width:320 | height:180 |+|
!canvas | fill | red:8 | green:16 | blue:35 |+|
!canvas | circle | x:160 | y:90 | radius:34 | red:255 | green:210 | blue:35 |+|
!canvas | text | text:"HELLO" | x:142 | y:133 | scale:2 | red:255 | green:255 | blue:255 |+|
!canvas | update |+|
!log | "HelloView is ready" |+|
```

`!renderer | create` adds or configures a direct scene source of the requested kind. `!canvas | create` makes a pixel buffer and selects it. Drawing changes that buffer; `!canvas | update` sends the finished image to the renderer. The 320 × 180 buffer is scaled to the renderer's 640 × 360 output.

`!renderer | create` also accepts `locked:true` or `locked:false` to set the OBS scene item's lock. Omit it to keep the current lock state; locking helps when a script uses mouse drags over OBS's main preview.

To animate, run a frame loop. `tick` is the elapsed **seconds** since the previous `!wait | frame` resume:

```text
!renderer | create | name:MovingView | kind:pixel | width:640 | height:360 |+|
!canvas | create | name:MovingView | width:320 | height:180 |+|
!var | number x | 0 |+|
!label | frame |+|
!canvas | fill | red:0 | green:0 | blue:0 |+|
!canvas | circle | x:x | y:90 | radius:10 | red:255 | green:220 | blue:0 |+|
!canvas | update |+|
!wait | frame |+|
!var | x | (x + 80 * tick) % 320 |+|
!jump | frame |+|
```

### Learn by changing the first program

- Change `width` and `height` on `!canvas | create` to change the drawing resolution.
- Change `x` and `y` to move a shape in **buffer pixels**.
- Change `red`, `green`, and `blue` from 0 to 255.
- Add another `!canvas` drawing command before `update`; drawing order is command order.
- Add `!input | key | A | left_down | left_pressed |+|` inside the loop to read input. Focus OBS's main window when testing on Windows or Linux/X11.

## Language syntax
 
The normal statement shape is:

```text
!command | argument | argument |+|
```

`!` begins a command, `|` separates its fields, and `|+|` ends it. A statement can span several lines; multiple statements may share a line. Spaces around separators are optional. Commands run in source order unless a branch, wait, or task changes the flow. Text after `--` is a comment outside quotes.

```text
-- A comment
!var | number score | 0 |+|  -- trailing comment
!log | score |+|
```

Quoted strings may use `'single'` or `"double"` quotes. Quotes protect separators and commas inside a string. Use quotes for literal text that might otherwise be mistaken for a variable or expression. The parser is purpose-built, so do not assume arbitrary Lua syntax or Lua libraries are accepted.

**Named fields** are supported by `!renderer | create`, the drawing `!canvas` commands, `!array | unpack`, `!sprite`, and `!animation`. In a named call, field order can vary and comma groups can replace some pipes. Do not mix positional and named values in one call. For named `!canvas` calls, the action itself may appear anywhere among fields:

```text
!canvas | text | text:"READY" | x:10 | y:20 | scale:2 | red:255 | green:125 | blue:255 |+|
!canvas | x:10,y:20 | text | text:'READY' | r:255,g:125,b:255,scale:2 |+|
```

This flexibility is **not** a blanket rule for every command. For example, `!move`, `!path`, `!pin`, and source methods accept comma-separated `key:value` pairs within a particular dictionary argument; their other arguments still have fixed positions. The [graphics guide](#drawing-and-animation) lists every named drawing field and short alias.

### Assigning command results

Commands that produce data can write it to a variable using this optional
suffix:

```text
!command | arguments | -> | result |+|
```

`result` is the destination variable name, not a quoted string or an expression.
It must start with a letter or underscore and contain only letters, digits,
and underscores. The engine creates it if needed, or updates its existing
scope. Declared types are checked. The arrow and destination must be the last
two fields before `|+|`.

For commands with an existing output field, the arrow replaces that field:

```text
-- These two calls produce the same result table:
!world3d | list | into:parts |+|
!world3d | list | -> | parts |+|

-- These two calls produce the same numeric value:
!media_time | Music | playhead |+|
!media_time | Music | -> | playhead |+|

!connection | addresses | -> | interfaces |+|
!clipboard | paste | -> | clipboard_result |+|
!array | unpack | type:u8,encoding:hex,data:"0102" | -> | values |+|
!array.copy | values | -> | copied_values |+|
!array.pop | values | -> | last_value |+|
```

Use either the arrow or the original destination for one command. Combining
them, repeating the arrow, or adding an arrow to an unsupported command reports
a result-assignment error. Existing `into:`, `name:` and positional output
forms continue to work.

| Command or action | Result assigned by `->` |
| --- | --- |
| `!connection`, `!websocket`, `!network`: `addresses`, `invite`, `decode`, `send`, `receive`, `status` | The same value as `into:`: interface data, a private code string, decoded endpoint details, a send result, an event, or connection status. |
| `!clipboard`: `copy`, `paste` | `{ok,text,error}`, as with `into:`. |
| `!world3d`: `list`, `stats`, `get`, `bounds`, `snapshot`, `pick`, `camera`, `view`, `spotlight`, `background`, `mesh`, `instances` | The same table as `into:`. Camera, view, light and background commands can update supplied fields before returning their current values. Async meshes and instance batches return a live build-status record. |
| `!physics`: `step` | A new physics-state table; the input state remains unchanged. Accepts `into:` or `->`. |
| `!world3d`: `import`, `save`, `load`, `export` | An operation result with `ok` and `error`; import also includes `names`. Check `ok` before using imported data. |
| `!world3d`: `animate` with `mode:list` or `mode:status` | A clip-name list or playback-status table. Other animation modes do not return a result. |
| `!input`: `snapshot`, `keys` | The usual input table. Put requested keys after the action and before the arrow; omit the original table destination. |
| `!input`: `key`, `mouse` | A table with numeric `down`, `pressed`, and `released` fields. The original separate output variables remain supported. |
| `!input`: `pointer` | A table with `x`, `y`, `mouse_inside`, and `focused`. The last two fields are numeric 0 or 1. |
| `!input`: `recenter` | A table with `supported`, `warped` (numeric 0/1), and source coordinates `x`, `y`. |
| `!input`: `focus`, `text`, `wheel` | A numeric focus flag, typed UTF-8 text, or wheel delta. |
| `!array` with `unpack`, or `!array.unpack` | A decoded table; omit `name:` when using the arrow. |
| `!array.copy` | A deep copy of the source table. Supply only the source before the arrow. |
| `!array.pop` | The removed last entry. An empty array leaves the destination unchanged. |
| `!media_time` | The current media playhead in milliseconds. |
| `!fetch` | The downloaded string, or decoded JSON when parsing succeeds, after the fetch completes. |
| `!load` | The saved value or supplied fallback. The name before the arrow still selects the saved key; only the assignment destination changes. No saved value and no fallback leaves the destination unchanged. |
| `!worker` expression, block, or computation label | The live job result table. Assignment does not wait for completion; check `state` before reading `value`. |
| `!worker`: `read` or `get_result` | A nonblocking snapshot of the named worker job. |
| `!function_name` or `!call` | The value passed to `!return`, using the existing function/label return behavior. |
| `!start_independent_task` or `!spawn` | The task name, using the existing task-handle syntax. This is not the task's computed result. |
| `!@function(...)` | The first returned value from an engine expression function. |
| Selected source getter, such as `!width` or `!pos` | Its returned property value. Select exactly one source and pass no setter arguments. |

Multiple input outputs fit into one table:

```text
!input | key | W | -> | key_state |+|
!if | key_state.pressed == 1 { !log | "W pressed" |+| } |+|
!input | pointer | -> | pointer |+|
!input | snapshot | W | A | S | D | MOUSE_LEFT | -> | keys |+|
```

Other result examples:

```text
!load | number best | 0 | -> | saved_best |+|
!worker | (2 + 3) | -> | calculation |+|
!worker | read | calculation | -> | calculation_status |+|
!@dist(0,0,3,4) | -> | distance |+|
!use_sources | Title |+|
!width | -> | current_width |+|
```

Workers continue publishing into their assigned result table after the start
command returns. A completed fetch assigns its result when its waiting command
finishes. Ordinary queries assign immediately. Zero and `false` are valid
results. `!then` / `!execute_command` forward the arrow to the invoked command.
Commands such as `!wait`, canvas drawing, and connection `close` do not return
data; their internal completion flags are not values for arrow assignment.

`!include | path |+|` inserts another text file at compile time. In File mode, relative paths start beside the selected main program; Text/Input mode starts beside the engine Lua file. Nested includes are relative to the file that contains them. Missing files and circular includes produce an error. The compiler accepts full-line `--` comments in included files.

```text
!include | definitions.txt |+|
!include | drawing/shapes.txt |+|
```

`-skip-` and `-end-` delimit skipped text at compile time. Functions and inline blocks provide explicit control over reusable code and conditional execution.

## Values, expressions, and tables

### Variables and scope

```text
!var | score | 0 |+|
!var | number speed | 80 |+|
!var | string title | "READY" |+|
!var | bool enabled | true |+|
!var | table player | {x:20, y:40} |+|
!var | player.x | player.x + speed * tick |+|
!var | local number temporary | 3 |+|
```

`!var` assigns a value. The optional type is `string`, `number`, `bool`, or `table`; an explicit type validates later writes. `local` creates a name in the current call/task scope. Without `local`, writing an existing name updates the scope that owns it; a new name is created in the active scope. Access fields with `player.x` and list elements with `list[1]`. `screen`, `pi`, and `huge` are initialized when a program starts; `screen.width` and `screen.height` are the OBS canvas dimensions. `tick` is supplied after `!wait | frame`.

For a numeric update, `!var | score | ++10 |+|`, `--2`, and `**3` mean add, subtract, and multiply the existing value. The same relative-value notation works in compatible source/movement fields. `--` at the start of a value can be mistaken for a comment if separated incorrectly; put the value after its `|` and prefer an ordinary expression when in doubt.

Use numeric literals, quoted strings, `true`/`false`, variables, and supported expressions in value positions. Examples include `x + speed * tick`, `(score + 1)`, `math.min(a,b)`, comparisons, `and`, and `or`. The engine validates expressions rather than evaluating arbitrary Lua source. A bare unquoted word can be treated as a variable or source name depending on the command; quote display text.

Concatenate strings and numbers with `..`: `"SCORE "..score.." POINTS"`.
Spaces around `..` are optional. An escaped quote inside a string remains part
of that literal; a quoted fragment followed by `..` is an expression.

### Tables and arrays

```text
!var | table speeds | [0.11, 0.09, 0.07] |+|
!var | table player | {x:20, y:40, lives:3} |+|
!var | table pellets | [{x:2, y:4}, {x:3, y:4}] |+|
!log | speeds[1] |+|
!log | pellets[2].y |+|
```

`[...]` is a **1-based dense list**. `{key:value,...}` is a record. Entries can be nested or span lines. A literal allows up to 4,096 entries at each level and 16 nesting levels. A packed `!array | unpack` is better for very large static numeric data.

A complete lookup keeps the value's type, including a table, string, or `false`.
Arithmetic inside its brackets calculates the index; it does not turn the
returned record into a number:

```text
!var | next_index | 1 |+|
!var | chosen | pellets[next_index+1] |+|
!var | same_record | (pellets[next_index+1]) |+|
```

These assignments reference the same selected table in the current program;
use `!array.copy` for a deep copy. Existing intermediate-index variables still
work. Adding arithmetic or comparisons **outside** a lookup remains an ordinary
expression, for example `pellets[next_index+1].x + 10`.

To append a record, first declare it with `!var`, then pass its variable name to
`!array.push`. For an appended calculation, use parentheses, for example
`!array.push | positions | (x+1) |+|`.

| Command | Purpose |
| --- | --- |
| `!array.push \| list \| value \|+\|` | Append a value; creates the list if absent. |
| `!array.pop \| list \| destination \|+\|` | Remove the last value and optionally store it. |
| `!array.remove \| list \| value \|+\|` | Remove the last matching value. |
| `!array.clear \| list \|+\|` | Replace the list with an empty table. |
| `!array.copy \| destination \| source \|+\|` | Deep-copy a table. |
| `!array.shift \| list \| first \| last \|+\|` | Shift entries right by one into the inclusive destination range. |
| `!array \| unpack \| name:bytes \| type:u8 \| encoding:hex \| data:"00FF" \|+\|` | Decode packed numeric data into a 1-based table. |

`!array.unpack` is an alias for `!array | unpack`. Unpack supports `u8` or little-endian `u16`, `hex` or `base64`, and optional `count` validation. See [packed graphics](#packed-data-and-sprites).

### Persistence

```text
!load | number best | 0 |+|
!var | best | best + 10 |+|
!save | best |+|
```

`!save` stores one **string, number, or boolean** in OBS script settings; `!load` reads it or uses the fallback. Tables are not persisted. File-based programs have a storage namespace derived from their file path; text/input output uses a shared `global` namespace. Renaming or moving a file therefore changes which saved values it sees.

## Control flow and functions

### Inline conditions and loops

```text
!if | score > best {
    !var | best | score |+|
    !save | best |+|
} |+|
!else {
    !log | "No new record" |+|
} |+|

!for | item in pellets {
    !log | item.x |+|
} |+|
!for | i from 3 to 1 {
    !log | i |+|
} |+|
```

The optional `!else` must immediately follow its `!if`. `!if | condition | { ... } |+|` and `!else | { ... } |+|` also work. Numeric `0` and boolean `false` are false; nonzero numbers and `true` are true. Other strings are not general truthy values. `!for` accepts a list or an inclusive whole-number range, including descending ranges. Bounds and list are captured at loop start. Its iterator's previous value is restored at loop end. Inline blocks are compiled into normal queue commands and count toward the work budget; they can span OBS ticks.

List loops visit indexes `1` through `#list`; use a dense list without missing
entries. Blocks can contain nested `!if` and `!for` commands. Invalid condition
expressions report an error. Put `!wait | frame |+|` inside a loop or block when
each iteration should advance one visible frame.

### Functions

```text
!fn | add_points | amount, bonus:0 | {
    !var | score | score + amount + bonus |+|
    !return | score |+|
} |+|

!var | number score | 0 |+|
!add_points | 10 | -> | latest_score |+|
!add_points | amount:5, bonus:2 | -> | latest_score |+|
```

The brace body is required and is registered without running it. Parameters are optional. Declare positional parameters in the definition; `name:default` supplies omitted values. Calls can also pass named fields, separated by `|` or grouped by commas. In the body, parameter names are local and `args` contains their named and positional values. `!return | value |+|` exits and optionally writes to `-> | destination`. Calls can nest up to 128 levels. Built-in command names cannot be redefined.

A function without a parameter list can receive named values. Reaching the
closing brace returns without a value. Functions can call other functions,
including functions defined later in the program.

**Global labels are forbidden inside functions.** A `!label | <name> |+|`
declaration anywhere in a function body reports a compile error, including
inside nested conditions, loops, task/worker blocks, nested function definitions,
and included code. The rule applies even if that branch or function never runs.
Quoted text and comments are not label declarations. Code compiled later from
a function context inherits the same restriction.

Ordinary labels such as `!label | retry |+|` remain local to their function's
compiled body. Use `!jump | retry |+|` within that body. Enter a function through
`!function_name`, which sets up its arguments, local scope, and return point;
`!jump` and `!call` cannot enter it by its function name.

### Labels and older control flow

```text
!label | frame |+|
!log | "one frame" |+|
!wait | frame |+|
!jump | frame |+|
```

`!label` marks a location; it **does not skip the following commands**. To keep a helper label from running on initial pass, jump around it, put it after a terminating flow, or use `!fn` instead. `!jump | label` branches; `!call | label | optional_name:value | -> | result` enters a label with a return point; `!return` returns. `!if | condition | label | ret |+|` conditionally calls a label, while the form without `ret` jumps. Labels and functions are separate: `!call` and `!jump` do not invoke `!fn` definitions. `!label | <name> |+|` declares a global label usable from compatible contexts.

`!loop | count | label_or_{block} |+|` and `!foreach | table | item_name | label |+|` are older forms. For new frame loops, prefer `!for` where possible and place `!wait | frame` deliberately. A tight `!jump` loop with no yield eventually triggers the runaway-script guard.

## Units and coordinate systems

| Value | Unit / range | Used by |
| --- | --- | --- |
| `10`, `500ms`, `1.5s`, `2mi`, `1hr` | Unqualified durations are **milliseconds**; `mi` means minutes | `!wait`, `!move`, `!fade`, `!path`, `!transition`, `!despawn`, and other duration fields that call the time parser. |
| `tick` | Seconds since the preceding frame resume | Frame-rate-independent game movement. |
| `!media_time` result | Milliseconds on the OBS media playhead | Music cues and hit windows. |
| `!animation` `duration` and `time` | Seconds | Choosing sprite frames. Do not append `ms` here. |
| Renderer `width`, `height` | Output source pixels, 1–8192 each | `!renderer \| create`. |
| Canvas `width`, `height`, `x`, `y`, `radius` | Buffer pixels; buffer dimensions 1–8192, up to 16 million total pixels | `!canvas`, `!sprite`, `!animation`. The origin is at the top left; x increases rightward, y downward. |
| OBS source `pos`, `size`, `width`, `height` | OBS scene canvas pixels | Source methods and movement commands. These can differ from buffer pixels. |
| 3D `x`, `y`, `z`, box `width`, `height`, `depth`, mesh vertices | World units; positive x is right, positive y is up, and **negative z is in front of the default camera** | `!world3d`. These are not OBS or canvas pixels. |
| 3D `yaw`, `pitch`, `roll`, camera `fov` | Degrees | `!world3d`; `fov` is vertical field of view. |
| `red`, `green`, `blue` (`r`, `g`, `b`) | Integer channel intensity, 0–255 | Canvas colors and source color effects. |
| `interpolation` (`alpha`) | 0–1 | `!canvas \| rectangles` old/current-position blending. |
| `scale` on renderer | Scene-item multiplier, above 0 through 32 | `!renderer \| create`. |
| `scale` on canvas text | Whole font-pixel multiplier, 1–8 | `!canvas \| text`. |
| `rot` | Degrees | OBS source rotation. |

The duration parser recognizes `s`, `mi`, and `hr`; other/no suffixes are treated as milliseconds. It reads a nonnegative numeric portion. Use explicit units for readability. OBS's own FPS counter and a program's animation rate are different: the scene can still render at 60 FPS while a script updates its picture only a few times per second.

`!wait` accepts either a duration or the special word `frame`:

```text
!wait | 100 |+|     -- 100 milliseconds
!wait | 500ms |+|   -- 500 milliseconds
!wait | 2s |+|      -- 2 seconds
!wait | frame |+|   -- resume on the next OBS video tick
```

At 60 FPS, one frame is roughly 16.7 ms; at 30 FPS, roughly 33.3 ms. The exact interval can vary. `frame` also updates `tick` with the elapsed **seconds** since the previous frame resume, making `speed * tick` useful for smooth movement. A numeric wait is a duration and does not serve as that explicit frame boundary.

## Drawing and animation

### Renderer creation fields

| Command | Named attributes | Meaning |
| --- | --- | --- |
| `!renderer \| create` | `name`, `kind`, `width`, `height`, optional `scale`, `locked` | Create or configure a direct renderer source in the active OBS scene. `kind` is `pixel`, `shader`, or `3d`. Width and height are source pixels (whole numbers from 1 to 8192). `scale` is the OBS scene item size multiplier, above 0 and at most 32; it defaults to 1. |

`!renderer | create` checks the existing source's type if the name is already
used. It reports a collision instead of silently selecting another source.

`locked:true` or `locked:false` sets the scene item lock. If omitted, the
existing lock state is kept. Named fields accept expressions; use one style
per call rather than mixing positional and named arguments.

### Pixel canvas

```text
!renderer | create | name:View | kind:pixel | width:640 | height:360 | scale:1 |+|
!canvas | create | name:View | width:320 | height:180 |+|
!canvas | fill | red:0 | green:0 | blue:0 |+|
!canvas | rectangle | x:20 | y:20 | width:70 | height:12 | red:20 | green:80 | blue:255 |+|
!canvas | circle | x:80 | y:80 | radius:10 | red:255 | green:220 | blue:0 |+|
!canvas | text | text:"SCORE (score)" | x:8 | y:8 | scale:2 | red:255 | green:255 | blue:255 |+|
!canvas | update |+|
```

`!canvas | update` is the public readable name for the older `present` action. It publishes a complete copy of the current drawing pixels for the next OBS render. Drawing after that command changes only the working buffer: the preview and projectors keep showing the last published image until another `update`. This prevents incomplete UI redraws from flashing on screen when drawing spans several script ticks. Repeated calls without changes do not copy pixels or force another upload. Each canvas keeps one additional RGBA buffer for its published image (width × height × 4 bytes), reused across updates. A `create` replaces that buffer, while `!canvas | use | name:View |+|` switches to an existing buffer **without clearing it**. Multiple renderers can therefore have separate buffers. `snapshot` remembers the selected buffer's working pixels, and `restore` copies them back; this is useful for an expensive static background under moving sprites. Canvas dimensions may be 1–8192 pixels per side, with a 16-million-pixel total limit.

Drawing inside a function that has not selected its own canvas inherits the
nearest caller's selection. This also applies to `!sprite | draw` and
`!animation | draw`, so a reusable drawing helper can serve several canvases.
An explicit `!canvas | use` in the helper overrides inheritance. Async calls use
their task's call stack when finding the caller's canvas. `create` and `use`
make the selected OBS source visible; hide it again when drawing background UI
that should remain hidden.

| Command | Named attributes | Meaning |
| --- | --- | --- |
| `!canvas \| create` | `name`, `width`, `height` | Create a blank pixel buffer for a direct pixel renderer. Dimensions must be whole numbers from 1 to 8192, with at most 16 million pixels total. This also selects the buffer used by the following drawing commands. |
| `!canvas \| use` | `name` | Use a previously created buffer without clearing it. |
| `!canvas \| fill` | `red`, `green`, `blue`, optional `opacity` | Fill the selected buffer with one color. `opacity:0` makes it transparent; the default is 255. |
| `!canvas \| rectangle` | `x`, `y`, `width`, `height`, `red`, `green`, `blue` | Draw a filled rectangle. `x,y` is its top-left corner. |
| `!canvas \| circle` | `x`, `y`, `radius`, `red`, `green`, `blue` | Draw a filled circle centered at `x,y`. Radius is in buffer pixels and must be 0 to 2048. |
| `!canvas \| text` | `text`, `x`, `y`, `red`, `green`, `blue`; optional `scale`, `font` | Draw text at its top-left position. `font:classic` (default) uses a 3 × 5 bitmap; `font:readable` uses a clearer 5 × 7 bitmap. `scale` magnifies each font pixel; it defaults to 1 and must be a whole number from 1 to 8. |
| `!canvas \| rectangles` | See below | Draw many filled rectangles from coordinate tables in one command. |
| `!canvas \| update` | None | Send the finished buffer to the OBS renderer on its next render. Call this after drawing a frame. Repeating it with no pixel changes does not upload a new frame. |
| `!canvas \| snapshot` / `restore` | None | Remember or restore the selected buffer pixels. |

In named renderer/canvas calls, `w`/`h` mean `width`/`height`, `r`/`g`/`b` mean full color names, `renderer`/`source` mean `name`, and renderer `type` means `kind`. Canvas text also accepts `message` or `content` for `text`. Unknown, repeated, missing, or mixed positional/named fields are errors. Positional calls keep the documented action-first order.

Both built-in canvas fonts contain uppercase `A`–`Z`, digits, spaces, and common punctuation for values and paths. For a menu, use `!canvas | text | font:readable | text:"SETTINGS" | x:10,y:20,scale:2,red:255,green:255,blue:255 |+|`. `font:classic` keeps existing scripts' text layout. For typography beyond these bitmap faces, use an OBS text source or a packed sprite. Circle radius is limited to 0–2048 buffer pixels.

#### Drawing many rectangles

```text
!canvas | rectangles |
    x_table:positions_x | y_table:positions_y | first:1 | last:count |
    origin_x:16 | origin_y:28 | stride_x:12 | stride_y:12 |
    inset_x:1 | inset_y:1 | width:10 | height:10 |
    red:162 | green:247 | blue:92 |+|
```

`x_table` and `y_table` are table variable names. `first` and `last` are
**1-based** inclusive cell indexes; a call may cover at most 4096 entries.
Each rectangle is drawn at:

```text
x = origin_x + x_table[index] * stride_x + inset_x
y = origin_y + y_table[index] * stride_y + inset_y
```

The origins, strides, insets, width, and height are in buffer pixels. To blend
between previous and current positions, add all three optional attributes:
`previous_x`, `previous_y`, and `interpolation`. The previous attributes name
the old coordinate tables. `interpolation` is **0 to 1**: 0 uses the previous
position, 1 uses the current position.

#### Drawing field aliases

| Short name | Full name | Commands |
| --- | --- | --- |
| `renderer` or `source` | `name` | Renderer create, canvas create/use |
| `type` | `kind` | Renderer create |
| `message` or `content` | `text` | Canvas text |
| `xs`, `ys` | `x_table`, `y_table` | Canvas rectangles |
| `old_x`, `old_y` | `previous_x`, `previous_y` | Canvas rectangles |
| `alpha` | `interpolation` | Canvas rectangles |

Named commands report missing, repeated, or unknown attributes and reject a
mix of named and positional values. Existing action names (`ensure`, `init`,
`select`, `clear`, `rect`, `rects`, and `present`) and positional values remain valid. `!canvas | update |+|`
replaces `!canvas | present |+|` in new examples; both perform the same update.


### Packed data and sprites

Packed data stays inside the 4IM3-SCRIPT file. It is decoded when the command
runs, then used like an ordinary table or reusable sprite. No image file,
module, or native library is needed.

```text
!array | unpack | name:points | type:u16 | encoding:base64 | count:2 | data:"AQACAA==" |+|
!sprite | create | name:dot | width:2 | height:1 | palette:"transparent,#FF0000" | pixels:"AAE=" |+|
!sprite | draw | name:dot | x:20 | y:30 |+|
!canvas | update |+|
```

`!array | unpack` accepts `type:u8` or `type:u16` and `encoding:base64` or
`encoding:hex`. `u16` values use little-endian byte order. `count` is optional;
when present, it checks the number of decoded values. The resulting table is
1-based and works with `!array.copy`, `!canvas | rectangles`, and normal table
access. `!array.unpack` is an alias that takes the same attributes without the
`unpack` action.

`!sprite | create` takes a name, width, height, a comma-separated palette, and
base64 pixel bytes. Each pixel byte indexes the palette starting at zero.
`transparent` leaves the current canvas pixel untouched; other entries are
`#RRGGBB` colors. The number of pixel bytes must equal width × height. A sprite
can have at most 256 palette entries and 65536 pixels.

`!sprite | draw` paints the stored sprite at the specified top-left `x,y` on
the **currently selected canvas**. Coordinates can be expressions. Switch
buffers with `!canvas | use | name:... |+|`; finish the frame with
`!canvas | update |+|`. Definitions are cleared when a script is executed
again. Both commands accept positional arguments or named attributes in any
order, including comma-grouped attributes. Generate packed strings from an
image or data source at build time rather than typing them manually.

### Sprite animations

`!animation | create` defines a timed sequence. `!animation | draw` chooses
its frame from a time value and draws it into the selected canvas. Define an
animation once, then draw it as often as needed.

#### Sequence of existing sprites

```text
!sprite | create | name:red | width:2,height:1 |
    palette:"transparent,#FF0000,#0000FF" | pixels:"AQE=" |+|
!sprite | create | name:blue | width:2,height:1 |
    palette:"transparent,#FF0000,#0000FF" | pixels:"AgI=" |+|
!animation | create | name:flash | frames:[red,blue] | duration:1,loop:true |+|
```

Every name in `frames` must refer to an existing sprite. The list order is
the playback order.

#### Packed frames with one palette

The same two frames can be stored together:

```text
!animation | create | name:flash | width:2,height:1,count:2 |
    palette:"transparent,#FF0000,#0000FF" | pixels:"AQECAg==" |
    duration:1,loop:true |+|
```

Each decoded byte is a zero-based palette index. Frames are consecutive;
each frame contains `width * height` bytes in row order, left to right and top
to bottom. This example contains four bytes: `1,1,2,2`. Palette entry `0` is
transparent, `1` is red, and `2` is blue.

#### Draw and advance time

After either definition above:

```text
!renderer | create | name:View,kind:pixel,width:320,height:180 |+|
!canvas | create | name:View,width:160,height:90 |+|
!var | elapsed | 0 |+|
!label | frame |+|
!canvas | fill | red:0,green:0,blue:0 |+|
!animation | draw | name:flash | time:elapsed,x:20,y:30 |+|
!canvas | update |+|
!wait | frame |+|
!var | elapsed | elapsed + tick |+|
!jump | frame |+|
```

`duration` is the entire sequence length in seconds, not the duration of each
frame. `loop:true` repeats; `loop:false` is the default and holds the final
frame. `time` is supplied by the script: leave it unchanged to pause, set it
to `0` to restart, or assign another seconds value to seek. Draw coordinates
use canvas buffer pixels.

Named fields can appear in any order and can be grouped with commas or
separated by `|`. Definitions reset when the program is executed again.

#### Animation fields and limits

| Action | Required fields | Optional fields |
| --- | --- | --- |
| `!animation \| create` with sprites | `name`, `frames`, `duration` | `loop` |
| `!animation \| create` with packed frames | `name`, `width`, `height`, `count`, `palette`, `pixels`, `duration` | `loop` |
| `!animation \| draw` | `name`, `time`, `x`, `y` | None |

Packed frames contain `width * height * count` decoded bytes, with up to
256 frames, 256 palette entries, and 65,536 total pixel bytes. `duration` must
be greater than zero and at most 3,600 seconds. Negative time selects the first
frame. A transparent pixel leaves the existing canvas pixel untouched.
Referenced sprites remain available for individual `!sprite | draw` calls.
The packed definition is decoded once at creation, not on every draw.

### Real 3D renderer

The `3d` renderer draws GPU triangles with a perspective camera and a depth buffer. Boxes and custom meshes can rotate in all three axes and correctly cover objects behind them. The built-in effect lives inside the engine Lua file; this feature needs **no separate `.effect`, module, DLL, or other project file**.

```text
!renderer | create | name:World | kind:3d | width:960 | height:540 |+|
!world3d | camera | x:0,y:0,z:0 | fov:70 |+|
!world3d | box | name:Front | x:-0.3,y:0,z:-3 | red:255,green:90,blue:80 |+|
!world3d | box | name:Back | x:0.5,y:0,z:-5 | red:60,green:140,blue:255 |+|
!world3d | box | name:Front | yaw:45 |+|
```

`!renderer | create` also selects that world. A later `!world3d | box` or `!world3d | mesh` with the **same name updates that object**; fields you omit keep their previous values. `!world3d | set` updates an existing box, mesh, or all parts of an animated import without specifying its shape type. Draw changes appear on the next OBS render. Use `!world3d | update` when several transforms and the camera must change together. For a running animation, change `yaw`, `pitch`, `roll`, or position in a frame loop using `tick`.

If you delete the selected 3D renderer source in OBS while its program is running, the engine stops that program on the next tick and logs a short notice. Press **Execute** to create the source again.

| `!world3d` action | Named fields | Effect |
| --- | --- | --- |
| `use` | `name` | Select an existing 3D renderer when a program has more than one. `!world3d \| use \| World \|+\|` also works. |
| `camera` | Optional `x`, `y`, `z`, `yaw`, `pitch`, `roll`, `fov`, `near`, `far`, `into` | Move/turn/bank the camera and set its perspective. Defaults: position and angles 0, `fov:70`, `near:0.1`, `far:1000`. `near` must be less than `far`. `into:camera_info` copies the current camera fields. |
| `view` | Required `name`; optional camera fields, `width`, `height`, `enabled`, `offcenter`, `left`, `right`, `top`, `bottom`, `clip_enabled`, `clip_x`, `clip_y`, `clip_z`, `clip_d`, `delete`, `into` | Define or update a camera that renders the selected world into a live mesh texture. Supports an asymmetric frustum and one world-space clipping plane. See camera-view textures below. |
| `spotlight` | Optional `enabled`, `x`, `y`, `z`, `yaw`, `pitch`, `angle`, `range`, `intensity`, `ambient`, `red`, `green`, `blue`, `into` | Set one 3D cone light per renderer. `enabled:1` turns it on; position and angles aim it in world space. `angle` is the full cone width in degrees, `range` is world units, and `ambient` keeps unlit areas visible. `into:light_info` copies its fields. |
| `blur` | `amount` from `0` to `8` | Blur this renderer's final image by the given pixel radius. `amount:0` turns it off. The effect is built into the Lua engine and is useful behind menus or pause screens. |
| `background` | Optional `red`, `green`, `blue`, `into` | Set the clear color. Defaults: `8,12,26`. `into:background_info` copies its fields. |
| `box` | Required `name`; optional `x`, `y`, `z`, `width`, `height`, `depth`, `yaw`, `pitch`, `roll`, `red`, `green`, `blue`, `visible` | Create or update a solid box. Defaults: `x:0,y:0,z:-4`, size `1,1,1`, angles `0`, color `255,190,70`, visible. |
| `set` | Required `name`; optional transform, color, and `visible` fields | Update an existing box or mesh without replacing its shape or geometry. An animated import's name updates all its parts. `visible:0` hides it from drawing and picking; `visible:1` shows it. |
| `update` | Optional `objects`, `camera`; at least one required | Apply a table of object transform records and/or a camera record together. All fields and targets are validated before changes are applied. |
| `mesh` | Required `name`, `vertices`, `triangles` when creating or replacing geometry; optional `uvs`, `texture`, `image`, `mime`, `view`, `unlit`, `async`, `into`, and box transform/color fields | Create a custom triangle mesh, optionally textured. `view` binds a live camera-view texture. `async:true` prepares geometry across ticks and uploads it in packets. Default `async:false` retains the synchronous behavior. Async calls require both geometry fields. |
| `instances` | Required `name`, `mesh`, `transforms`; optional `async`, `into` | Create or replace one batched mesh from repeated placements of an existing mesh's local geometry. Defaults to `async:true`. See the batching example below. |
| `cancel` | `name` | Cancel an unfinished mesh/batch build or upload and keep the previous complete object. Does nothing if no build is pending. Mesh edit transactions use `edit` with `mode:cancel` instead. |
| `import` | `path`, `name`; optional `x`, `y`, `z`, `scale`, `into` | Import an OBJ, glTF 2.0 (`.gltf`), or binary glTF (`.glb`) model. glTF animation clips are retained. Multiple material groups or mesh primitives become `name_1`, `name_2`, etc. `into:result` supplies `result.ok`, `result.error`, and `result.names`. Import validates all parts before changing the world. |
| `animate` | `name`; optional `mode`, `clip`, `time`, `loop`, `speed`, `into` | Control clips of an imported glTF/GLB model. `mode:play` starts or restarts, `resume` continues after pause, `pause` holds the pose, `stop` restores the original pose, and `seek` sets a time in seconds. `list \| into:clips` returns clip names; `status \| into:state` returns clip, time, playing, loop, speed, pose_time, and pending. |
| `list` | `into` | Put the selected world's object names into a 1-based table. |
| `stats` | `into` or `->` | Copy statistics from the last completed render: `backend`, `instance_draws`, `instanced_objects`, `native_available`, `view_count`, and `view_ms`. See native instancing and camera-view textures below. |
| `get` | `name`, `into` | Copy an object's kind, transform, color, and (for meshes) `vertices` and `triangles` into a table. Mesh triangles are 1-based triples. |
| `bounds` | `name`, `into` | Project a visible object's vertices into renderer pixels, returning `found`, `x`, `y`, `width`, and `height` for selection outlines. Hidden or offscreen objects return `found:0`. |
| `snapshot`, `restore` | `into` for snapshot; `from` for restore | Copy a complete world into a table, then restore it. The current renderer dimensions are kept. |
| `duplicate`, `rename` | `name`, `as` | Copy an object under another name (offset 0.5 world units on x), or change its name while preserving scene order. |
| `vertex` | `name`, `index`, optional `x`, `y`, `z` or `delete:true` | Change one mesh vertex. `index:append` creates one; deletion requires removing faces that use it first. |
| `triangle` | `name`, `index`, `a`, `b`, `c` or `delete:true` | Change one mesh face. `a`, `b`, and `c` are 1-based vertex indices; `index:append` creates a face. |
| `edit` | `name`, `mode:begin/commit/cancel` | Stage several vertex and face changes, then validate and rebuild the mesh once on `commit`. `cancel` discards staged changes. |
| `pick` | `x`, `y`, `into` | Cast a ray through a renderer pixel and return the frontmost hit object, triangle, and nearest vertex of that triangle. |
| `save`, `load` | `path`; optional `into` | Write or load a complete 3D world (camera, camera views, background, objects, mesh geometry) in the engine's versioned model format. `load` replaces the selected world after validation. `into:result` returns `result.ok` (1/0) and `result.error` instead of stopping on a file error. |
| `export` | `path`; optional `into` | Write a runnable 4IM3 script that recreates the world and its renderer source. The optional result field works as above. |
| `remove` | `name` | Remove one box or mesh from the selected world. |
| `clear` | None | Remove all objects; keep the camera, spotlight, and background. |

For example, `!world3d | spotlight | enabled:1 | x:0,y:4,z:0 | pitch:-40 | angle:60,range:20,intensity:2,ambient:0.3 |+|` shines a cone into the scene. The GPU calculates it on visible pixels. It does not cast shadows or provide physically based material response. Saved models and exported scripts retain the light settings.

To move an animated import, use its import name in `set`; use an individual
returned mesh name to change just that part. Group updates assign the same
absolute fields to each part; they do not add offsets. A static import without
animation data still uses its returned part names.

For a following camera, separate commands can land on different OBS ticks when
the script exhausts its budget. Publish the object and camera together instead:

```text
!var | actor_pose | {name:"Actor",x:player_x,y:0,z:player_z,yaw:player_yaw} |+|
!var | poses | [actor_pose] |+|
!var | view | {x:camera_x,y:camera_y,z:camera_z,yaw:camera_yaw,pitch:-30} |+|
!world3d | update | objects:poses | camera:view |+|
```

`objects` is a dense 1-based list of records. Each record requires `name` and
accepts the numeric transform, color, and `visible` fields of `set`. `camera` is
a record of numeric camera fields from the table above. Values inside these
records are evaluated when the records are created. Either attribute may be
omitted. Invalid fields, missing objects, or an invalid near/far pair leave the
entire batch unchanged. This updates existing objects; it does not create meshes
or change their geometry. All changes become available to the next render at once.

`vertices` is a quoted list of local `x,y,z` points separated by semicolons. `triangles` (alias `faces`) is a quoted list of **1-based** vertex index triples. For example, `vertices:"-1,-1,0;1,-1,0;0,1,0" | triangles:"1,2,3"` defines one triangle. You may store either list in a string variable and use its variable name. Each triangle must have area; there is no preset vertex or triangle count cap per mesh. To change geometry, provide **both** fields again; changing only position or rotation does not rebuild the GPU buffer. A mesh's `width`, `height`, and `depth` multiply its local vertex coordinates along each axis. A box and mesh cannot share the same name unless you remove the old object first.

Geometry fields also accept **numeric tables**, either flat lists or lists of
rows. `vertices` uses groups of three numbers, `triangles` uses three integer
indices, and `uvs` uses two numbers per vertex. Both forms use dense, 1-based
lists; do not mix flat numbers and rows in one field. The engine validates and
copies the geometry. Changing your original table later does not change the
mesh; submit it again to rebuild. Empty geometry is rejected; remove or hide an
object when it has no surfaces. String geometry remains supported.

```text
!var | points | [[-1,0,0],[1,0,0],[0,1,0]] |+|
!var | faces | [1,2,3] |+|
!var | texcoords | [[0,1],[1,1],[0.5,0]] |+|
!world3d | mesh | name:Triangle | vertices:points | triangles:faces |
    uvs:texcoords | texture:"images/surface.png" |+|
```

This also lets the main script submit geometry prepared by a native worker:
pass the returned table fields directly to `vertices`, `triangles`, and `uvs`.
Mesh validation and drawing stay on the main/graphics side. The synchronous
form completes geometry validation inside one command; use `async:true` to
spread validation, copying, and vertex packing across OBS ticks.

### Incremental meshes and camera roll

```text
!world3d | camera | yaw:20,pitch:-10,roll:15 |+|
!world3d | mesh | name:Landscape | vertices:points,triangles:faces,async:true | -> | build |+|
-- Continue handling input and drawing in your normal frame loop.
!await | build.state!="running" |+|
!if | build.state=="done" {
    !world3d | set | name:Landscape | x:10 |+|
} |+|
```

`roll` banks the camera around its local viewing axis, in degrees. It works
with `camera`, camera records passed to `update`, screen bounds, and picking.
Snapshots, saved worlds, and exported scripts retain it. Older saved worlds
without camera roll load with `roll:0`.

An async mesh/batch returns this **live status table**, using either `into:`
or `->`:

| Field | Meaning |
| --- | --- |
| `name` | Target object name. |
| `state` | `running`, `done`, `error`, or `cancelled`. `done` means CPU geometry is ready and installed in the world. |
| `stage` | `preparing`, `packing`, `queued`, `uploaded`, `error`, or `cancelled`. |
| `uploaded` | `0` until all GPU packets are ready, then `1`. |
| `error` | Error text when preparation or a GPU allocation fails. |
| `prepare_ms`, `prepare_peak_ms` | Accumulated main-thread time preparing/packing this build, and the longest individual coroutine step, in milliseconds. Updated while preparation runs. |
| `upload_ms`, `upload_peak_ms` | Accumulated time submitting GPU buffers/publishing the replacement, and the longest individual packet step, in milliseconds. Includes old-buffer cleanup at publication. These measure main/graphics-thread calls, not GPU execution time. |
| `packets`, `packets_uploaded` | Planned GPU packets, and successfully submitted packets. `packets` may increase during uploading if a slow driver call causes a prepared packet to be subdivided. At successful completion these fields agree. |
| `buffers_reused` | Uploaded packets that updated a matching idle dynamic GPU buffer instead of allocating a new one. Starts at `0`. |
| `elapsed_ms` | Wall time from submission to the latest preparation update, then to complete upload or cancellation; includes waiting between callbacks. |

While preparation runs, the old object stays unchanged. After preparation,
queries and saving use the new geometry, but rendering keeps the complete old
mesh until **all** replacement packets upload. A new object is not drawn until
its upload finishes. If you need rendering and picking to agree exactly, wait
for `uploaded:1` before enabling interaction with the replacement. Uploads
advance only when OBS renders that source; a hidden source can stay `queued`.
An upload failure sets `state:"error"` and restores the previous object.

Keep input geometry/UV/placement tables unchanged while `state` is `running`.
The engine borrows these tables to avoid an initial blocking deep copy, then
owns its validated geometry. You may modify or discard your inputs after
preparation finishes. Numeric transform expressions are captured at submission.
Starting another geometry build with the same name cancels the previous one.
Removing/renaming/editing that object, clearing/replacing the world, stopping
the program, reloading the script, or destroying the renderer cancels pending
work. A playing imported animation's next pose also supersedes a pending
manual build for its mesh. Cancelled work never publishes later.

The engine divides work into packets; it does not impose a total mesh size
limit. Uploads adapt to observed driver time: a slow allocation reduces later
submission sizes, down to 192 vertices; fast allocations gradually restore
larger submissions, up to 12,288 vertices. Splits preserve whole triangles.
GPU allocation for one packet remains an indivisible driver operation, so
this reduces the size of later calls rather than guaranteeing a frame time.
When the host supports dynamic vertex-buffer updates, async uploads reuse
idle buffers of exactly the same vertex count. The visible buffer is never
overwritten while a replacement is being built. A renderer retains at most
one previous complete generation per mesh as spare buffers; unmatched older
spares are discarded on the next successful publication. Removing the mesh,
replacing its world, or destroying the renderer releases its spares. An update
exception discards that spare and attempts a new allocation. Older hosts
without this API keep the ordinary allocation path. Dynamic updates can still
wait inside the driver; reuse does not make a driver call interruptible.
`async:false` is supported for callers that deliberately want synchronous CPU
preparation. Ordinary `mesh` calls without `async:true` keep their existing
behavior and return an object copy if `into:` or `->` is supplied.

### Repeated mesh placements

```text
!world3d | mesh | name:Triangle | vertices:"-1,0,0;1,0,0;0,2,0" |
    triangles:"1,2,3" | visible:0 | red:80,green:190,blue:100 |+|
!var | placements | [
    {x:-3,y:0,z:-12},
    {x:0,y:0,z:-12,yaw:45,scale:1.5},
    {x:3,y:0,z:-12,width:0.5,height:2,depth:1}
] |+|
!world3d | instances | name:Group | mesh:Triangle | transforms:placements | -> | build |+|
```

Each placement accepts `x`, `y`, `z`, `yaw`, `pitch`, `roll`, `scale`, `width`,
`height`, and `depth`. Position/angles default to `0`; scale and sizes default
to `1`. Explicit axis sizes override the uniform `scale`. Sizes must be
positive. `transforms` must be a nonempty dense list of records. The source
must be an existing mesh, and the batch must have a different name.

Placements use the source's **local geometry**, UVs, diffuse texture, and color;
they ignore its object position, rotation, size, and visibility. Hide the
source if it is only a template. A batch is one normal mesh object: use `set`
to transform/color/hide the whole batch, `remove` to delete it, or submit
`instances` again to replace its placements. There is no per-placement picking,
animation, or automatic synchronization with later changes to the source.
Save/export preserve the resulting baked geometry.

The `instances` command builds portable **mesh batches**. It reduces draw
calls but duplicates geometry in memory; very large batches use several GPU
packets/draws. OBS's [public graphics API](https://github.com/obsproject/obs-studio/blob/master/libobs/graphics/graphics.h)
provides the portable buffer/draw operations used here, without a public
hardware-instanced draw entry point.

For repeated copies with independent transforms or picking, `duplicate` shares
the original mesh's immutable vertices, triangles, UVs, and GPU buffers within
the same renderer. Position, rotation, size, visibility, color, and texture
remain independent. For example:

```text
!world3d | duplicate | name:Triangle | as:SecondTriangle |+|
!world3d | set | name:SecondTriangle | x:4,y:0,z:-12 |+|
```

Vertex/triangle edits, UV changes, geometry replacement, and animation poses
detach the changed geometry; other copies retain theirs. The engine releases
a shared GPU buffer only after its last rendered owner releases it. Snapshots
and saves still contain ordinary independent object data. Duplicating a whole
batch shares that batch's geometry too. It does not remove the baked copies
inside a newly constructed `instances` batch.

### Automatic native instancing

On 64-bit Windows with OBS's Direct3D 11 backend, consecutive visible mesh
copies created by `duplicate` can be drawn with true hardware instancing.
They share one geometry buffer while each keeps its own position, rotation,
size, color, and picking identity. This requires no different script syntax:

```text
!world3d | duplicate | name:Triangle | as:TriangleTwo |+|
!world3d | set | name:TriangleTwo | x:3,y:1,z:-12,yaw:35 |+|
!world3d | stats | -> | rendering |+|
```

A group must share its vertices, triangles, UVs, and diffuse texture. Individual
tints may differ. A different object/material, hidden object, or pending upload
ends a group. Groups use up to 256 objects per draw; larger runs use further
draws without limiting scene capacity. Grouping follows scene order, preserving
the order of ordinary opaque draws. Camera roll, spotlight lighting, textured
meshes, and multipart geometry buffers are supported. Editing one copy detaches
its geometry and may split its group. Animation continues to update normally;
only meshes whose current geometry is actually shared can group. Ordinary
independently created meshes and the placements baked inside one `instances`
batch are not automatically converted into shared instances. Saving/loading or
restoring independent geometry arrays may therefore remove this optimization
without changing the saved object's appearance or behavior.

The engine compiles its native vertex shader in memory using the Windows
shader compiler available to OBS. It calls Direct3D through LuaJIT FFI, restores
the native vertex shader and constant-buffer binding after each draw, and queues
native resource releases without leaving Lua callbacks behind. No additional
distributed DLL, library package, model file, or shader file is required.
Unsupported backends, initialization failures, and failed transform-buffer
updates use ordinary rendering. Native instancing is currently implemented for
Windows/D3D11; Linux/macOS retain portable rendering.

`stats` returns the last completed render's statistics, so its values can lag
script changes until OBS renders that source. `backend` is `"pending"` before
the first completed render, `"portable"` when that render made no instanced
draws, or `"d3d11_instancing"` when it used native instancing.
`instance_draws` counts actual instanced draws (including separate mesh packets),
and `instanced_objects` counts objects drawn through them. `native_available`
is `1` when native resources have been initialized successfully; initialization
is lazy, so `0` alone does not indicate unsupported hardware. A D3D11 draw also
uses a one-vertex, triangle-free OBS draw to synchronize its state before the
native submission; `instance_draws` does not count those setup draws. These
fields describe the last redraw, not a cumulative FPS counter.
As with other GPU transform paths, floating-point rounding can change a few
edge pixels or depth ties between overlapping coplanar surfaces; avoid relying
on such depth ties for layering.

For a textured mesh, `uvs:"0,0;1,0;0,1"` supplies one `u,v` pair per vertex. Use `texture:"images/diffuse.png"` for a PNG/JPEG file, or `image:"...base64..." | mime:"image/png"` for image data embedded in the script. `texture` paths use the selected main program's folder in File mode, or the engine Lua file's folder in Text/Input mode. Embedded images are passed to OBS's image loader through a temporary file that is removed after loading; they need no extra file in the distributed project. New vertex geometry without new UVs clears the old UVs and texture.

### Camera-view textures and clipping planes

A named `view` is another camera into the **same selected world**. Bind it to
a mesh with UV coordinates to create a live screen, window, or portal surface.
It is rendered internally; it does not create another OBS source.

```text
!renderer | create | name:World | kind:3d | width:960,height:540 |+|
!world3d | box | name:Subject | x:10,y:0,z:-5 |+|
!world3d | view | name:Remote | x:10,y:0,z:0 | width:512,height:512 |+|
!world3d | mesh | name:Screen | z:-4 |
    vertices:"-1,-1,0;1,-1,0;1,1,0;-1,1,0" |
    triangles:"1,2,3;1,3,4" | uvs:"0,1;1,1;1,0;0,0" |
    view:Remote | red:255,green:255,blue:255 |+|
!world3d | view | name:Remote | yaw:15 | -> | view_info |+|
```

The view must exist before it is bound. `view:none` detaches it. A mesh can
use a camera view or an asset texture; a new binding replaces the previous
one. Geometry replacement still requires new UVs. Camera surfaces default to
`unlit:1`: their live image keeps its colors and is multiplied by the mesh's
red/green/blue tint. Use white `255,255,255` to show the unchanged image.
`unlit:0` applies the normal face shading and spotlight. This flag controls
camera surfaces; ordinary asset materials keep their existing lighting.

| View attributes | Defaults and units |
| --- | --- |
| `x`, `y`, `z`, `yaw`, `pitch`, `roll` | Position in world units and angles in degrees; all default to `0`. Same camera axes as the main camera. |
| `fov`, `near`, `far` | Vertical field of view `70` degrees, near plane `0.05`, far plane `1000`. Require `0<fov<180` and `0<near<far`. |
| `width`, `height` | Render texture size, default `512,512`; whole pixels from `1` to `8192`, subject to the graphics device's allocation limits. Independent of the main renderer's resolution. |
| `enabled` | `1` renders the view; `0` disables it and releases its render resources on the next source render. A disabled or unavailable view leaves the mesh with its ordinary untextured appearance. |
| `offcenter` | `0` uses `fov` and texture aspect ratio. `1` uses `left`, `right`, `top`, and `bottom` instead. |
| `left`, `right`, `top`, `bottom` | Bounds of an asymmetric camera frustum **at the near plane**, in camera-space world units. Defaults `-0.05,0.05,0.05,-0.05`. Require `left<right` and `bottom<top`. Right and up are positive. |
| `clip_enabled` | `0` by default; `1` enables the world-space clipping plane below. |
| `clip_x`, `clip_y`, `clip_z`, `clip_d` | Plane coefficients, default `0,0,1,0`. The normal must be nonzero when enabled. |
| `into` or `->` | Return an independent copy of the current view fields after applying any updates. |
| `delete:true` | Remove this view and detach meshes bound to it. Other cameras and objects remain. |

Clipping keeps pixels whose world position satisfies
`clip_x*x + clip_y*y + clip_z*z + clip_d >= 0`. For example:

```text
-- Keep the side y >= 2; hide surfaces below that plane in Remote only.
!world3d | view | name:Remote | clip_enabled:1 |
    clip_x:0,clip_y:1,clip_z:0,clip_d:-2 |+|
-- Restore the ordinary field-of-view projection and remove clipping.
!world3d | view | name:Remote | offcenter:0,clip_enabled:0 |+|
```

The plane is evaluated per visible pixel; it does not cut mesh data or create
faces to fill the cut. Off-center projection lets scripts align a view with
a window's corners as the observer moves. Portal placement, paired camera
transforms, collision openings, and traversal remain script logic.

Each enabled view renders the world once before the main view. **Meshes bound
to camera views are omitted from all camera-view passes**, preventing recursive
feedback; this provides one level of live views. Lower texture resolution or
disable unused views to reduce cost. Views use the previous complete mesh
while a replacement upload is pending. Parent and child render resources are
owned and released by the engine when views or renderers are removed or worlds
are replaced. `snapshot`, `restore`, `save`, `load`, and `export` preserve view
definitions and mesh bindings, not captured pixels or GPU resources.

`!world3d | stats | -> | rendering |+|` also returns `view_count` (enabled
views rendered during the most recent source render) and `view_ms` (time in
milliseconds spent submitting those view passes). It measures graphics-thread
call time, including resource setup; it is not GPU execution time. The native
instancing counters describe the main view separately.

Replace model paths below with your own OBJ, glTF, or GLB assets.

```text
!renderer | create | name:ModelView | kind:3d | width:960 | height:540 |+|
!world3d | import | path:"models/object.obj" | name:Object | x:0,y:0,z:-5 | into:loaded |+|
```

OBJ imports positions and polygon faces, including negative indices and UV seams; an adjacent `.mtl` supplies `Kd` colors and `map_Kd` diffuse textures. glTF/GLB imports the selected scene's nodes, transforms, triangle primitives, base color factors, and base color textures (external or embedded PNG/JPEG). Referenced `.bin` and image files are resolved beside the model; binary GLB and data URIs can keep assets in one file. Each imported glTF mesh instance or OBJ material group gets a GPU buffer. There is no preset vertex/triangle split or model file size, accessor count, or imported part-count cap. Import time, available memory, and graphics hardware determine what a machine can handle. Unsupported required glTF extensions and nontriangle primitives report errors.

glTF clips can animate node translation, rotation, scale, skeletal joints, and position morph targets. `STEP`, `LINEAR` (quaternion rotation uses spherical interpolation), and `CUBICSPLINE` keyframes are supported. Skinned primitives need `JOINTS_0` and `WEIGHTS_0`; up to four weights per vertex are used. Geometry is deformed on the CPU and its GPU buffer is refreshed for each new pose. Large animated models can therefore lower FPS. The renderer has simple face shading and an optional spotlight; normal/tangent morphs, normal maps, material animation, and full physically based shading are not displayed. Sparse accessors and required glTF extensions are rejected.

```text
!world3d | import | path:"models/actor.glb" | name:Actor | z:-5 |+|
!world3d | animate | name:Actor | mode:list | into:clips |+|
!world3d | animate | name:Actor | clip:Wave | mode:play | loop:true | speed:1 |+|
!world3d | animate | name:Actor | mode:pause |+|
!world3d | animate | name:Actor | mode:seek | time:0.5 |+|
!world3d | animate | name:Actor | mode:resume |+|
!world3d | animate | name:Actor | mode:stop |+|
```

The `name` in `animate` is the **import name**, even when that import created several numbered mesh objects. `clip` defaults to the first clip in the file; `mode` defaults to `play`; `loop` defaults to `true`; `speed` defaults to `1`. Time is in seconds. Clip playback advances on OBS ticks while the 4IM3 program is running. Replace `Wave` with a clip name returned by `mode:list`. Node transforms, skeletal skinning, and position morph targets are supported. The `.im3model` save and script export store the **current mesh pose**, not the glTF animation tracks; keep the original `.gltf`/`.glb` asset to play its clips after loading.

`loop` accepts `true`/`false`, `1`/`0`, or a variable/expression resolving to one
of those values. For example, `loop:repeat_clip` can use a boolean variable.
`mode:seek` applies a pose immediately and keeps the previous playing/paused
state. To drive clips with a script-owned clock, pause first, then seek each
frame using `time:clip_seconds`. Automatic playback reserves up to one quarter
of the configured tick work budget for CPU deformation, checking time between
small batches of vertices and nodes. Unfinished poses resume on later ticks;
models receive turns in rotation. All parts of a completed pose are published
together, while the previous complete pose remains visible during computation.
These time checks are cooperative, so one batch can slightly exceed its slice.

Playback time continues to advance with OBS ticks. Under load, the displayed
pose can trail that clock and refresh less often. In `mode:status`, `time` is
the playback clock, `pose_time` is the last completed pose's clip time, and
`pending:1` means pose computation is in progress (`0` otherwise). Pause or seek
discards unfinished automatic work so it cannot overwrite the requested pose.
A seek command remains immediate CPU work and cannot yield partway through
one pose. GPU uploads and drawing also cost time; scheduling does not guarantee
a particular frame rate.

Object names may be literals (`name:Wheel` or `name:"Front Wheel"`) or a parenthesized variable/expression (`name:(selected_part)`). This lets scripts create and inspect parts whose names are chosen while the script runs. For example:

```text
!world3d | list | into:parts |+|
!world3d | get | name:(selected_part) | into:part |+|
!world3d | edit | name:(selected_part) | mode:begin |+|
!world3d | vertex | name:(selected_part) | index:2 | x:0.5,y:1,z:0 |+|
!world3d | triangle | name:(selected_part) | index:append | a:1,b:2,c:4 |+|
!world3d | edit | name:(selected_part) | mode:commit |+|
!world3d | pick | x:(mouse_x) | y:(mouse_y) | into:hit |+|
```

`parts[1]` is the first name. `part.name`, `part.kind`, and `part.x` are examples of fields returned by `get`; mesh data is in `part.vertices[1][1]` (first point's x) and `part.triangles[1][1]` (first face's first vertex index). Mesh results also include `part.vertex_count` and `part.triangle_count`. `hit.found` is `1` or `0`; when found, `hit.name`, `hit.kind`, `hit.distance`, `hit.x/y/z`, `hit.triangle`, and `hit.vertex` are available. A box returns triangle and vertex `0`. `pick` expects pixels inside the selected renderer's buffer, starting at `0,0` in the top left; if the source is scaled in OBS, convert pointer coordinates before picking. An immediate `vertex` or `triangle` change must leave the entire mesh valid. Use `edit` when adding points and faces in several steps. The staged geometry does not appear until `commit`.

```text
!world3d | save | path:"C:/Models/my-car.im3model" |+|
!world3d | load | path:"C:/Models/my-car.im3model" |+|
!world3d | export | path:"C:/Models/my-car.txt" |+|
```

The script chooses each path; there is no fixed model file. A string variable also works as `path`. Relative paths use the selected main program's folder in File mode, or the engine Lua file's folder in Text/Input mode. `save` and `export` overwrite the chosen file. `load` checks the file before replacing the current world and keeps the renderer's current dimensions. Exported script names that contain punctuation or spaces are assigned safe aliases such as `ExportPart1`; `save` preserves the exact names. The engine's model format is distinct from OBJ and glTF. It preserves imported UVs and embedded images; an external texture path still needs its image file.

3D positions and box sizes use **world units**. At zero camera rotation, x points right, y points up, and objects with negative z are in front of the camera. Angles and `fov` use degrees; colors use channel values from 0 to 255. `fov` must be 1–179 degrees, `near` must be positive and smaller than `far`, and dimensions must be positive. Coordinates, sizes, import scale, and clipping distances have no arbitrary ±1,000,000/10,000 caps; finite numbers and meaningful validation still apply. The GPU uses 32-bit floating point, so very large coordinates lose precision; a floating render origin is useful for large worlds. Named fields can be reordered and grouped with commas, as with canvas commands. Multiple worlds have independent cameras and objects. The renderer supports opaque colored or diffuse-textured triangles with simple face shading and uses OBS's graphics API.

### Shader renderer

```text
!renderer | create | name:EffectView | kind:shader | width:640 | height:360 |+|
!shader | select | EffectView | path/to/my.effect | optional_texture.png |+|
```

The programmer explicitly chooses a `.effect` file with `!shader | select`. Paths can be absolute or relative to the selected main program in File mode (the engine Lua file in Text/Input mode). The texture is optional. Shader programs are external assets by choice; the pixel renderer and canvas do not need them. **These two commands alone do not display a shader:** the shader render callback also needs a world record (and any changing uniforms/overlay) supplied through an optional module. There is no core `!shader | uniform` command.

## 3D physics

`!physics` calculates collisions and rigid-body motion from ordinary copied
tables. It does not create renderer objects, change OBS sources, or add game
rules. The solver is embedded in the engine Lua file and needs no physics DLL,
module, or package. Supported shapes are oriented boxes and spheres.

```text
!var | state | {
    gravity:-9.81,
    bodies:[
        {id:1,name:"Crate",shape:"box",x:0,y:5,z:-5,width:1,height:1,depth:1,mass:2},
        {id:2,name:"Ball",shape:"sphere",x:2,y:4,z:-5,radius:0.5,mass:1}
    ],
    joints:[]
} |+|
!physics | step | state:state | seconds:(1/60) | -> | next_state |+|
```

`state:`, `seconds:`, and a result destination are required. Named fields may
be grouped or reordered. `seconds` is finite and nonnegative. `seconds:0`
validates and normalizes the data and produces poses without advancing time.
Invalid input reports a `Physics Error` and leaves the input unchanged. Each
result is independent data; subsequent edits do not modify previous states.
Fields beginning with `_` are reserved for internal work and are not retained.

### Physics state and units

Use consistent length, mass, and second units. With metres and kilograms,
the default gravity is metres per second squared, forces are newtons, and
torques are newton-metres. There is no fixed body-count capacity guarantee.

| State field | Meaning / default |
| --- | --- |
| `bodies` | Required dense list of body records. An empty list is allowed. |
| `joints` | Dense list of constraints; defaults to `[]`. |
| `gravity` | Vertical acceleration on dynamic bodies; default `-9.81`. |
| `ground` | Height of an infinite horizontal collision plane; default `0`. |
| `ground_friction`, `ground_bounce` | Ground material; defaults `0.75`, `0.08`. Friction is nonnegative; bounce is from `0` to `1`. |
| `substep` | Maximum integration step in seconds; default `1/120`. Must be positive. The requested duration is divided into equal steps no longer than this value. |
| `iterations` | Positive whole number of contact/constraint solver passes per substep; default `10`. More passes cost more work. |
| `damping` | Nonnegative linear/angular drag rate; default `0.06`. |
| `sleep`, `sleep_after` | `sleep:0` disables sleeping; otherwise supported, quiet bodies may sleep after `0.8` seconds by default. `sleep_after` is nonnegative. |
| `time`, `step_count` | Simulation seconds and completed integration substeps; defaults `0`. Returned with accumulated values. |
| `cache` | Opaque contact warm-start data returned by the solver. Pass it into the next step, or use `{}` after manually changing topology/transforms. |

| Body field | Meaning / default |
| --- | --- |
| `id` | Unique positive whole number. Defaults to the body's initial list index; explicit stable IDs are preferable when adding/removing bodies. |
| `name` | Optional renderer-object name used in the returned `poses`. Does not create or look up an OBS object. |
| `shape` | `"box"` (default) or `"sphere"`. |
| `x`, `y`, `z` | World-space **centre**, default `0,0,0`. |
| `width`, `height`, `depth` | Positive box dimensions, default `1,1,1`. For spheres, these are returned as the diameter. |
| `radius` | Positive sphere radius; default `0.5`. |
| `mass` | Positive mass for a dynamic body; `0` creates a static body. Default `1`. |
| `vx`, `vy`, `vz` | World-space linear velocity in length units per second; default `0`. |
| `wx`, `wy`, `wz` | World-space angular velocity in **radians per second**; default `0`. |
| `qx`, `qy`, `qz`, `qw` | Unit orientation quaternion. Nonzero quaternions are normalized. If `qw` is absent, the initial orientation comes from `pitch`, `yaw`, `roll`, in **degrees**, using the renderer's rotation order. |
| `pitch`, `yaw`, `roll` | Returned renderer angles in degrees. After initialization the quaternion is authoritative; changing only Euler fields on an existing quaternion does not turn the body. |
| `fx`, `fy`, `fz` | World-space force, default `0`. Persists until changed; set it to zero to stop applying it. |
| `torque_x`, `torque_y`, `torque_z` | World-space torque, default `0`. Persists until changed. |
| `friction`, `bounce` | Nonnegative friction and bounce from `0` to `1`; defaults `0.65`, `0.08`. |
| `ccd` | Spheres use swept collision checks unless `ccd:0`; `1` explicitly enables them. |
| `sleeping`, `sleep_time`, `sleep_support` | Sleeping state (`0`/`1`), accumulated quiet time, and support body ID (`0` for ground). Preserve returned values for the next step. Clear sleeping/time after manually editing a body. Applied force, moving contacts, or removal/waking of a recorded support can wake it. |
| `impact` | Greatest incoming contact speed during this call, in length units per second; reset for each step call. |

Additional copied data fields are retained, allowing scripts to attach their
own material, lifespan, or gameplay metadata. These fields do not acquire any
built-in behavior. Removing a body also requires removing its joint records.

### Joint records

Every joint requires `a` and `b`, which are body **IDs**, not list positions.
Use `b:0` to anchor the joint to the stationary world. `ax,ay,az` and
`bx,by,bz` are anchor offsets in each body's local space; for body `0`, the
second anchor is an absolute world position. All anchor components default to
`0`.

| Joint field | Meaning / default |
| --- | --- |
| `kind` | `"ball"` holds the anchors together and allows rotation. `"hinge"` also aligns the two hinge axes. `"distance"` maintains `length`. `"rope"` limits the maximum distance and can go slack. Default `"ball"`. |
| `length` | Nonnegative target/maximum distance for distance/rope joints; default `1`. |
| `axis_x`, `axis_y`, `axis_z` | First body's local hinge axis; defaults `0,0,1`. Must be nonzero. |
| `other_x`, `other_y`, `other_z` | Second body's local hinge axis, or a world axis when `b:0`; defaults to the first axis. |
| `break_force` | Positive linear reaction-force threshold; default `1e30`. Exceeding it sets `broken:1`. |
| `broken` | `1` disables the joint. A broken joint stays in the returned list. |
| `collide` | Connected bodies do not collide with each other unless `collide:1`. |

```text
!var | rope | {a:2,b:0,kind:"rope",bx:2,by:8,bz:-5,length:4} |+|
!array.push | state.joints | rope |+|
```

### Worker execution and rendering

Physics is an indivisible calculation on its caller's thread. Use a native
worker for larger worlds; the same `step` syntax is supported inside a worker
block or computation label. The computation checks worker cancellation during
substeps, broad-phase processing, and solver passes. It cannot call OBS.

```text
!worker | {
    !physics | step | state:state,seconds:(1/60) | -> | advanced |+|
    !return | advanced |+|
} | -> | simulation_job |+|
-- Keep input/camera handling in the ordinary frame loop while it runs.
!await | (simulation_job.state!="running") |+|
!if | simulation_job.state=="done" {
    !var | state | simulation_job.value |+|
    -- Create the named renderer objects separately before applying poses.
    !world3d | update | objects:state.poses |+|
} |+|
!worker | release | simulation_job |+|
```

Returned fields:

| Field | Meaning |
| --- | --- |
| `bodies`, `joints` | Advanced, normalized records. Static bodies are included. |
| `index` | Maps body ID to its current 1-based position in `bodies`. |
| `poses` | Object transforms for bodies that supplied `name`: position, Euler angles, and dimensions. Can be passed to `!world3d \| update`. No objects are created automatically. |
| `hits` | Records `{id,speed}` for bodies with incoming contact speeds above `0.8`. This is reporting data; the engine does not apply damage or fracture. |
| `stats` | `bodies`, `awake`, `sleeping`, `pairs`, `contacts`, `ccd_hits`, `substeps`, and `solve_ms`. Pair/contact/swept-hit counts accumulate across this call's substeps. `solve_ms` measures kernel wall time, including validation and copying, using the host's monotonic clock when available (Lua clock fallback); it is not rendering FPS or GPU time. |

The solver uses oriented-box separation tests, contact impulses with friction,
angular inertia, contact warm starting, and iterative joints. It is an
approximate real-time solver: deep initial overlaps, extreme size/mass ratios,
long joint chains, and large steps can cause drift or instability. Swept tests
currently cover **moving spheres** against boxes/spheres. Target translation is
included; target rotation is approximated within each substep. Fast boxes and
arbitrarily rotating shapes do not have full continuous collision detection.
There are no mesh/convex-hull colliders, cloth, fluids, joint motors, or arbitrary
constraint graphs with guaranteed stability. Use smaller substeps and measured
stress tests rather than assuming a particular body count will meet a frame
budget.

## Input and timing

The engine can poll keyboard, mouse buttons, pointer position, and focus directly. A key's `down`, `pressed`, and `released` values are numeric `1` or `0`; `pressed` is a one-poll edge, so poll every frame when you need it.

```text
!label | frame |+|
!input | key | W | w_down | w_pressed | w_released |+|
!input | mouse | left | left_down | left_pressed |+|
!input | pointer | mouse_x | mouse_y | inside |+|
!input | wheel | wheel_steps |+|
!input | focus | focused |+|
!wait | frame |+|
!jump | frame |+|
```

Use `!input | snapshot | controls | W | A | S | D | UP | MOUSE_LEFT |+|` to get one table with `focused`, `mouse_inside`, `x`, `y`, `interaction_source`, and each requested key's `KEY`, `KEY_pressed`, and `KEY_released` fields. `!input | viewport | View |+|` binds native pointer polling to that renderer: `x` and `y` then account for scaling and padding in its Interact preview, and `interaction_source` names `View` while the pointer is inside. Without a viewport binding, the Windows fallback reports main OBS window client coordinates. `!input | keys | controls | W | A | S | D |+|` samples keyboard and focus without a pointer check. Key names are normalized (for example `W`, `UP`, `ENTER`, `MOUSE_LEFT`); unknown names raise an error. A freshly focused key that was already held is blocked until released, so it does not cause a surprise press.

### Input event handlers

Register a handler once to respond to a key without writing a frame loop.
Existing polling commands and `!onpress` remain available.

```text
!var | jumps | 0 |+|
!var | position_x | 0 |+|

!input | press | SPACE | {
    !var | jumps | jumps+1 |+|
    !log | "Jump pressed" |+|
} |+|

!input | release | SPACE | {
    !log | "Jump released" |+|
} |+|

!input | hold | D | {
    !var | position_x | position_x+180*event.dt |+|
} |+|
```

The program can end after registration: handlers stay active until removed,
`!stop | all`, Execute/restart, or script unload. No label, jump, wait, OBS hotkey
binding, additional library, or manual frame loop is required for registration.
Handler bodies require `{ ... }`. They may call ordinary `!function_name`
functions, use conditionals, update existing variables, draw, and return early
with `!return`. Global labels are forbidden inside handlers, including nested
bodies; an external jump cannot enter a handler.

| Action | When the body runs |
| --- | --- |
| `press` | Once on a released-to-held transition |
| `release` | Once on a held-to-released transition, including loss of input focus |
| `hold` | Each OBS tick while held, subject to the shared execution budget |

`pressed`, `released`, and `held` are aliases. All supported input key names work,
including `W`, `ENTER`, `NUMPAD1`, and `MOUSE_LEFT`. Mouse-button handlers use the
existing preview/viewport pointer bounds and require the pointer to be inside.
Handlers retain access to the variables and selected sources at registration;
new `local` variables belong to that callback invocation. Declare shared state
before registering if callbacks should update it.

Each callback has its own `event` record:

| Field | Value |
| --- | --- |
| `key`, `kind` | Normalized key and `press`, `release`, or `hold` |
| `dt` | Elapsed OBS tick seconds; pending hold updates accumulate this time |
| `down`, `pressed`, `released`, `focused` | Numeric `1` or `0` |
| `x`, `y`, `mouse_inside` | Pointer coordinates and inside flag for mouse-button handlers; keyboard-only handlers skip pointer sampling |

The callback's `tick` also equals `event.dt`. These are cooperative callbacks on
the main thread, so rendering/source commands are allowed. They share the normal
script budget and may yield with `!wait`. Each key/action has one active body
and at most one pending invocation; repeated triggers while busy are coalesced
into that pending invocation. A released key cancels an unstarted pending hold.
Keep handlers short for prompt input. Different handlers may interleave when
they yield; the language does not guarantee a cross-handler execution order.

Registering the same normalized key/action again replaces its previous handler
and cancels its active/pending callback. Other key/actions keep their handlers.

```text
!input | off | SPACE | press |+|  -- remove only Space's press handler
!input | off | SPACE |+|          -- remove all Space handlers
!input | off | all |+|            -- remove this program's input handlers
```

`off` does not unregister `!onpress` hotkeys or disable polling. A fatal callback
error reports its body line and disables that binding; a fatal main-program
error clears the program's input handlers.

Events use the same platform input backends and focus rules as polling. The
engine samples once per OBS tick; this is not an operating-system keyboard hook,
and a complete press/release between samples may be missed. A key already held
when registered or when focus returns cannot trigger press/hold until released.
Polling and events keep independent histories, so sampling with `!input | key`
or `snapshot` does not consume the handler's press/release transition.

### Pointer, wheel, text, and focus events

These block forms are available alongside their polling forms:

```text
!input | move | {
    !log | ("Pointer: "..event.x..", "..event.y) |+|
} |+|
!input | wheel | {
    !var | zoom | zoom+event.delta |+|
} |+|
!input | text | {
    !var | player_name | player_name..event.text |+|
} |+|
!input | focus | gained | { !log | "Focus gained" |+| } |+|
!input | focus | lost | { !log | "Focus lost" |+| } |+|
```

Declare `zoom` and `player_name` before these handlers. `move` also accepts
`pointer_move` and `mouse_move`. It supplies `x,y,dx,dy` in the same coordinate
system as pointer polling, and fires only while focused and inside. The first
sample after registration, focus regain, or pointer re-entry establishes a
baseline and produces no jump. Wheel events supply signed `delta`; text events
supply `text`, including `\b` for Backspace where supported. The script still
owns text-field focus and editing. Focus accepts `gain/gained` and `lose/lost`.
Each event also has `kind`, `key`, `dt`, `focused`, and `mouse_inside`.

Pending pointer updates combine movement deltas, wheel updates add deltas,
and text updates concatenate text. Other input events keep the latest pending
invocation. Polling and handlers can both read wheel/text in the same tick;
the optional legacy copy is discarded on the next event tick if unread, so an
event-only program does not accumulate unused polling data. Continue reading
polling streams once per frame when combining the forms. Existing platform
limitations for wheel and text input still apply.

Use `!input | off | move/wheel/text |+|` (choose one action), or
`!input | off | focus | lost |+|` to remove one focus direction.
`!input | off | all |+|` removes input handlers only; worker, connection, and
other registered event handlers remain active.

### Pointer control and platform support

`!input | recenter | -> | cursor |+|` moves the pointer once to the center of
the focused, bound preview or viewport on Windows. The positional output form
`!input | recenter | cursor |+|` and the form without an output are also valid.
The returned record contains `supported` (0/1), `warped` (0/1), and `x,y` in
source pixels. `warped:1` means those coordinates are the new center; otherwise
they are the sampled pointer coordinates. No warp occurs when OBS is unfocused,
the pointer is outside the preview, or no preview/viewport is bound. Native
recentering is unavailable on Linux/macOS and in renderer Interact callbacks;
check `warped` and provide a fallback. This does not hide the system pointer.

For a centered mouse-look mode, sample input, calculate movement from the last
center to the sampled pointer, call `recenter`, then remember its returned center
for the next sample. Skip the initial movement after activating/focusing the view.
Only call it while gameplay has control. This is a single cursor movement with no
hook, clipping region, persistent capture, or extra DLL; stopping calls immediately
releases control, including on pause, Stop, reload, and shutdown.

On Windows, `!input | preview |+|` binds the pointer to the OBS main scene preview or a focused **Preview Projector** window. Its `x` and `y` are active scene canvas coordinates, and `interaction_source` is `ScenePreview` while inside. Projector coordinates account for letterboxing. It needs no Interact window. Keep OBS main preview scaling at **Scale to Window** for accurate mapping. `preview` and `viewport` replace each other when called again.

Use `!input | preview | focus |+|` to bind the preview and request keyboard focus for it on OBS's UI thread. This is useful at game startup or after a click inside the game: otherwise a previously selected zoom dropdown or source list can still react to the game's arrow keys. The request is asynchronous and does not bring OBS in front of another application. A focused Preview Projector keeps its focus. This does not disable OBS shortcuts or consume keys; keep game renderer scene items locked if arrow keys should not nudge them in OBS.

`!projector | fullscreen | monitor:0 |+|` opens OBS's current Preview Projector fullscreen on monitor index 0. The monitor attribute is optional and defaults to 0; use `monitor:1` for the next display. The projector follows OBS's current preview scene. Esc closes the projector window and returns to the main OBS preview; OBS stays open. To bind a key in a frame loop, include `F` in an input snapshot, then call `!if | keys.F_pressed == 1 { !projector | fullscreen | monitor:0 |+| } |+|`. On Windows, the command queues the request for OBS's UI thread and returns immediately; the window appears when that thread processes it. It also binds focused keyboard and scene-relative mouse input to the Preview Projector, so movement and mouse controls continue there without a separate `!input | preview` call. A Preview Projector opened through OBS's own menu is bound automatically when it gains focus. Pressing F while that projector already has focus does not open another. This command uses OBS's frontend API and requires no additional library file.

For games that use right-button drag over OBS's preview or a **Preview Projector**, call `!input | preview_menu | block |+|` after `!input | preview |+|`. On Windows, it temporarily prevents those views' right-click menus while direct mouse polling remains available. `!input | preview_menu | allow |+|` restores the original behavior. The engine also restores it when the program stops, when Execute starts a new program, and when the engine reloads. The main preview uses OBS's bundled Qt 6 widget library; Preview Projector uses a temporary Windows window subclass because OBS opens its menu directly on right-button press. Other OBS controls and non-preview projectors retain their menus. No additional file is installed. Other operating systems report an unsupported input error for `block`.

`!input | wheel | wheel_steps |+|` reads relative mouse-wheel movement while OBS has focus and the pointer is inside its main scene preview or focused Preview Projector after `!input | preview |+|`. Positive values mean wheel up; negative values mean wheel down; `0` means no new movement. Fractional values are possible on high-resolution wheels. Read it once per frame: each read consumes the accumulated movement. On Windows it uses the system DirectInput library through LuaJIT FFI, with no project DLL or Interact window. Wheel polling is not yet implemented on Linux or macOS, where this command returns `0`.

Windows polls the focused OBS main window or Preview Projector; Linux/X11 polls the focused OBS window through the system X11 library. The engine no longer has a command that opens OBS Interact. `!input | viewport | View |+|` remains available if a user manually opens that source's Interact window in OBS. The current engine has no direct macOS keyboard polling path; OBS interaction callbacks require a manually opened Interact window and have not been verified there. A window cannot receive a key while another window owns keyboard focus. `!onpress | HotkeyName | pressed_label | optional_released_label |+|` is an alternative: it registers an OBS hotkey, which the user binds in OBS Settings → Hotkeys.

| Input action | Fields after action | Output |
| --- | --- | --- |
| `key` | `key_name \| down_var \| [pressed_var] \| [released_var]` | Numeric key state. |
| `mouse` | `left/right/middle/x1/x2 \| down_var \| [pressed_var] \| [released_var]` | Numeric button state. |
| `pointer` | `x_var \| y_var \| inside_var` | Renderer-local pointer position and inside flag; outside positions are `-1`. |
| `wheel` | `steps_var` | Relative wheel steps on Windows while the pointer is inside the main scene preview or focused Preview Projector. |
| `focus` | `focused_var` | Numeric focus flag. |
| `snapshot` | `table_var \| key_name...` | One table with focus, pointer, and requested key/button states. |
| `keys` | `table_var \| key_name...` | Focus and keyboard states without pointer polling. Mouse keys are rejected. |
| `viewport` | `renderer_source_name` | Map native mouse coordinates in that source's Interact preview to renderer pixels. |
| `preview` | optional `focus` | On Windows, map mouse coordinates in the main scene preview or focused Preview Projector to scene pixels. `focus` also requests keyboard focus for the preview. |
| `recenter` | optional output variable, or `->` output | One focused pointer movement to the bound preview/viewport center; returns `supported`, `warped`, `x`, `y`. |
| `preview_menu` | `block` or `allow` | On Windows, suppress or restore right-click menus in the main preview and Preview Projector for a running game. |
| `text` | `output_var` | Text typed since the previous read; backspace is returned as `\b`. Empty string means no new text. |

Accepted key names are `A`–`Z`, `0`–`9`, `NUMPAD0`–`NUMPAD9`, `NUMPAD_DECIMAL`, `NUMPAD_ADD`, `NUMPAD_SUBTRACT`, `NUMPAD_MULTIPLY`, `NUMPAD_DIVIDE`, `NUMPAD_SEPARATOR`, `F1`–`F12`, `UP`, `DOWN`, `LEFT`, `RIGHT`, `HOME`, `DELETE`, `ENTER`, `SPACE`, `ESCAPE`, `TAB`, `BACKSPACE`, `SHIFT`, `CTRL`, `ALT`, `MOUSE_LEFT`, `MOUSE_RIGHT`, `MOUSE_MIDDLE`, `MOUSE_X1`, and `MOUSE_X2`. Aliases include `RETURN`, `ESC`, `CONTROL`, `DEL` (for `DELETE`), `MOUSE1`–`MOUSE3`, `KP_0`–`KP_9`, and `NUMPAD_0`–`NUMPAD_9`. `ENTER` accepts either Enter key; `KP_ENTER` and `NUMPAD_ENTER` are aliases for it. Number-row keys and named keypad digits remain separate when polling.

```text
!input | keys | controls | NUMPAD1 | NUMPAD_DECIMAL | ENTER |+|
!if | controls.NUMPAD1_pressed == 1 { !log | "Keypad 1 pressed" |+| } |+|
!input | text | typed |+|
```

Text input accepts keypad digits, decimal point, and `+ - * /` (plus a keypad separator where provided). On Windows, turn **Num Lock on** to type digits; Num Lock off retains the operating system's navigation behavior. The Linux X11 fallback uses XKB to distinguish numeric text from keypad navigation with Num Lock/Shift. Keypad Enter submits through `ENTER` rather than inserting a character. These mappings follow [Windows virtual-key codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes) and [X11 keyboard symbol lookup](https://www.x.org/releases/current/doc/libX11/XKB/xkblib.html).

For naming parts or files, call `!input | text | typed |+|` once per frame and append `typed` to your editor's own text field. The command returns printable UTF-8 from OBS interaction events where available. Its Windows and Linux polling fallback supports US keyboard letters, numbers, spaces, common punctuation, Shift, and Backspace, one character per key press; it does not implement key repeat or full IME text composition. Control/Alt combinations are ignored. The script decides how to handle `\b`, Enter, and on-screen focus. On Linux/X11, keep an OBS window focused; other Linux sessions and macOS still require a working Interact event path.

For music timing, `!media | Music | restart |+|` starts a media source, `!media_wait | Music | 12.5s |+|` waits until an **absolute** playhead position, and `!media_time | Music | playhead_ms |+|` reads the current position. Absolute cues avoid drift from chains of relative waits. `!wait | frame` yields until the next OBS tick and updates `tick`; `!wait | 500ms` waits for a duration. Drawing code should normally use `frame`, then multiply speed by `tick`.

## Event handlers

In addition to input, workers, connections, animation, mesh publication, variable
changes, and OBS-source collisions accept `{ ... }` callbacks. Registration
does not execute the body. The engine schedules callbacks on OBS ticks, without
a user frame loop. Existing polling commands, label callbacks, and `!await`
remain available.

Callbacks run cooperatively on the main thread under the shared script budget.
State observers sample on OBS ticks; several changes between samples can be
coalesced into one observed change.
OBS source changes and drawing are allowed; a callback does not create a native
thread. Variables and selected sources from registration remain accessible.
Declare shared variables first. `event` is local to each invocation, `event.dt`
and `tick` contain elapsed tick seconds, and `!return` exits that invocation.
Bodies may call user functions and yield. Keep them short for prompt delivery.
Global labels are forbidden inside event bodies, including nested bodies.
Errors report the body line and disable the failing binding.

### Worker results

```text
!var | total | 0 |+|
!worker | done | calculation | {
    !var | total | event.value |+|
} |+|
!worker | error | calculation | { !log | event.error |+| } |+|
!worker | cancelled | calculation | { !log | "Cancelled" |+| } |+|
!worker | (21*2) | -> | calculation |+|
```

Register before or after starting a job. The selector is its result variable
or legacy job name; field paths such as `jobs.terrain` also work for result
records. `done`, `error`, and `cancelled` match their terminal states;
`finished` matches any terminal state. The event has `name`, `state`, `value`,
`error`, and `status` (the result record). A finished job fires once per binding;
starting another job into the same variable rearms the handler. This does not
automatically release the job; the existing ownership/cleanup rules still apply.
For legacy job-name selectors, keep the job until its callback has observed the
result. Releasing a legacy job first removes the record that would be observed.

### Connection events

```text
!connection | connected | name:game | { !log | "Opponent joined" |+| } |+|
!connection | message | name:game | {
    !log | event.text |+|
    -- Structured messages are available in event.data.
} |+|
!connection | disconnected | name:game | { !log | "Opponent left" |+| } |+|
!connection | error | name:game | { !log | event.text |+| } |+|
```

Register before or after `host/join`. `connected` and `disconnected` are readable
aliases for the inbox's authenticated `join` and normal `leave` events. Connection
failures are `error` events. The callback receives the existing packet fields
`available,event,peer,address,text,data`, plus `kind,name,dt`. `!network` supports
the same forms for its endpoints; `!websocket` remains an alias of `!connection`.
`!connection` handlers only accept events from WebSocket endpoints.

Handlers and `receive` share one inbox: each packet goes to one consumer.
Messages for a binding stay queued while its previous callback runs. Unhandled
event types remain available to `receive`, and their relative order is preserved.
Do not also manually receive the same message type if its handler should process
every packet. Existing queue, admission, byte/rate, and transport security checks
still apply. Malformed structured data becomes an error event when read and is
never run as code. Unmatched queued messages are not decoded merely to look for
other event types. Registering handlers alone opens no socket.

### Mesh readiness and animation completion

```text
!world3d | prepared | terrain_mesh | { !log | "Mesh prepared" |+| } |+|
!world3d | ready | terrain_mesh | { !log | "Mesh uploaded to GPU" |+| } |+|
!world3d | error | terrain_mesh | { !log | event.error |+| } |+|
!world3d | cancelled | terrain_mesh | { !log | "Mesh cancelled" |+| } |+|
-- Start mesh/instances with async:true and into:terrain_mesh.

!animation | done | name:flash | { !log | "Sprite animation finished" |+| } |+|
!world3d | animation_done | name:Actor | { !log | event.clip |+| } |+|
```

Mesh selectors reference the `into` status record. `prepared` means CPU
preparation finished and publication was queued. `ready` additionally requires
`uploaded:1` after actual GPU upload; preparation alone never fires it. A hidden
or undrawn renderer may therefore delay `ready`. Events have `name,state,status`
and `error`; a fresh status record rearms the binding. Cancellation does not
produce a ready event.

Animation selectors are animation/model names. Sprite `done` fires when a
non-looping `draw` reaches its duration; the script still supplies draw time.
Drawing the final frame again does not repeat it. Drawing an earlier time rearms
it. Looping sequences do not fire `done`.
For imported 3D animation, `animation_done` fires after natural non-looping
completion **and publication of the final complete pose**. Pause, stop, and loop
wrapping do not count as completion. These events contain `name,clip,time,sequence`.
The selected 3D renderer is captured at registration. Completion handlers can
observe an already completed sequence once; register before playback to observe
only subsequent completions.

### Variable changes and collision blocks

```text
!var | health | 100 |+|
!change | health | {
    !log | ("Health: "..event.old_value.." -> "..event.value) |+|
} |+|
!change | health | < | 20 | { !log | "Low health" |+| } |+|

!collision | PlayerSource | WallSource | {
    !log | ("Hit "..event.other_name) |+|
} |+|
```

Change events fire when the selected value changes, not at registration. Optional
comparisons are checked after a change, using the new value. Supported operators
are `==`, `!=`, `~=`, `<`, `>`, `<=`, `>=`. The event contains `name,old_value,
new_value,value`; `new_value` and `value` are the same. Watch a specific field
such as `player.health` to observe table contents; watching a table itself
detects replacement, not every mutation. Different conditions on one variable
can coexist. Pending updates retain the earliest old value and newest new value.

Collision blocks use the existing **2D OBS-source bounds** collision system,
including its source/template groups. They do not subscribe to `!physics`'s 3D
contact list. The event contains `source,other,source_name,other_name,pair`;
`_collider` and `_collided_with` are also available. The colliding source is
selected for source commands in the callback. Persistent overlap fires once,
then rearms when the pair separates. Distinct contact pairs are queued in order;
repeated pending enters for one pair are coalesced while its callback is busy.
Existing label-based `!change` and `!collision` forms continue to work.

### Handler replacement and cleanup

One binding is kept for each family/selector/event (and each variable condition).
Registering that binding again replaces it and cancels its active/pending work.
Most non-network events keep one active and one coalesced pending callback.
Connection packets stay in their bounded inbox until their binding can run;
collision pairs have separate pending entries. Different callbacks may interleave
when they yield; no cross-handler execution order is guaranteed.

```text
!events | off | worker | calculation | done |+|
!events | off | connection | game | message |+|
!events | off | world3d | terrain_mesh |+|
!events | off | change | health |+|
!events | off | collision | PlayerSource | WallSource |+|
!events | off | collision |+|
!events | off | all |+|
```

Families are `input`, `worker`, `connection`, `world3d`, `animation`, `change`,
and `collision`. The selector and event kind are optional. Use normalized keys
and kinds in this general cleanup form (`join/leave` for connection aliases).
For a specific collision binding, supply its two source selectors instead.
`!input | off` is a shortcut for removing input handlers. `!events | off` removes
block handlers only, leaving older label listeners and OBS hotkeys unchanged.
Stopping all script work, Execute/restart, fatal main-program failure, and unload
clear all block handlers. Registered handlers keep the program alive after its
main statements end, including its open connections.

Runnable syntax examples are in `examples/event-handlers/`: `main.txt` combines
input, worker, and variable events; `mesh.txt`, `animation.txt`, `collision.txt`,
and `connection-host.txt` / `connection-guest.txt` demonstrate the other forms.

## Sources and OBS

`!use_sources` selects one or more **direct items in the active scene** by exact name. Subsequent source methods and movement/effect commands apply to that selection. Missing names produce an error containing the active scene name. An empty `!use_sources |+|` restores the original source selection. `!source` is the older alias.

```text
!use_sources | Player |+|
!pos | x:100,y:200 |+|
!rot | 15 |+|
!show |+|
!move | x:400,y:200 | 500ms | quad_out |+|
```

Source methods include `!pos`, `!scale`, `!rot`, `!align`, `!bounds`, `!size`, `!width`, `!height`, `!crop`, `!order`, `!top`, `!up`, `!down`, `!ground`, `!show`, `!hide`, `!text`, `!opacity`, `!style.color`, `!style.bg_color`, `!style.size`, `!style.face`, and `!rename`. These are methods of the selected OBS source, so not every method is meaningful for every source type. `!pos | x:...,y:... |+|` and similar dictionary calls allow comma-grouped fields. OBS scene coordinates can be much larger than pixel-buffer coordinates. For text sources, `!text | "HELLO" |+|` edits the OBS text source; `!canvas | text` draws the engine's small bitmap font instead.

| Source method group | What it changes |
| --- | --- |
| `pos`, `scale`, `rot`, `align`, `bounds`, `size`, `width`, `height`, `crop`, `transform` | Scene-item transform, dimensions, or crop. `pos`/`scale` use `x,y`; `size` accepts `width,height`; `crop` uses `left,right,top,bottom`. |
| `order`, `top`, `up`, `down`, `ground` | Layer order in the scene. |
| `show`, `hide`, `isHidden`, `bounding` | Visibility and bounds-related methods. Despite its name, the current `isHidden` wrapper returns OBS's **visible** flag; check it accordingly. |
| `text`, `rename` | OBS source text or name. |
| `opacity`, `style.color`, `style.bg_color`, `style.bg_opacity`, `style.opacity`, `style.size`, `style.face` | Color-filter or text-source styling. |
| `style.grad.enable`, `style.grad.disable`, `style.grad.dir`, `style.grad.color`, `style.grad.opacity` | Text-source gradient settings. |

Some styling methods rely on source-specific OBS settings and may have no visible effect on other source types. For animations across several scene items, select several names with one `!use_sources` call; a compatible method is then applied to each.

`!renderer | create` is the exception to manual source setup for graphics: it creates a named direct renderer item if absent and checks its type if present. Other OBS sources used by name must already exist unless a script explicitly clones/creates them through supported operations.

## Tasks and workers

Two kinds of concurrent-looking work are available:

| Kind | Syntax | What runs where |
| --- | --- | --- |
| Cooperative task | `!start_task \| label_or_{block} \|+\|` or `!start_independent_task \| label_or_{block} \| -> \| task_name \|+\|` | Commands are scheduled across OBS ticks on the script/main thread. They may read or change OBS sources. The independent form starts with a new context and no selected source. |
| Native worker | `!worker \| (expression) \| result_name \|+\|`, `!worker \| { ... } \| result_name \|+\|`, or `!worker \| computation_label \| result_name \|+\|` | An isolated LuaJIT computation runs on an OS thread. It gets copied data and cannot manipulate OBS sources. |

`!await | task_name |+|` waits for a cooperative task; `!await | (condition) |+|` waits for a condition. `!stop | task_name |+|` cancels matching tasks; `!stop | all |+|` stops script work and native workers. The older `!run` and `!spawn` are aliases for the two cooperative forms. `!attach` starts a task bound to a source. These are **not** native threads.

A native worker writes a result table to `result_name`; check `result_name.state` for `running`, `done`, `error`, or cancellation before using its value. Work is bounded and its input is copied. `!worker | read | job | result_table |+|` takes a nonblocking snapshot of a legacy `start` job. Use `cancel`, `release`, or the scoped cleanup commands below to manage jobs. Built-in legacy computations include `sum` and grid `path`. OBS operations belong on the main thread. Workers use the platform's native thread facilities through LuaJIT FFI, without a project-specific DLL.

### Returning copied data from workers

The script form's `!return` accepts a finite number, string, boolean, or table.
Tables may contain nested lists and records with string or integer keys and
these same value types. Define a table with `!var`, fill it with worker commands,
then return its variable name. `job.value` contains the copied result after
`job.state` becomes `"done"`.

```text
!var | samples | [2,3,4] |+|
!worker | {
    !var | table result | [] |+|
    !var | i | 1 |+|
    !label | next_sample |+|
    !array.push | result | samples[i]*samples[i] |+|
    !var | i | i+1 |+|
    !if | i<=3 | next_sample |+|
    !return | result |+|
} | -> | squares |+|
!await | (squares.state!="running") |+|
!if | squares.state=="done" {
    !var | squared_values | squares.value |+|
} |+|
!worker | release | squares |+|
```

Inputs are copied at launch; only root variables referenced by the reachable
worker expressions are included. Unrelated large scene tables are not copied.
The worker cannot call main-script functions or read later changes to its inputs.
Returned data is copied back through a typed binary format, never evaluated as
code. No Lua state pointers or shared mutable tables cross the thread boundary.
Changing a returned table cannot alter the worker's former input or another job.

Workers can also write fields and indexed entries in their **copied tables**:

```text
!var | objects | [{x:2,y:0},{x:4,y:0}] |+|
!worker | {
    !var | index | 2 |+|
    !var | objects[index].x | objects[index].x+10 |+|
    !var | result | {} |+|
    !var | result.objects | objects |+|
    !var | result.count | 2 |+|
    !return | result |+|
} | -> | movement |+|
!await | (movement.state!="running") |+|
!if | movement.state=="done" {
    !var | objects | movement.value.objects |+|
} |+|
!worker | release | movement |+|
```

`!var | record.field | value`, `!var | list[index] | value`, and nested paths
such as `objects[indices[i]].x` work inside worker blocks and computation labels.
`!array.push` also accepts nested destinations:

```text
!var | units | [{orders:[]}] |+|
!worker | {
    !array.push | units[1].orders | 42 |+|
    !return | units |+|
} | -> | queued |+|
```

Every intermediate table must already exist; create one with `!var | name | {}`
or `!var | record.child | {}` before writing its children. Dot fields use literal
field names. Bracket keys use the worker's arithmetic expressions and must return
a string or finite integer. Paths allow up to 16 levels. An existing table used
only as a nested assignment or append destination is still copied at launch.
These writes affect only that
worker's isolated data; they never change the caller's variables automatically.
The worker's built-in `math` table is read-only, including through aliases.
Missing intermediate tables or invalid runtime keys fail the job with
`state:"error"`; inspect `job.error`. Existing worker arithmetic, command,
instruction and copied-data limits still apply.

Inputs allow at most 6 nested table levels, 524288 inspected values/keys, and
4 MiB of serialized worker payload (including program metadata). This replaces
the older 256 KiB / 16384-value input allowance. Capture still happens during
the launch command and can exceed its tick budget for large states. Repeated
field/value literals are cached only within that fresh capture; no live values
are reused across launches.

Results permit at most 16 nested table levels and 4 MiB of encoded data per
script job. Cycles, functions, unsupported keys, and non-finite numbers fail the
job with `state:"error"`; inspect `job.error`. Cancellation is checked during
computation and large result encoding. Large results also take main-thread time
to decode, so divide work into manageable jobs when responsiveness matters.

This 4 MiB value is the encoded-result limit, not a per-job reservation.
Numeric scalar results need no transfer buffer. Other results start with
1 KiB of worker-owned storage, which grows as needed. Dense numeric arrays
use a compact binary representation and are decoded in bounded blocks;
scripts still receive ordinary copied tables. Encoding writes directly into
native storage, avoiding an additional full-result string and copy. The
storage stays owned by its runtime until decoding finishes or cancellation
discards it, then its ownership is released.

During a running program, worker-result decoding and asynchronous mesh
preparation run after foreground commands and collision processing. A small
slice is reserved for pending background work, and the first background
consumer alternates each tick. Both use the same overall script tick budget.
An `!await` or frame wait leaves more time for these jobs; worker results and
meshes become visible only after their complete result is published.

### Worker preparation and input copies

Validated label programs are cached, including their branch structure and input
requirements. Statically named label jobs are prepared after program compilation,
before gameplay executes; inline blocks are cached when first reached. A cache
stores code metadata, not live scope values or worker results.
Changed compiled steps or label targets invalidate the label cache. Execute/reload
creates fresh program caches. Cache eviction can require preparation again and
does not limit how many different computations a program may use.

The engine compiles its built-in worker bootstrap once in memory and keeps
up to four isolated LuaJIT runtimes per running program. A runtime is reused
only after its previous OS thread has joined and its result has been fully
decoded or discarded. Each invocation has fresh copied inputs, job variables,
expression environments, and result storage. No job can enter a runtime while
another job or its decoder owns it. Each launch still creates a new OS thread;
the pool avoids rebuilding the LuaJIT state and callback on repeated launches.
Program-wide worker cleanup, Stop, Execute, reload, and unload close these
runtimes after joining their jobs. Scoped cleanup leaves idle runtimes
available to the rest of the same program. This adds no runtime files or
dependencies.

Every actual launch still captures **fresh copied inputs during that command**.
Input analysis follows branches and loops: a variable whose old value is
overwritten before every possible read does not need to be copied. A variable
read before assignment on even one possible path remains an input. Scope lookup
selects the currently visible value, including `false`, rather than copying
shadowed parent values too. Existing alias variables and intermediate indexes
continue working.

Program compilation may take more time up front, while repeated launches avoid
rebuilding the same program. Input copying, a cold runtime, OS thread creation,
and result decoding still have a cost. One command can still exceed the script tick budget; this
optimization does not make native startup preemptible or guarantee a frame rate.

### Repeating a worker start

Reaching the same worker start command again, such as through `!jump`, uses
the job name to decide what to do:

| Existing job with that name | Behavior |
| --- | --- |
| Running, including cancellation still in progress | Skip the repeated start without an error or a wait. Keep the original job, copied inputs, and live result table. The short form binds that same result table in the current caller's scope. |
| Done, failed, or cancelled | Start a fresh computation with the current inputs. The short form assigns a new result table with `state:"running"`. |
| No job, or previously released | Start a new job. |

This applies to expression, block, and computation-label forms, with either
positional or `->` destinations, and to `!worker | start`. It does not queue
another run. New inputs supplied during an active job are ignored; reach the
start command after completion to use updated inputs. Completion is recognized
when the engine polls the worker; a repeat before that poll is still skipped.
Different job names remain independent, subject to the worker limits.

`read`, `cancel`, `release`, and `clear` retain their normal behavior. To inspect
a result without starting another computation:

```text
!worker | read | calculation | -> | result |+|
```

### Worker ownership and cleanup

Each newly launched job belongs to the execution scope that created it:

- Each function invocation has a separate owner, including recursive or repeated
  calls to the same function.
- Each cooperative task has its own owner. A function called by that task has
  a separate invocation owner.
- Synchronous loop blocks inherit their caller's owner; a function invoked
  inside such a block gets its own owner.
- Commands in the main program belong to the main execution scope.

```text
!worker | clear | scope |+|    -- stop and remove this owner's jobs
!worker | clear | program |+|  -- stop and remove every job in this program
!worker | release | calculation |+| -- cancel/discard one named job
```

`clear | scope` affects only directly owned jobs, including finished results
retained for that owner. It does not affect a parent, child function, sibling
invocation, or separate task. `clear | program` affects every owner in the
current program. `clear | all` and `stop_all` remain program-wide compatibility
forms; use `scope` or `program` to make new code's intent explicit.

Cleanup requests cancellation of all selected jobs before joining and releasing
them. Results already finished remain finished; jobs that process cancellation
report `state:"cancelled"`. Retained result-table references are updated before
the jobs are removed, so they do not remain stuck at `state:"running"`.
Cleanup does not wait for unrelated owners' jobs. `cancel | name` requests
cancellation without removing the job; `release | name` discards that named job
when it is safe. `cancel | all` and `release | all` remain program-wide.

Job names remain unique within the program; ownership does not create a new
name namespace. If another scope reaches a start with the same running name,
it borrows the existing result table without taking ownership. Its own
`clear | scope` therefore cannot remove the creator's job. Once that job has
finished, a new start replaces it and belongs to the new creator.

```text
!fn | square_async | n | {
    !worker | (n * n) | -> | square_job |+|
    !return | square_job |+|
} |+|

!square_async | 3 | -> | first |+|
!square_async | 4 | -> | second |+|
```

When the second call happens while `square_job` is running, `first` and `second`
refer to the same live result table. The second call does not change its copied
input or restart it. If the first job has already been completed and polled,
the second call starts a new job instead.

Returning from a function or finishing a cooperative task does not automatically
cancel its workers. Returned result tables can continue receiving updates while
the program runs. To clean up before returning, call `clear | scope` inside
that invocation. To release a returned job later, use its original job name, or
use `clear | program` for a complete reset. Keep the program running with a
frame loop or wait while asynchronous results are needed. Stop, reload,
program completion and shutdown clean up all program workers.

Within a worker block/label, the supported commands are `!var`, `!array.push`, `!if` (label form), `!jump`, `!label`, and a required reachable `!return`. Pure worker expressions are bounded arithmetic/comparisons, not arbitrary Lua. A worker label may contain at most 1,024 reachable commands and execute at most 1,000,000 interpreted steps per run. The engine allows up to four running and eight retained jobs; copied input is capped at 256 KiB (up to 16,384 inspected values, six nested table levels, and 64 KiB per string). Result states are `running`, `done`, `error`, and `cancelled` (double **l**). Release finished jobs when you no longer need them.

Input values are captured completely at launch, using one validation/encoding
pass. Later writes in the main program cannot change that worker's input.
Capturing and starting a worker still cost main-thread time. Large returned
tables are decoded directly from the worker's owned binary buffer in small
slices within the tick budget. The job stays `running` until the whole result
is ready; scripts never see a partially decoded `value`. Cancellation during
decoding discards that result and releases its native storage. Existing
`!await`, `read`, cancellation, and automatic-result syntax remain unchanged.

Worker result/status records also expose these numeric profiling fields. They
do not change the worker's returned `value`:

| Field | Meaning |
| --- | --- |
| `launch_ms` | Main-thread duration of the launch command, including program preparation, input capture/encoding and native startup. Available immediately on automatic-result records. |
| `startup_ms` | Native launch/setup portion of `launch_ms`. |
| `capture_ms` | Input validation/encoding and payload construction portion of `launch_ms`; zero for built-in numeric/path jobs. |
| `decode_ms`, `decode_peak_ms` | Accumulated main-thread result decoding time and longest individual decoding step. Updated while a large automatic result is decoded. |
| `elapsed_ms` | Wall time from launch command to result delivery or cancellation, including worker execution, scheduling, and decoding. This is not isolated worker CPU time. |
| `input_bytes`, `output_bytes` | Encoded input payload/map bytes and binary result bytes. Built-in numeric/path results do not use the binary table format. |
| `result_capacity_bytes` | Final native result-buffer capacity; `0` for numeric scalar results. Available on the delivered result, including errors/cancellation. |
| `runtime_reused` | `1` when launch rented an existing idle LuaJIT runtime, otherwise `0`. This does not mean the OS thread was reused. |

Finished records returned by `read` contain these fields too. Timings use the
engine's monotonic clock where available, with its existing process-clock
fallback. A peak step is not the sum of all work performed in one video frame.
For example:

```text
!var | amount | 10 |+|
!worker | (amount*2) | -> | job |+|
!await | job.state!="running" |+|
!var | launch_cost | job.launch_ms |+|
!var | decode_cost | job.decode_ms |+|
!worker | release | job |+|
```

<a id="dedicated-websocket-messaging"></a>

## Connection messaging

`!connection` creates a dedicated encrypted game messaging channel. It does not
connect to OBS's remote-control WebSocket service, use its password, or expose
scene/streaming controls. Received messages are data; they are not executed as
commands. No external lobby account, helper process, or project DLL is required.

`!websocket` remains an alias for existing scripts. `!network` remains available
for the older TCP API; it has not been removed or renamed. New scripts can use
`!connection` with the commands below. The underlying WebSocket protocol and
private invitation format are unchanged.

### Host and join with one private code

```text
-- Host computer:
!connection | addresses | into:lan |+|
!if | lan.ok == 0 { !log | lan.error |+| !stop | all |+| } |+|
!connection | host | name:game,port:7779 |+|
!connection | invite | name:game,address:lan.address,into:private_code |+|
!clipboard | copy | text:private_code,into:copied |+|

-- Guest computer: use these instead of the host lines.
-- !clipboard | paste | into:pasted |+|
-- !connection | join | name:game,invite:pasted.text |+|

!label | messages |+|
!connection | receive | name:game,into:packet |+|
!if | packet.event == "join" {
    !connection | send | name:game,text:"Welcome!" |+|
} |+|
!wait | frame |+|
!jump | messages |+|
```

Share the host's code privately. Complete codes begin with `IM3WSS1-` and use at
most 152 characters. They carry the host IPv4 address, listening port,
certificate pin, and random invitation secret. Players can use one hidden code
field; the engine handles the endpoint details. The address is encoded, not
encrypted inside the code. Anyone holding the code can attempt to join. Closing
and recreating the host invalidates its old credentials. Generate a new code
when switching from the older TCP transport.

Keep a frame loop or registered event handler alive: socket work runs on OBS
ticks, and `receive` pops one queued event without waiting. Program completion
(no remaining main work, tasks, or block handlers) closes its connections.

### Connection commands

Put the action first. Named attributes accept variables/expressions and can be
grouped with commas or separated by `|`, in any order.

| Action | Attributes | Behavior |
| --- | --- | --- |
| `addresses` | required `into` | Detect active local IPv4 interfaces; returns `{ok,address,count,candidates,error}`. |
| `host` | required `name`, `port`; optional `address` and protection settings | Listen on all IPv4 interfaces by default. Port `0` requests a free port. Creates fresh pinned TLS credentials. |
| `invite` | required `name`, `into`; optional `address` | With an address, return a complete private code using the actual listening port. Without one, return the underlying TLS token; complete codes are recommended. Never prints it. |
| `decode` | required `invite`, `into` | Inspect a complete code without connecting. Returns `{ok,address,port,transport,error}`, without the secret. Older TCP codes are rejected. |
| `join` | required `name`, `invite`; optional `timeout` and protection settings | Start a nonblocking connection. A complete code supplies the endpoint internally. Connect timeout defaults to `10000` ms. |
| `send` | required `name` and exactly one of `text` / `data`; optional `peer`, `into` | Queue a string or JSON-compatible value. Host broadcasts unless a peer is specified. Optional result reports `{ok,error,recipients}`; success means queued, not acknowledged. |
| `receive` | required `name`, `into` | Pop one event/message using the same event tables as `!network`. |
| `status` | required `name`, `into` | Read state, peers, errors and counters. `transport` is `"websocket"`; status never reveals the invitation. |
| `close` | required `name`; optional `peer` | Immediately close an endpoint or one peer. `name:all` closes this program's WebSocket endpoints. Does not wait for delivery. |
| `configure` | optional `budget` | Shared socket work slice per OBS tick in milliseconds; default `1`. Also respects the script deadline. |

Examples of application messages:

```text
!connection | send | name:game,data:{kind:"move",square:12} |+|
!connection | send | name:game,text:"hello",into:sent |+|
!connection | status | name:game,into:connection |+|
!connection | close | name:game |+|
```

Names identify endpoints within one program; close an active name before reuse.
Addresses accept numeric IPv4 or `localhost`, not DNS names or IPv6. The
[networking attributes and protection settings](#commands-and-attributes)
below are shared, including message, buffer, queue, admission, rate and timeout
limits. WebSocket requires TLS; `security:plain` is rejected. Its per-peer
`buffer_limit` must be `0` (disabled) or at least 1024 bytes. HTTP upgrade headers
are limited to 8192 bytes, or the smaller configured buffer limit.

Peer phases are `tcp`, `tls`, `websocket`, `invitation`, then `connected`.
The initial TCP connection has its own timeout; the handshake deadline starts
after it connects and covers TLS, WebSocket upgrade, and invitation verification.
Incomplete messages have a read deadline. Buffer accounting includes fragments
and their metadata; control frames are also subject to rate protection.

### Protocol, security and portability

This is a dedicated [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455.html)
profile: TLS (`wss`), HTTP path `/4im3`, subprotocol `4im3.messages.v1`, client
masking, fragmented messages, Ping/Pong, Close, and UTF-8 checks for text/close
reasons. Compression/extensions are not negotiated. Binary messages use a
one-byte application tag: `A` plus the raw 32-byte invitation secret, `K` for
authentication acknowledgement, `T` plus string bytes, or `J` plus JSON
`{"data":...}`. Application join events/messages are released only after private
authentication succeeds. The SHA-1 accept hash required by RFC 6455 is used
only for the public HTTP upgrade; certificate pinning uses SHA-256.

TLS 1.2 ECDHE/AES-GCM, certificate pinning and the random 256-bit secret use the
existing native TLS provider: built-in Schannel/CNG on Windows, or an already
installed compatible OpenSSL 1.1.1/3 on Linux/macOS. Unavailable TLS fails closed.
No OBS password is shared. A standard WebSocket client must implement this
application profile and pin verification; browser certificate trust is not
automatically configured.

A received Close is echoed with a bounded close period. Explicit close, Stop,
reload, and shutdown release owned sockets/TLS resources without waiting for
the remote machine. These protections do not guarantee immunity to every attack
or internet bandwidth floods.

**Network reachability is still required.** WebSocket uses TCP underneath; it
does not relay traffic, discover internet lobbies, traverse NAT, bypass a
firewall, or repair device isolation. A private code simplifies entry but does
not make an unreachable host reachable. The engine handles transport and
authentication; scripts define their message formats and synchronization rules.

The older `!network` API remains available for existing programs. `!connection`
adds a real HTTP upgrade and WebSocket framing over the shared native socket/TLS
and lifecycle implementation.

## TCP networking

`!network` provides generic TCP host/client connections through LuaJIT FFI:
Winsock on Windows, POSIX sockets on Linux/macOS. **Connections use encrypted,
invitation-authenticated TLS by default.** No project DLL, Python process,
networking package, or OBS WebSocket connection is required.

Windows uses its built-in Schannel/CNG APIs. Linux/macOS use an already
installed OpenSSL 1.1.1/3 library discoverable by the system loader. If a
compatible provider is unavailable, the connection reports an error and stays
closed; it never silently falls back to plaintext.

### Host, invite, join

```text
-- On the host computer:
!network | addresses | into:lan |+|
!if | lan.ok == 0 { !log | lan.error |+| !stop | all |+| } |+|
!network | host | name:game,address:"0.0.0.0",port:7777 |+|
!network | invite | name:game,address:lan.address,into:invitation |+|
!clipboard | copy | text:invitation,into:copied |+|

-- On the guest computer instead of the host lines:
-- !clipboard | paste | into:pasted |+|
-- !network | join | name:game,invite:pasted.text |+|

!label | frame |+|
!network | receive | name:game,into:packet |+|
!if | packet.event == "join" {
    !network | send | name:game,peer:packet.peer,text:"Welcome!" |+|
} |+|
!if | packet.event == "message" { !log | packet.text |+| } |+|
!if | packet.event == "error" { !log | packet.text |+| } |+|
!wait | frame |+|
!jump | frame |+|
```

Share the host's **private invitation** with the intended guest through a trusted
channel, then copy it on the guest's computer before joining. With `address`
on `invite`, the engine produces a **complete private connection code**:
`IM3JOIN1-<8 hex IPv4 digits>-<port>-<64 hex fingerprint>-<64 hex secret>`.
The guest supplies only `name` and `invite`; the engine decodes the endpoint
internally. Players do not need address/port fields in the game UI. The format
is at most 153 characters. The address is encoded, not encrypted; the code is
a private credential and must be shared privately.

For compatibility, `invite` without `address` still returns the original
137-character `IM3TLS1.<64 hex certificate fingerprint>.<64 hex secret>`.
Joining with that older token requires the explicit `port` and host `address`.
Both formats pin the host's certificate and contain a random 256-bit secret.
The guest verifies the certificate before sending that secret inside TLS.
Application `join` events and messages are allowed only after authentication.
TLS 1.2 is restricted to ECDHE with AES-GCM; packet tampering/replay fails TLS
integrity checks. An invitation proves possession of the secret, not a person's
account identity. Anyone who obtains it can attempt to join.

`status` never returns the invitation. Only an explicit `invite` command retrieves
it from a listening TLS host. A new host endpoint generates a new invitation;
closing/restarting it invalidates the previous invitation. Rematches on the same
endpoint can reuse it. Keep invitations out of broadcasts, public logs, source
repositories, and screenshots. Error traces redact recognizable invitation
strings; this is not a substitute for keeping credentials private.

Keep a frame loop alive: socket work runs on OBS ticks, and `receive` pops one
queued event without waiting. Program completion closes its connections. Busy
games can consume several events per frame in a bounded `!for` loop.

### Commands and attributes

Put the action first. Named attributes can appear in any order, separated by
commas, `|`, or both. Attributes accept variables/expressions; connection names
and addresses can also be literal strings. Ports, rates, counts, and byte limits
are whole numbers. Timeouts and work budgets use **milliseconds**.

| Action | Attributes | Behavior |
| --- | --- | --- |
| `addresses` | required `into` | Read active local IPv4 interfaces into `{ok,address,count,candidates,error}`. No connection name or socket is needed. See LAN detection below. |
| `host` | required `name`, `port`; optional `address`, `security`, and protection settings below | Listen for clients. Address defaults to `"0.0.0.0"` (all IPv4 interfaces). Port `0` asks the OS for a free port; read it with `status`. Generates a fresh invitation for TLS. |
| `invite` | required `name`, `into`; optional `address` | With `address`, create a complete private connection code using that IPv4/localhost and the actual listening port. Without it, retrieve the original TLS token. Never prints either. `0.0.0.0` cannot be shared as a connection address. |
| `decode` | required `invite`, `into` | Validate a complete code without connecting. Returns `{ok,address,port,transport,error}`, with no authentication secret. Missing/invalid code returns `ok:0`; malformed command attributes are errors. |
| `join` | required `name`, plus `invite` for TLS; `port` required unless supplied by a complete code; optional `address`, `security`, `timeout`, protection settings | Start a nonblocking connection and authentication. Complete codes supply address/port internally; contradictory explicit fields are rejected. Older tokens default to `"127.0.0.1"` if no address is supplied. Connect timeout defaults to `10000` ms (`0` disables it). |
| `send` | required `name` and exactly one of `text` / `data`; optional `peer`, `into` | Queue a complete message to authenticated recipients. Host broadcasts by default; `peer:id` targets one client. A client sends to host peer `1`. Optional `into` gets `{ok:1,error:"",recipients:n}` or `{ok:0,error:"reason",recipients:0}`. Success means queued, not acknowledged. |
| `receive` | required `name`, `into` | Pop one event/message into a table; returns immediately. |
| `status` | required `name`, `into` | Read connection state, peers, errors, counters, and queue usage. |
| `close` | required `name`; optional `peer` | Close an endpoint or one peer. `name:all` closes every endpoint owned by the program. Does not wait for outgoing messages. |
| `configure` | optional `budget` | Total socket work slice per OBS tick; default `1` ms. Also respects the script deadline. Must be positive; this is not a latency/FPS setting. |

Addresses accept **numeric IPv4** or `localhost`; DNS hostnames and IPv6 are not
implemented. Ports are 1-65535, except host's port `0`. Names identify endpoints
inside one program; `all` is reserved. Close an active name before reusing it.
A name in `closed`/`error` state can be hosted/joined again.

### Automatic LAN address detection

```text
!network | addresses | into:lan |+|
!if | lan.ok == 1 {
    !var | share_address | lan.address .. ":7777" |+|
    !network | host | name:game,address:"0.0.0.0",port:7777 |+|
} |+|
!else { !log | lan.error |+| } |+|
```

`addresses` asks the operating system for addresses already assigned to its
active network interfaces. It does not invent an address, contact an external
IP service, perform a DNS lookup, open a connection, or change firewall/router
settings. Windows uses its installed `iphlpapi` API through LuaJIT FFI;
Linux/macOS use `getifaddrs` in their system C library. No extra project file,
DLL download, or package is required. References: [Windows adapter enumeration](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getadaptersaddresses),
[Linux](https://man7.org/linux/man-pages/man3/getifaddrs.3.html),
[macOS](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getifaddrs.3.html).

Result fields:

| Field | Meaning |
| --- | --- |
| `ok` | `1` when at least one usable local IPv4 address was found; otherwise `0`. |
| `address` | Recommended address, or `""` on failure. This is an interface address, not a discovered public router address. |
| `count` | Number of unique candidate addresses. |
| `candidates` | Ordered 1-based list of `{address,name,kind,private,link_local,metric,recommended}` records. |
| `error` | Empty on success; explanatory text on failure or no active address. Enumeration failure is returned here without stopping the script. Invalid command attributes still produce command errors. |

`name` is the adapter/interface name. `kind` is `wifi`, `ethernet`, `virtual`,
or `other`, inferred from native metadata and adapter names. macOS `en*` names
alone do not identify Wi-Fi versus Ethernet, so they may be `other`.
`private` identifies RFC 1918 addresses; `link_local` identifies `169.254.*.*`.
These and `recommended` use `1`/`0`. `metric` is the Windows interface IPv4
metric, or `0` where unavailable.

Loopback, disconnected, unspecified, multicast, and invalid addresses are
excluded. Active physical Wi-Fi/Ethernet and private addresses are preferred;
recognizable VPN/virtual adapters and link-local addresses remain available
as lower-ranked alternatives. Windows interface metrics break ties. This is
a recommendation, not proof that another PC can reach that interface. Provide
a selector when `count > 1`. The first candidate has `recommended:1`.

Read again when starting a new host or after a network change; the command
returns a snapshot, not a background monitor. An empty result never silently
substitutes localhost. Share the selected address and the actual listening
port; `0.0.0.0` is a listen address, not an address for a guest to join.
TLS authentication remains required; include the selected address with `invite`
to put all connection information in one private code. This command
does not discover other hosted games or bypass network isolation/firewalls.

**Existing raw TCP programs:** `security:plain` explicitly selects unencrypted,
unauthenticated legacy framing on both host and guest. It accepts no invitation.
Old clients do not interoperate with the new default TLS endpoint. Plain mode is
an explicit compatibility choice and removes the TLS/authentication protections.

```text
!var | position | {kind:"position",x:120,y:80} |+|
!network | send | name:game,data:position,into:sent |+|
!network | send | name:game,data:{kind:"score",value:25} |+|
!network | send | name:game,text:"Hello" |+|
!network | status | name:game,into:connection |+|
!network | close | name:game,peer:2 |+|
!network | close | name:all |+|
```

`data` copies numbers, strings, booleans, nested plain tables, and dense 1-based
arrays as JSON. Tables need string keys or dense array indices. Cycles,
metatables, sparse/mixed-key tables, non-finite numbers, and more than 60 nested
table levels are rejected. Inline `{key:value}` / `[value,value]` use existing
table-literal validation. Empty tables travel as `{}`. Received data is never
executed as script code. Scripts must still validate message schemas and rules.

### Protection settings

These optional `host`/`join` attributes guard storage and work. All have defaults;
a small game can use tighter values. `0` disables the corresponding guard and
weakens protection. They do not change graphics/model limits.

| Attribute | Default | Meaning |
| --- | --- | --- |
| `message_limit` | `1048576` bytes | Maximum encoded frame payload, including format byte. TLS needs at least `64` or `0` for its internal authentication frame. |
| `buffer_limit` | `8388608` bytes | Per-peer outgoing queue and incoming payload/inbox buffering. TLS needs at least `64` or `0`. |
| `queue_limit` | `33554432` bytes | Aggregate engine buffering per endpoint, including event metadata, frame queues, and TLS I/O buffers. Must be `0` or at least `1024`. Not a measure of all native-library/kernel memory. |
| `event_limit` | `1024` | Queued events, including joins, leaves, errors, and messages. |
| `max_peers` | `64` | Total accepted open sockets per host, including pending authentication. |
| `max_pending` | `8` | Host sockets still completing TLS/invitation authentication. |
| `max_clients` | `0` | Authenticated clients per host; `0` disables this additional cap. |
| `connection_rate` | `30` / second | Host admission token bucket, initial burst `max(8,rate)`. |
| `address_rate` | `4` / second | Per-source-IPv4 admission bucket, burst `max(8,rate*2)`. Address bookkeeping is bounded to 256 entries. |
| `message_rate` | `120` / second | Incoming messages per peer, burst `max(16,rate*2)`. Also bounds encrypted record processing. |
| `byte_rate` | `1048576` / second | Incoming wire bytes per peer, burst `max(65536,rate*2)`; includes TLS handshakes/records. |
| `handshake_timeout` | `5000` ms | Combined TLS/invitation authentication time, starting only after TCP connects or is accepted. TCP connection attempts use the separate join `timeout` setting. |
| `read_timeout` | `5000` ms | Maximum duration of an unfinished frame or encrypted record. Sending tiny fragments does not restart it. Completed messages can be followed by long idle periods without triggering this timeout. |

Admission checks run before allocating a peer's TLS context. Unauthenticated
failures count toward `rejected` without creating application join/error events
on the host. Oversized frames, protocol failures, rate excesses, and stalled
frames drop the offending peer. Incoming payload reads pause when the inbox is
full; sends return `ok:0` if their queue is full. Event-count or aggregate overflow
while enqueuing an event closes the endpoint and retains one error event, so the
program cannot silently lose connection state or accumulate endless errors.
Broadcast enqueue is all-or-nothing if one recipient's outgoing queue is full.

These guards reduce resource abuse; they do not prevent an attacker from
saturating your internet connection or prove the absence of vulnerabilities.
Network data has no remote-control/file/script execution command in this API.
An application's choice to execute received content would be unsafe.

### Events and status

Every receive result has `available`, `event`, `peer`, `address`, `text`, and
`data`. `available` is numeric 1 or 0. With no event, it is `0`, `event`/`text`
are empty, `peer` is `0`, and `data` is an empty table.

| `packet.event` | Meaning |
| --- | --- |
| `join` | TLS and invitation authentication completed; in explicit plain mode, TCP connected. |
| `message` | Complete message; read `text` or `data`. The unused field is empty. |
| `leave` | Peer disconnected or was explicitly closed. |
| `error` | Connection/protocol/decoding failure; `text` contains the reason. Malformed JSON reports an error without executing it. |

Peer IDs start at `1` and increase without reuse during the endpoint's lifetime.
A client calls its host peer `1`. IDs are connection identities, not accounts.

Status contains `state` (`hosting`, `connecting`, `connected`, `closed`, `error`),
`mode`, `address`, `port`, `error`, `connections`, `peers`, `messages`,
`queued_bytes`, `last_send_error`, `security` (`tls`/`plain`), `authenticated`,
`rejected`, `buffered_bytes`, and `phase`. Each peer has
`{id,address,state,authenticated,phase,tls_sent_bytes,tls_received_bytes}`.
Pending phases are `tcp`, `tls`, and `invitation`; authenticated peers report
`connected`. A listening host reports `listening` at the top level; inspect
its peer phases for pending handshakes. A failed client retains its failure
phase. The TLS byte counters contain only byte counts, not credentials/data.
Connection timeout before TCP completes is reported as **Connection timed out
before reaching host**. TLS and invitation timeouts are reported separately;
the handshake clock never runs against a pending TCP connection. Neither
connection progress nor received fragments reset their configured deadline.
`connections` includes pending sockets; use peer state/authentication to distinguish
them. Top-level `authenticated` is `1` only for a connected TLS client.
`messages` counts all queued events; `queued_bytes` counts application bytes not
yet submitted to TLS/socket output; `buffered_bytes` includes engine TLS buffers
and event metadata too. Invalid syntax raises an engine error. Busy ports,
unavailable TLS, refused connections, and handshake failures become status/error
events. Check `into`/`last_send_error` when sending before authentication.

### Clipboard access

```text
!clipboard | copy | text:invitation,into:copied |+|
!clipboard | paste | into:pasted |+|
```

These explicit local commands currently use Windows native Unicode clipboard
APIs. Results are `{ok:1,text:"...",error:""}` or `{ok:0,text:"",error:"reason"}`;
copy success has empty `text`. Both require `into`; copy also requires `text`.
Text is limited to 1 MiB. Busy/unavailable clipboard returns an error result.
Other platforms report unsupported; a programmer can pass the invitation as a
string variable instead. A network message never automatically accesses the
clipboard. Copying replaces clipboard text, and OS clipboard history/sync may
retain it: treat invitations as private credentials.

### Cleanup and transport

Socket calls are nonblocking and handled in rotating chunks. JSON processing,
TLS operations, credential creation, and an individual command are synchronous;
the tick budget cannot interrupt a native call already in progress.

Stop, Execute, program completion, shutdown, and engine unload close sockets,
free TLS contexts, and discard queues without waiting for peers. Windows hosts
create a temporary named key in the Windows CNG keystore for Schannel; normal
endpoint cleanup deletes it. Certificates are generated in memory, with no
certificate download/file or distributed DLL. An abrupt process crash may leave
an orphaned OS-managed key. OpenSSL keys/certificates are held in memory.
Connections do not reconnect automatically. A client may rejoin using the same
invitation while that host endpoint remains alive.

Inside TLS, a four-byte unsigned **big-endian** length precedes each payload.
The first client payload is `A` followed by the invitation's raw 32-byte secret;
after verification the host returns `K`. These internal authentication frames
are not exposed to the game. Normal payloads are `T` + raw text bytes, or
`J` + UTF-8 JSON `{"data":value}`. Compatible external clients must implement
TLS, certificate pinning, authentication, and this framing; explicit plain mode
uses only the legacy T/J framing. This is not OBS WebSocket. TCP preserves byte
order, but games define authority, synchronization, and interpolation.

LAN/internet use the same commands if the firewall/router allows reaching the
host; the engine does not configure either or provide router traversal.

## Command reference

This index covers the engine's public command families. `[…]` means optional; `name`/`label` are programmer-chosen identifiers. `|+|` ends each statement, even when omitted from a compact signature below. Internal compiler commands beginning `__` are not program APIs. A module may register additional commands, but those are not part of the core language.

### State, flow, and diagnostics

| Command | Form / effect |
| --- | --- |
| `!var` | `name_or_type_name \| value`; assignment, including fields such as `player.x`. Add `local` for a local name. |
| `!save`, `!load` | `name`; `name \| fallback`. OBS-settings persistence for scalar values. |
| `!log` | `message_or_expression`; write to OBS log. Literal messages can interpolate `(variable)` in fallback text. |
| `!label`, `!jump` | `label`; mark or branch to a label. |
| `!call`, `!return` | `label \| [name:value] \| [-> \| result]`; call a label. `!return \| [value]` returns from a label/function. |
| `!fn`, `!function_name` | `name \| [param, optional:default \|] { body }`; call with positional or named values and optional `-> \| result`. |
| `!if`, `!else` | `condition { body }`, optional following `!else { body }`; older `!if \| condition \| label \| [ret]` works. |
| `!for` | `item in list { body }` or `i from first to last { body }`; inclusive queued loop. |
| `!loop`, `!foreach` | `count \| label_or_block`; `table \| item_name \| label`; older loop forms. |
| `!wait`, `!await` | `duration_or_frame`; `task_name_or_condition`. Both yield while pending. |
| `!then` | `command_name \| command_arguments...`; execute a named command; `!execute_command` is its alias. |
| `!change` | `variable \| label_or_{body}` or `variable \| operator \| value \| label_or_{body}`; register a change watcher. |
| `!easing` | `easing_name`; set the default movement easing. |

### OBS scene, source, media, and animation

| Command | Form / effect |
| --- | --- |
| `!use_sources` | `source_name \| [more_names...]`; select exact direct source(s), or no names to restore. Older `!source` works. |
| `!renderer` | `create \| name \| pixel_or_shader_or_3d \| width \| height \| [scale]` positionally, or `create \| name:... \| kind:pixel_or_shader_or_3d \| width:... \| height:...`; create/configure a direct renderer. Older `ensure` works. |
| `!switch`, `!transition` | `scene_name`; `scene_name \| [transition_name] \| [duration]`; switch OBS scenes. |
| `!media`, `!media_wait`, `!media_time` | `source \| play/pause/restart/stop/seek \| [time]`; `source \| absolute_time`; `source \| destination_ms`. |
| `!sound` | `source \| play/pause/stop` or `source \| volume \| value \| [duration]`; control a media source. |
| `!move`, `!path`, `!spiral`, `!fade` | `key:value,... \| duration \| [easing]`; `control_x:y \| end_x:y \| duration \| [easing]`; `center_x:y \| radius \| rotations \| duration \| [easing]`; `opacity \| duration \| [easing]`. Apply to selected source(s). |
| `!shake`, `!camera_shake`, `!glitch` | `intensity \| duration`; shake/jitter the selected item, then restore it. |
| `!rainbow`, `!breathing`, `!dvd`, `!sway` | `speed \| duration`; procedural selected-source effects. Zero duration means they keep running. |
| `!filter` | `source \| filter_name \| setting_name \| number \| [duration]`; set or interpolate a numeric OBS filter setting. |
| `!add_color` | `red \| green \| blue`; add/update a color-add filter on selected source(s). Older `!foreground` works. |
| `!shader` | `select \| renderer_name \| effect_path \| [texture_path]`; explicitly choose a shader file. |
| `!world3d` | `use`, `camera`, `spotlight`, `blur`, `background`, `box`, `mesh`, `import`, `animate`, `set`, `update`, `list`, `get`, `vertex`, `triangle`, `edit`, `pick`, `save`, `load`, `export`, `remove`, `clear`; also `prepared/ready/error/cancelled \| job \| { ... }` and `animation_done \| name:model \| { ... }`. See [real 3D renderer](#real-3d-renderer) and [events](#event-handlers). |
| `!physics` | `step`: advance a copied state with box/sphere rigid bodies and joints, returning the next state with `->` or `into:`. Also supported in native workers. See [3D physics](#3d-physics). |

### Graphics and data

| Command | Form / effect |
| --- | --- |
| `!canvas` | `create`, `use`, `fill`, `rectangle`, `rectangles`, `circle`, `text`, `snapshot`, `restore`, `update`. See [full field table](#pixel-canvas). |
| `!array` / `!array.unpack` | `unpack \| name \| type \| encoding \| data \| [count]` positionally, or named fields in any order; decode a packed numeric table. |
| `!array.push/pop/remove/clear/copy/shift` | List/table operations described [above](#tables-and-arrays). |
| `!sprite` | `create \| name \| width \| height \| palette \| pixels`; `draw \| name \| x \| y`. |
| `!animation` | `create` with `frames` or packed `pixels`; `draw \| name \| time \| x \| y`; `done \| name:animation \| { ... }`. |

### Input, tasks, objects, and extensions

| Command | Form / effect |
| --- | --- |
| `!input` | `press/release/hold \| key \| { ... }`, `off \| key/all`; also `key`, `mouse`, `pointer`, `recenter`, `wheel`, `focus`, `snapshot`, `keys`, `text`, `preview`, `preview_menu`, `viewport`; see [input](#input-and-timing). |
| `!events` | `off \| all`, or `off \| family \| [selector] \| [event_kind]`; remove block handlers. See [event handlers](#event-handlers). |
| `!projector` | `fullscreen \| [monitor:index]`; open the current OBS Preview Projector fullscreen on a zero-based monitor index. |
| `!onpress` | `hotkey_name \| press_label \| [release_label]`; register an OBS hotkey and callbacks. |
| `!start_task`, `!start_independent_task` | `label_or_block`; the independent form also accepts `-> \| task_name`. Cooperative tasks. Older `!run`/`!spawn` work. |
| `!worker` | `expression/block/label \| result_name` or `expression/block/label \| -> \| result_name`; isolated native computation. `done/error/cancelled/finished \| job \| { ... }` register callbacks. `read`, `cancel`, `release`, and `clear \| scope/program` manage jobs. Older aliases remain compatible. |
| `!connection` (`!websocket` alias) | `addresses`, `host`, `invite`, `decode`, `join`, `send`, `receive`, `status`, `close`, `configure`; dedicated encrypted game messaging with private codes, independent of OBS remote control. See [connection messaging](#connection-messaging). |
| `!network` | `addresses`, `host`, `invite`, `decode`, `join`, `send`, `receive`, `status`, `close`, `configure`; local LAN interface detection and generic TCP with private connection codes, TLS authentication and named attributes. See [networking](#tcp-networking). |
| `!clipboard` | `copy` with `text` / `paste`, both with `into`; explicit local Windows clipboard access. See [clipboard access](#clipboard-access). |
| `!attach`, `!stop`, `!detach` | `source \| label`; `task/source/all`; `collision/spawn/pin/onpress/...`; start or remove scheduled behaviors. |
| `!collision` | `source_a \| source_b \| callback_label_or_{body}`; register a 2D source-bounds collision callback. The named items must exist. |
| `!template`, `!clones`, `!delete` | `template_name`; `remove`, `clone_name_or_index \| remove`, or `template_source \| remove_orphans`; remove selected scene item(s). |
| `!spawn_repeatedly`, `!remove_after` | `source \| max_count \| interval \| callback_label`; `duration`; clone emission and scheduled removal. Older `!emitter`/`!despawn` work. |
| `!pin` | `parent_source \| x:offset,y:offset` or `none`; follow a parent. |
| `!fetch` | `url \| destination_variable`; fetch external data, using a `curl` helper on the host. Not needed for local programs. |
| `!module` | `load \| path/to/module.lua`; optional Lua extension that can register commands. Core canvas, animation, input, and worker syntax does not require it. |

Selected OBS source methods such as `!pos` and `!text` are resolved after built-in commands. The engine also exposes script functions through `@name(...)` and math functions, for example `math.min(a,b)`; these are distinct from `!fn` declarations. The existing `@` and source-method surface is broader than the stable command families above, so inspect the current engine or focused examples for a specific advanced method.

## Advanced syntax and compatibility

### Source methods versus built-in commands

After a `!use_sources` selection, an unknown built-in name is checked as a method on each selected source. Methods such as `!pos | x:120,y:90 |+|`, `!scale | x:2,y:2 |+|`, and `!crop | left:4,top:4 |+|` receive a dictionary. `!rot | 30 |+|`, `!width | 100 |+|`, and `!text | "READY" |+|` receive a scalar. An omitted value often reads the current property for expression use, but a standalone method call does not automatically store a return value. Most methods apply to each selected item. A method called with no selection reports an unknown-command/no-source error.

The engine's predefined expression functions include `@dist(x1,y1,x2,y2)`, `@mass(...)`, `@mouse()`, `@source(name)`, `@clone(...)`, and wrappers for Lua math functions, also exposed as `math.*`. `@mouse()` returns a screen-pointer record where available; `!input | pointer` is the renderer-focused game input. `@clone(...)` duplicates the currently selected OBS source into the active scene, and clone cleanup is handled with `!clones`.

### Swept circle collision query

`@math.sweep_circles(first,second,plane)` checks both circles over a complete
movement step, including fast crossings between their starting and ending
positions. It returns a fresh record and does not modify either input.

```text
!var | first | {old_x:-10,old_y:0,x:10,y:0,radius:1} |+|
!var | second | {old_x:10,old_y:0,x:-10,y:0,radius:1} |+|
!var | contact | @math.sweep_circles(first,second) |+|
!@math.sweep_circles(first,second) | -> | contact |+|
```

| Input | Meaning |
| --- | --- |
| `x`, `y`, `radius` | End position and positive circle radius. Values must be finite numbers. |
| `old_x`, `old_y` | Start position; each omitted coordinate defaults to its end coordinate. |
| `plane` | Optional `"xy"` (default) or `"xz"`. In `"xz"`, use `z` and `old_z` in place of `y` and `old_y`. |

| Returned field | Meaning |
| --- | --- |
| `hit` | `1` if the swept circles overlap or touch, otherwise `0`. |
| `time` | First contact as a fraction of the step (`0`–`1`); `0` when already touching/overlapping, `1` on a miss. |
| `normal_x`, `normal_y`, `normal_z` | Contact unit normal pointing from the second circle towards the first. Unused axes are zero; coincident centres use positive X. Zero on a miss. |
| `penetration` | Nonnegative separation needed along the contact normal to keep the end positions on their original sides. It can stay positive after a complete crossing, or be zero for a tangent or circles already separating. |
| `correction_x`, `correction_y`, `correction_z` | Half that overlap along the normal. For equal sharing, add this vector to the first circle and subtract it from the second. Zero on a miss. |

The query measures a selected plane. A script can check height separately for
ground-level collisions. It does not apply movement, damage, or velocity changes.

`@fps()` returns OBS's measured active video frame rate through `obs_get_active_fps`.
It returns `0` when OBS cannot supply a valid positive reading. This is the OBS
video rate, not the rate at which a script finishes a logical frame or a worker
updates simulation data. A script may take several OBS ticks to reach its next
`!wait | frame` when its work exceeds the tick budget.

```text
!var | video_fps | @fps() |+|
!var | game_fps | 1 / math.max(tick, 0.000001) |+|
```

For the second value, sample `tick` once per logical frame after `!wait | frame`.
Average readings over time for a stable display; do not treat one sample as a
GPU benchmark. Identical 3D camera/object updates preserve the cached scene;
changed transforms still trigger a redraw. Explicit mesh geometry or texture
replacement continues to rebuild/reload the supplied resource.

### Easing names

`!easing | name |+|` sets the current default for movement. A movement command's explicit easing argument overrides it. Names implemented in this engine are `linear`, `quad_in`, `quad_out`, `quad_inout`, `sine_inout`, `back_out`, `elastic_out`, and `bounce_out`. Unknown names fall back to `linear` in the movement handlers.

### Older spellings that still work

| Current spelling | Alias | Purpose |
| --- | --- | --- |
| `!renderer \| create` | `!renderer \| ensure` | Create or configure a named renderer source. |
| `!canvas \| create` | `!canvas \| init` | Create and select a blank pixel buffer; replaces an existing buffer. |
| `!canvas \| use` | `!canvas \| select` | Switch buffers without clearing pixels. |
| `!canvas \| fill` | `!canvas \| clear` | Fill the selected buffer with a color. |
| `!canvas \| rectangle` | `!canvas \| rect` | Draw one filled rectangle. |
| `!canvas \| rectangles` | `!canvas \| rects` | Draw rectangles from coordinate tables. |
| `!canvas \| update` | `!canvas \| present` | Publish changed pixels for the next OBS render. |
| `!use_sources` | `!source` | Select scene sources for following commands. |
| `!add_color` | `!foreground` | Add a color filter to the selected sources. |
| `!start_task` | `!run` | Start a cooperative task with the current source and context. |
| `!start_independent_task` | `!spawn` | Start a cooperative task in a new context without source selection. |
| `!spawn_repeatedly` | `!emitter` | Clone sources at a timed interval and run a callback for each. |
| `!remove_after` | `!despawn` | Schedule selected sources for removal after a duration. |
| `!then` | `!execute_command` | Execute the command named by the first argument. |
| `!worker \| read` | `!worker \| get_result` | Read a worker result without waiting. |
| `!worker \| release` | `!worker \| remove` | Cancel or discard a worker job and release it when safe. |
| `!worker \| clear \| all` | `!worker \| stop_all` | Cancel and remove all worker jobs; `stop_all` takes no second argument. |
| `!array \| unpack` | `!array.unpack` | Decode packed numeric data. |
| `!connection` | `!websocket` | Open encrypted message connections. `!network` is a separate TCP API. |

Older positional forms still run. The named graphics form exists to make units and intent visible; it does not change the drawing result.

### Specialized prefixes and compile markers

The parser also recognizes `[[variable1,variable2]] [label] !command...` to watch variables while that command is pending and request an interrupt label when one changes. `<<material>> !command...` tags the selected item as an active collider for the duration of a pending command. These are specialized animation/physics features; their placement before `!` matters. `-skip-` and `-end-` delimit skipped text at compile time. Prefer explicit `!if`, `!for`, and `!fn` for new general-purpose code.

`!detach | change |+|` removes all variable-change watchers, or add variable/label names to narrow removal. `!detach | onpress |+|` removes all script hotkeys, or add callback labels to narrow removal. For selected sources, `!detach` can remove `collision`, `spawn`/`thread`/`loop`, `pin`, `emitter`, or `despawn` behaviors; omitting the type removes their associated behaviors together. `!clones | remove |+|` clears clones made in this execution in small batches, while `!clones | TemplateSource | remove_orphans |+|` finds older clones of a named template in the current scene.

## Less obvious behavior

- **A renderer is an OBS source; a canvas is an in-memory pixel buffer.** `!renderer | create` handles the scene item. `!canvas | create` handles drawing data. `!canvas | update` connects a finished frame to that source. Several canvas buffers can coexist and `use` switches without clearing.
- **A command that waits remains the current command.** `!wait`, an animation over time, `!await`, and similar commands return to OBS and resume on later ticks. `!wait | frame` is the explicit frame boundary for games.
- **The budget is shared work, not an animation delay.** Raising it can allow more game logic in one tick, but can also make OBS less responsive. The engine also has a 1,000-command safety backstop and detects loops that keep exhausting budgets without yielding.
- **`!canvas | snapshot`/`restore` can avoid redrawing a static map.** Draw the map once, snapshot it, then restore and draw moving objects each frame. Call `update` after the completed frame.
- **Packed art is decoded once when defined.** Reuse `!sprite | draw` or `!animation | draw` each frame rather than rebuilding the definition. `transparent` palette entries preserve pixels already on the canvas.
- **An animation does not keep its own clock.** Pass a seconds value to `time`; increment it with `tick`, or set it directly to pause, replay, or seek.
- **Native workers have a copied scope.** They are for computation. Read results on the main script side, then change OBS sources there. Cooperative tasks are the right tool for timed OBS actions.
- **Input focus is part of the design.** Focus the OBS main window for direct input on Windows or Linux/X11. `pressed` means an edge observed by polling; calling it only sporadically can miss a short key press.
- **`!use_sources` searches the active scene and uses exact names.** A source inside a nested scene/group may not match a direct scene item. Use `!renderer | create` for an engine renderer if it does not yet exist.
- **Not every family uses named arguments.** A comma-separated `x:...,y:...` dictionary inside `!move` is one positional argument. `!canvas` field order flexibility applies to its named form specifically.
- **External files are optional features.** A program can be one text file plus the engine. `!shader`, `!module`, `!include`, and `!fetch` intentionally read or contact things outside that file.
