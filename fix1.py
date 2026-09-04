import io
p='flutter/lib/common/widgets/chat_page.dart'
s=io.open(p,encoding='utf-8').read()
s2=s.replace("translate('AI Model')", "translate('AI Models')")
assert s2!=s
io.open(p,'w',encoding='utf-8').write(s2)
print('replaced AI Model -> AI Models')
