import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/formatters.dart';
import '../../core/settings_store.dart';
import '../../core/web_download.dart';
import '../../models/torrent_result.dart';
import '../../widgets/theme_toggle_button.dart';
import 'tmdb_enrichment_section.dart';

/// Full-screen view of a single torrent result. Mirrors what a typical
/// torrent-site "view page" shows: title, swarm stats, file size, indexer,
/// publish date, magnet hash, and the primary actions.
class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.result,
    this.embedded = false,
    this.settings,
  });

  final TorrentResult result;

  /// When `true`, render only the inner body (no `WlmAppScaffold` /
  /// `WlmAppBar`). Used by the wide-screen two-pane shell where the page
  /// already has chrome from the parent scaffold.
  final bool embedded;

  /// When non-null and we're rendering our own AppBar, show the shared
  /// theme toggle in the top-right so the user can flip themes from the
  /// detail screen too. Optional purely so older callers compile.
  final SettingsStore? settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hash = _extractHash(result.magnetUri);

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: _buildBody(context, theme, scheme, hash),
    );

    if (embedded) return body;

    return WlmAppScaffold(
      appBar: WlmAppBar(
        title: 'Torrent',
        leading: WlmHeaderIconButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (settings != null) ThemeToggleButton(settings: settings!),
          WlmHeaderIconButton(
            icon: Icons.share_outlined,
            tooltip: 'Share link',
            onPressed: () => _share(),
          ),
        ],
      ),
      body: body,
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    String? hash,
  ) {
    return [
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

          // Cover image (when the indexer publishes one). Many private
          // trackers do; most public ones don't, so guard.
          if (result.coverUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: result.coverUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, _) => const WlmSkeleton(height: 180),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // TMDB enrichment — only when we have a settings handle (so the
          // wide-screen embedded variant in AppShell, which doesn't pass
          // settings yet, gracefully skips).
          if (settings != null)
            TmdbEnrichmentSection(result: result, settings: settings!),

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

          const WlmSectionLabel('Details',
              padding: EdgeInsets.only(bottom: 8)),
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
            const WlmSectionLabel('Info hash',
                padding: EdgeInsets.only(bottom: 8)),
            const SizedBox(height: 8),
            WlmCodeBlock(code: hash, language: 'btih'),
            const SizedBox(height: 16),
          ],

          if (result.hasMagnet) ...[
            const WlmSectionLabel('Magnet',
                padding: EdgeInsets.only(bottom: 8)),
            const SizedBox(height: 8),
            WlmCodeBlock(code: result.magnetUri, language: 'magnet'),
            const SizedBox(height: 16),
          ],

          if (result.files.isNotEmpty) ...[
            WlmSectionLabel('Files (${result.files.length})',
                padding: const EdgeInsets.only(bottom: 8)),
            const SizedBox(height: 8),
            _FileList(files: result.files),
            const SizedBox(height: 16),
          ],

          if (result.trackers.isNotEmpty) ...[
            WlmSectionLabel('Trackers (${result.trackers.length})',
                padding: const EdgeInsets.only(bottom: 8)),
            const SizedBox(height: 8),
            _TrackerList(trackers: result.trackers),
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
          // Only show .torrent download when the indexer actually exposes one.
          // Most public trackers (TPB, RARBG, Nyaa) only return magnets, in
          // which case showing a permanently-disabled button is just noise.
          if (result.downloadUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            WlmSecondaryButton(
              label: 'Download .torrent',
              icon: Icons.download_outlined,
              expand: true,
              onPressed: () => _downloadTorrent(context),
            ),
          ],
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
          // A subtle reminder that Torrex is search-only.
          // (callout + legal copy intentionally omitted — the share/copy
          // buttons above are explanation enough).
        ];
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

  /// Hand off the .torrent URL to the browser (web) or the OS (mobile).
  /// On web we use a DOM anchor with `download` so popup blockers don't kill
  /// the request and the file lands in Downloads instead of being navigated
  /// to in the same tab.
  Future<void> _downloadTorrent(BuildContext context) async {
    final url = result.downloadUrl;
    if (url.isEmpty) return;
    if (kIsWeb) {
      final filename = _safeFilename(result.title);
      final ok = await forceDownload(url, filename: filename);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed.')),
        );
      }
      return;
    }
    await _openUri(context, url);
  }

  static String _safeFilename(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final base = cleaned.isEmpty ? 'torrent' : cleaned;
    return base.toLowerCase().endsWith('.torrent') ? base : '$base.torrent';
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

/// Compact file-list rendering. Caps the visible rows at a sensible
/// number with a "show more" toggle so torrents with thousands of files
/// (e.g. season packs, course bundles) don't explode the layout.
class _FileList extends StatefulWidget {
  const _FileList({required this.files});
  final List<TorrentFile> files;

  @override
  State<_FileList> createState() => _FileListState();
}

class _FileListState extends State<_FileList> {
  static const _initialVisible = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = widget.files;
    final visible = _expanded ? all : all.take(_initialVisible).toList();
    final hidden = all.length - visible.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 14, color: scheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (f.bytes != null && f.bytes! > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    formatBytes(f.bytes!),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ],
            ),
          ),
        if (hidden > 0)
          InkWell(
            onTap: () => setState(() => _expanded = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Show $hidden more',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Trackers list \u2014 mono code-style rows in a single bordered block.
class _TrackerList extends StatelessWidget {
  const _TrackerList({required this.trackers});
  final List<String> trackers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in trackers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SelectableText(
              t,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurface,
                  ),
              maxLines: 1,
            ),
          ),
      ],
    );
  }
}
