import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/formatters.dart';
import '../../models/torrent_result.dart';

/// One row in the search results list.
///
/// Mirrors what mainstream torrent sites put on a result row — release
/// name, parsed quality badges, swarm health, size, age, indexer — plus
/// the two actions people actually use (copy link / open in client).
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.result,
    required this.chipIds,
    required this.onTap,
    required this.onOpen,
    required this.onCopy,
    this.showQualityBadges = true,
  });

  final TorrentResult result;

  /// Which metadata chips the user enabled in Settings.
  final List<String> chipIds;

  final ValueChanged<TorrentResult> onTap;
  final ValueChanged<TorrentResult> onOpen;
  final ValueChanged<TorrentResult> onCopy;
  final bool showQualityBadges;

  /// Max quality badges before we start dropping them — a UHD REMUX with
  /// Atmos and DV can legitimately produce eight.
  static const int _maxBadges = 5;

  /// Build the chip for a given preference id, or `null` to hide it
  /// (e.g. magnet chip on a torrent without a magnet link).
  Widget? _chipFor(String id) {
    switch (id) {
      case 'seeders':
        return WlmChip(label: '\u2191 ${result.seeders}');
      case 'leechers':
        return WlmChip(label: '\u2193 ${result.leechers}');
      case 'size':
        return WlmChip(label: formatBytes(result.sizeBytes));
      case 'age':
        return WlmChip(label: formatRelative(result.publishDate));
      case 'indexer':
        if (result.indexer.isEmpty) return null;
        return WlmChip(label: result.indexer);
      case 'category':
        if (result.category.isEmpty) return null;
        return WlmChip(label: result.category);
      case 'magnet':
        if (!result.hasMagnet) return null;
        return const WlmChip(label: 'magnet');
      case 'health':
        return WlmChip(label: result.healthLabel);
      case 'files':
        if (result.files.isEmpty) return null;
        return WlmChip(label: '${result.files.length} files');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = result.release;
    final chips = <Widget>[for (final id in chipIds) ?_chipFor(id)];
    final badges = showQualityBadges
        ? info.badges.take(_maxBadges).toList(growable: false)
        : const <String>[];
    final extraSources = result.sourceIndexers.length - 1;

    return WlmCard(
      onTap: () => onTap(result),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.title,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (badges.isNotEmpty || extraSources > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in badges) _QualityBadge(label: b),
                if (extraSources > 0)
                  _QualityBadge(
                    label:
                        '+$extraSources source'
                        '${extraSources == 1 ? '' : 's'}',
                    subdued: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _HealthRow(result: result),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (result.indexer.isNotEmpty && !chipIds.contains('indexer'))
                Flexible(
                  child: Text(
                    result.indexer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ),
              const Spacer(),
              WlmGhostButton(
                label: 'Copy',
                icon: Icons.copy_outlined,
                onPressed: () => onCopy(result),
              ),
              const SizedBox(width: 8),
              WlmPrimaryButton(
                label: 'Open',
                icon: Icons.open_in_new,
                onPressed: () => onOpen(result),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Seed/leech line with a coloured health bar — the single most useful
/// signal on a torrent list, and the thing every popular site leads with.
class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.result});

  final TorrentResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final health = result.health;
    final color = _healthColor(health, scheme);
    final labelStyle = theme.textTheme.labelSmall;

    return Semantics(
      label:
          'Swarm health ${result.healthLabel}, '
          '${result.seeders} seeders, ${result.leechers} leechers',
      child: Row(
        children: [
          Icon(Icons.arrow_upward_rounded, size: 13, color: color),
          const SizedBox(width: 2),
          Text('${result.seeders}', style: labelStyle?.copyWith(color: color)),
          const SizedBox(width: 10),
          Icon(Icons.arrow_downward_rounded, size: 13, color: scheme.outline),
          const SizedBox(width: 2),
          Text(
            '${result.leechers}',
            style: labelStyle?.copyWith(color: scheme.outline),
          ),
          const SizedBox(width: 12),
          Expanded(
            // The bar is decoration: the Semantics wrapper above already
            // announces the swarm in words. Without this exclusion the
            // progress indicator's implicit role propagates up and the
            // whole result card gets announced as a progress bar.
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: health,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatBytes(result.sizeBytes),
            style: labelStyle?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static Color _healthColor(double health, ColorScheme scheme) {
    if (health <= 0) return scheme.error;
    if (health < 0.35) return const Color(0xFFE0913A);
    if (health < 0.65) return const Color(0xFFC9C24B);
    return const Color(0xFF5BB974);
  }
}

/// Small outlined tag for a parsed release attribute (1080p, WEB-DL, x265…).
class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label, this.subdued = false});

  final String label;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = subdued ? scheme.outline : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: fg.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          letterSpacing: 0.6,
          fontSize: 10,
        ),
      ),
    );
  }
}
