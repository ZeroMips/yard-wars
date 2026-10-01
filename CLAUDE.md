# Yard Wars (LÖVE 11.x)

Top-down arena shooter (mobile twin-stick style) in LÖVE (Lua). Currently 1 player vs. 1 bot
in a mirrored arena. Developed on Linux, tested on a Pixel 6a and a moto g67 (second
phone for LAN tests), both with the official LÖVE for Android 11.5 (same MTP path).

## Running
- Desktop: `love .` in the project folder.
- Quick smoke test (no errors on load/first frames): `timeout 6 love .` — LÖVE prints
  error tracebacks to stdout; exit code 124 means it ran until the timeout.
- Packed build: `zip -9 -r ../yard-wars.love . -x '.git/*'`
- LAN test on one machine: `love . --host` (or `--host waves`) and `love . --join 127.0.0.1`
  (or `love . --find` for the join screen with discovery) in a second terminal.
  UDP ports 27015 (game) + 27016 (discovery); if a phone can't connect/find the desktop:
  `sudo ufw allow 27015:27016/udp`.
- Scripted test harnesses (copy main.lua to game.lua in a temp dir, override love.update/
  draw, symlink `src`/`assets`): NEVER symlink conf.lua (writing the test conf overwrote
  the real one once), and set `t.window.vsync = 0` + `love.timer.sleep` — with vsync the
  window blocks forever when the screen is locked. Print needs `io.stdout:setvbuf("no")`
  if the process gets killed by `timeout`.

## Android test workflow (took a while to figure out — don't change without reason)
- Use the OFFICIAL "LÖVE for Android" (package `org.love2d.android`, APK from
  github.com/love2d/love/releases, 11.5). NOT `com.rk.love2d` (a different IDE app).
