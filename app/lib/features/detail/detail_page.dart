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
        padding: const EdgeInsets.all(16),
        children: [
          Text(result.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              WlmChip(label: '↑ ${result.seeders} seeders'),
              WlmChip(label: '↓ ${result.leechers} leechers'),
              WlmChip(label: formatBytes(result.sizeBytes)),
              WlmChip(label: formatRelative(result.publishDate)),
              if (result.indexer.isNotEmpty) WlmChip(label: result.indexer),
              if (result.category.isNotEmpty) WlmChip(label: result.category),
              if (result.hasMagnet) const WlmChip(label: 'magnet'),
            ],
          ),
          const SizedBox(height: 24),
          const WlmSectionLabel('Details'),
          const SizedBox(height: 8),
          WlmSpecRow(label: 'Seeders', value: '${result.seeders}'),
          WlmSpecRow(label: 'Leechers', value: '${result.leechers}'),
          WlmSpecRow(label: 'Size', value: formatBytes(result.sizeBytes)),
          WlmSpecRow(
            label: 'Published',
            value: result.publishDate?.toLocal().toString().split('.').first ??
                'Unknown',
          ),
          if (result.indexer.isNotEmpty)
            WlmSpecRow(label: 'Indexer', value: result.indexer),
          if (result.category.isNotEmpty)
            WlmSpecRow(label: 'Category', value: result.category),
          if (hash != null) WlmSpecRow(label: 'Info hash', value: hash),
          const SizedBox(height: 24),
          if (result.hasMagnet) ...[
            const WlmSectionLabel('Magnet'),
            const SizedBox(height: 8),
            WlmCard(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                result.magnetUri,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
          ],
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
          WlmGhostButton(
            label: 'Copy link',
            icon: Icons.copy_outlined,
            expand: true,
            onPressed: () => _copy(context),
          ),
          if (result.detailsUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            WlmGhostButton(
              label: 'View on indexer',
              icon: Icons.public_outlined,
              expand: true,
              onPressed: () => _openUri(context, result.detailsUrl),
            ),
          ],
          const SizedBox(height: 24),
          const WlmCallout(
            title: 'How does "Open magnet" work?',
            body:
                'Android shows a chooser with every torrent client installed '
                '(LibreTorrent, Flud, 1DM, …). If you have none installed, '
                'install one from the Play Store / F-Droid first.',
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
