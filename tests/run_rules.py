"""Run authority/protocol tests without starting the game."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True, register_eval=False, register_builtins=False)
compile_lua = lua.eval("function(source, name) local f,e=load(source,name); assert(f,e); return f end")
for path in sorted((root / "mod" / "Scripts").glob("*.lua")):
    compile_lua(path.read_text(encoding="utf-8-sig"), path.name)
rules = compile_lua((root / "mod/Scripts/combat_rules.lua").read_text(), "combat_rules.lua")()
tests = compile_lua((root / "tests/combat_rules_test.lua").read_text(), "combat_rules_test.lua")()
print(f"PASS: {tests(rules)} combat/authority/protocol checks; all mod Lua files compile")
scenario = compile_lua((root / "mod/Scripts/scenario_rules.lua").read_text(), "scenario_rules.lua")()
scenario_tests = compile_lua((root / "tests/scenario_rules_test.lua").read_text(), "scenario_rules_test.lua")()
print(f"PASS: {scenario_tests(scenario)} Infiltrator faction checks")
mission = compile_lua((root / "mod/Scripts/mission_rules.lua").read_text(), "mission_rules.lua")()
mission_tests = compile_lua((root / "tests/mission_rules_test.lua").read_text(), "mission_rules_test.lua")()
print(f"PASS: {mission_tests(mission)} native mission slot/protocol checks")

geometry_factory = compile_lua((root / "mod/Scripts/geometry_sync.lua").read_text(), "geometry_sync.lua")()
geometry = geometry_factory(lua.table(), lua.table(role="host"), lambda _: None)
decode = geometry.decode
prefix = "TRMP1|G|/Game/Maps/DLC1/Prefabs/Dungeon_01|"
assert decode(prefix + "1,2,3,0,0,0,1") is not None
for payload in ["1,2,3,0,0,0,2", "1,2,3,0,0,0", "nan,2,3,0,0,0,1", "1e99,2,3,0,0,0,1", "1,2,3,0,0,0,1,9"]:
    assert decode(prefix + payload) is None
assert decode("TRMP1|G|/Game/UnapprovedMap|1,2,3,0,0,0,1") is None
print("PASS: 7 mission interior protocol checks")
lua.globals().package.loaded["combat_rules"] = rules
weapon = compile_lua((root / "mod/Scripts/npc_weapon.lua").read_text(), "npc_weapon.lua")()
weapon_tests = compile_lua((root / "tests/npc_weapon_test.lua").read_text(), "npc_weapon_test.lua")()
print(f"PASS: {weapon_tests(weapon)} native rifle authority/cover checks")
scheduler = compile_lua((root / "mod/Scripts/scheduler.lua").read_text(), "scheduler.lua")()
scheduler_tests = compile_lua((root / "tests/scheduler_test.lua").read_text(), "scheduler_test.lua")()
print(f"PASS: {scheduler_tests(scheduler)} game-thread scheduling/travel/reentry checks")
lobby = compile_lua((root / "mod/Scripts/lobby_state.lua").read_text(), "lobby_state.lua")()
lobby_tests = compile_lua((root / "tests/lobby_state_test.lua").read_text(), "lobby_state_test.lua")()
print(f"PASS: {lobby_tests(lobby)} Steam lobby status/UI checks")
session = compile_lua((root / "mod/Scripts/session_rules.lua").read_text(), "session_rules.lua")()
session_tests = compile_lua((root / "tests/session_rules_test.lua").read_text(), "session_rules_test.lua")()
print(f"PASS: {session_tests(session)} restart generation/rejoin checks")
online_factory = compile_lua((root / "mod/Scripts/steam_session.lua").read_text(), "steam_session.lua")()
online_tests = compile_lua((root / "tests/steam_session_test.lua").read_text(), "steam_session_test.lua")()
print(f"PASS: {online_tests(online_factory, lobby, session)} Steam invite/role/relay-join lifecycle checks")
