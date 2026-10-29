# Yard Wars (LÖVE 11.x)

Top-down arena shooter in LÖVE (Lua) with mobile twin-stick controls. Modes: duel, team
fight, waves, Yardball (a ball game), King of the Yard (4 teams of 3, last team standing),
Hide and seek (1 seeker, 5 hiders) and boss fights, solo against bots or over LAN, in a
mirrored arena. The characters are "rowdies" (code: `Rowdy`, `Rowdies`).
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
- LAN test on one machine: `love . --host` (or `--host waves` / `team` / `yardball` / `king` / `hide`) and `love . --join 127.0.0.1`
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
  stays local; authority LDI NRW; e-mail contact: mailbox at manitu), linked in the footer.
  Contact for players: yardwars@zeromips.org (footer of index.html, datenschutz section 5;
  the legal contact in Impressum/Datenschutz stays info@zeromips.org). Keep them true when adding
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
  the start screen (`Menu.entries`: Duel, Team fight, Waves, Yardball, King of the Yard, Hide and seek, Host duel =
  free-for-all, Host team fight, Host waves = co-op, Host Yardball, Host King of the Yard, Host hide and
  seek, Join); PLAY starts the chosen mode with the chosen
  rowdy (`Menu.rowdy`); a locked rowdy: `openBoss` (panel) → `startBoss(host)` = newGame with
  mode `{ boss = index }` and `Menu.fighter`; matchOver of a won boss fight →
  `Unlock.won` (message = result subtitle); result screen (Play again / Rowdy / Menu; LAN clients:
  Rowdy / Leave, the host starts the next round), fixed-step loop (`World.TICK` = 1/60, a shot from the
  controls is kept until a step uses it), local player by id (`localId`), world events →
  particles/shake, camera, HUD, minimap, rowdy switching.
  Yard Pass: every world event goes to `Pass.onEvent`, `matchOver` to `Pass.onRoundOver`
  (result screen XP, `tierUp` sound when its bar is full); `Pass.style(def)` (skin/trail/
  title/badge) goes into `addPlayer`/`setRowdy`/`Net.newClient`/`selectRowdy`.
  Yardball: goals + ball drawn with src/ball.lua, kick preview while carrying, a tap
  kicks at the opponents' goal (passed to `Controls.get` as a `kick` target), banners
  "GOAL!"; `openMenu` sets the arena back to the "yard" layout.
  King of the Yard: `teamColor`/`teamName` (own team blue "your team", the other three
  red/green/yellow in team-id order - per viewer), `focus()` = camera + sound listener
  (out: a living team mate), HUD lines (out with/without heart, in the fog, "stand on your
  team mate's heart"), scoreboard kind "king", banners (team out, last two teams, fog
  closing + `fog` sound, "You're back!"), result: own team rowdy by rowdy + one line per
  other team (Result shows 8 lines at most), title Victory / "2nd place".
  Hide and seek (`MODES.hide`, `hideseek = true`): seeker cover during the hide phase
  (`HideSeek.drawCover`, only the seeker's screen; the hiders see it counting in a bubble),
  disguised opponents drawn as a bush (team mates normal + a leaf, the own one with a
  see-through bush), pieces on the ground / above the carrier, the hint shimmer above the
  bushes, the frame below everything; the seeker's minimap never shows hiders (except
  during a hint); auto-aim skips disguised ones (`nearestOpponent`); no super button
  (`Controls.hasSuper`), the seeker's aim preview = the tag's reach (`HideSeek.drawTagAim`),
  hiders have none; `noBars` hides health/ammo bars; `focus()` follows a hider team mate
  once found; HUD lines, banners (seek, found, last hider, piece/picture, hint, time
  marks, countdown `tick`s), scoreboard kind "hide", result: "Seeker wins!" / "Hiders
  win!", the seeker first, then the hiders by how long they stayed hidden ("found 1st"
  ... "never found!", pieces placed).
  Escape / Android back: game → menu, menu → quit. (F2 used to toggle a Kenney
  character style; those sprites were removed 2026-10-04.)
