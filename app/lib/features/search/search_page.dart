import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/formatters.dart';
import '../../core/settings_store.dart';
import '../../core/torznab_client.dart';
import '../../models/torrent_result.dart';
import '../detail/detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _client = TorznabClient();
  final _controller = TextEditingController();

  bool _loading = false;
  String? _error;
  List<TorrentResult> _results = const [];
  _SortBy _sort = _SortBy.seeders;

  @override
  void initState() {
    super.initState();
    // In demo mode, auto-populate the result list on first build so the
    // home screen looks alive without typing a query.
    if (widget.settings.baseUrl == 'demo') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    final isDemo = widget.settings.baseUrl == 'demo';
    if (query.isEmpty && !isDemo) return;

    if (!widget.settings.isConfigured) {
      setState(() {
        _error = 'Backend not configured. Open Settings to add your URL + key.';
        _results = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final r = await _client.search(
        baseUrl: widget.settings.baseUrl,
        apiKey: widget.settings.apiKey,
        indexer: widget.settings.indexer,
        query: query,
      );
      setState(() {
        _results = _applySort(r);
        _loading = false;
      });
    } on TorznabException catch (e) {
      setState(() {
        _error = e.message;
        _results = const [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unexpected error: $e';
        _results = const [];
        _loading = false;
      });
    }
  }

  List<TorrentResult> _applySort(List<TorrentResult> source) {
    final list = [...source];
    switch (_sort) {
      case _SortBy.seeders:
        list.sort((a, b) => b.seeders.compareTo(a.seeders));
      case _SortBy.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case _SortBy.date:
        list.sort(
          (a, b) => (b.publishDate ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.publishDate ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: WlmSearchField(
            controller: _controller,
            hintText: 'Search torrents…',
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: WlmSegmentedControl<_SortBy>(
                  value: _sort,
                  onChanged: (v) {
                    setState(() {
                      _sort = v;
                      _results = _applySort(_results);
                    });
                  },
                  segments: const [
                    WlmSegment(value: _SortBy.seeders, label: 'Seeders'),
                    WlmSegment(value: _SortBy.size, label: 'Size'),
                    WlmSegment(value: _SortBy.date, label: 'Date'),
                  ],
                ),
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  '${_results.length}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, _) => const WlmSkeleton(height: 72),
      );
    }
    if (_error != null) {
      return WlmErrorState(
        title: 'Search failed',
        body: _error,
        onRetry: _runSearch,
      );
    }
    if (_results.isEmpty) {
      if (!widget.settings.isConfigured) {
        return const WlmEmptyState(
          eyebrow: 'SETUP',
          icon: Icons.settings_outlined,
          title: 'Connect a backend',
          body:
              'Add your Jackett or Prowlarr URL and API key in Settings to start searching.',
        );
      }
      return const WlmEmptyState(
        eyebrow: 'SEARCH',
        icon: Icons.search_outlined,
        title: 'Search the swarm',
        body: 'Type a query above to search across all your indexers.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ResultCard(
        result: _results[i],
        onTap: _openDetail,
        onOpen: _openMagnet,
        onCopy: _copy,
      ),
    );
  }

  void _openDetail(TorrentResult r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(result: r)),
    );
  }

  Future<void> _openMagnet(TorrentResult r) async {
    final uri = r.bestUri;
    if (uri.isEmpty) {
      _snack('No magnet or download link in this result.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse(uri),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('No app installed to handle this link.');
  }

  Future<void> _copy(TorrentResult r) async {
    final uri = r.bestUri;
    if (uri.isEmpty) {
      _snack('No link to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: uri));
    _snack('Link copied.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _SortBy { seeders, size, date }

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.onTap,
    required this.onOpen,
    required this.onCopy,
  });

  final TorrentResult result;
  final ValueChanged<TorrentResult> onTap;
  final ValueChanged<TorrentResult> onOpen;
  final ValueChanged<TorrentResult> onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              WlmChip(label: '↑ ${result.seeders}'),
              WlmChip(label: '↓ ${result.leechers}'),
              WlmChip(label: formatBytes(result.sizeBytes)),
              WlmChip(label: formatRelative(result.publishDate)),
              if (result.indexer.isNotEmpty) WlmChip(label: result.indexer),
              if (result.hasMagnet) const WlmChip(label: 'magnet'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
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
