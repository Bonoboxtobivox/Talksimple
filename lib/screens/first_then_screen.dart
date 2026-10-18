import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';
import '../widgets/empty_tile_picker.dart';
import '../widgets/symbol_tile_widget.dart';

/// "Zuerst - Dann" board: one big tile at a time.
///
/// Empty tile -> [EmptyTilePicker] fills it (speak, type, or take a photo).
/// Tapping the filled "Zuerst" tile reveals the empty "Dann" tile with the
/// same interaction. Tapping the filled "Dann" tile resets both, ready for
/// the next first-then cycle.
class FirstThenScreen extends StatefulWidget {
  const FirstThenScreen({super.key});

  @override
  State<FirstThenScreen> createState() => _FirstThenScreenState();
}

enum _Step { first, then }

class _FirstThenScreenState extends State<FirstThenScreen> {
  _Step _step = _Step.first;
  SymbolTile? _firstTile;
  SymbolTile? _thenTile;

  SymbolTile? get _currentTile =>
      _step == _Step.first ? _firstTile : _thenTile;

  void _advanceOrReset() {
    if (_step == _Step.first) {
      setState(() => _step = _Step.then);
    } else {
      setState(() {
        _step = _Step.first;
        _firstTile = null;
        _thenTile = null;
      });
    }
  }

  void _onResolved(SymbolTile tile) {
    setState(() {
      if (_step == _Step.first) {
        _firstTile = tile;
      } else {
        _thenTile = tile;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tile = _currentTile;
    return Scaffold(
      appBar: AppBar(title: Text(_step == _Step.first ? 'Zuerst' : 'Dann')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: tile != null
              ? SizedBox.expand(
                  child: SymbolTileWidget(tile: tile, onTap: _advanceOrReset),
                )
              : EmptyTilePicker(onResolved: _onResolved),
        ),
      ),
    );
  }
}
