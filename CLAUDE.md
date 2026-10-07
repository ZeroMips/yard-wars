# Yard Wars (LÖVE 11.x)

Top-down arena shooter in LÖVE (Lua) with mobile twin-stick controls. Currently 1 player
vs. 1 bot in a mirrored arena. The characters are "rowdies" (code: `Rowdy`, `Rowdies`).
Name everything "Yard Wars" / "yard-wars": no references to other games or their
trademarks anywhere (code, comments, docs, website, file names; renamed 2026-10-04).
Developed on Linux, tested on a Pixel 6a, a moto g67 (second
phone for LAN tests) and a Lenovo tablet (TB330FU, MTP name `LENOVO_TB330FU_...`), all with
the official LÖVE for Android 11.5 (same MTP path).

## Charter (read first)
`CHARTER.md` ("don't be evil"): fun and motivating but never addictive - no addiction
mechanisms, no graphical violence (target audience 6+), not the least interest in making
money. EVERY design decision is checked
against its five questions before it goes in; when in doubt, leave it out. Point out
existing things that break it.

## Running
- Desktop: `love .` in the project folder.
- Quick smoke test (no errors on load/first frames): `timeout 6 love .` — LÖVE prints
  error tracebacks to stdout; exit code 124 means it ran until the timeout.
- Packed build: `zip -9 -r ../yard-wars.love . -x '.git/*'`
- Test coins: `love . --coins 300` (adds to the saved coins in `profile.txt`).
- Boss fight: `love . --boss 4` (against rowdy 4, any rowdy, also owned ones; `--boss 4 host`
  hosts it for LAN helpers).
- LAN test on one machine: `love . --host` (or `--host waves`) and `love . --join 127.0.0.1`
  (or `love . --find` for the join screen with discovery) in a second terminal.
  UDP ports 27015 (game) + 27016 (discovery); if a phone can't connect/find the desktop:
  `sudo ufw allow 27015:27016/udp`.
- Self-update test: `love dist/yard-wars-N.love --update-url http://127.0.0.1:8000/updates/`
  (serve a dir filled by `tools/publish.sh --local DIR/updates` with `python3 -m http.server`;
  use a test clone with its own `t.identity` so the real save folder stays clean);
  `--no-update` turns the updater off. `love .` (git checkout, no build.txt) never updates.
- Scripted test harnesses (copy main.lua to game.lua in a temp dir, override love.update/
  draw, symlink `src`/`assets`): NEVER symlink conf.lua (writing the test conf overwrote
  the real one once), and set `t.window.vsync = 0` + `love.timer.sleep` — with vsync the
  window blocks forever when the screen is locked. Print needs `io.stdout:setvbuf("no")`
  if the process gets killed by `timeout`.

## Publishing updates (self-update over http, see `src/updater.lua`)
- Commit, then `tools/publish.sh`: `tools/build.sh` packs HEAD into `dist/yard-wars-<build>.love`
  (build = `git rev-list --count HEAD`, adds build.txt + version.txt; refuses a dirty tree),
  writes the manifest `latest.txt` (build/version/file/size/sha256), signs it (RSA-2048, key
  `~/.config/yard-wars/update-key.pem`, outside the repo; `--init-key` made it once and printed
  `Updater.PUBLIC_KEY`) and uploads via FTPS to `/updates/` (.love first, latest.txt last).
  Host/paths in `tools/publish.conf`; FTP login only in `~/.netrc` (chmod 600).
  Installed copies check on every start and switch to the new build automatically.
