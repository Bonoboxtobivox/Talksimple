import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';

/// A large, high-contrast, single-purpose button for one [SymbolTile].
///
/// Sized and styled for users with limited fine motor control: big hit area,
/// bold label, no secondary actions hiding on the same tile.
class SymbolTileWidget extends StatelessWidget {
  const SymbolTileWidget({super.key, required this.tile, required this.onTap});

  final SymbolTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tile.label,
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: _TileImage(tile: tile)),
                const SizedBox(height: 8),
                Text(
                  tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileImage extends StatelessWidget {
  const _TileImage({required this.tile});

  final SymbolTile tile;

  @override
  Widget build(BuildContext context) {
    final imageFile = tile.imageFile;
    if (imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(imageFile, fit: BoxFit.cover),
      );
    }
    return Icon(
      Icons.image_outlined,
      size: 48,
      color: Theme.of(context).colorScheme.onSecondaryContainer,
    );
  }
}
