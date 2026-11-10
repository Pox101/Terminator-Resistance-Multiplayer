# 0.6.0-steam-dev — experimental invitation and relay transport

Adds local crash diagnostics with per-launch correlation, classified native
exceptions/relative module stack offsets, bounded projected event history,
release/helper hashes and signatures for grouping reports. A finite process
watcher prepares reports after abnormal exit; force-stops remain explicitly
uncertain. No report is uploaded automatically. The launcher provides local
review, public-sharing warnings and an option to disable report preparation.
Raw logs, dumps, saves, account/IP identifiers and freeform messages are
excluded. See DIAGNOSTICS-PRIVACY.txt. Includes parser/privacy/retention and
real watcher normal/abnormal-exit tests without crashing the game.

Adds accepted-invite callback handling, asynchronous lobby joining, owner/member
authorization and code/content compatibility checks. A running isolated mod
can switch from host to defender at the menu. The Versus panel starts the
original Infiltrator flow; native mission objectives are preserved.

Adds an authenticated/encrypted relay-only SteamNetworkingSockets UDP tunnel
with bounded frames/rates, a version/content/lobby handshake and restart
generations. The engine remains on loopback. Native restart metadata can be
carried by the lobby. Unsupported relay setup fails without direct-IP fallback.

Includes deterministic lifecycle/authorization tests and a developer local
Steam socket-pair mode for exercising actual two-instance game traffic.
Separate-account invitation delivery and Internet/real-peer privacy validation
remain pending. Recipients must run the isolated mod before accepting invites;
cold Steam launches of the original game are not redirected. There is no host
migration. This is not an Internet-ready public release; 0.5.1 stays local-only.

# 0.5.1 — first public local PvP technical test

Corrects the defender's result text: Infiltrator completion means Resistance
MISSION FAILED; native Infiltrator failure means Resistance MISSION SUCCESS.
The wire phase still describes the original Infiltrator mission. Native host
summary, mission objectives and death callbacks remain unchanged.

Adds a player quick start, test checklist, feedback template and a separate
Steam Community post draft. Explicitly identifies the build as two instances
on one PC with focused-window control, not Internet/LAN, split-screen or
simultaneous two-controller play. Steam invite acceptance and Internet game
transport remain future work. The public post/download are prepared locally;
creating a public release or submitting a community post is a separate action.

# 0.5.0 — mission restart and Resistance hands preview

Keeps the original Restart Mission call and tracks local session generations.
The previously connected defender waits for the new host listener, rejoins
and takes control of a fresh native soldier. Native loading-screen key presses
and the original Infiltrator intro remain. A restarted host process still
requires an explicit join. The generation provider is loopback-only.

Clears old-world references before gameplay updates when native C++ travel
bypasses reflected OpenLevel hooks. Finished clients stay quiescent through
disconnect; the new world resets their input/death presentation.

Adds installed Avatar arms, native plasma idle/aim/fire/reload animations and
Weapon_socket attachment to the Resistance first-person view. Replicates the
native rifle's reload flag to drive the hands. Includes reload/protocol and
restart-generation tests. Both instances should use this version.

Local accelerated restart validation does not certify long sessions or a
complete normal playthrough. Steam invitation acceptance and Internet game
transport remain unimplemented.

# 0.4.0 — native mission lifecycle preview

Preserves native Infiltrator weapon hits and the original soldier's health,
death callbacks and kill-statistic contribution. Stops movement, firing and
reloads after defender death without ending the Infiltrator mission.

Replicates native mission completion/failure and disables further defender
combat. Observes the shipped Infiltrator summary callback because its quest
actor remains Active even after the native MISSION COMPLETE screen appears.
Native failure/death takes priority over a summary. Excludes named commanders
from takeover and resets the mod's input lock when a new world is loaded.
Quiesces finished-client presentation and clears cached world handles on
supported travel callbacks; avoids the incompatible UE4SS3.0.1 LoadMap pre-hook.

Includes mission phase/protocol tests and accelerated local integration
validation. Full-duration normal playthroughs and repeated reconnect/travel
remain experimental. Native in-place Restart Mission is unreliable; relaunch
the isolated preview games for another run. Both instances should use this version. Steam invitation
acceptance and Internet game transport are still the next milestone.

# 0.3.0 — Steam menu and invitation preview

Adds Play Versus below Infiltrator Mode in the original Play menu, without
modifying game assets. It creates a private two-person Steam lobby and opens
Steam's native friend invitation dialog. Includes lobby status, reinviting
and leaving, plus native lifecycle and Lua status tests.

This is an invitation UI preview. Invitation acceptance, joining a game and
Steam Internet game transport remain unimplemented. Existing local gameplay
and isolated copied saves remain the test path.

# 0.2.0 — experimental Infiltrator mission takeover

Preserves the native Infiltrator mission and lets a joining player control
one existing bunker soldier. Hosting starts in the initialized world without
reopening the map. Original health, NPC mission references and objectives
remain native; there are no added round rules or player respawns.

Adds safe client character mirrors, bunker transform synchronization and
player aiming/damage using the original soldier rifle configuration.
Uses a fixed game-thread scheduler and queued key input after an observed
UE4SS Lua callback crash; no recurring async callback scheduling is required.
Local tests cover connection, takeover, native damage and interior placement.
Full mission completion, long-session stability, native weapon animation and
additional defenders are not yet validated. The client uses placeholder visuals.

# 0.1.0 — local development preview

Two isolated instances can connect on one PC, move independently and use a
human/Terminator combat prototype. The host validates ammunition, fire rate,
reloads and player hits. PvP is first-person only; co-op blocks player damage.

Includes installation, a small launcher, dependency and payload checksums,
save isolation, native helper sources, authority/protocol tests and a build
workflow. The archive contains no game files or personal runtime data.

This preview is local-only. Steam Internet transport, full PvE/campaign
support, faction selection, first-person hands, full vision mechanics and
competitive security are unfinished. Please report the game executable hash
and reproduction steps when reporting a problem; do not upload saves or logs
containing personal information to a public issue.
