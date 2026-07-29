import 'package:flutter/material.dart';

import '../../models/ai_config_model.dart';
import '../wechat_ui_tokens.dart';
import '../common.dart';

/// AI configuration page — set API endpoint, key, model for chat translation.
class AiConfigPage extends StatefulWidget {
  const AiConfigPage({Key? key}) : super(key: key);

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  late TextEditingController _endpointCtrl;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _modelCtrl;
  bool _enabled = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final cfg = AiConfig.current;
    _endpointCtrl = TextEditingController(text: cfg.endpoint);
    _apiKeyCtrl = TextEditingController(text: cfg.apiKey);
    _modelCtrl = TextEditingController(text: cfg.model);
    _enabled = cfg.enabled;
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AiConfig.save(AiConfig(
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim().isNotEmpty
          ? _modelCtrl.text.trim()
          : 'gpt-4o-mini',
      enabled: _enabled,
    ));
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translate('Configuration saved'))),
      );
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // Temporarily apply current form values for the test
    final tempConfig = AiConfig(
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim().isNotEmpty
          ? _modelCtrl.text.trim()
          : 'gpt-4o-mini',
      enabled: true,
    );
    // Override cached config temporarily
    final saved = AiConfig.current;
    await AiConfig.save(tempConfig);
    final result = await AiTranslateService.translate('Hello, how are you?');
    await AiConfig.save(saved); // restore

    setState(() {
      _testing = false;
      if (result != null) {
        _testResult = '✅ $result';
      } else {
        _testResult = '❌ ${translate('Connection failed')}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = dark ? const Color(0xFF1C1E23) : kWeChatCanvasColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: dark ? const Color(0xFF25272C) : Colors.white,
        foregroundColor: dark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text(translate('AI Translation Settings'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(translate('Save'),
                    style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable toggle
          Card(
            color: dark ? const Color(0xFF2B2D32) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: SwitchListTile(
              title: Text(translate('Enable AI Translation'),
                  style: const TextStyle(fontSize: 15)),
              subtitle: Text(
                  translate('Translate messages via AI when right-clicking'),
                  style: TextStyle(
                      fontSize: 12,
                      color: dark ? Colors.white54 : Colors.black45)),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              activeColor: kWeChatPrimaryColor,
            ),
          ),
          const SizedBox(height: 16),

          // API Endpoint
          _buildSection(dark, translate('API Endpoint'),
              translate('e.g. https://api.openai.com/v1/chat/completions'), [
            TextField(
              controller: _endpointCtrl,
              decoration: InputDecoration(
                hintText: 'https://api.openai.com/v1/chat/completions',
                filled: true,
                fillColor: dark ? const Color(0xFF1C1E23) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ]),
          const SizedBox(height: 16),

          // API Key
          _buildSection(dark, translate('API Key'), translate('Your API key'), [
            TextField(
              controller: _apiKeyCtrl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'sk-...',
                filled: true,
                fillColor: dark ? const Color(0xFF1C1E23) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ]),
          const SizedBox(height: 16),

          // Model name
          _buildSection(
              dark, translate('Model'), translate('e.g. gpt-4o-mini'), [
            TextField(
              controller: _modelCtrl,
              decoration: InputDecoration(
                hintText: 'gpt-4o-mini',
                filled: true,
                fillColor: dark ? const Color(0xFF1C1E23) : const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ]),
          const SizedBox(height: 24),

          // Test button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.translate_rounded, size: 18),
              label: Text(_testing
                  ? translate('Testing...')
                  : translate('Test Connection')),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(_testResult!,
                  style: TextStyle(
                    fontSize: 14,
                    color: _testResult!.startsWith('✅')
                        ? kWeChatPrimaryColor
                        : Colors.redAccent,
                  )),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
      bool dark, String title, String subtitle, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                fontSize: 12, color: dark ? Colors.white54 : Colors.black45)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}
