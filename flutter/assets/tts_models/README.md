# TTS Model Bundle

构建含模型版本时，将 sherpa-onnx-vits-zh-ll 模型文件放在此目录。

## 文件结构

```
vits-zh-ll/
├── model.onnx
├── tokens.txt
├── lexicon.txt
├── date.fst
├── number.fst
├── phone.fst
├── new_heteronym.fst
└── dict/
    ├── jieba.dict.utf8
    ├── hmm_model.utf8
    ├── idf.utf8
    ├── stop_words.utf8
    └── user.dict.utf8
```

## 获取模型文件

从 hf-mirror 下载：

```bash
BASE_URL="https://hf-mirror.com/csukuangfj/sherpa-onnx-vits-zh-ll/resolve/main"
mkdir -p vits-zh-ll/dict

# 模型文件
for f in model.onnx tokens.txt lexicon.txt date.fst number.fst phone.fst new_heteronym.fst; do
  curl -L "$BASE_URL/$f" -o "vits-zh-ll/$f"
done

# 字典文件
for f in jieba.dict.utf8 hmm_model.utf8 idf.utf8 stop_words.utf8 user.dict.utf8; do
  curl -L "$BASE_URL/dict/$f" -o "vits-zh-ll/dict/$f"
done
```

## 构建含模型版本

```bash
flutter build apk --dart-define=BUNDLE_TTS_MODEL=true
flutter build windows --dart-define=BUNDLE_TTS_MODEL=true
```

## 注意事项

- 模型总大小约 133MB，会显著增加安装包体积
- model.onnx 约 100MB，是最大的文件
- 首次启动时会自动从 assets 复制到应用目录（约 2-5 秒）
- 复制完成后创建标记文件，后续启动跳过复制
