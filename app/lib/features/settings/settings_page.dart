import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/settings_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _indexer;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _indexer = TextEditingController(text: widget.settings.indexer);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _indexer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settings.update(
      baseUrl: _baseUrl.text,
      apiKey: _apiKey.text,
      indexer: _indexer.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const WlmSectionLabel('Backend'),
        const SizedBox(height: 8),
        WlmTextField(
          controller: _baseUrl,
          label: 'Base URL',
          hintText: 'https://your-space.hf.space',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        WlmKeyField(controller: _apiKey, label: 'API key'),
        const SizedBox(height: 12),
        WlmTextField(
          controller: _indexer,
          label: 'Indexer',
          hintText: 'all',
        ),
        const SizedBox(height: 24),
        const WlmSectionLabel('Appearance'),
        const SizedBox(height: 8),
        WlmSegmentedControl<ThemeMode>(
          value: widget.settings.themeMode,
          onChanged: (m) => widget.settings.update(themeMode: m),
          segments: const [
            WlmSegment(value: ThemeMode.system, label: 'System'),
            WlmSegment(value: ThemeMode.light, label: 'Light'),
            WlmSegment(value: ThemeMode.dark, label: 'Dark'),
          ],
        ),
        const SizedBox(height: 32),
        WlmPrimaryButton(label: 'Save', onPressed: _save),
        const SizedBox(height: 24),
        const WlmCallout(
          title: 'Where do these come from?',
          body:
              'Run the Hugging Face Space described in backend/README.md. '
              'Use the Space URL as Base URL and the API key shown on '
              "Jackett's dashboard.",
        ),
      ],
    );
  }
}