- Opening `.love` files via Drive / Files "open with" fails (content:// URIs).
- Working method: copy the unpacked game (main.lua at top level) via USB MTP to
  `/sdcard/Android/data/org.love2d.android/files/games/lovegame/`, force-stop LÖVE,
  start it from its icon. Also write `version.txt` (`git log -1 --format='%h %cd'`, not in
  git) into the game folder: the menu shows it bottom-left, so you can see which build runs
  (LÖVE keeps running in the background unless force-stopped).

## Layout
- `main.lua` — client: state (menu/pick/join/game), roles local/host/client, `MENUS` pages:
  main (Duel, Team fight, Waves, LAN game) and lan (Host duel = free-for-all, Host team
  fight, Host waves = co-op, Join, Back); every game entry
  first opens the rowdy choice; result screen (Play again / Rowdy / Menu; LAN clients:
  Rowdy / Leave, the host starts the next round), fixed-step loop (`World.TICK` = 1/60, a shot from the
  controls is kept until a step uses it), local player by id (`localId`), world events →
  particles/shake, camera, HUD, minimap, rowdy switching.
  Escape / Android back: game → menu, menu → quit. F2 toggles the art style
  (comic / Kenney) for player and bots.
- `src/world.lua` — the simulation, no graphics/input/effects (runs headless): entities with
  `id`/`team`/`def`/kills/deaths, bullets (sub-stepped, hit other teams), waves, bush
  hiding (`isHiddenFrom`), `nearestOpponent`, medpacks (dropped when a player makes a kill, not
  by bot kills; hurt players, not bots, heal `MEDPACK_HEAL` = 40% of max HP; gone after 15 s, max 24); `update(dt,
  inputs[id])`; team fight (`mode.teams`): blue (left, `TEAM_BLUE`) vs red (right), 3 spawn
  spots per side, bots fill to `TEAM_SIZE` 3, `addTeamPlayer` (team with fewer players,
  replaces a bot), `removePlayer` (bot refills), `teamScores`, first team to
  `TEAM_KILL_TARGET` 15; rounds (`world.match`): duel = first to `KILL_TARGET` 10 or most kills after
  `TIME_LIMIT` 180 s (tie = draw), waves = `LIVES` 3 per player (`out` = no respawn), over
  when all players are out; `restartMatch()`; the world stands still while over; things
  that happened go to `world.events` (also shot/superReady/matchStart/matchOver for sounds) (spawn/death/step/impact/hit/heal)
  via `emit`, read with `takeEvents()`. Snapshots carry medpacks (`m`).
- `src/net.lua` — discovery (`Net.newFinder`: query to broadcast + every address of the
  own /24 on UDP 27016 every 2 s, hosts answer with mode/players; one short-lived socket
  per 32 addresses because queries to absent hosts block the send buffer for ~3 s;
  use `socket.udp4()` + bind "0.0.0.0": `socket.udp()` + "*" becomes IPv6 on Android and
  sendto IPv4 fails with "hostname nor servname provided"), enet LAN server (runs next to the World on the host: hello → player,
  input per step, events reliable + 30 Hz snapshots unreliable, 6 s timeout) and client
  (hello/input/rowdy; input `fire` is a counter so lost packets lose no shot)
- `src/replica.lua` — client-side World copy from snapshots: others interpolated 100 ms
  behind the host, own rowdy 50 ms; bullets drawn from spawn records (straight lines);
  events played when their time comes; clock offset = max(t - arrival), pulled down 10%
- `src/codec.lua` — message serializer (no loadstring; rejects malformed input)
- `src/join.lua` — join screen: address field in the upper half (last address saved; phone
  keyboard opens only when the field is tapped), found games below as tap-to-join buttons
- `src/medpack.lua` — medpack drawing (comic box + red cross, bob, pop-in, blinks last 3 s);
  confirmed on the Pixel 2026-10-01
- `src/picker.lua` — rowdy choice screen (cards: picture, role, HP, attack, super)
- `src/result.lua` — end-of-round screen (title, scoreboard, buttons)
- `src/menu.lua` — start screen with one button per mode (mouse, touch, keyboard)
- `conf.lua` — identity "yard-wars", 1280x720 resizable window
- `src/assets.lua` — tilesheet quads + Kenney pose images + comic sprites; `Assets.style`
  ("comic" | "kenney"), `Assets.look(def)` → plain-data look (image names, origin, muzzle;
  usable without graphics)
- `src/arena.lua` — 40x24 tiles (64px), left half defined and mirrored to the right;
  walls (solid, 2x2), crates (solid), bushes (hiding, 2x2); `resolveCircle`, `hitsSolid`,
  raycast, `hasLineOfSight`, `randomOpenPoint`, spawns
- `src/camera.lua` — follows player; `viewSize=720` world units along the SHORTER screen
  side (landscape + portrait); clamp to arena; shake; `toWorld()`
- `src/controls.lua` — input abstraction → `{ dx, dy, aim, fire, aiming }`
  - desktop: WASD + mouse (hold LMB to fire)
  - touch: left half = floating move stick; right half = aim stick, drag = aim beam,
    RELEASE = fire, drag back to center = cancel, quick TAP = auto-aim at nearest visible
    enemy in range (ignores walls); super button (left
    of the aim stick, charge ring, glows when full) = same gestures for the super.
    No in-game rowdy switching (chosen before each round; switching healed fully)
  - desktop super: hold right mouse button or E to aim, release to fire
- `src/rowdy.lua` — base class: stats, HP, ammo (3 bars + refill timer), shoot
  (pellets/spread), aim beam/cone (`drawAim`), health/ammo bars, animation (pose, walk
  sway/bob, breathing, recoil, muzzle flash, spawn pop-in); logic reports via `self:emit`
- `src/rowdies.lua` — data: Gunner (pistol), Shotgunner (5 pellets, 0.6 rad cone),
  Sniper (range 720), plus `Rowdies.bot` (enemy look + stats). Supers (`stats.super`,
  charged by normal-attack damage, `charge` = damage needed): Gunner "Bullet Storm" (10-bullet
  fan), Shotgunner "Wrecking Ball" (big slow piercing ball), Sniper "Railgun" (fast,
  long, piercing). Super bullets: own `radius`, `pierce` (each rowdy hit once). See the comment at the top for
  stat meanings and the `comic` look entry.
- `src/player.lua` — Player subclass, `update(dt, input, bullets)`, 0.25s fire buffer
- `src/enemy.lua` — Bot subclass (`isBot`), `update(dt, world)` targets the nearest opponent;
  states patrol/chase/strafe/retreat/flee/search, LOS +
  bush-reveal rules, aim spread, stuck detection (slides sideways)
- `src/bullet.lua` — owner/team/damage/color; speed+range read from owner (default range 480)
- `src/sound.lua` — sound effects synthesized at startup (sfxr-style layers: square/saw/
  sine/triangle/noise with pitch slides + envelopes; no files): per-rowdy shots, hit/hurt,
  impact, death, spawn, super, superReady chime, heal, round start, victory/defeat/draw, click.
  `Sound.play(name, x, y)`: quieter with distance from the own rowdy, panned; same sound
  not faster than 35 ms; M mutes (touch: speaker button top right on every screen, the
  minimap moves left for it); the setting is saved in `sound.txt`. ~70 ms to build on desktop (~220 ms without JIT).
- `src/effects.lua` — particles: puff, sparks, burst, ring, heal ("+" signs) (`drawBelow`/`drawAbove` layers)
- `assets/images/` — `tilesheet.png` (Kenney), `characters/<name>_<pose>.png`,
  `comic/<name>.png`
- `tools/make_comic_sprites.py` — AI image (white bg, facing up) → cut out, trimmed,
  88px-wide sprite; prints origin + muzzle for `src/rowdies.lua`

## Conventions
- Code and comments in English.
- Keep game logic separate from input/rendering: nothing under `World:update` may call
  love.graphics, Effects, Camera or Controls (multiplayer: see Multiplayer plan below).
- World units: 1 tile = 64px. HUD is laid out for a 720px short screen side and scaled
  by `uiScale = min(w,h)/720`; fonts use dpiscale.
- Colors are relative to the viewer: own health bar green, allies blue, enemy bots red,
  enemy players orange (team fight: enemies red); team fight adds a ring in that color.
- Rowdy stats live in `src/rowdies.lua`; bullets read range/bulletSpeed/damage from owner.
- Tile art uses nearest filtering to avoid bleeding when scaled.

## Art
- Comic style (default): one still sprite per character, generated with
  Google Gemini (prompts + raw 1024px JPEGs in ~/Downloads/yard-wars-art/, not in the repo),
  top-down, facing UP, bold outline. Stored at 2x (88px wide), drawn at
  `Assets.comicScale` 0.6 with mipmaps; rotates around the head (`origin`). Keeps the
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

## Multiplayer plan (merged into master 2026-10-01)
Server-authoritative, host device = server, LAN first (enet is built into LÖVE 11.5).
1. DONE: `src/world.lua` refactor (single-player, same gameplay). Headless-tested: world
   runs with graphics/window modules disabled. Confirmed on the phone (2026-09-29).
2. DONE on desktop (two instances, 2026-09-29): host/join by IP, input → host, events +
   snapshots → clients, interpolation. Duel = free-for-all (own team per player), Waves =
   co-op. Checked: PvP kills/deaths agree on both sides, rowdy switch from a client,
   no friendly fire in co-op, disconnect removes the player / client returns to the menu.
   Confirmed phone <-> phone (Pixel 6a + moto g67, 2026-09-30).
3. DONE: LAN discovery (join screen lists hosts). Confirmed on devices (2026-10-01): Pixel
   6a finds a desktop host, and a phone as host is found too. moto g67 still has an older build.
   Open: own-player prediction/reconciliation, team mode, lobby/ready, player names.
4. Optional: internet play via a dedicated headless server on a VPS.
Not done yet: render interpolation between steps (60 Hz sim looks slightly uneven on
>60 Hz desktop monitors; Pixel 6a runs at 60 Hz).

## Next-step ideas
1. (done: super attack with charge meter + touch button; confirmed on the Pixel 2026-10-01)
2. (done: rowdy choice, rounds with timer/kill target/lives, result screen; confirmed on
   the Pixel 2026-10-01)
3. Sprite-frame animation system (legs walk cycle, torso pose, weapon layer)
4. More rowdies, gadgets, arena variety, bot A* pathfinding for bigger maps
   (done: team fight 3v3 with bots, local + LAN, 2026-10-01; not yet on a phone)
5. (done: LAN multiplayer; synthesized sound effects 2026-10-01, not yet on a phone)
