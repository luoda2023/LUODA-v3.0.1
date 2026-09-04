# -*- coding: utf-8 -*-
import io
p = 'flutter/lib/common/widgets/chat_page.dart'
s = io.open(p, encoding='utf-8').read()
lines = s.split('\n')

def block_of(needle, start_from=0):
    """Return (index_of_first_line_of_block, index_of_last_line_inclusive) for the block whose
    first statement line matches needle (searching from start_from)."""
    # We'll find the line index of needle, then we need the *statement start*: we assume needle is a method signature.
    for i in range(start_from, len(lines)):
        if needle in lines[i]:
            return i
    raise SystemExit('needle not found: ' + needle)

# 1) Replace _closeTransientPanels body
i = block_of('void _closeTransientPanels()')
assert 'if (!_showEmojiPicker && !_atOverlayVisible) return;' in lines[i+1]
j = i + 4  # closing brace of that method (signature, if-line, setState open, 3 lines, close)... verify below
# signature at i; body:
# i+1 if...
# i+2 setState( {
# i+3   _showEmojiPicker...
# i+4   _atOverlayVisible...
# i+5 });
# i+6 }
print('close block lines', i+1, '..', i+6)
for k in range(i, i+7): print(k+1, repr(lines[k]))
