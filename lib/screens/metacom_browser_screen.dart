import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/drive_symbol_source.dart';

/// The symbol a caregiver picked in [MetacomBrowserScreen].
class PickedSymbol {
  const PickedSymbol({required this.bytes, required this.label});

  final Uint8List bytes;

  /// Suggested label, from the file name (`wein_rot.png` -> `wein rot`).
  final String label;
}

/// Browse the Metacom library like a folder: categories first, then the
/// symbols of one category as large pictures. The search field on top
/// searches all categories at once and is pre-filled when opened for a
/// specific word.
///
/// Pops a [PickedSymbol], or null if cancelled.
class MetacomBrowserScreen extends StatefulWidget {
  const MetacomBrowserScreen({super.key, this.catalog, this.initialQuery});

  /// Only overridden in tests; the app uses the Drive library.
  final SymbolCatalog? catalog;
  final String? initialQuery;

  @override
  State<MetacomBrowserScreen> createState() => _MetacomBrowserScreenState();
}

class _MetacomBrowserScreenState extends State<MetacomBrowserScreen> {
  late final SymbolCatalog _catalog =
      widget.catalog ?? DriveSymbolSource.instance;
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery ?? '',
  );

  SymbolFolder? _folder;
  Future<List<Object>>? _content;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _reload() {
    final query = _query.text.trim();
    setState(() {
      _content = query.isNotEmpty
          ? _catalog.search(query)
          : _folder != null
          ? _catalog.filesIn(_folder!.id)
          : _catalog.folders();
    });
  }

  void _openFolder(SymbolFolder folder) {
    _folder = folder;
    _reload();
  }

  void _clearSearch() {
    _query.clear();
    _reload();
  }

  Future<void> _pick(SymbolEntry entry) async {
    if (_picking) return;
    setState(() => _picking = true);
    final data = await _catalog.bytes(entry.id);
    if (!mounted) return;
    setState(() => _picking = false);
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bild konnte nicht geladen werden.')),
      );
      return;
    }
    Navigator.of(context).pop(PickedSymbol(bytes: data, label: entry.label));
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.text.trim().isNotEmpty;
    final folder = _folder;
    return PopScope(
      // Inside a category, "back" first returns to the category list.
      canPop: folder == null || searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _folder = null;
          _reload();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            searching
                ? 'Metacom: Suche'
                : folder?.displayName ?? 'Metacom-Bibliothek',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    hintText: 'Symbol suchen, z.B. Schnee',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searching
                        ? IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.clear),
                            tooltip: 'Suche löschen',
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _reload(),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Object>>(
                  future: _content,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      final error = snapshot.error;
                      return _ErrorView(
                        message: error is DriveException
                            ? error.problem.message
                            : DriveProblem.offline.message,
                        onRetry: _reload,
                      );
                    }
                    final items = snapshot.data ?? const [];
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          searching
                              ? 'Kein Symbol für „${_query.text.trim()}“ gefunden.'
                              : 'Dieser Ordner ist leer.',
                          style: const TextStyle(fontSize: 18),
                        ),
                      );
                    }
                    if (items.first is SymbolFolder) {
                      return _FolderList(
                        folders: items.cast<SymbolFolder>(),
                        onOpen: _openFolder,
                      );
                    }
                    return Stack(
                      children: [
                        _SymbolGrid(
                          entries: items.cast<SymbolEntry>(),
                          catalog: _catalog,
                          onPick: _pick,
                        ),
                        if (_picking)
                          const ColoredBox(
                            color: Color(0x66FFFFFF),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderList extends StatelessWidget {
  const _FolderList({required this.folders, required this.onOpen});

  final List<SymbolFolder> folders;
  final ValueChanged<SymbolFolder> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: folders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final folder = folders[index];
        return Material(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onOpen(folder),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.folder_outlined, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      folder.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SymbolGrid extends StatelessWidget {
  const _SymbolGrid({
    required this.entries,
    required this.catalog,
    required this.onPick,
  });

  final List<SymbolEntry> entries;
  final SymbolCatalog catalog;
  final ValueChanged<SymbolEntry> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Semantics(
          button: true,
          label: entry.label,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onPick(entry),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Expanded(
                      child: FutureBuilder<Uint8List?>(
                        future: catalog.bytes(entry.id),
                        builder: (context, snapshot) {
                          final data = snapshot.data;
                          if (data != null) {
                            return Image.memory(
                              data,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            );
                          }
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            return const Icon(Icons.broken_image_outlined);
                          }
                          return const Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.orange.shade900),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }
}
