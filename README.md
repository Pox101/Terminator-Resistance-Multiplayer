# Resistance Multiplayer — local preview

An unofficial Terminator Resistance experiment with two isolated game
instances on one Windows PC. The Infiltrator experiment keeps the original
mission: the host plays the native Infiltrator, while player two takes
control of an existing Resistance soldier in the selected bunker.

**This release connects two instances on one Windows PC. Steam Internet
matches are not implemented. It is a development preview, not finished
campaign co-op or a competitive multiplayer release.**

Stability is experimental. Native client initialization required safe visual
mirrors. A crash dump identified a fault inside UE4SS Lua callback handling;
recurring asynchronous scheduling was replaced by a fixed game-thread callback
and a local deadline queue. Longer sessions and complete mission playthroughs
remain unverified. See [the related UE4SS issue](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180).

## Infiltrator mission experiment

- The original mission creates its randomized world before listen hosting
  starts. Hosting does not reopen or replace the mission.
- The joining player drives one existing bunker soldier. Its original
  actor, health, team and mission references stay on the host.
- The host keeps the native Infiltrator weapon, health, HUD and vision.
- Native Infiltrator shots damage the original player-controlled soldier.
  Its native death contributes to the game's own kill statistics. A dead
  defender loses movement and firing and stays eliminated without respawning.
- Player shooting uses the soldier's original rifle range, rate, ammo and
  damage type, with server hit tests feeding the native damage system.
  Reload requests use the native weapon component.
- Randomized bunker interior transforms are sent to the client.
- Original mission objectives remain. There is no added round timer,
  defender-kill victory condition or automatic player respawn.
- The client receives the native mission outcome. Native mission completion
  and Infiltrator defeat stop further defender actions and show an end message.
  For another test, close and relaunch the isolated preview games. The native
  **Restart Mission** path is unreliable with a connected client.

This is a one-defender experiment. Other soldiers remain NPCs. Additional
human slots, full NPC animation/ragdoll synchronization and polished first-person
hands still need work. End-to-end native weapon hits, defender death and the
native ending flow were exercised in an accelerated local integration test;
a normal full-length playthrough and longer sessions remain unverified. The joining player's
weapon/body presentation uses placeholder visuals.

## Earlier arena prototype

- Plasma firing requests over the existing owned player connection.
- Host-controlled ammunition, fire rate, two-second reloads and hit tests.
- Player health, kills/deaths and five-second respawns without invoking the
  single-player game-over/save pipeline.
- PvP uses first person; its third-person switch is disabled.
- Co-op blocks damage between players and permits first/third person.
- A combat HUD, weapon meshes, muzzle/audio effects and Terminator vision
  preview. First-person hands and proper weapon animations remain unfinished.

The arena prototype assigns the native host as human and joining base
characters as Terminators. Human/Terminator balancing is preliminary (100
versus 1000 health). General faction selection and additional players have
not been play-tested.

## Install

1. Own and install the compatible Steam game. Download the release ZIP and
   extract it before running anything.
2. Double-click **Install-Mod.cmd**. It finds the Steam game, downloads the
   pinned official UE4SS dependency, and prepares isolated game copies under
   `%LOCALAPPDATA%\TRMP-LocalPreview`.
3. Open **Launch-Mod.cmd in the installed folder**. For the mission test,
   select **Start Infiltrator mission host**.
4. In the host game choose **Play → New Infiltrator Mode**, finish the intro
   and wait for automatic hosting. Existing copied campaign saves remain available.
5. Select **Play a Resistance NPC**, then **Join player two** and finish the
   joining game's loading screen. The soldier appears inside the chosen bunker.

For the earlier arena test, start a co-op/PvP host, choose **Play → Continue**
to use the copied save, then **Host loaded save** before joining player two.

### Steam invitation preview

In an isolated mod game, choose **Play → Play Versus**, below Infiltrator
Mode. This creates a private two-person Steam lobby and opens Steam's friend
invitation dialog. **Invite Friends** reopens that dialog; **Back** leaves
the lobby. Steam must be running with the overlay enabled.

This previews the menu and invitation flow only. Accepting an invitation,
joining a match and carrying game traffic over Steam are not implemented.
Use the launcher steps above for the existing two-instance local test.

If automatic discovery fails, run:

```powershell
.\Install-Mod.ps1 -GameRoot 'D:\SteamLibrary\steamapps\common\Terminator Resistance'
```