- `src/world.lua` — the simulation, no graphics/input/effects (runs headless): entities with
  `id`/`team`/`def`/kills/deaths, bullets (sub-stepped, hit other teams), waves, bush
  hiding (`isHiddenFrom`), `nearestOpponent`, bots (since 2026-10-10: `newBot` picks a
  random rowdy of all of them (19 since 2026-10-14), locked ones too, `randomBotDef` prefers one nobody in the world
  uses; kept for the round incl. respawns, new ones at `restartMatch`/new wave/team refill;
  handicap `BOT_DAMAGE` 0.75 (applied in `damage()` via `damageScale`), `BOT_SPEED` 0.8,
  `BOT_CHARGE` 0.6 (`chargeScale` in `Rowdy:addCharge`); bosses not handicapped;
  `botTarget`: nearest opponent + `TARGET_CROWD` 250 px per other bot already after it,
  so bots split up), medpacks (dropped when a player makes a kill, not
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
  when all players are out; Yardball (`mode.yardball`, also `teams`, so team placement/
  bots/refill/colours work as in the team fight; checked BEFORE the `teams` branches):
  `World.new` switches the arena to the "pitch" layout, `world.ball` {x, y, vx, vy,
  carrier, lastKick, noPick}, walk over it = carry it (`e.carrying`, `World.carrySpot` in
  front along the aim), a player's `fire` while carrying = `World:kick` (aimDist from the
  body centre, `KICK_MIN` 120..`KICK_MAX` 650, the ball rolls exactly that far with
  `BALL_FRICTION`; the kicker can't take it back for 0.4 s), `Rowdy:shoot`/beam refuse
  while carrying, the super works; rolling ball bounces (axis-separated sub-steps) off
  solids, chests and the border except the goal mouths; reaching a goal's back line
  (rolling or carried) = goal for the other team (own goals count), `match.goals`,
  `e.goals`; carrier knocked out / frozen / grabbed / burrowed / vanished drops it; after
  a goal everybody respawns at the spot (no knockout) and the ball goes to the centre
  (`KICKOFF_DELAY` 1.5 s `world.kickoff`); first to `YARDBALL_GOALS` 2, no time limit
  (bot-only rounds: median ~100 s, 2026-10-11); a carrier is never hidden in a bush;
  `World:ballPlan(e)` for the bots (carrier: to the goal / the middle lane, shoots from
  520 px or when an opponent is within 120 px; free ball: the nearest bot of each team;
  opponent carries: the nearest bot goes for it, `botTarget` makes the carrier 700 px
  "nearer"); boxes never appear on the ball or near a goal; King of the Yard
  (`mode.king`, also `teams`, checked BEFORE the `teams` branches; 2026-10-14):
  `World.new` switches to the "kingdom" layout, `KING_TEAMS` 4 teams of `TEAM_SIZE` in the
  corners (`Arena.teamSpawns`), bots fill them; `addTeamPlayer` -> `addKingPlayer`: humans
  fill team 1, then 2, ... (LAN: host + first two joiners = team 1), taking a bot's place
  where it stands (out with its heart if it was out); `removePlayer` the reverse. A
  knockout (`knockout()`, shared by all modes) makes it `out` + a heart beacon
  (`world.beacons` {id, team, owner, x, y, born, expires, progress}); a team mate (player
  or bot, not burrowed) within radius + `BEACON_REACH` 34 for `REVIVE_TIME` 2 s brings it
  back there with `REVIVE_HP` 50% (progress resets when nobody stands on it); gone after
  `BEACON_LIFE` 20 s or when its team is out. Fog (`world.zone` {x, y, r0, r1, startAt,
  endAt, finalAt, finalEnd, r}, `World.zoneRadius(z, t)`, `World:inZone`): clear for
  `ZONE_WAIT` 15 s, shrinks to `ZONE_MIN` 350 over `ZONE_SHRINK` 90 s around a spot up to
  250 px from the middle, holds `ZONE_HOLD` 20 s, closes completely over `ZONE_FINAL` 30 s
  (every round ends by ~2:35; until 2026-10-15 30/150/30/45 s = ~4:15 - the user's first
  rounds ended in under 3 min and hardly noticed the fog); outside: `ZONE_DAMAGE` 12 HP/s in 0.5 s nibbles (`fog`
  event, a knockout there credits nobody). `checkMatch`: `teamUp(team)`, `match.place`
  [team] (eliminated in the same step = same place, `teamOut` event), `teamsLeft`; one team
  left = `winnerTeam`, none = draw. Bots: `botTarget` only sees opponents within
  `KING_NOTICE` 800 px (and never `out` ones, all modes), `World:kingPlan(e, visible,
  dist)`: out of the fog (to a point 350 px inside the edge, not the middle) / onto a team
  mate's heart within 900 px unless an opponent is in sight within 250 px; patrol stays
  near the bot and inside the clear circle. Bot-only rounds (10 seeds): median ~110 s
  (73-219) with the first fog times, ~74 s (56-99) with the faster fog (2026-10-15; bots
  keep out of it, no fog knockouts), 0-6 revives per round; Hide and seek (`mode.hideseek`,
  also `teams`, checked BEFORE the `teams` branches; 2026-10-25, Gideon's idea): `World.new`
  switches to the "hideout" layout; `start()` fills up to `HIDE_PLAYERS` 6 with bots and
  `startHideSeek` picks the seeker at random (`math.random`, the host) every round: team
  `TEAM_SEEKER` 1 at the frame, the others `TEAM_HIDERS` 2 on a circle around it
  (`hideSpawn`); `prepareHide`: fixed speeds `HIDER_SPEED` 240 / `SEEKER_SPEED` 255 (bots
  too), `noAttacks` (Rowdy:shoot/shootSuper refuse); `world.hide` {seekerId, phase
  "hide"|"seek", hideUntil, endAt, nextHint, hintUntil, placed, pieces = {id, x, y,
  carrier, placed}}; the seeker only ticks during `HIDE_TIME` 15 s; then `SEEK_TIME` 180
  s; its fire = `World:tag` (a `TAG` bullet: range 70, radius 30, pierce, projectile
  "swing", every `TAG_COOLDOWN` 0.6 s; a hit = `findHider`: death event (poof, killer =
  seeker), `out`, `foundAt`, `found` event, a carried piece drops there); `updateHide`:
  a hider standing still `DISGUISE_TIME` 2 s = `disguised` (moving or carrying ends it;
  only drawing - `isHiddenFrom` is unchanged, a carrier is never hidden), pieces picked
  up only while seeking (no piece runs in the hide phase), placed within `FRAME_REACH` of
  `Arena.frame` (`World.pieceSlot(k)`): `PIECE_TIME` 20 s off `endAt`, all 4 =
  `PICTURE_BONUS` 20 more; hints from `HINT_AFTER` 120 s of seeking every `HINT_EVERY` 20 s
  for `HINT_LENGTH` 1 s; `match.timeLeft` = endAt - time; `checkMatch`: no hider up =
  seeker wins, time up = hiders win. Joining (`addHidePlayer`) takes a bot's place as it
  is (a hider not found yet first, the seeker bot last; `takeOver`), leaving the reverse.
  No loot boxes in this mode. Bots (`World:hidePlan`, `Enemy:updateHide`): hiders walk to
  a hiding place (`hideSpots`: bush blocks + open spots at wall corners, not near the
  frame; far from the seeker, apart from each other) and stand still; run from a seeker
  in sight within `FLEE_DIST` 400 (a disguised one only within `BOLT_DIST` 130); half of
  them (`FETCH_SHARE`) fetch pieces from 5-55 s into the seeking while the seeker is out
  of sight or beyond `FETCH_SAFE` 900; the seeker chases hiders it sees (`SEEK_SIGHT` 650,
  a disguised one only within `NOTICE_DIST` 230 at `NOTICE_RATE` 1.2/s), swings within
  `TAG_REACH` 95, goes to the last seen / hinted spot, else checks the nearest unchecked
  hiding place (a swing into bushes); `GIVE_UP` 4 s without getting closer = another goal.
  Bot-only rounds (20 seeds, 2026-10-25): seeker wins 9/20, median 95 s, every round ends,
  2.5 pieces placed on average (BOLT_DIST was 190: seeker 12/20); boss fight (`mode.boss` = rowdy index): the players (team
  `TEAM_PLAYERS`) vs one big bot with that rowdy's def (`boss` flag, `BOSS_HP` 3x HP,
  `BOSS_SIZE` 1.4: `World.bossLook`, radius), no time limit, players respawn forever, the
  boss never respawns (`out`) - won (`winnerTeam` = players) when it is out (charter: you
  can't lose); `world:boss()`; `restartMatch()`; the world stands still while over; things
  that happened go to `world.events` (also shot/superReady/matchStart/matchOver for sounds,
  turn/freeze) (spawn/death/step/impact/hit/heal)
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
  FIELDS `boss` - the replica makes the boss proxy big with `World.bossLook`; 6 since the
  Student/Chef/Agent Angel: bullet + blast `projectile`, `turn` event (a boomerang's
  second leg: the replica keeps `legs` per bullet), `freeze` event, FIELDS `frozen`; 7
  since Doctor/Wrestler/Digger: pull/punch/leap/burrow events, FIELDS `air` + `burrowed`
  (a boolean on the wire); 8 since Ghostman/Wizard: input `hold`, blink/vanish/appear/
  grab/fling/bonk events, FIELDS beam/grabbing/held/vanished; 9 since Yardball: welcome
  `mode.yardball`, snapshot `y` (ball: x, y, carrier or 0, vx, vy, kickoff) +
  `match.goals`, kick/pickup/ballDrop/goal/bounce events, FIELDS `goals`; 10 since the
  mechanics for Gideon's 2026-10-12 sheets: snapshot `w` (barriers: id, team, expires,
  points), cuff/gust/barrier/magnet events, FIELDS `rooted` + `goo`; 11 since King of the
  Yard: welcome `mode.king`, snapshot `z` (zone: x, y, r0, r1 + the 4 times; the client
  computes r with `World.zoneRadius`) + `h` (beacons: id, team, owner, x, y, expires,
  progress) + `match.place`/`teamsLeft`, beacon/revive/beaconGone/fog/teamOut events; a
  king host doesn't `respawn` a joiner - `addTeamPlayer` placed it); 12 since Hide and
  seek: welcome `mode.hideseek`, snapshot `k` (seekerId, phase 1/2, hideUntil, endAt,
  hintUntil, placed, pieces {id, x, y, carrier or 0, placed 0/1}), FIELDS `disguised`,
  `placed`, `foundAt`, seek/tag/found/disguise/pieceUp/pieceDrop/piece/picture/hint
  events (no respawn of a joiner either; the replica puts a carried piece on its
  carrier's proxy and sets `carryingPiece`). Version
  check: hello and welcome carry `Net.version()` = `Net.PROTOCOL` (bump when messages or
  `Net.FIELDS` change) + a hash of the `src/rowdies.lua` data + the build; a mismatch is
  refused with a reason ("The host has a newer build (52): restart to update"), different
  builds with the same protocol and rowdies may play together (git checkout <-> phone).
  Clients up to build 51 have no check: a newer host refuses them ("Could not connect")
- `src/replica.lua` — client-side World copy from snapshots: others interpolated 100 ms
  behind the host, own rowdy 50 ms; the ball at the remote time, a carried one at its
  carrier's proxy (`carrying` set on the proxies); bullets drawn from spawn records (straight lines);
  events played when their time comes; clock offset = max(t - arrival), pulled down 10%
- `src/updater.lua` — self-update: `Updater.boot()` (first line of main.lua) mounts a
  downloaded newer build (`update-N.love` in the save folder, `update.txt`: build/file/
  state ok|trying|retry/crashed/bad) over the game source and runs its main.lua; a build
  whose start never got past 3 s gets one more start ("retry"), unless it logged an error
  then ("crashed"); after that it is marked bad and skipped (builds up to 71: bad at the
  first failed start, so closing the app within 3 s of a new build's first start killed
  it). Every Lua error goes to `crash.txt` in the save folder (build, date, traceback;
  wraps LÖVE 11.5's default `love.errhand` - `love.errorhandler` is nil there); the lobby's
  status line shows "last crash (build N): ..." while that build or an older one runs.
  These boot() rules only apply on devices whose hand-installed build has them.
  `update-log.txt` (save folder, last 160 lines): every start (installed build or
  downloaded update + update.txt then), check results, "confirmed", crashes, (only
  where the hand-installed build has it, from build 85 on) boot's decisions, and since
  build 106 the loading steps (`Updater.begin`/`Updater.step`: "load: begin / assets /
  sound / done / first frame" - a native crash or freeze while starting shows the last
  step) and a heartbeat: `alive.txt` (save folder) rewritten every 30 s with the time +
  `Updater.where` (main.lua: state, mode, role), removed in `love.quit` (`Updater.quit`);
  still there at the next start = "previous session ended without quitting (last seen
  ...)" (closed from the app list, killed by Android or a native crash; Lua errors are in
  crash.txt). Desktop-tested with `kill -9`.
  `Updater.report()` = header + update.txt + crash.txt + that log: shown by the info
  screen (`src/infoview.lua`: long press 0.6 s on the build line in the lobby, key I;
  scrolls; while update.txt lists bad builds a "Try build N again" button / key R =
  `Updater.retryBad`: clears the bad list, logs "retry asked", runs the update check
  again - the newest build is downloaded once more and used at the next start; tested on
  desktop with a local server (bad 107 -> downloaded -> next start runs 107, confirmed).
  Only there on devices whose running fallback build has it: a device whose hand-installed
  build is older needs one more hand install) and copied (`Updater.mirror()`, at start/check result/confirm/crash/info
  screen) to `yard-wars-info.txt` in the app's shared folder on Android
  (`.../Android/data/org.love2d.android/files/`, next to games/, readable over USB -
  the save folder is in private storage and is not), desktop only with `--info-dir DIR`.
  It is deleted and written anew each time: USB (MTP) keeps the size of a file's first
  write and cut rewritten copies off there (Pixel, 2026-10-10). Confirmed on the Pixel:
  info screen, and the copy read complete over USB (`gio cat mtp://...`). `Updater.start()`
  runs `src/updater_thread.lua` (love.thread: socket.http GET latest.txt, RSA check, download,
  size + sha256, write) and `Updater.update()` reads its status for the lobby's version line;
  a finished download restarts the game at once (`love.event.quit("restart")`) if the lobby
  is idle (not on Android, see the moto g67 below), otherwise it's used at the next start.
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
- `src/barrier.lua` — drawing of the Officer's barriers (traffic cones + striped tape,
  a line in the team colour, blinks in its last second)
