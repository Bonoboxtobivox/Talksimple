import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/symbol_tile.dart';
import '../screens/metacom_browser_screen.dart';
import '../services/drive_symbol_source.dart';
import '../services/symbol_library.dart';

/// An image chosen via [pickImage]: a local file plus, for Metacom
/// symbols, the label suggested by the file name.
class PickedImage {
  const PickedImage({required this.path, this.suggestedLabel});

  final String path;
  final String? suggestedLabel;
}

enum _Source { metacom, camera, gallery }

/// Asks where the picture should come from - the Metacom library first,
/// since that is the usual source, then camera or gallery/Drive files -
/// and returns the chosen image, or null if cancelled at any point.
///
/// [word] pre-fills the Metacom search (e.g. the word that had no
/// symbol). [catalog] is only overridden in tests.
Future<PickedImage?> pickImage(
  BuildContext context, {
  String? word,
  String title = 'Bild hinzufügen',
  SymbolCatalog? catalog,
}) async {
  final source = await showDialog<_Source>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SourceButton(
            icon: Icons.collections_outlined,
            label: 'Metacom-Bibliothek',
            onTap: () => Navigator.of(context).pop(_Source.metacom),
          ),
          const SizedBox(height: 12),
          _SourceButton(
            icon: Icons.photo_camera_outlined,
            label: 'Kamera',
            onTap: () => Navigator.of(context).pop(_Source.camera),
          ),
          const SizedBox(height: 12),
          _SourceButton(
            icon: Icons.folder_open_outlined,
            label: 'Galerie / Dateien',
            onTap: () => Navigator.of(context).pop(_Source.gallery),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return null;

  switch (source) {
    case _Source.metacom:
      final picked = await Navigator.of(context).push<PickedSymbol>(
        MaterialPageRoute(
          builder: (_) =>
              MetacomBrowserScreen(catalog: catalog, initialQuery: word),
        ),
      );
      if (picked == null) return null;
      final file = await writeTempImage(picked.bytes);
      return PickedImage(path: file.path, suggestedLabel: picked.label);
    case _Source.camera:
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      return photo == null ? null : PickedImage(path: photo.path);
    case _Source.gallery:
      // FileType.image would launch Android's restricted Photo Picker,
      // which excludes cloud providers like Google Drive. FileType.custom
      // launches the full system document picker instead.
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'],
      );
      final path = result?.files.single.path;
      return path == null ? null : PickedImage(path: path);
  }
}

/// Lets the caregiver pick a picture for [word] (Metacom search pre-filled
/// with it) and saves it in the symbol library under [word], so the word
/// finds it by itself from then on. Null if cancelled.
Future<SymbolTile?> pickSymbolForWord(BuildContext context, String word) async {
  final picked = await pickImage(
    context,
    word: word,
    title: 'Bild für „$word“',
  );
  if (picked == null) return null;
  final library = await SymbolLibrary.open();
  return library.import(sourcePath: picked.path, label: word);
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      height: 56,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
