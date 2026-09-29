# Yard Wars (LÖVE 11.x)

Top-down arena shooter (mobile twin-stick style) in LÖVE (Lua). Currently 1 player vs. 1 bot
in a mirrored arena. Developed on Linux, tested on a Pixel 6a (official LÖVE for Android 11.5).

## Running
- Desktop: `love .` in the project folder.
- Quick smoke test (no errors on load/first frames): `timeout 6 love .` — LÖVE prints
  error tracebacks to stdout; exit code 124 means it ran until the timeout.
- Packed build: `zip -9 -r ../yard-wars.love . -x '.git/*'`

## Android test workflow (took a while to figure out — don't change without reason)
- Use the OFFICIAL "LÖVE for Android" (package `org.love2d.android`, APK from
  github.com/love2d/love/releases, 11.5). NOT `com.rk.love2d` (a different IDE app).
- Opening `.love` files via Drive / Files "open with" fails (content:// URIs).
- Working method: copy the unpacked game (main.lua at top level) via USB MTP to
  `/sdcard/Android/data/org.love2d.android/files/games/lovegame/`, force-stop LÖVE,
  start it from its icon.

## Layout
- `main.lua` — state (menu/game), game modes (`MODES`: Duel = respawning bot, Waves = +1 bot
  per cleared wave), game loop, bullet/hit logic (sub-stepped), HUD, minimap, rowdy switching.
  Escape / Android back: game → menu, menu → quit. F2 toggles the art style
  (comic / Kenney) for player and bots.
- `src/menu.lua` — start screen with one button per mode (mouse, touch, keyboard)
- `conf.lua` — identity "yard-wars", 1280x720 resizable window
- `src/assets.lua` — tilesheet quads + Kenney pose images + comic sprites; `Assets.style`
  ("comic" | "kenney"), `Assets.look(character, weapon, comic)`
- `src/arena.lua` — 40x24 tiles (64px), left half defined and mirrored to the right;
  walls (solid, 2x2), crates (solid), bushes (hiding, 2x2); `resolveCircle`, `hitsSolid`,
  raycast, `hasLineOfSight`, `randomOpenPoint`, spawns
- `src/camera.lua` — follows player; `viewSize=720` world units along the SHORTER screen
  side (landscape + portrait); clamp to arena; shake; `toWorld()`
- `src/controls.lua` — input abstraction → `{ dx, dy, aim, fire, aiming }`
  - desktop: WASD + mouse (hold LMB to fire)
  - touch: left half = floating move stick; right half = aim stick, drag = aim beam,
    RELEASE = fire, drag back to center = cancel, quick TAP = auto-aim at nearest visible
    enemy in range (ignores walls); top-left button switches rowdy
- `src/rowdy.lua` — base class: stats, HP, ammo (3 bars + refill timer), shoot
  (pellets/spread), aim beam/cone (`drawAim`), health/ammo bars, animation (pose, walk
  sway/bob, breathing, recoil, muzzle flash, spawn pop-in), hooks into Effects
- `src/rowdies.lua` — data: Gunner (pistol), Shotgunner (5 pellets, 0.6 rad cone),
  Sniper (range 720), plus `Rowdies.bot` (enemy look). See the comment at the top for
  stat meanings and the `comic` look entry.
- `src/player.lua` — Player subclass, `update(dt, input, bullets)`, 0.25s fire buffer
- `src/enemy.lua` — Bot subclass: states patrol/chase/strafe/retreat/flee/search, LOS +
  bush-reveal rules, aim spread, stuck detection (slides sideways)
- `src/bullet.lua` — owner/damage/color; speed+range read from owner (default range 480)
- `src/effects.lua` — particles: puff, sparks, burst, ring (`drawBelow`/`drawAbove` layers)
- `assets/images/` — `tilesheet.png` (Kenney), `characters/<name>_<pose>.png`,
  `comic/<name>.png`
- `tools/make_comic_sprites.py` — AI image (white bg, facing up) → cut out, trimmed,
  88px-wide sprite; prints origin + muzzle for `src/rowdies.lua`

## Conventions
- Code and comments in English.
- Keep game logic separate from input/rendering (multiplayer via enet/sock.lua may come later).
- World units: 1 tile = 64px. HUD is laid out for a 720px short screen side and scaled
  by `uiScale = min(w,h)/720`; fonts use dpiscale.
- Rowdy stats live in `src/rowdies.lua`; bullets read range/bulletSpeed/damage from owner.
- Tile art uses nearest filtering to avoid bleeding when scaled.

## Art
- Branch `art/comic` (default style there): one still sprite per character, generated with
  Google Gemini (prompts + raw 1024px JPEGs in ~/Downloads/yard-wars-art/, not in the repo),
  top-down, facing UP, bold outline. Stored at 2x (88px wide), drawn at
  `Assets.comicScale` 0.5 with mipmaps; rotates around the head (`origin`). Keeps the
  Kenney-style animation (sway, bob, recoil, flash); no reload pose.
  New character: same Gemini chat, then add the name to `NAMES` in the tool and
  `Assets.comicNames`, run the tool, copy origin/muzzle into `src/rowdies.lua`.
- Kenney "Top-down Shooter" (CC0, see CREDITS.md). 6 still poses per character
  (stand/hold/gun/machine/silencer/reload), all sharing body-center origin (16, 21.5).
- Set aside (too gritty, comic style preferred): "Undead Empire 2D Assets" (2015), prototype
  on local branch `art/undead-empire` — 64x64 top-down, layered characters
  (4-frame legs walk cycle + torso poses 1h/2h/DW + separate weapon sprites), zombies,
  effects, dungeon tiles. Gritty horror style rather than cartoon. No license file in the
  zip → verify source and license before any public use. Would need a small
  sprite/animation loader (legs animate, torso rotates to aim).

## Status
- Confirmed on phone: game runs, touch controls, portrait/landscape, aim beam,
  ammo/release-to-fire.
- NOT yet confirmed on device: auto-aim fix (preview + fire buffer) and the animation
  update (poses, walk sway, recoil, muzzle flash, dust, sparks, death burst, respawn pop-in).
  Desktop smoke test loads without errors (2026-09-29).

## Next-step ideas
1. Super attack with charge meter (charges on hits) + touch HUD button
2. Start screen with rowdy picker + match timer / game over
3. Sprite-frame animation system (legs walk cycle, torso pose, weapon layer)
4. More rowdies, gadgets, arena variety, bot A* pathfinding for bigger maps
5. Optional: multiplayer (enet), sound effects (jsfxr / Kenney audio)
