import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/formatters.dart';
import '../../models/torrent_result.dart';

/// Full-screen view of a single torrent result. Mirrors what a typical
/// torrent-site "view page" shows: title, swarm stats, file size, indexer,
/// publish date, magnet hash, and the primary actions.
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.result});

  final TorrentResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hash = _extractHash(result.magnetUri);

    return WlmAppScaffold(
      appBar: WlmAppBar(
        title: 'Torrent',
        leading: WlmHeaderIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          WlmHeaderIconButton(
            icon: Icons.share_outlined,
            onPressed: () => _share(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Title — wraps cleanly, no overflow even for long release names.
          Text(
            result.title,
            style: theme.textTheme.titleMedium,
            softWrap: true,
          ),
          const SizedBox(height: 12),
          if (result.indexer.isNotEmpty || result.category.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (result.indexer.isNotEmpty) WlmChip(label: result.indexer),
                if (result.category.isNotEmpty) WlmChip(label: result.category),
                if (result.hasMagnet) const WlmChip(label: 'magnet'),
              ],
            ),
          const SizedBox(height: 20),

          // Swarm stats — three balanced columns using WlmStat for the
          // editorial big-number look.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: WlmStat(
                  label: 'Seeders',
                  value: '${result.seeders}',
                  trend: '\u2191',
                  trendPositive: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WlmStat(
                  label: 'Leechers',
                  value: '${result.leechers}',
                  trend: '\u2193',
                  trendPositive: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WlmStat(
                  label: 'Size',
                  value: formatBytes(result.sizeBytes),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const WlmDivider(),
          const SizedBox(height: 16),

          const WlmSectionLabel('Details'),
          const SizedBox(height: 8),
          WlmSpecRow(
            label: 'Published',
            value: result.publishDate?.toLocal().toString().split('.').first ??
                'Unknown',
          ),
          WlmSpecRow(
            label: 'Age',
            value: formatRelative(result.publishDate),
          ),
          if (result.indexer.isNotEmpty)
            WlmSpecRow(label: 'Indexer', value: result.indexer),
          if (result.category.isNotEmpty)
            WlmSpecRow(label: 'Category', value: result.category),

          const SizedBox(height: 24),

          if (hash != null) ...[
            const WlmSectionLabel('Info hash'),
            const SizedBox(height: 8),
            WlmCodeBlock(code: hash, language: 'btih'),
            const SizedBox(height: 16),
          ],

          if (result.hasMagnet) ...[
            const WlmSectionLabel('Magnet'),
            const SizedBox(height: 8),
            WlmCodeBlock(code: result.magnetUri, language: 'magnet'),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 8),
          WlmPrimaryButton(
            label: 'Open magnet',
            icon: Icons.open_in_new,
            expand: true,
            onPressed: result.hasMagnet
                ? () => _openUri(context, result.magnetUri)
                : null,
          ),
          const SizedBox(height: 8),
          WlmSecondaryButton(
            label: 'Download .torrent',
            icon: Icons.download_outlined,
            expand: true,
            onPressed: result.downloadUrl.isNotEmpty
                ? () => _openUri(context, result.downloadUrl)
                : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: WlmGhostButton(
                  label: 'Copy link',
                  icon: Icons.copy_outlined,
                  expand: true,
                  onPressed: () => _copy(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WlmGhostButton(
                  label: 'Indexer page',
                  icon: Icons.public_outlined,
                  expand: true,
                  onPressed: result.detailsUrl.isNotEmpty
                      ? () => _openUri(context, result.detailsUrl)
                      : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const WlmCallout(
            tone: WlmCalloutTone.info,
            title: 'How does \u201cOpen magnet\u201d work?',
            body:
                'Android shows a chooser with every torrent client installed '
                '(LibreTorrent, Flud, 1DM, \u2026). If you have none installed, '
                'install one from the Play Store / F-Droid first.',
          ),
          const SizedBox(height: 16),
          // A subtle reminder that Torrex is search-only.
          Text(
            'Torrex never downloads or seeds. Use only for legal content.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _openUri(BuildContext context, String uri) async {
    final ok = await launchUrl(
      Uri.parse(uri),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No app installed to handle this link. Install a torrent client.',
          ),
        ),
      );
    }
  }

  Future<void> _copy(BuildContext context) async {
    final uri = result.bestUri;
    if (uri.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: uri));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied.')));
  }

  Future<void> _share() async {
    final uri = result.bestUri;
    if (uri.isEmpty) return;
    await Share.share(uri, subject: result.title);
  }

  static String? _extractHash(String magnet) {
    if (!magnet.startsWith('magnet:')) return null;
    final match = RegExp(
      r'xt=urn:btih:([A-Fa-f0-9]{40}|[A-Z2-7]{32})',
    ).firstMatch(magnet);
    return match?.group(1);
  }
}
