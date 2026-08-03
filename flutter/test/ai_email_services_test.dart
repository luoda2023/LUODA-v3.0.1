import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/email_draft_service.dart';
import 'package:luoda_flutter/models/ai_config_model.dart';

void main() {
  test('text AI uses the chat completions endpoint and preserves Unicode',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final responseFuture = server.first.then((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer local-test-key');
      final payload = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      expect(payload['model'], 'local-text');
      expect(jsonEncode(payload), contains('生成一段文字'));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': '中文𠮷与 emoji 😀'}
          }
        ]
      }));
      await request.response.close();
    });

    final result = await callAiText(
      AiProfile(
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'local-test-key',
        model: 'local-text',
      ),
      '生成一段文字',
    );
    await responseFuture;
    expect(result, '中文𠮷与 emoji 😀');
  });

  test('text AI supports local compatible endpoints without an API key',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestSeen = Completer<void>();
    server.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'message': {'content': '本地模型正常'}
          }
        ]
      }));
      await request.response.close();
      requestSeen.complete();
    });

    final result = await callAiText(
      AiProfile(
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        model: 'local-no-auth',
      ),
      '测试本地模型',
    );

    expect(result, '本地模型正常');
    await requestSeen.future.timeout(const Duration(seconds: 2));
  });

  test('AI profile selection keeps text and image models separate', () {
    const builtInImage = AiProfile(
      name: 'built-in-image',
      endpoint: 'https://built-in.invalid/v1',
      apiKey: 'built-in',
      model: 'built-in-image',
      builtIn: true,
      profileType: AiProfileType.image,
    );
    const customText = AiProfile(
      name: 'custom-text',
      endpoint: 'http://127.0.0.1:11434/v1',
      model: 'local-text',
      profileType: AiProfileType.text,
    );
    const customImage = AiProfile(
      name: 'custom-image',
      endpoint: 'https://images.invalid/v1',
      apiKey: 'custom',
      model: 'custom-image',
      profileType: AiProfileType.image,
    );
    const config = AiConfig(
      profiles: <AiProfile>[builtInImage, customText, customImage],
      activeProfileIndex: 1,
    );

    expect(config.getProfileByType(AiProfileType.text).name, 'custom-text');
    expect(config.getProfileByType(AiProfileType.image).name, 'custom-image');
  });

  test('image AI accepts a base endpoint and writes returned bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final responseFuture = server.first.then((request) async {
      expect(request.uri.path, '/v1/images/generations');
      final payload = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      expect(payload['prompt'], '生成图片：绿色桌面');
      expect(payload.containsKey('response_format'), isFalse);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': [
          {
            'b64_json': base64Encode(<int>[137, 80, 78, 71, 13, 10, 26, 10])
          }
        ]
      }));
      await request.response.close();
    });
    final outputDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}ai_service_test',
    );

    final path = await AiImageService.generateWithProfile(
      AiProfile(
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'local-image-key',
        model: 'local-image',
        profileType: AiProfileType.image,
      ),
      '生成图片：绿色桌面',
      outputDirectory: outputDir,
    );
    await responseFuture;
    expect(path, isNotNull);
    final file = File(path!);
    expect(path, endsWith('.png'));
    expect(await file.readAsBytes(), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    await file.delete();
  });

  test('image AI downloads a URL response from compatible providers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final completed = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/v1/images/generations') {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'data': [
            {'url': 'http://127.0.0.1:${server.port}/generated.jpg'}
          ]
        }));
      } else if (request.uri.path == '/generated.jpg') {
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add(<int>[255, 216, 255, 217]);
        if (!completed.isCompleted) completed.complete();
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final outputDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}.dart_tool'
      '${Platform.pathSeparator}ai_service_url_test',
    );

    final path = await AiImageService.generateWithProfile(
      AiProfile(
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'local-image-key',
        model: 'local-image',
        profileType: AiProfileType.image,
      ),
      'URL image response',
      outputDirectory: outputDir,
    );
    await completed.future.timeout(const Duration(seconds: 5));
    expect(path, isNotNull);
    final file = File(path!);
    expect(path, endsWith('.jpg'));
    expect(await file.readAsBytes(), <int>[255, 216, 255, 217]);
    await file.delete();
  });

  test('email draft contains 20-message content and Unicode safely', () async {
    final messages = List<EmailDraftMessage>.generate(
      20,
      (index) => EmailDraftMessage(
        sender: index.isEven ? '本地' : 'VPS',
        sentAt: DateTime.utc(2026, 8, 3, 20, 0, index),
        text: '第 ${index + 1} 条 😀',
        fileName: index == 3 ? '图片𠮷.png' : '',
      ),
    );
    final body = EmailDraftService.formatMessages(
      messages,
      fileLabel: '文件',
    );
    Uri? launched;
    final opened = await EmailDraftService.openDraft(
      recipient: 'owner@example.com',
      subject: '聊天消息',
      body: body,
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    );

    expect(opened, isTrue);
    expect(launched?.scheme, 'mailto');
    expect(launched?.path, 'owner@example.com');
    expect(launched?.queryParameters['subject'], '聊天消息');
    expect(launched?.queryParameters['body'], contains('第 20 条 😀'));
    expect(launched?.queryParameters['body'], contains('[文件] 图片𠮷.png'));
  });
}
