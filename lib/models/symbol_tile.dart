import 'dart:io';

/// A single tappable symbol on a board: a label plus an optional image.
///
/// The image is always a local file — either a photo the user took, or a
/// symbol (e.g. a Metacom symbol) imported once via [SymbolLibrary] and
/// reused from there. Symbol sets like Metacom are commercially licensed,
/// so their images live only on-device and are never bundled with the app
/// or committed to source control.
class SymbolTile {
  const SymbolTile({required this.label, this.imageFile});

  final String label;
  final File? imageFile;
}
