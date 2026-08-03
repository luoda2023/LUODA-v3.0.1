import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_config_model.dart';
import '../wechat_ui_tokens.dart';
import 'package:luoda_flutter/common.dart';

/// AI configuration page — manage multiple AI profiles + email binding.
class AiConfigPage extends StatefulWidget {
  const AiConfigPage({Key? key}) : super(key: key);

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  late List<_ProfileFormState> _profiles;
  late TextEditingController _emailCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final cfg = AiConfig.current;
    _profiles = cfg.profiles.asMap().entries.map((entry) {
      final p = entry.value;
      return _ProfileFormState(
        nameCtrl: TextEditingController(text: p.name),
        endpointCtrl: TextEditingController(text: p.endpoint),
        apiKeyCtrl: TextEditingController(text: p.apiKey),
        modelCtrl: TextEditingController(text: p.model),
        enabled: p.enabled,
        builtIn: p.builtIn,
        profileType: p.profileType,
        originalIndex: entry.key,
      );
    }).toList();
    _emailCtrl = TextEditingController(text: cfg.email);
  }

  @override
  void dispose() {
    for (final p in _profiles) {
      p.dispose();
    }
    _emailCtrl.dispose();
    super.dispose();
  }

  void _addProfile() {
    setState(() {
      _profiles.add(_ProfileFormState(
        nameCtrl: TextEditingController(),
        endpointCtrl: TextEditingController(),
        apiKeyCtrl: TextEditingController(),
        modelCtrl: TextEditingController(text: 'gpt-4o-mini'),
        enabled: true,
        builtIn: false,
        profileType: AiProfileType.text,
        originalIndex: -1,
      ));
    });
  }

  void _removeProfile(int index) {
    final profile = _profiles[index];
    if (profile.builtIn) return;
    setState(() => _profiles.removeAt(index));
    profile.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final current = AiConfig.current;
    final activeForm = _profiles.cast<_ProfileFormState?>().firstWhere(
          (profile) => profile!.originalIndex == current.activeProfileIndex,
          orElse: () => null,
        );
    final userForms = _profiles.where((profile) => !profile.builtIn).toList();
    var activeIndex = 0;
    if (activeForm != null) {
      activeIndex = activeForm.builtIn
          ? activeForm.originalIndex
          : AiConfig.builtInProfiles.length + userForms.indexOf(activeForm);
    }
    await AiConfig.save(AiConfig(
      profiles: userForms
          .map((p) => AiProfile(
                name: p.nameCtrl.text.trim(),
                endpoint: p.endpointCtrl.text.trim(),
                apiKey: p.apiKeyCtrl.text.trim(),
                model: p.modelCtrl.text.trim().isNotEmpty
                    ? p.modelCtrl.text.trim()
                    : 'gpt-4o-mini',
                enabled: p.enabled,
                profileType: p.profileType,
              ))
          .toList(),
      activeProfileIndex: activeIndex,
      email: _emailCtrl.text.trim(),
      usageByProfile: current.usageByProfile,
    ));
    for (var i = 0; i < _profiles.length; i++) {
      _profiles[i].originalIndex = i;
    }
    if (mounted) setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translate('Configuration saved'))),
      );
    }
  }

  Future<void> _testProfile(int index) async {
    final p = _profiles[index];
    final profile = AiProfile(
      name: p.nameCtrl.text.trim(),
      endpoint: p.endpointCtrl.text.trim(),
      apiKey: p.apiKeyCtrl.text.trim(),
      model: p.modelCtrl.text.trim().isNotEmpty
          ? p.modelCtrl.text.trim()
          : 'gpt-4o-mini',
      enabled: true,
      profileType: p.profileType,
    );
    if (profile.endpoint.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(translate('Please fill endpoint'))),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(translate('Testing...'))),
    );

    String? result;
    if (profile.profileType == AiProfileType.image) {
      final path = await AiImageService.generateWithProfile(
        profile,
        'A single green circle centered on a white background',
      );
      if (path != null) {
        result = translate('Image model');
        try {
          await File(path).delete();
        } catch (_) {}
      }
    } else {
      result = await callAiText(
        profile,
        'Reply with only OK.',
        temperature: 0,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result != null
              ? '${translate('Test succeeded')}: $result'
              : '❌ ${translate('Connection failed')}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
        title: Text(translate('AI Settings'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(translate('Save'), style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Email binding
          _buildSection(dark, translate('Bind Email'),
              translate('Send chat content to this email'), [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'you@example.com',
                filled: true,
                fillColor:
                    dark ? const Color(0xFF1C1E23) : const Color(0xFFF5F5F5),
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

          // Profile list header
          Row(
            children: [
              Text(translate('AI Models'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addProfile,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(translate('Add'),
                    style: const TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Profile cards
          ...List.generate(_profiles.length, (i) {
            return _buildProfileCard(dark, i);
          }),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProfileCard(bool dark, int index) {
    final p = _profiles[index];
    final profiles = AiConfig.current.profiles;
    final origProfile = index < profiles.length ? profiles[index] : null;
    final isBuiltIn = p.builtIn;
    final isActive = p.originalIndex == AiConfig.current.activeProfileIndex;

    return Card(
      color: dark ? const Color(0xFF2B2D32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: kWeChatPrimaryColor, width: 1.5)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header: name + status + actions
            Row(
              children: [
                // Profile name
                Expanded(
                  child: Text(
                    p.nameCtrl.text.isNotEmpty
                        ? p.nameCtrl.text
                        : translate('Profile name'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                // Built-in badge
                if (isBuiltIn)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      translate('Built-in'),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                if (isBuiltIn) const SizedBox(width: 4),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kWeChatPrimaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      translate('Active'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: kWeChatPrimaryColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                if (!isBuiltIn) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: p.enabled,
                      onChanged: (v) => setState(() => p.enabled = v),
                      activeColor: kWeChatPrimaryColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),

            // Built-in profiles: show only a subtitle, no credentials
            if (isBuiltIn) ...[
              const SizedBox(height: 6),
              Text(
                origProfile?.freeQuota != null && origProfile!.freeQuota > 0
                    ? '${translate("Text model")} \u2022 ${translate("Free 100 calls")}'
                    : translate('Image model'),
                style: TextStyle(
                    fontSize: 12,
                    color: dark ? Colors.white38 : Colors.black38),
              ),
            ],

            // User profiles: show endpoint/key/model fields
            if (!isBuiltIn) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<AiProfileType>(
                value: p.profileType,
                decoration: _inputDeco(
                  dark,
                  translate('Model type'),
                ).copyWith(labelText: translate('Model type')),
                items: <DropdownMenuItem<AiProfileType>>[
                  DropdownMenuItem(
                    value: AiProfileType.text,
                    child: Text(translate('Text model')),
                  ),
                  DropdownMenuItem(
                    value: AiProfileType.image,
                    child: Text(translate('Image model')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => p.profileType = value);
                },
              ),
              const SizedBox(height: 6),
              TextField(
                controller: p.endpointCtrl,
                decoration: _inputDeco(dark, 'https://api.openai.com/v1'),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: p.apiKeyCtrl,
                      obscureText: true,
                      decoration: _inputDeco(dark, 'sk-...'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: p.modelCtrl,
                      decoration: _inputDeco(dark, 'gpt-4o-mini'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _testProfile(index),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: Text(translate('Test'),
                        style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _removeProfile(index),
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 16, color: Colors.redAccent),
                    label: Text(translate('Remove'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.redAccent)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
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

  InputDecoration _inputDeco(bool dark, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: dark ? const Color(0xFF1C1E23) : const Color(0xFFF5F5F5),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    );
  }
}

/// Internal mutable state for one profile form.
class _ProfileFormState {
  final TextEditingController nameCtrl;
  final TextEditingController endpointCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController modelCtrl;
  bool enabled;
  final bool builtIn;
  AiProfileType profileType;
  int originalIndex;

  _ProfileFormState({
    required this.nameCtrl,
    required this.endpointCtrl,
    required this.apiKeyCtrl,
    required this.modelCtrl,
    required this.enabled,
    required this.builtIn,
    required this.profileType,
    required this.originalIndex,
  });

  void dispose() {
    nameCtrl.dispose();
    endpointCtrl.dispose();
    apiKeyCtrl.dispose();
    modelCtrl.dispose();
  }
}
