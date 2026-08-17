# -*- coding: utf-8 -*-
import io
p = r'J:\codex-work\LUODA-v3.0.1\flutter\lib\common\widgets\chat_page.dart'
s = io.open(p, encoding='utf-8', newline='\n').read()

# Find the mobile composer build's Column children (the one right before _DesktopChatComposer class).
anchor = """        if (_showEmojiPanel) _buildEmojiPanel(),
        if (_showMorePanel) _buildMorePanel(),
        _buildInputBar(),
      ],
    );
  }
}

class _DesktopChatComposer extends StatefulWidget {"""
if s.count(anchor) != 1:
    raise SystemExit('anchor count=%d' % s.count(anchor))
new = """        if (_showEmojiPanel) _buildEmojiPanel(),
        if (_showMorePanel) _buildMorePanel(),
        if (AiConfig.current.profiles.isNotEmpty)
          _AiModelSelector(
            dark: Theme.of(context).brightness == Brightness.dark,
            chatModel: widget.chatModel,
            onOpen: closePanels,
          ),
        _buildInputBar(),
      ],
    );
  }
}

class _DesktopChatComposer extends StatefulWidget {"""
s = s.replace(anchor, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('MOBILE AI SELECTOR ADDED')
