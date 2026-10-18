import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';
import '../services/board_store.dart';
import '../widgets/paged_symbol_grid.dart';
import '../widgets/symbol_tile_widget.dart';
import 'add_tile_screen.dart';

/// Shows one board as a grid of large symbol tiles.
///
/// This is intentionally the whole app for now: one board, seeded with a
/// small placeholder set on first run and then whatever tiles get added via
/// [AddTileScreen]. Board switching lands as its own follow-up feature.
class BoardScreen extends StatefulWidget {
  /// [openRepository] overrides where board tiles are persisted; only meant
  /// for tests (an in-memory fake instead of real device storage). The app
  /// itself always uses the default, which persists to disk.
  const BoardScreen({super.key, this.openRepository});

  final Future<BoardRepository> Function()? openRepository;

  @override
  State<BoardScreen> createState() => BoardScreenState();
}

@visibleForTesting
class BoardScreenState extends State<BoardScreen> {
  static const _seedTiles = [
    SymbolTile(label: 'Ja'),
    SymbolTile(label: 'Nein'),
    SymbolTile(label: 'Mehr'),
    SymbolTile(label: 'Fertig'),
    SymbolTile(label: 'Trinken'),
    SymbolTile(label: 'Essen'),
    SymbolTile(label: 'Hilfe'),
    SymbolTile(label: 'Pause'),
  ];

  /// Unter dieser Breite: Handy-Layout (fixes 2x2-Raster, kein Scrollen).
  static const _phoneBreakpoint = 600.0;

  /// Ab Tablet-Breite mehr Spalten, weil dort genug Platz ist.
  static int _columnsForWidth(double width) {
    if (width < 900) return 3;
    return 4;
  }

  List<SymbolTile>? _tiles;
  int _phonePage = 0;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  Future<void> _loadBoard() async {
    final store = await (widget.openRepository ?? FileBoardStore.open)();
    final saved = await store.load();
    final tiles = saved ?? List.of(_seedTiles);
    if (saved == null) {
      await store.save(tiles);
    }
    if (!mounted) return;
    setState(() => _tiles = tiles);
  }

  Future<void> _addTile() async {
    final newTile = await Navigator.of(
      context,
    ).push<SymbolTile>(MaterialPageRoute(builder: (_) => const AddTileScreen()));
    if (newTile == null || !mounted) return;
    await _appendTile(newTile);
  }

  /// Test-only seam: lets widget tests exercise "a tile got added" without
  /// driving the real AddTileScreen, which needs a real device file picker.
  @visibleForTesting
  Future<void> addTileForTest(SymbolTile tile) => _appendTile(tile);

  Future<void> _appendTile(SymbolTile tile) async {
    final updated = [...?_tiles, tile];
    setState(() => _tiles = updated);
    final store = await (widget.openRepository ?? FileBoardStore.open)();
    await store.save(updated);
  }

  void _onTileTap(SymbolTile tile) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(tile.label)));
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TalkSimple'),
        actions: [
          IconButton(
            onPressed: tiles == null ? null : _addTile,
            icon: const Icon(Icons.add),
            tooltip: 'Kachel hinzufügen',
          ),
        ],
      ),
      body: tiles == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              // Keeps tiles and the Zurueck/Weiter buttons clear of the
              // phone's own system navigation bar (buttons or gesture strip)
              // instead of drawing underneath it.
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < _phoneBreakpoint) {
                      return PagedSymbolGrid(
                        tiles: tiles,
                        page: _phonePage,
                        onTileTap: _onTileTap,
                        onPageChanged: (page) => setState(() => _phonePage = page),
                      );
                    }
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columnsForWidth(constraints.maxWidth),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemCount: tiles.length,
                      itemBuilder: (context, index) {
                        final tile = tiles[index];
                        return SymbolTileWidget(
                          tile: tile,
                          onTap: () => _onTileTap(tile),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
    );
  }
}
