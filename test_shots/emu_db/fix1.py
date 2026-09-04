import re, io
p = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\home_page.dart"
s = io.open(p, encoding="utf-8").read()
comment = "// main caller enters \"calling\" state; exit driven by on_voice_call_started/closed callbacks"
def repl(m):
    indent = m.group(1)
    return indent + "gFFI.chatModel.onVoiceCallWaiting(); " + comment + "\n" + indent + "bind.sessionRequestVoiceCall(sessionId: gFFI.sessionId);"
pat = re.compile(r"^(\s*)bind\.sessionRequestVoiceCall\(sessionId: gFFI\.sessionId\);", re.M)
new, n = pat.subn(repl, s)
io.open(p, "w", encoding="utf-8", newline="").write(new)
print("replaced:", n)
