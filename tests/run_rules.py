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
print(f"PASS: {scenario_tests(scenario, rules)} Infiltrator round/faction/protocol checks")
