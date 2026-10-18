import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';
import 'symbol_tile_widget.dart';

/// A fixed 2x2 grid of symbol tiles with Zurueck/Weiter paging instead of
/// scrolling.
///
/// Scrolling asks for precise, repeatable small gestures that are exactly
/// what's hard for someone with limited fine motor control. A big
/// previous/next button is a single, predictable tap instead. Tiles fill
/// the whole available area (no dead space) so the touch targets stay as
/// large as the screen allows.
class PagedSymbolGrid extends StatelessWidget {
  const PagedSymbolGrid({
    super.key,
    required this.tiles,
    required this.page,
    required this.onTileTap,
    required this.onPageChanged,
  }) : assert(tiles.length > 0);

  static const pageSize = 4;

  final List<SymbolTile> tiles;
  final int page;
  final ValueChanged<SymbolTile> onTileTap;
  final ValueChanged<int> onPageChanged;

  int get _pageCount => (tiles.length / pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    final start = page * pageSize;
    final pageTiles = tiles.skip(start).take(pageSize).toList();
    final hasPrevious = page > 0;
    final hasNext = page < _pageCount - 1;

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(child: _TileRow(tiles: pageTiles.take(2).toList(), onTileTap: onTileTap)),
              const SizedBox(height: 12),
              Expanded(
                child: _TileRow(
                  tiles: pageTiles.skip(2).take(2).toList(),
                  onTileTap: onTileTap,
                ),
              ),
            ],
          ),
        ),
        if (_pageCount > 1) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NavButton(
                  icon: Icons.arrow_back,
                  label: 'Zurück',
                  onTap: hasPrevious ? () => onPageChanged(page - 1) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NavButton(
                  icon: Icons.arrow_forward,
                  label: 'Weiter',
                  onTap: hasNext ? () => onPageChanged(page + 1) : null,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.tiles, required this.onTileTap});

  final List<SymbolTile> tiles;
  final ValueChanged<SymbolTile> onTileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tile in tiles) ...[
          Expanded(
            child: SymbolTileWidget(tile: tile, onTap: () => onTileTap(tile)),
          ),
          if (tile != tiles.last) const SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
