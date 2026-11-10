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
