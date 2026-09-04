import io
p='flutter/lib/common/widgets/chat_page.dart'
s=io.open(p,encoding='utf-8').read()
rem=[
"import 'package:luoda_flutter/common/favorites_send.dart';\n",
"import 'package:luoda_flutter/common/widgets/friend_picker_dialog.dart';\n",
]
for r in rem:
    if r in s:
        s=s.replace(r,''); print('removed', r.strip())
    else:
        print('NOT FOUND', r.strip())
io.open(p,'w',encoding='utf-8').write(s)
