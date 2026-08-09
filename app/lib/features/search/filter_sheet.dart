import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/formatters.dart';
import '../../core/release_parser.dart';
import '../../core/search_filters.dart';

/// Advanced filter sheet — the "refine" panel every mature torrent site
/// has, expressed as a single scrollable bottom sheet.
///
/// Returns the edited [SearchFilters] on apply, or `null` when dismissed.
Future<SearchFilters?> showFilterSheet({
  required BuildContext context,
  required SearchFilters current,
  required List<String> availableIndexers,
  required List<String> availableLanguages,
}) {
  return showWlmBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _FilterSheet(
      initial: current,
      availableIndexers: availableIndexers,
      availableLanguages: availableLanguages,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.availableIndexers,
    required this.availableLanguages,
  });

  final SearchFilters initial;
  final List<String> availableIndexers;
  final List<String> availableLanguages;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SearchFilters _f = widget.initial;
  late final TextEditingController _exclude = TextEditingController(
    text: widget.initial.excludeTerms,
  );

  /// Seeder slider stops. A linear 0–500 slider spends 90% of its travel
  /// in a range nobody cares about, so we snap to useful values instead.
  static const _seederStops = [0, 1, 5, 10, 25, 50, 100, 250, 500];

  /// Size stops in bytes; `null` = unbounded.
  static const _sizeStops = <int?>[
    null,
    100 * 1024 * 1024,
    500 * 1024 * 1024,
    1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    5 * 1024 * 1024 * 1024,
    10 * 1024 * 1024 * 1024,
    20 * 1024 * 1024 * 1024,
    50 * 1024 * 1024 * 1024,
  ];

  @override
  void dispose() {
    _exclude.dispose();
    super.dispose();
  }

  void _update(SearchFilters next) => setState(() => _f = next);

  Set<T> _toggled<T>(Set<T> set, T value) {
    final next = {...set};
    if (!next.remove(value)) next.add(value);
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (!_f.isPristine)
                  WlmGhostButton(
                    label: 'Reset',
                    icon: Icons.refresh_rounded,
                    onPressed: () {
                      _exclude.clear();
                      _update(_f.cleared());
                    },
                  ),
              ],
            ),
          ),
          const WlmDivider(),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              shrinkWrap: true,
              children: [
                _section('Quality'),
                _chipRow<Resolution>(
                  values: Resolution.values.reversed.toList(),
                  labelOf: (r) => r.label,
                  selected: _f.resolutions,
                  onToggle: (r) => _update(
                    _f.copyWith(resolutions: _toggled(_f.resolutions, r)),
                  ),
                ),
                const SizedBox(height: 16),
                _section('Source'),
                _chipRow<Source>(
                  values: Source.values.reversed.toList(),
                  labelOf: (s) => s.label,
                  selected: _f.sources,
                  onToggle: (s) =>
                      _update(_f.copyWith(sources: _toggled(_f.sources, s))),
                ),
                const SizedBox(height: 16),
                _section('Codec'),
                _chipRow<Codec>(
                  values: Codec.values,
                  labelOf: (c) => c.label,
                  selected: _f.codecs,
                  onToggle: (c) =>
                      _update(_f.copyWith(codecs: _toggled(_f.codecs, c))),
                ),
                if (widget.availableLanguages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section('Language'),
                  _chipRow<String>(
                    values: widget.availableLanguages,
                    labelOf: (l) => _titleCase(l),
                    selected: _f.languages,
                    onToggle: (l) => _update(
                      _f.copyWith(languages: _toggled(_f.languages, l)),
                    ),
                  ),
                ],
                if (widget.availableIndexers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section('Indexer'),
                  _chipRow<String>(
                    values: widget.availableIndexers,
                    labelOf: (i) => i,
                    selected: _f.indexers,
                    onToggle: (i) => _update(
                      _f.copyWith(indexers: _toggled(_f.indexers, i)),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _section('Minimum seeders'),
                WlmSlider(
                  value: _stopIndex(_seederStops, _f.minSeeders).toDouble(),
                  min: 0,
                  max: (_seederStops.length - 1).toDouble(),
                  divisions: _seederStops.length - 1,
                  formatLabel: (v) {
                    final n = _seederStops[v.round()];
                    return n == 0 ? 'Any' : '$n+';
                  },
                  onChanged: (v) =>
                      _update(_f.copyWith(minSeeders: _seederStops[v.round()])),
                ),
                const SizedBox(height: 16),
                _section('Size'),
                Row(
                  children: [
                    Expanded(
                      child: _sizeSlider(
                        title: 'Min',
                        value: _f.minSizeBytes,
                        onChanged: (v) =>
                            _update(_f.copyWith(minSizeBytes: () => v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _sizeSlider(
                        title: 'Max',
                        value: _f.maxSizeBytes,
                        onChanged: (v) =>
                            _update(_f.copyWith(maxSizeBytes: () => v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _section('Exclude words'),
                WlmTextField(
                  controller: _exclude,
                  hintText: 'cam, hindi, hdts',
                  prefixIcon: Icons.block_outlined,
                  clearable: true,
                  helperText:
                      'Space or comma separated. Any match hides the result.',
                  onChanged: (v) => _f = _f.copyWith(excludeTerms: v),
                ),
                const SizedBox(height: 16),
                const WlmDivider(),
                _FilterSwitch(
                  title: 'Magnet links only',
                  subtitle: 'Hide results that only offer a .torrent file',
                  value: _f.magnetOnly,
                  onChanged: (v) => _update(_f.copyWith(magnetOnly: v)),
                ),
                _FilterSwitch(
                  title: 'HDR / Dolby Vision only',
                  value: _f.hdrOnly,
                  onChanged: (v) => _update(_f.copyWith(hdrOnly: v)),
                ),
                _FilterSwitch(
                  title: 'Merge duplicates',
                  subtitle:
                      'Collapse the same torrent reported by several indexers',
                  value: _f.dedupe,
                  onChanged: (v) => _update(_f.copyWith(dedupe: v)),
                ),
                _FilterSwitch(
                  title: 'Safe mode',
                  subtitle: 'Hide adult (XXX) categories',
                  value: _f.excludeXxx,
                  onChanged: (v) => _update(_f.copyWith(excludeXxx: v)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const WlmDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: WlmGhostButton(
                    label: 'Cancel',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: WlmPrimaryButton(
                    label: 'Apply',
                    expand: true,
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_f.copyWith(excludeTerms: _exclude.text)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: WlmSectionLabel(label),
  );

  Widget _chipRow<T>({
    required List<T> values,
    required String Function(T) labelOf,
    required Set<T> selected,
    required ValueChanged<T> onToggle,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          WlmChip(
            label: labelOf(v),
            selected: selected.contains(v),
            onTap: () => onToggle(v),
          ),
      ],
    );
  }

  Widget _sizeSlider({
    required String title,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    final index = _sizeStops.indexOf(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelSmall),
        WlmSlider(
          value: (index < 0 ? 0 : index).toDouble(),
          min: 0,
          max: (_sizeStops.length - 1).toDouble(),
          divisions: _sizeStops.length - 1,
          formatLabel: (v) {
            final bytes = _sizeStops[v.round()];
            return bytes == null ? 'Any' : formatBytes(bytes);
          },
          onChanged: (v) => onChanged(_sizeStops[v.round()]),
        ),
      ],
    );
  }

  static int _stopIndex(List<int> stops, int value) {
    final i = stops.indexOf(value);
    if (i >= 0) return i;
    // Snap to the closest stop that doesn't loosen the user's filter.
    for (var j = stops.length - 1; j >= 0; j--) {
      if (stops[j] <= value) return j;
    }
    return 0;
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Boolean option row for the sheet.
///
/// Deliberately **not** `WlmSwitchTile`: that widget nests a
/// `SwitchListTile` inside `WlmCard`'s coloured `DecoratedBox`, which trips
/// Flutter's "ListTile background color or ink splashes may be invisible"
/// assertion on current stable (it fires in every debug build, not just
/// tests). Composing the row by hand keeps the WolwoLoom look without
/// putting a `ListTile` under a decorated ancestor at all, so there is
/// nothing for that assertion to catch.
class _FilterSwitch extends StatelessWidget {
  const _FilterSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: WlmCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Excluded from semantics because the whole card is already an
            // activatable target — otherwise screen readers announce the
            // option twice.
            ExcludeSemantics(
              child: Switch.adaptive(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