- Server side must answer PLAIN http (LÖVE has no https, the client doesn't follow redirects):
  `curl -I http://yardwars.zeromips.org/updates/latest.txt` must give 200 (until 2026-10-04 the
  host answered `301 -> https`; switched off in the manitu panel). publish.sh also uploads
  `updates/.htaccess` (`RewriteEngine Off`). The https site sends HSTS, so browsers that
  visited it upgrade on their own - test with curl, not a browser.
- The web space is only ~5 MB ("Exceeded storage allocation" on 2026-10-04): publish.sh
  keeps only the current build in /updates/ (deletes the others before and after the
  upload) and uploads it once more as `download/yard-wars.zip` for the website;
  `download/.htaccess` rewrites `yard-wars.love` to that zip (a .love is a zip). Keep the
  package small: the lobby side views are 256-colour PNGs (~160 KB for all six). `.gitattributes` keeps CLAUDE.md, tools/ and website/ out of
  the package (export-ignore).
- Website (`website/`: index.html, style.css, images/): static page about the game and its
  installation at http://yardwars.zeromips.org/, uploaded by `tools/publish-site.sh` (FTPS
  to the web root; robots.txt/sitemap.xml there are the hoster's). Shows the newest build
  from updates/latest.txt. Never mention the game that inspired this one on the website or
  in the shipped code - describe it on its own terms.
  "Our promise" section (after "What is it?", linked from the hero): the charter's main
  points for parents, linking CHARTER.md on GitHub. Only promise what is true NOW (no
  "toy weapons" while the guns still look real).
  Legal pages (German law): `impressum.html` (§ 5 DDG, noindex) and `datenschutz.html`
  (DSGVO: no cookies/tracking/third-party content; manitu server logs ~21 days with IP
  anonymization switched on in the manitu panel + AV-Vertrag; the game's update check; LAN
  stays local; authority LDI NRW), linked in the footer. Keep them true when adding
  anything that sends data (analytics, embeds, fonts from a CDN, online play, crash
  reports...). publish-site.sh refuses to upload while a `TODO-` placeholder is left.
  Screenshots in website/images/ come from a scripted harness (team fight with an
  autopilot overriding `Controls.get`, FPS line removed in the copy). Icons (favicon.ico
  16/32/48, images/icon-192.png, apple-touch-icon.png 180): the Shotgunner's head cropped
  from assets/images/side/shotgunner.png (box 6,0-200,194) on a rounded dark-teal square
  with a gold edge (made with a PIL snippet, not kept as a tool).
- conf.lua runs before an update is mounted: changes to it (window, identity) still need a
  manual install. Same for `Updater.boot()` itself: the hand-installed build's boot() mounts
  every later update, so keep update.txt's format compatible.

## Android test workflow (took a while to figure out — don't change without reason)
- Use the OFFICIAL "LÖVE for Android" (package `org.love2d.android`, APK from
  github.com/love2d/love/releases, 11.5). NOT `com.rk.love2d` (a different IDE app).
- Opening `.love` files via Drive / Files "open with" fails (content:// URIs).
- Working method: copy the unpacked game (main.lua at top level) via USB MTP to
  `/sdcard/Android/data/org.love2d.android/files/games/lovegame/`, force-stop LÖVE,
  start it from its icon. Also write `version.txt` (`git log -1 --format='%h %cd'`, not in
  git) into the game folder: the menu shows it bottom-left, so you can see which build runs
  (LÖVE keeps running in the background unless force-stopped). Also write `build.txt`
  (`git rev-list --count HEAD`), otherwise the copy never updates itself - or simply unzip
  `tools/build.sh`'s .love into the folder.

## Layout
- `main.lua` — client: state (menu/pick/join/game/pass/style), roles local/host/client, the modes of
  the start screen (`Menu.entries`: Duel, Team fight, Waves, Host duel = free-for-all, Host
  team fight, Host waves = co-op, Join); PLAY starts the chosen mode with the chosen
  rowdy (`Menu.rowdy`); a locked rowdy: `openBoss` (panel) → `startBoss(host)` = newGame with
  mode `{ boss = index }` and `Menu.fighter`; matchOver of a won boss fight →
  `Unlock.won` (message = result subtitle); result screen (Play again / Rowdy / Menu; LAN clients:
  Rowdy / Leave, the host starts the next round), fixed-step loop (`World.TICK` = 1/60, a shot from the
  controls is kept until a step uses it), local player by id (`localId`), world events →
  particles/shake, camera, HUD, minimap, rowdy switching.
  Yard Pass: every world event goes to `Pass.onEvent`, `matchOver` to `Pass.onRoundOver`
  (result screen XP, `tierUp` sound when its bar is full); `Pass.style(def)` (skin/trail/
  title/badge) goes into `addPlayer`/`setRowdy`/`Net.newClient`/`selectRowdy`.
  Escape / Android back: game → menu, menu → quit. (F2 used to toggle a Kenney
  character style; those sprites were removed 2026-10-04.)
- `src/world.lua` — the simulation, no graphics/input/effects (runs headless): entities with
  `id`/`team`/`def`/kills/deaths, bullets (sub-stepped, hit other teams), waves, bush
  hiding (`isHiddenFrom`), `nearestOpponent`, medpacks (dropped when a player makes a kill, not
  by bot kills; hurt players, not bots, heal `MEDPACK_HEAL` = 40% of max HP; gone after 15 s, max 24);
  loot boxes (`world.boxes`: first after `BOX_FIRST` 8 s, then every `BOX_EVERY` 20 s, max 3,
  away from rowdies/walls/bushes; block bullets and rowdies, `BOX_HP` 120, anybody's bullets
  break them) scatter `BOX_COINS` 4 coins (`world.coins`, `COIN_VALUE` 5, gone after 12 s) that
  only players collect -> `coin` event {id, value} (the world keeps no money); `update(dt,
  inputs[id])`; team fight (`mode.teams`): blue (left, `TEAM_BLUE`) vs red (right), 3 spawn
  spots per side, bots fill to `TEAM_SIZE` 3, `addTeamPlayer` (humans together on blue,
  red only when blue is full; replaces a bot), `removePlayer` (bot refills), `teamScores`, first team to
  `TEAM_KILL_TARGET` 15; rounds (`world.match`): duel = first to `KILL_TARGET` 10 or most kills after
  `TIME_LIMIT` 180 s (tie = draw), waves = `LIVES` 3 per player (`out` = no respawn), over
  when all players are out; boss fight (`mode.boss` = rowdy index): the players (team
  `TEAM_PLAYERS`) vs one big bot with that rowdy's def (`boss` flag, `BOSS_HP` 3x HP,
  `BOSS_SIZE` 1.4: `World.bossLook`, radius), no time limit, players respawn forever, the
  boss never respawns (`out`) - won (`winnerTeam` = players) when it is out (charter: you
  can't lose); `world:boss()`; `restartMatch()`; the world stands still while over; things
  that happened go to `world.events` (also shot/superReady/matchStart/matchOver for sounds) (spawn/death/step/impact/hit/heal)
  via `emit`, read with `takeEvents()`; also box/boxHit/boxBreak/coin. `death` carries
  `killer` (shooter id), `boxBreak` carries `by` (for the pass XP). Snapshots carry medpacks
  (`m`), boxes (`b`) and coins (`c`). `addPlayer(def, x, y, team, style)` / `setStyle`:
  cosmetics on the entity (`skin`/`trail`/`title`/`badge`, the skin goes into `look`),
  never used by the simulation.
- `src/net.lua` — discovery (`Net.newFinder`: query to broadcast + every address of the
  own /24 on UDP 27016 every 2 s, hosts answer with mode/players; one short-lived socket
  per 32 addresses because queries to absent hosts block the send buffer for ~3 s;
  use `socket.udp4()` + bind "0.0.0.0": `socket.udp()` + "*" becomes IPv6 on Android and
  sendto IPv4 fails with "hostname nor servname provided"), enet LAN server (runs next to the World on the host: hello → player,
  input per step, events reliable + 30 Hz snapshots unreliable, 6 s timeout) and client
  (hello/input/rowdy; input `fire` is a counter so lost packets lose no shot; hello and
  rowdy carry `style` = cosmetic ids, cleaned by `cleanStyle`; `Net.FIELDS` ends with
  skin/trail/title/badge/boss; `Net.PROTOCOL` 3 since the Yard Pass, 4 since bombs: input
  `dist`/`shotDist`, bullet `lob`, `blast` event; 5 since boss fights: welcome `mode.boss`,
  FIELDS `boss` - the replica makes the boss proxy big with `World.bossLook`). Version
  check: hello and welcome carry `Net.version()` = `Net.PROTOCOL` (bump when messages or
  `Net.FIELDS` change) + a hash of the `src/rowdies.lua` data + the build; a mismatch is
  refused with a reason ("The host has a newer build (52): restart to update"), different
  builds with the same protocol and rowdies may play together (git checkout <-> phone).
  Clients up to build 51 have no check: a newer host refuses them ("Could not connect")
- `src/replica.lua` — client-side World copy from snapshots: others interpolated 100 ms
  behind the host, own rowdy 50 ms; bullets drawn from spawn records (straight lines);
  events played when their time comes; clock offset = max(t - arrival), pulled down 10%
- `src/updater.lua` — self-update: `Updater.boot()` (first line of main.lua) mounts a
  downloaded newer build (`update-N.love` in the save folder, `update.txt`: build/file/
  state ok|trying/bad) over the game source and runs its main.lua; a build whose start never
  got past 3 s ("trying" at the next start) is marked bad and skipped. `Updater.start()`
  runs `src/updater_thread.lua` (love.thread: socket.http GET latest.txt, RSA check, download,
  size + sha256, write) and `Updater.update()` reads its status for the lobby's version line;
  a finished download restarts the game at once (`love.event.quit("restart")`) if the lobby
  is idle, otherwise it's used at the next start.
- `src/rsa.lua` — pure-Lua RSA verify (PKCS#1 v1.5 + SHA-256, e = 65537; 24-bit limbs,
  Montgomery multiplication; ~5 ms on desktop)
- `src/codec.lua` — message serializer (no loadstring; rejects malformed input)
- `src/join.lua` — join screen: address field in the upper half (last address saved; phone
  keyboard opens only when the field is tapped), found games below as tap-to-join buttons
- `src/profile.lua` — progress on this device (`profile.txt`): coins + bought rowdies (by
  name) + `beaten` (boss fights won, line "beaten ..."; old builds ignore it). Start: only
  the Shotgunner (`STARTER`, no `price`); Gunner 150, Sniper 300, Robot 500, Pirate 450
  (`price` in `src/rowdies.lua`); pass rowdies (`pass = true`, the Gardener) never for
  coins (`canAfford` false). Coins: own `coin` events (boxes) + round reward on
  `matchOver` (`REWARD`: win 30, draw 10, loss 5, waves 5 per cleared wave), added in
  main.lua's `playEvents` — so LAN clients earn on their own device too. `Profile.grant(name)`:
  a rowdy for free (pass reward).
  Hidden test mode (`Profile.testMode`, file `testmode.txt`): tap the build line bottom
  left in the lobby 7 times within 4 s (on/off, red "TEST MODE" tag). Every rowdy
  (`Profile.isUnlocked`) and every cosmetic (`Pass.owns`) counts as owned, nothing is
  written to profile.txt / pass.txt's `own`; rewards and challenge choice use the real
  ownership (`Profile.owns`).
- `src/seasons.lua` — Yard Pass data, checked on load like rowdies.lua: `Seasons.list`
  (id, name, `starts` date - shown from then on, so a season can ship early - `tierXp`,
  `tiers` = one reward each: `{coins}`, `{rowdy}` (= that rowdy's boss fight: the claimed
  tier is the ticket, src/unlock.lua; beaten before: the rowdy itself; already owned:
  `DUPLICATE_COINS`; every `pass` rowdy must be a tier reward - checked on load;
  `Seasons.rowdyTier(name)` → season, tier),
  `{cosmetic}`), `XP` table (win 100 / draw 60 / loss 40, waves 40 + 20 per cleared wave,
  knockout (`kill`) 10, chest 5, challenge 150, big challenge 600; no first-win-of-the-day
  bonus - removed for the charter), `BONUS_XP`/`BONUS_COINS` after the last tier,
  challenge pools `challenges`/`big` (`{id, kind, n, rowdy, mode}`; kinds kills (=
  knockouts)/wins/rounds/coins/chests/supers/medpacks/waves; ids stay "d."/"w." from the
  old daily/weekly pools), `OPEN` 3, `SWAPS` 1, `describe` ("Knock out 20 opponents").
  Season 1 "Garden Party" (starts 2026-10-05, 30 tiers x 1200 XP); tier 10 is the Gardener
  (build 57 still gave the Robot there).
- `src/pass.lua` — Yard Pass progress in its own `pass.txt` (NOT profile.txt: an older
  build after a bad update rewrites profile.txt with coins + rowdies only; checked: build
  53 leaves pass.txt alone): XP per season, claimed tiers, bonus count, selected season
  (default newest), the 3 open challenges + the big one (NOTHING depends on the date -
  CHARTER.md: they never expire; a done one stays until the next round starts / the pass
  screen opens - `Pass.refresh(true)` - then a new one takes its place; picked with a
  Park-Miller generator seeded by the number drawn so far, rowdy challenges only for
  really owned rowdies), swaps (1 in stock, finishing a challenge gives it back), owned +
  equipped cosmetics. Reads the old daily/weekly lines (before build 68) as open/big ones.
  `onEvent`, `roundStart`, `onRoundOver` (returns the breakdown for the result screen),
  `claim`, `claimBonus`, `claimable`, `swap`, `level`, `style`, `skinFor`, `equip`.
  `Pass.clock` (only for season start dates) can be replaced in tests. All XP goes into
  the selected season.
- `src/passview.lua` — pass screen: tier track (cards, scrolls sideways: drag/wheel/arrow
  keys, `dragged` like the picker), tap = claim (sound `claim` + spark burst), Claim all,
  challenges with a Swap button, the big challenge, season switcher (only with 2+ seasons).
  `PassView.drawBar` is also used by the lobby and the result screen.
- `src/cosmetics.lua` — cosmetics data, checked on load: skins (`rowdy` + `hue`/`sat`/
  `bright`/`tint` through a shader in assets.lua, or their own `image`), trails
  (`color`, `style` leaf/spark/bubble, drawn in bullet.lua), pedestals (`flowerpot`),
  badges (`icon`, `color`), titles. Unknown ids (another build over LAN) = default.
- `src/decor.lua` — drawing of badges, pedestals, titles and the pass reward icons
  (`Decor.drawReward`).
- `src/wardrobe.lua` — STYLE screen: skin for the shown rowdy (arrows switch rowdy),
  trail, pedestal, badge, title; locked ones dark ("Win it in the Yard Pass"). From the
  lobby (STYLE, key Y) and the picker cards' "Skins" button (also between rounds).
- `src/loot.lua` — drawing of loot boxes (treasure chest, shake/flash on hit, HP bar), coins
  (fly out, spin, blink), coin icon/counter and padlock for the menus
- `src/medpack.lua` — medpack drawing (comic box + red cross, bob, pop-in, blinks last 3 s);
  confirmed on the Pixel 2026-10-01
- `src/unlock.lua` — how a locked rowdy is won: `Unlock.state(def)` → nil / "challenge"
  (boss fight; coin rowdy: needs the coins, `canChallenge`; pass rowdy: its tier claimed,
  `hasTicket`) / "buy" (beaten, not paid: a LAN helper or too few coins then) / "pass"
  (tier not claimed); `Unlock.won(def, challenger)` after a won fight: marks it beaten,
  pays + unlocks on the device that started it (pass rowdy: granted with the ticket);
  `Unlock.why` (notice when it can't start). Rowdies owned before stay owned.
- `src/picker.lua` — rowdy choice screen (cards: picture, role, HP, attack, super), from the
  lobby (ROWDIES) or between rounds; locked cards dark with padlock + price (pass rowdy:
  "Yard Pass tier 10" / "Boss fight - free"), confirm button becomes "Challenge" (lobby:
  the boss panel; between rounds only a message), "Unlock" or "Yard Pass" (a second tap on
  a locked card doesn't buy). Fixed-size cards (210x310 HUD
  units) in a grid (landscape 5 columns, portrait 3) that scrolls between title and buttons:
  mouse wheel (`love.wheelmoved` → `Picker.wheel`), touch drag (`Picker.drag`; a touch that
  scrolled more than 12 units sets `Picker.dragged` and its release taps nothing), arrows
  (up/down = one row); `Picker.reveal()` scrolls the selected card into view
- `src/result.lua` — end-of-round screen (title, scoreboard with badge + title, coins, Yard
  Pass XP: parts, a bar filling over 1.5 s, "TIER 8!", completed challenges, buttons)
- `src/menu.lua` — start screen in mobile-game lobby style: chosen rowdy big on a pedestal
  (arrows switch, ROWDIES opens the card picker), mode card bottom right (tap: list of all
  modes, solo + LAN), PLAY button (locked rowdy, by `Unlock.state`: CHALLENGE + price (grey
  if too few coins) / CHALLENGE "Boss fight" (pass rowdy) / UNLOCK + price / YARD PASS +
  tier), boss fight panel (`Menu.bossOpen`: rules - you can't lose -, "You fight as" with
  arrows = `Menu.fighter` (usable rowdies only), FIGHT / WITH FRIENDS (LAN host) / BACK;
  keys left/right, Enter, H, Esc),
  coin counter next to the logo; YARD PASS button (season, tier, XP bar, red dot while
  something is claimable) and STYLE button; the rowdy with its skin, the equipped
  pedestal, badge (next to the name) and title (under the stats); landscape + portrait
  layouts; last rowdy + mode + fighter saved in `lobby.txt` ("4 duel 2"; old builds read
  the first two). Keys: left/right rowdy, up/down mode,
  Enter play, B cards, P pass, Y style
- `conf.lua` — title "Yard Wars", identity "yard-wars" (save folder), 1280x720 resizable window.
  Until build 46 the identity had another name; conf.lua is never replaced by an update, so
  devices installed by hand before keep their old save folder (and progress) until they
  are reinstalled by hand - then they start fresh.
- `src/assets.lua` — tilesheet quads (Kenney) + comic sprites; the image list comes from
  `src/rowdies.lua` (every entry + `Rowdies.bot`, `comic.image`): top view required (clear
  error if missing), side view optional; `Assets.look(def)` → plain-data look (image name,
  origin, muzzle; usable without graphics; `Assets.look(def, skin)` adds the skin's image/
  hue), `Assets.drawPortrait` (rowdy picture for menus, top view), `Assets.drawStanding`
  (side view on the lobby pedestal, false if none), both with an optional skin id;
  `Assets.beginSkin(look)` sets the hue/tint shader (Rowdy:draw uses it)
- `src/arena.lua` — 40x24 tiles (64px), left half defined and mirrored to the right;
  walls (solid, 2x2), crates (solid), bushes (hiding, 2x2); `resolveCircle`, `hitsSolid`,
  raycast, `hasLineOfSight`, `randomOpenPoint`, spawns
- `src/camera.lua` — follows player; `viewSize=720` world units along the SHORTER screen
  side (landscape + portrait); clamp to arena; shake; `toWorld()`
- `src/controls.lua` — input abstraction → `{ dx, dy, aim, fire, aiming }`
  - desktop: WASD + mouse (hold LMB to fire)
  - touch: left half = floating move stick; right half = aim stick, drag = aim beam,
    RELEASE = fire, drag back to center = cancel, quick TAP = auto-aim at nearest visible
    enemy in range (ignores walls; leads a walking target by its velocity over the last
    0.1 s and the attack's bulletSpeed); super button (left
    of the aim stick, charge ring, glows when full) = same gestures for the super.
    No in-game rowdy switching (chosen before each round; switching healed fully)
  - desktop super: hold right mouse button or E to aim, release to fire
  - `aimDist` (bombs): touch = how far the aim stick is pulled (dead zone = shortest
    throw, rim = full range), tap = distance to the auto-aim spot, desktop = mouse
    distance; main.lua keeps it with the pending shot (`pendingDist`), the LAN client
    sends it as `shotDist` too (a lost packet loses no distance)
- `src/rowdy.lua` — base class: stats, HP, ammo (3 bars + refill timer), shoot
  (pellets/spread), aim beam/cone (`drawAim`), health/ammo bars, animation (pose, walk
  sway/bob, breathing, recoil, muzzle flash, spawn pop-in); logic reports via `self:emit`
- `src/rowdies.lua` — data: Gunner (pistol), Shotgunner (5 pellets, 0.6 rad cone),
  Sniper (range 720), Robot (tank: 160 HP, slow, heavy single bolts), Gardener (season 1
  rowdy, boss fight from the pass at tier 10 (`pass = true`, no price; 400 coins up to build 68): spray of 4 water drops, narrow cone; origin set
  by hand - the water tank made the tool's guess too low), Pirate (bomb thrower, 450 coins,
  bought only; origin/muzzle by hand: the tool took the fuse spark as the muzzle),
  plus `Rowdies.bot` (enemy look + stats).
  Bombs: `lob = true` + `blast` (radius) on an attack (normal or super): the bomb flies
  `aimDist` far (clamped `Bullet.MIN_THROW`..range, measured from the body centre:
  `Rowdy:throwDist`/`landing`) in an arc over walls, rowdies and chests and explodes
  (world `explode`: every opponent and chest in the radius once, walls don't shield;
  `blast` event). Pirate: 40 dmg, radius 90, 2 bombs; super "Powder Keg" 90 dmg, radius 170. Supers (`stats.super`,
  charged by normal-attack damage, `charge` = damage needed): Gunner "Bullet Storm" (10-bullet
  fan), Shotgunner "Wrecking Ball" (big slow piercing ball), Sniper "Railgun" (fast,
  long, piercing), Gardener "Sprinkler Burst" (fan of 7 big piercing drops), Robot "Shockwave" (ring of 16 bolts: `spread` >= pi means an even ring
  from the body centre, aim preview = circle of its range). Super bullets: own `radius`, `wallRadius` (smaller size against walls: the Wrecking Ball
  grazes them instead of vanishing next to one), `pierce` (each rowdy hit once). Optional
  `shot` = shot sound name (src/sound.lua). The comment at the top is the "how to add a
  rowdy" checklist and explains the stats and the `comic` look entry. The entries are
  checked when the file loads (unknown fields, wrong types, names with spaces or twice,
  price, origin/muzzle; `shot` is checked in `Sound.load`): a typo stops the game with
  "src/rowdies.lua: entry 3 (Sniper): unknown field 'stats.bulletspeed'". Adding a rowdy = one
  entry here + its images (assets, tool and picker pick it up).
- `src/player.lua` — Player subclass, `update(dt, input, bullets)`, 0.25s fire buffer
- `src/enemy.lua` — Bot subclass (`isBot`), `update(dt, world)` targets the nearest opponent;
  states patrol/chase/strafe/retreat/flee/search, LOS +
  bush-reveal rules, aim spread, stuck detection (slides sideways); shoots within 0.88 of
  its range (and keeps a distance scaled to it), fires its super when ready and in range,
  bombs aimed at the target's distance (`aimDist`); a `boss` never flees
- `src/bullet.lua` — owner/team/damage/color; speed+range read from owner (default range 480)
- `src/sound.lua` — sound effects synthesized at startup (sfxr-style layers: square/saw/
  sine/triangle/noise with pitch slides + envelopes; no files): per-rowdy shots, hit/hurt,
  impact, poof (knockout), spawn, super, superReady chime, heal, round start, victory/defeat/draw, click,
  box/boxHit/boxBreak, coin, unlock, tierUp, claim.
  `Sound.play(name, x, y)`: quieter with distance from the own rowdy, panned; same sound
  not faster than 35 ms; M mutes (touch: speaker button top right on every screen, the
  minimap moves left for it); the setting is saved in `sound.txt`. ~70 ms to build on desktop (~220 ms without JIT).
- `src/scoreboard.lua` — in-game scoreboard top centre (duel/team: scores with bars to the kill
  target + timer, red in the last 30 s; waves: wave, lives as hearts, bots left; boss: one
  wide health bar; below the minimap on narrow screens) and banners (time marks, new wave,
  lost life, 1 kill to win, boss at half / 20%)
- `src/effects.lua` — particles: puff, sparks, burst, ring, heal ("+" signs), poof (a
  knocked-out rowdy: white clouds + yellow stars, no coloured blobs - charter)
  (`drawBelow`/`drawAbove` layers). On screen it's "knockouts" / "out", never kills/deaths
  (internally the fields and events keep the names kills/deaths/death).
- `assets/images/` — `tilesheet.png` (Kenney arena tiles), `comic/<name>.png` (top views),
  `side/<name>.png` (lobby side views)
- `tools/build.sh`, `tools/publish.sh`, `tools/publish.conf` — packing + signed upload (see
  "Publishing updates")
- `tools/make_comic_sprites.py` — AI image (white bg, facing up) → cut out, trimmed,
  88px-wide sprite; prints a ready-to-paste `comic = { image, origin, muzzle },` line for
  `src/rowdies.lua`; default names = the `image = "..."` of the playable rowdies in
  `src/rowdies.lua` that have a <name>.png in the folder (not the bot: top/bot.png in the new
  folder is a robot, the bot's sprite comes from ~/Downloads/yard-wars-art; name it to
  process it); optional names after the folder process only those (`... ~/Downloads/yard-wars-art-new/top robot`); `--scale K` keeps the
  relative sizes of the source images instead of scaling each to 88px wide; `--side` makes
  the lobby side views (`assets/images/side/`, 400px tall; enclosed white areas from
  `SIDE_HOLE_MIN` 1500 source px on are cut out - eyes are smaller, the gap in the
  Gardener's hose loop bigger). Check the printed origin: it assumes the head sits at the
  bottom of the sprite (wrong with something on the back)

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
- Comic style (the only character art): one still sprite per character, generated with
  Google Gemini (prompts + raw 1024px JPEGs in ~/Downloads/yard-wars-art/, not in the repo;
  the newer top + side view sheets are in ~/Downloads/yard-wars-art-new/, split into top/ and
  side/; the rowdies use these since 2026-10-04 (made with `--scale 0.27`, the Robot from
  top/bot.png), the enemy bot keeps the old sprite from ~/Downloads/yard-wars-art/),
  top-down, facing UP, bold outline. Stored at 2x (88px wide), drawn at
  `Assets.comicScale` 0.6 with mipmaps; rotates around the head (`origin`). Keeps the
  procedural animation (sway, bob, recoil, flash); no reload pose.
  New character: follow the checklist at the top of `src/rowdies.lua`.
- Kenney "Top-down Shooter" (CC0, see CREDITS.md): only the arena tiles (tilesheet.png).
  Its character sprites (and the F2 style toggle) were removed on 2026-10-04.
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
- Picker grid (scrolling, 210x310 cards) + data-driven art + Kenney characters removed
  (build 51, 2026-10-04): tested on desktop (smoke tests, LAN host/join/find, harness with
  12 rowdies in landscape + portrait: wheel, keys, auto-scroll, drag doesn't tap). NOT yet
  confirmed on device: touch-drag scrolling in the picker.

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

## Self-update status (2026-10-04)
- Tested on desktop with a local http server: update + instant restart, tampered .love /
  manifest rejected, crashing build marked bad (fallback to the built-in build), no server /
  timeout / 301 -> "update failed: ..." while the lobby keeps working.
- moto g67: build 38 + uncommitted changes installed by hand (has the updater) 2026-10-04.
- Pixel 6a: build 53 (the published .love, unzipped) installed by hand 2026-10-05; before it
  had a build from 2026-10-01 with the old identity, so its progress started fresh.
- Published to the real server: builds 47, 51 (replaced), 53 (2026-10-04: rowdy entry
  check + LAN version check), 57 (2026-10-05: Yard Pass, protocol 3), 59 (2026-10-05: Gardener), 62 (2026-10-06: Pirate +
  bombs, protocol 4), 64 (2026-10-06: hidden
  test mode), build 68 (2026-10-06: charter fixes - challenges never expire, no
  first-win bonus, knockouts, poof; website "Our promise"), build 71 (2026-10-07,
  current: boss fights to unlock rowdies, Gardener only via the pass, protocol 5;
  latest.txt + .love answer 200 over plain http). Website ("coins + boss fight")
  uploaded the same day.
- Boss fights NOT yet tried on a device (touch on the panel, fight feel on a phone).
- Tablet (TB330FU): build 68 (the published .love, unzipped) installed by hand 2026-10-07;
  before it had a build from 2026-10-03 without build.txt (never updated itself).
- Open: `love.event.quit("restart")` on Android (if it fails, the
  update is still used at the next start).

## Yard Pass status (2026-10-05, published as build 57)
- Free season pass, phases 1-3 of the plan: XP/tiers/challenges/pass screen, cosmetics
  (skins, trail, pedestal, badge, title; LAN shows the others' skins), season 1 content +
  website section. Tested on desktop: headless test of Pass (XP totals, challenge
  counters + filters, date-seeded choice, reroll, claims incl. rowdy unlock, bonus tiers,
  save/load), screenshot harness (lobby/pass/style/result/picker, landscape + portrait),
  LAN host + client (XP on both sides, cosmetics both ways), build 53 refused with the
  version message and leaves pass.txt alone, smoke tests duel/team/waves.
- Gardener added in build 59 (art: one Gemini sheet with top + side view, split in
  halves into ~/Downloads/yard-wars-art-new/top|side/gardener.png; prompts in
  gardener-prompts.md there). Tested on desktop (lobby, picker, staged firing + super).
- Open: NOT yet on a device (touch drag on the track, skin shader on GLES).

## Pirate status (2026-10-06)
- Bomb mechanics done and tested on desktop: headless (lands where aimed over a wall,
  only the radius is hit, chests too, range clamp, super radius), screenshot harness
  (arc + shadow + fuse, preview arc + blast circle, explosion), LAN (client throw lands
  at the aimed distance via `shotDist`), smoke tests.
- Art: one Gemini sheet (1376x768, so `--scale 0.253` = 0.27 x 720/768 for the same size),
  the side half mirrored (Gemini drew it facing left); prompt in
  ~/Downloads/yard-wars-art-new/pirate-prompts.md.
- Open: touch throw distance on a phone.

## Next-step ideas
1. (done: super attack with charge meter + touch button; confirmed on the Pixel 2026-10-01)
2. (done: rowdy choice, rounds with timer/kill target/lives, result screen; confirmed on
   the Pixel 2026-10-01)
3. Sprite-frame animation system (legs walk cycle, torso pose, weapon layer)
4. More rowdies, gadgets, arena variety, bot A* pathfinding for bigger maps
   (done: team fight 3v3 with bots, local + LAN, 2026-10-01; not yet on a phone)
5. (done: LAN multiplayer; synthesized sound effects 2026-10-01, not yet on a phone)
