import io
p = r"J:\codex-work\LUODA-v3.0.1\flutter\lib\mobile\pages\home_page.dart"
lines = io.open(p, encoding="utf-8").read().split("\n")
# swap so onVoiceCallWaiting precedes _enterVoiceCallUi push
for i in range(len(lines)):
    if "_enterVoiceCallUi(peerId, video: video);" in lines[i]:
        # next line should be the onVoiceCallWaiting we inserted
        if i+1 < len(lines) and "onVoiceCallWaiting();" in lines[i+1]:
            lines[i], lines[i+1] = lines[i+1], lines[i]
io.open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("swapped")
