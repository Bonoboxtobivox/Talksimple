import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';
import '../services/symbol_library.dart';
import '../widgets/image_source_dialog.dart';
import '../widgets/symbol_tile_widget.dart';

/// Lets a caregiver add a tile to the board: either reuse an already
/// imported symbol (a "kleiner vorgefertigter Ordner" to pick from) or
/// import a new image — a photo or a Metacom symbol file from wherever it
/// lives on the device (e.g. a locally synced Google Drive folder).
///
/// Returns the chosen/created [SymbolTile] via [Navigator.pop], or null if
/// cancelled.
class AddTileScreen extends StatefulWidget {
  const AddTileScreen({super.key});

  @override
  State<AddTileScreen> createState() => _AddTileScreenState();
}

class _AddTileScreenState extends State<AddTileScreen> {
  late Future<List<SymbolTile>> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = _loadLibrary();
  }

  Future<List<SymbolTile>> _loadLibrary() async {
    final library = await SymbolLibrary.open();
    return library.loadAll();
  }

  Future<void> _importNew() async {
    final picked = await pickImage(context);
    if (picked == null || !mounted) return;
    final path = picked.path;

    final label = await _askForLabel(picked.suggestedLabel);
    if (label == null || label.trim().isEmpty || !mounted) return;

    final library = await SymbolLibrary.open();
    final tile = await library.import(sourcePath: path, label: label.trim());
    if (!mounted) return;
    Navigator.of(context).pop(tile);
  }

  Future<String?> _askForLabel([String? suggestion]) {
    final controller = TextEditingController(text: suggestion);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beschriftung'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'z.B. Trinken'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kachel hinzufügen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importNew,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Neues Bild'),
      ),
      body: FutureBuilder<List<SymbolTile>>(
        future: _libraryFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final library = snapshot.data!;
          if (library.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Symbole importiert.\n'
                  'Tippe unten auf "Neues Bild" — Foto oder Metacom-Symbol '
                  '(z.B. aus deinem synchronisierten Google-Drive-Ordner).',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: library.length,
              itemBuilder: (context, index) {
                final tile = library[index];
                return SymbolTileWidget(
                  tile: tile,
                  onTap: () => Navigator.of(context).pop(tile),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