- `src/hideseek.lua` — Hide and seek drawing: the frame (wooden, 4 slots, gold glow when
  complete), the picture pieces (`drawPart`: sun / cloud + bird / house / tree, made of
  shapes), ground + carried pieces, the disguise bush (the arena's bush quad at 76 px -
  smaller than the 128 px arena bushes, so it can be spotted), leaf, shimmer, counting
  bubble, the seeker's cover, minimap marks, the mode icon "hide" (used by src/menu.lua)
- `src/king.lua` — King of the Yard drawing: heart beacons (team-coloured ring, pulsing
  heart, green progress ring, blinks its last 4 s), the fog (a grey ring mesh from the
  clear circle outwards, soft edge, drifting cloud puffs; CHARTER.md: no poison look) and
  both on the minimap (zone circle clipped with a scissor, small hearts)
- `src/ball.lua` — Yardball drawing: the ball (spins while it rolls, pulses during the
  kick-off), goals (net + posts in the viewer's team colours), kick preview
  (`drawKickAim`), `drawIcon` (scoreboard, mode card icon "ball")
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
  walls (solid, 2x2), crates (solid), bushes (hiding, 2x2); layouts (`Arena.setLayout`,
  which also sets `Arena.cols/rows/width/height/center/spawn/enemySpawn` and rebuilds the
  grass batch on a size change - nothing may cache them: "yard" = the normal arena,
  "kingdom" = King of the Yard: 60x40 tiles, objects for the top-left quarter mirrored on
  both axes (`mirror4`), `Arena.teamSpawns[1..4]` = 3 spots per corner (1 top left, 2
  bottom right, 3 top right, 4 bottom left), open middle; "hideout" = Hide and seek: 60x40
  like "kingdom" (`mirror4`), 14 bush clusters/hedges, 7 sheds and 7 crates per quarter,
  open middle with `Arena.frame` (4x3 tiles, drawn, not solid), `Arena.pieceSpots` (one per
  quarter, tile 6.5/9.5 mirrored); "pitch" = Yardball: no centre wall, an open middle lane,
  `Arena.goals` [team defending it] = mouths of 4 tiles in the left/right border,
  `Arena.center`, pitch markings in `drawBelow`); `resolveCircle`, `hitsSolid`,
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
  - `hold` (Wizard's beam): touch = aim stick held outside the dead zone (releasing it
    fires nothing, a tap = a short beam), desktop = left button down
  - `aimDist` (bombs): touch = how far the aim stick is pulled (dead zone = shortest
    throw, rim = full range), tap = distance to the auto-aim spot, desktop = mouse
    distance; main.lua keeps it with the pending shot (`pendingDist`), the LAN client
    sends it as `shotDist` too (a lost packet loses no distance)
  - `Controls.kick` = {min, max} while carrying the ball (set by main.lua): the stick
    pull maps to the kick distance, a beam rowdy kicks on release too
- `src/rowdy.lua` — base class: stats, HP, ammo (3 bars + refill timer), shoot
  (pellets/spread), aim beam/cone (`drawAim`), health/ammo bars, animation (pose, walk
  sway/bob, breathing, recoil, muzzle flash, spawn pop-in); logic reports via `self:emit`
- `src/rowdies.lua` — data: Gunner (pistol), Shotgunner (5 pellets, 0.6 rad cone),
  Sniper (range 720), Robot (tank: 160 HP, slow, heavy single bolts), Gardener (season 1
  rowdy, boss fight from the pass at tier 10 (`pass = true`, no price; 400 coins up to build 68): spray of 4 water drops, narrow cone; origin set
  by hand - the water tank made the tool's guess too low), Pirate (bomb thrower, 450 coins,
  bought only; origin/muzzle by hand: the tool took the fuse spark as the muzzle),
  Student (300: fast long pen, super "Book Drop" = a lobbed book), Chef (400: frying pan
  `boomerang`, super "Waffle Toss" = 2 piercing waffle irons in a V), Agent Angel (450:
  `burst` of 4 from two toy blasters (`twin`), super "Freeze Balls" = 3 lobbed balls that
  `freeze` for 1.5 s), Doctor Fizzle (400: lobbed slime potions, super "Magnet Potion"
  = a shot that `pull`s the first one hit to the doctor), Wrestler (450: `kind = "leap"`
  body slam over walls, super "Punch Combo" = `burst` 4 with `dash` + glove melee),
  Digger (350: shovel melee = short wide piercing shot, super `kind = "burrow"` for 4 s),
  Ghostman (500: `kind = "blink"` teleport with a "boo" blast, super `kind = "vanish"` =
  5 s invisible beyond 150 px + through walls), Wizard (500: `kind = "beam"` held down,
  super `kind = "grab"` = Telekinesis: holds the first one on the beam 1.2 s, flings it;
  crashing into a wall/chest/rowdy does the damage), plus `Rowdies.bot` (the old grey
  enemy bot: no longer spawned since 2026-10-10, kept so the key "bot" and the LAN
  version hash stay valid).
  New rowdies from Gideon's 8 design sheets (2026-10-08, plan: phase 1 Student/Chef/Agent
  Angel, phase 2 Doctor Fizzle/Wrestler/Digger and phase 3 Ghostman/Wizard all coded;
  Doctor Fizzle = "Doctor Dummie" on the sheet, renamed with Gideon 2026-10-09). Art
  (2026-10-09): one Gemini sheet each (~/Downloads/yard-wars-art-new/<image>.jpeg, 1376x768,
  prompts in <image>-prompts.md), cut in halves into top/ and side/; the side views of
  Doctor, Digger and Wizard were drawn facing left and are mirrored. Top views made with
  `--scale 0.253`, origin (head centre; the Ghostman: the hat) and muzzle (weapon tip;
  Agent: one blaster, `twin` mirrors it) set by hand - the tool's guesses were off for
  most. Known quirks: the Wizard's top view is drawn half from the front (hands at the
  bottom, the wand pointing forward past the hat), the Doctor's beard points backwards;
  rotating doesn't fix either (a new Gemini image would). Website cards added
  (website/images/<image>.png = side view at 280 px), uploaded with build 79.
  Attacks: `Rowdy.attack` = the normal attack as a table (stats + defaults) like
  `stats.super`; `Bullet.new(..., attack, dist)` reads every attack field from it. Fields
  for both (checked on load, same list `ATTACK`): `radius`/`wallRadius`/`pierce` (now also
  on normal attacks), `boomerang` (flies `range`, a wall/chest turns it early, flies back
  to the throw point, hits everybody once per leg), `burst` + `burstDelay` (shots per
  attack, one ammo bar; `Rowdy.bursting` fires the rest in `tick`), `twin` (alternating
  mirrored muzzle), `freeze` (seconds; `Rowdy.frozen`: `canAct()` false, Player/Enemy
  stand still, drawn as an ice block), `projectile` (look in bullet.lua `ITEMS`: pen,
  book, pan, waffle, snowball, potion, magnet, glove, swing; slam/dirt = the blast of a
  leap/burrow), `pull` (World `PULL_SPEED`: `Rowdy:pushBy`, forced), `dash` (own push
  before each shot, stops in front of an opponent; bots use `Rowdy:reach`), `kind`
  ("leap": `Rowdy.leap`, `air` height, lands via `World:blastAt`, never in a wall:
  `leapTarget`; "burrow": `Rowdy.burrowed`, hidden + untouchable (`untouchable()`:
  bullets and blasts skip it), pops out on touching an opponent or after `duration`),
  "blink" (`leapTarget` too, may cross walls), "vanish" (`Rowdy.vanished`: `move` skips
  the walls, `reappear` puts it on open ground: `Arena.nearestOpen`; `isHiddenFrom`
  beyond HIDE_REVEAL, drawn as a shimmer up close), "beam" (`input.hold`; `Rowdy:shoot`
  only keeps `beamHold` up; `actBeam` traces with `World:traceBeam`, hits via
  `World:hitWith` every 0.1 s, ammo = smooth energy), "grab" (`Rowdy.grab`, the victim's
  `heldBy`; fling = a forced push with `impact` -> `crash`, "bonk" event),
  `duration`. `canMove()` (not frozen/pulled/leaping/held), `walks()` (also not
  dashing or handcuffed), `canAct()` (also not underground or grabbing).
  Since 2026-10-12 (for Gideon's second batch, see "New rowdies 2" below): `hold`
  (handcuffs: `Rowdy.rooted` s, can't walk, may attack), `goo` (extra damage over
  `World.GOO_TIME` 2 s in 0.5 s stings, `e.goo`), `chargeHit` (super charge per hit for
  an attack without damage), `blast` on a shot without `lob` = it bursts where it stops
  (rocket: first rowdy/wall/chest/range), kinds "heal" (`heal` share; bots use it below
  55% HP), "spin" (blast around itself; range = bot reach), "gust" (own push to aimDist,
  stops at the first opponent or wall, blast there; `Rowdy:gustTarget`), "magnet" (pulls
  the `targets` nearest opponents in sight, `pull = true`), "barrier" (`World:addBarrier`:
  an arc of 7 points 130 px in front, `world.barriers`, `duration`; opponents are pushed
  out and their shots/beams stop at it, bombs fly over, own team passes; drawn by
  src/barrier.lua). An even ring (`spread` >= pi) now starts at the aim (4 stones: one
  straight ahead; before, 4 pellets went out at +-45/135 degrees). Names may contain spaces ("Agent Angel"): profile.txt
  and pass.txt's skin lines write them with "_" (`Profile.encodeName`), so "_" is not
  allowed in names.
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
- `src/enemy.lua` — Bot subclass (`isBot`), `update(dt, world)` targets `World:botTarget`;
  spreads out (2026-10-10, measured in waves: average bot distance 470 -> 700 px):
  separation push from team mates within `SPREAD` 130 px, chase/retreat turned by a
  per-life `flank` angle (up to 0.8 rad), searches around the last seen spot (per-life
  offset up to 120 px), patrols near the target only 35% of the time (700 px area);
  states patrol/chase/strafe/retreat/flee/search (+ "ball": Yardball moves from
  `World:ballPlan`, shooting goes on), stuck = slides to the open side (2026-10-11;
  random before - bot-only team fights: stuck > 3 s 59 -> 40 times in 20 rounds), LOS +
  bush-reveal rules, aim spread, stuck detection (slides sideways); shoots within 0.88 of
  its range (and keeps a distance scaled to it), fires its super when ready and in range,
  bombs aimed at the target's distance (`aimDist`); a `boss` never flees
- `src/bullet.lua` — owner/team/damage/color; speed+range read from owner (default range 480)
- `src/sound.lua` — sound effects synthesized at startup (sfxr-style layers: square/saw/
  sine/triangle/noise with pitch slides + envelopes; no files): per-rowdy shots, hit/hurt,
  impact, poof (knockout), spawn, super, superReady chime, heal, round start, victory/defeat/draw, click,
  box/boxHit/boxBreak, coin, unlock, tierUp, claim, kick/pickup/bounce/goal,
  beacon/revive/fog (King of the Yard), tick/ready/rustle/piece/picture/hint (Hide and seek;
  the swing plays shot_shovel, a found hider the poof).
  `Sound.play(name, x, y)`: quieter with distance from the own rowdy, panned; same sound
  not faster than 35 ms; M mutes (touch: speaker button top right on every screen, the
  minimap moves left for it); the setting is saved in `sound.txt`. ~70 ms to build on desktop (~220 ms without JIT).
- `src/scoreboard.lua` — in-game scoreboard top centre (duel/team: scores with bars to the kill
  target + timer, red in the last 30 s; Yardball: goals, a ball instead of the timer;
  King of the Yard: 4 team boxes (own first) with the rowdies up, grey when out, + a fog
  box: countdown, then a pulsing cloud; Hide and seek ("hide"): hiders as heads (grey
  once found), the hide countdown / clock, the picture pieces as squares; waves: wave, lives as hearts, bots left; boss: one
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
  Gardener's hose loop bigger). Enclosed areas only count as background if they are as
  pure white as it (`HOLE_BRIGHT` 252: mean darkest channel; white clothes, beards and
  the ghost are shaded ~232-240 and stay - before 2026-10-09 the Chef's jacket was cut
  out). Check the printed origin: it assumes the head sits at the
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
- moto g67: build 38 + uncommitted changes installed by hand (has the updater) 2026-10-04;
  it updated itself, then marked build 71 bad ("build 71 crashed - skipped", back on 38).
  Desktop repro (build 38 booting update-71.love with old save data) ran fine; a start
  closed within 3 s gives exactly `bad 71`. Build 71 installed by hand 2026-10-08 (old
  files removed, the phone's conf.lua with identity `brawl-clone` kept, so its progress
  stays) and runs fine there. Gideon: played in the morning, the afternoon start
  crashed with no download in that session - so not the restart; cause unknown (no
  desktop repro with old or 71-written save data). Hence the crash log + retry rule;
  the moto needs one more hand install of a build that has them.
- Pixel 6a: build 53 (the published .love, unzipped) installed by hand 2026-10-05; before it
  had a build from 2026-10-01 with the old identity, so its progress started fresh.
  It updated itself up to 79, then dropped back to 53 after build 81 arrived (2026-10-10):
  53's boot marks a build bad at its first start that doesn't last 3 s, and the 79 file
  was already deleted. Cause unknown (the save folder with update.txt/crash.txt is in
  the app's private storage: not reachable over MTP, no adb here). Build 81 installed by
  hand the same day (all 69 files checked, conf.lua identity unchanged). The info
  screen then showed `bad 81` and no crash.txt (81 had the crash logger): most likely
  53's 3-s rule, not a crash. Build 85 (info screen + log, not published) installed by
  hand the same day.
- Published to the real server: builds 47, 51 (replaced), 53 (2026-10-04: rowdy entry
  check + LAN version check), 57 (2026-10-05: Yard Pass, protocol 3), 59 (2026-10-05: Gardener), 62 (2026-10-06: Pirate +
  bombs, protocol 4), 64 (2026-10-06: hidden
  test mode), build 68 (2026-10-06: charter fixes - challenges never expire, no
  first-win bonus, knockouts, poof; website "Our promise"), build 71 (2026-10-07:
  boss fights to unlock rowdies, Gardener only via the pass, protocol 5), build 79
  (2026-10-09: the 8 new rowdies from Gideon's sheets, protocol 8, updater crash
  log). Website with their cards uploaded the same day. Build 81 (2026-10-10:
  bots are random handicapped rowdies with supers and spread out; protocol unchanged).
  Build 86 (2026-10-10: info screen + update log + USB copy; latest.txt + .love
  answer 200 over plain http). Build 93 (2026-10-11: Yardball, protocol 9; website
  with the Yardball card uploaded the same day). Build 97 (2026-10-13: Posion,
  Fruit Man, Officer, Mecha Robot + their mechanics, protocol 10; website cards uploaded
  the same day). Build 101 (2026-10-14: Tornalo + King of the Yard, protocol 11;
  website with the King of the Yard card uploaded the same day). Build 103 (2026-10-15:
  King of the Yard's faster fog, protocol unchanged). Build 105 (2026-10-25: Hide and
  seek, protocol 12). Build 106 (2026-10-29, current: loading steps + heartbeat in the
  update log, protocol unchanged).
- New rowdies 2 (Gideon's photos of 2026-10-12, ~/Downloads/download (2).zip): Posion
  (goo spray cone + firework rockets; name as Gideon wants it), Fruit Man (two apples in
  a V + heals himself), Officer (handcuffs: 12 damage - "no damage" scored 0 knockouts,
  so the user chose a little damage 2026-10-12 - hold 1.2 s, quick and 4 ammo bars; + a
  barrier 6 s that also stops shots), Tornalo (spin + wind gust to an opponent), Mecha Robot (4 slingshot
  stones all around + pulls the two nearest). Mechanics coded + tested headless
  (2026-10-12, /tmp/yw-new); stats tuned in 1v1 bot fights (knockout shares Posion 46%,
  Fruit Man 41%, Officer 45%, Tornalo 47%, Mecha 39%, existing 38-50%). Gemini prompts
  <image>-prompts.md in ~/Downloads/yard-wars-art-new/. Art 2026-10-13 (one sheet each,
  --scale 0.253, origin/muzzle by hand; the top views of Fruit Man and the Officer were
  drawn facing down: turned 180 degrees; Posion's side view mirrored): Posion, Fruit Man,
  Officer and Mecha Robot are in src/rowdies.lua (+ website cards). Tested on desktop:
  mechanics test with the real entries, lobby/picker/game screenshots, LAN host + client
  (barriers, cuffs, goo, pulls, rockets, heals arrive), boss fights. Tornalo's art came
  2026-10-14 (top view: origin = the propeller hub, set by hand); appended at the END of
  the list (lobby.txt saves the rowdy by index - inserting would shift the Mecha), +
  website card. Tested: mechanics, boss fight, smoke tests, lobby/picker/game shots.
- King of the Yard (2026-10-14, plan with the user/Gideon: heart beacon instead of a
  tombstone, big map + fog, LAN teams in joining order): tested on desktop - headless rules
  test (layout + spawns + symmetry, yard restored, knockout -> out + heart, revive by a team
  mate in 2 s with 50% HP and not by an opponent, expiry, elimination + places, LAN order,
  leaving while out), 10 bot-only rounds (all end, median ~110 s), screenshots (start,
  out, revive, fog, result; landscape + portrait), LAN host + 2 clients on one machine
  (same teams/hearts/zone/revive on all, leavers become bots, protocol-10 build refused),
  smoke tests of all modes. Performance: a step with 12 rowdies ~0.1 ms with JIT, ~0.9 ms
  without (Android has no JIT); frames 5.3 ms vs 3.5 ms for a team fight (desktop).
  NOT yet on a device (frame rate with 12 rowdies + the fog mesh, round length with humans).
- Random-rowdy bots NOT yet tried on a device (feel of the handicap, how often bots
  use supers).
- New rowdies NOT yet tried on a device (Wizard's held beam on the touch stick, leap /
  blink distances, burrow and vanish, the feel of each).
- Boss fights NOT yet tried on a device (touch on the panel, fight feel on a phone).
- Hide and seek (2026-10-25, plan with the user/Gideon: random seeker, a tag swing for
  any rowdy, found = out and watching, bush disguise, 15 s hiding / 3 min seeking, hints
  after 2 min, the picture puzzle takes time off): tested on desktop - headless rules test
  (layout + symmetry, yard restored, 6 rowdies, random seeker, seeker frozen + no tag in
  the hide phase, no attacks, speeds, disguise after 2 s / ends when moving, one swing
  finds, carry / drop when found / place 4 = 100 s off, first hint at 2:00, end by time
  (15 + 180 s) and by all found, join/leave), 20 bot-only rounds, screenshots (hide phase,
  cover, disguised bushes, carrying, frame, hint, found spectator, result; landscape +
  portrait), LAN host + 2 clients on one machine. Frame on desktop: update 0.5 ms (host),
  draw 1.4 ms. NOT yet on a device (touch tag, readability of the disguise on a phone,
  round length with humans).
- Yardball (2026-10-11, published as build 93): tested on desktop (headless rules test, bot-only
  rounds, autopilot solo round + screenshots landscape/portrait, LAN host + client on one
  machine: same goals and carriers on both sides). NOT yet on a device (kick with the
  touch stick, tap-to-goal). Charter: no time limit, so a round only ends with 2 goals -
  watch the round length; a time limit would be one line in `World.newMatch`.
- Tablet (TB330FU): build 68 (the published .love, unzipped) installed by hand 2026-10-07;
  before it had a build from 2026-10-03 without build.txt (never updated itself). It
  updated itself up to 97; 2026-10-14 the user reported a crash on 97: the info file
  (read over USB) showed no Lua error, the 13:27 start of 97 never reached the update
  check result nor the 3-s confirm (earlier starts of 97 ran fine) - a native crash, a
  freeze or the app closed/killed within ~3 s; cause unknown. 68's boot marks a build
  bad after one such start, so build 97 (unzipped, all 80 files checked by sha256,
  conf.lua kept) was installed by hand the same day: now it has the retry rule and the
  crash/boot log from the first line.
- Android: no instant restart after a download (moto g67, 2026-10-08); the update is
  used at the next start.
- moto g67 crash 2026-10-29: the info file showed build 105 (downloaded, the phone's
  hand-installed base was still 71) with a start at 19:23:33 that logged nothing more (no
  check result, no confirm, no crash.txt): native crash, freeze or closed within ~1 s;
  the start before (19:13) was normal. 71's boot would have marked 105 bad at the next
  start, so build 105 was installed by hand the same day (the published .love, sha256
  checked, all 84 files compared on the phone by sha256, conf.lua with identity
  `brawl-clone` kept). Cause unknown - build 106 adds the loading steps + heartbeat to
  the log for the next time; ask Gideon what the screen showed.

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