The installer verifies this executable SHA256 before installing:
`5A01BBEE102990B1B1108C8656994ED19D46A9B2735C3B3A11EB9C7921CAFDB4`.
Other builds and content combinations have not been validated. The shipped
Infiltrator and Resistance soldier assets used by the prototype must be
installed; DLC/content compatibility still needs broader testing.

## Save isolation

The installer reads and copies original saves once into each isolated
profile. Game launches use their own `-UserDir`. Updating the preview keeps
those copied profiles. Installation never writes to the original game or
original save directory. The large Engine/Content folders are linked to the
existing installation and are not bundled or duplicated.

Close the preview game windows before updating. Do not publish your runtime,
profile, backup, crash or log directories when sharing the source project.

## Experimental Infiltrator mission takeover

The launcher also offers **Start Infiltrator mission host** and **Play a
Resistance NPC**. This scenario is under live validation; it is separate from the
campaign-save arena above.

1. Start the Infiltrator host. Choose **Play > New Infiltrator Mode**, select
   Normal difficulty and finish the loading screen and intro.
2. Hosting starts in the existing mission after the intro. Do not use
   **Host loaded save** for this scenario: it would reopen the level.
3. Start the Resistance defender and use **Join player two**. Finish its
   loading screen promptly; this map is larger than the arena map.
4. Player two takes control of an existing soldier in the selected Tech-Com
   bunker. Both players use first person. The Infiltrator still follows the
   original intel/bunker objectives. The defender tries to stop it.

The native host runs the Infiltrator and Resistance NPC simulation. The
client uses base-engine character mirrors to avoid executing unsupported
single-player callbacks. NPC mirrors currently use the common Resistance
soldier model, walking/idle animation and disappear on death; full ragdolls
and precise weapon-animation replication are unfinished. The defender's
movement drives the original NPC, and firing/reloading commands use that
NPC's original weapon component. Its original health and quest/death
callbacks remain authoritative. The current client weapon mesh is a visual
placeholder. The installed Infiltrator/Franco model is used;
an exact film-model T-850 designation has not been established.

There is no added survival timer or replacement victory condition. Killing
the controlled soldier removes that original NPC; the Infiltrator mission
continues. Restart through the game's original mission flow. The prototype
currently supports one remote NPC player; larger player counts are untested.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Left mouse | Fire plasma rifle |
| Right mouse | Aim zoom |
| R | Reload |
| F5 | First/third person in co-op; rejected in PvP |
| V | Joining Terminator's vision preview |
| F6 / F7 | Host current gameplay level / join localhost |

Focus the window for the player you want to control. Short automated key taps
may be missed by the loader; normal held input is sampled independently for
the foreground process. Spawning near scenery can obstruct movement; strafe
into clear space. The shoulder camera pulls forward around obstructions.

Resistance ultravision for all networked humans and full Terminator
scanning/highlighting are intended features, not completed ones. Campaign
AI, objectives, progression, enemy damage and general map travel are not
certified for co-op by this preview.

## Networking and security status

The launcher binds IP networking to **127.0.0.1**. Do not change it to expose
the prototype on the Internet. The host computes player hits and owns combat
state; clients send only fire/reload actions. Existing owned engine RPCs
carry these actions. That temporary carrier needs replacement/review before
production online use. Packet/state validation and weapon rate limits are
covered by tests, but the original engine's networking surface is not audited.

The optional Steam diagnostic found the game authenticated as app 954740,
obtained SteamNetworkingSockets012, delivered a local network socket-pair
payload and reported the relay network available. This does **not** prove
Steam peer-to-peer game connectivity, relay-only IP privacy or cheat resistance.
A real peer/session transport and Internet test are still required.

## Build and test

Use Visual Studio C++ x64 build tools on Windows:

```powershell
.\Build-Native.cmd
python -m pip install -r tests/requirements.txt
python tests/run_rules.py
.\Package-Release.ps1
```

The package builder uses an explicit file allowlist and generates a payload
manifest plus archive SHA256. It excludes game files, saves, logs and local
attachments. The GitHub workflow builds/tests and uploads a preview artifact;
an explicit release workflow can publish a prerelease once the repository is
connected. See `docs/RELEASE-NOTES.md` and `docs/ROADMAP.md`.

MIT applies to the project's original code. Game content and dependencies
retain their own rights; see `THIRD-PARTY-NOTICES.txt`.
