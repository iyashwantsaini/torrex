import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/build_flags.dart';
import '../../core/settings_store.dart';
import '../../widgets/theme_toggle_button.dart';

/// First-launch wizard. Three steps:
///   1. Welcome / pick a path (Demo vs Connect existing).
///   2. Backend URL + API key (skipped automatically when Demo).
///   3. Done — summary and "Take me in".
///
/// Kept intentionally lightweight — no shiny illustrations, no heavy state
/// machines. We deliberately don't bake any URLs or keys into the bundle:
/// the user supplies their own via `Connect existing` or chooses `Demo`.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.settings,
    required this.onFinished,
  });

  final SettingsStore settings;
  final VoidCallback onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

enum _Path { demo, connect }

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageCtrl = PageController();
  // In production builds the demo card is hidden, so pre-select the
  // only remaining choice for a one-tap experience.
  _Path? _path = kAllowDemo ? null : _Path.connect;
  int _step = 0;

  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;

  static const _kRepoUrl = 'https://github.com/iyashwantsaini/torrex';
  static const _kSetupGuideUrl =
      'https://github.com/iyashwantsaini/torrex/blob/main/backend/README.md';

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _go(int next) {
    setState(() => _step = next);
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_path == _Path.demo) {
      await widget.settings.update(baseUrl: 'demo', apiKey: 'demo');
    } else {
      await widget.settings.update(
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
      );
    }
    await widget.settings.update(onboardingDone: true);
    if (!mounted) return;
    widget.onFinished();
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return WlmAppScaffold(
      appBar: WlmAppBar(
        title: 'Welcome',
        // No back-arrow on the first step; users skip via the button row.
        leading: _step == 0
            ? null
            : WlmHeaderIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () => _go(_step - 1),
              ),
        actions: [
          // Always allow bailing out — the user can configure later.
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: WlmGhostButton(
              label: 'Skip',
              onPressed: () async {
                await widget.settings.update(onboardingDone: true);
                if (!mounted) return;
                widget.onFinished();
              },
            ),
          ),
          ThemeToggleButton(settings: widget.settings),
          const SizedBox(width: 4),
        ],
      ),
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildStepWelcome(context),
          _buildStepCreds(context),
          _buildStepDone(context),
        ],
      ),
    );
  }

  Widget _buildStepWelcome(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'Torrex is a search front-end for Jackett.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'It does not download or seed. It just finds links you can hand off '
          'to your torrent client of choice.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.outline,
              ),
        ),
        const SizedBox(height: 24),
        const WlmSectionLabel('Pick a path'),
        const SizedBox(height: 12),
        if (kAllowDemo) ...[
          _PathCard(
            selected: _path == _Path.demo,
            icon: Icons.science_outlined,
            title: 'Try the demo',
            body:
                'Browse the UI with built-in fake results. No backend needed. '
                'You can switch to a real backend later from Settings.',
            onTap: () => setState(() => _path = _Path.demo),
          ),
          const SizedBox(height: 12),
        ],
        _PathCard(
          selected: _path == _Path.connect,
          icon: Icons.link_rounded,
          title: 'Connect to my Jackett backend',
          body:
              'Paste your backend URL and Jackett API key. If you don\u2019t '
              'have one yet, the next screen links to a 5-minute setup guide '
              'that runs Jackett free on Hugging Face Spaces.',
          onTap: () => setState(() => _path = _Path.connect),
        ),
        const SizedBox(height: 24),
        WlmPrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward,
          expand: true,
          onPressed: _path == null
              ? null
              : () => _go(_path == _Path.demo ? 2 : 1),
        ),
        const SizedBox(height: 16),
        Center(
          child: WlmGhostButton(
            label: 'View source on GitHub',
            icon: Icons.code_rounded,
            onPressed: () => _open(_kRepoUrl),
          ),
        ),
      ],
    );
  }

  Widget _buildStepCreds(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'Connect your backend',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Both fields are stored locally on this device. The API key uses '
          'your platform\u2019s secure store (Keychain / Keystore). '
          'Torrex never phones home.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.outline,
              ),
        ),
        const SizedBox(height: 20),
        WlmTextField(
          controller: _baseUrl,
          label: 'Base URL',
          hintText: 'https://your-space.hf.space',
          keyboardType: TextInputType.url,
          prefixIcon: Icons.link_rounded,
          clearable: true,
        ),
        const SizedBox(height: 12),
        WlmTextField(
          controller: _apiKey,
          label: 'Jackett API key',
          hintText: 'shown on Jackett dashboard',
          obscureText: true,
          prefixIcon: Icons.key_rounded,
          clearable: true,
        ),
        const SizedBox(height: 16),
        WlmCallout(
          tone: WlmCalloutTone.info,
          title: 'Don\u2019t have a backend yet?',
          body:
              'The setup guide walks through deploying a free Jackett Space '
              'on Hugging Face in about five minutes.',
          action: WlmGhostButton(
            label: 'Open setup guide',
            icon: Icons.menu_book_outlined,
            onPressed: () => _open(_kSetupGuideUrl),
          ),
        ),
        const SizedBox(height: 24),
        WlmPrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward,
          expand: true,
          onPressed: (_baseUrl.text.trim().isEmpty ||
                  _apiKey.text.trim().isEmpty)
              ? null
              : () => _go(2),
        ),
      ],
    );
  }

  Widget _buildStepDone(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Icon(Icons.check_circle_rounded,
            size: 48, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          _path == _Path.demo ? 'Demo mode ready' : 'You\u2019re all set',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _path == _Path.demo
              ? 'Search will return canned results. Visit Settings to switch '
                  'to a real backend any time.'
              : 'Searches will hit your Jackett backend. You can change '
                  'creds, theme, or pick a specific indexer in Settings.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.outline,
              ),
        ),
        const SizedBox(height: 28),
        WlmPrimaryButton(
          label: 'Take me in',
          icon: Icons.arrow_forward,
          expand: true,
          onPressed: _finish,
        ),
      ],
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
            color: selected
                ? scheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(body,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.outline,
                            )),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
