import 'package:flutter/material.dart';

import '../models/symbol_tile.dart';
import '../services/drive_symbol_source.dart';
import '../services/favorites_store.dart';
import '../services/sentence_words.dart';
import '../services/speech_service.dart';
import '../services/speech_settings.dart';
import '../services/symbol_resolver.dart';
import '../widgets/image_source_dialog.dart';

/// "Sprechen → Symbole": the caregiver says (or types) a sentence, and it
/// appears as a row of large symbols for the symbol user — for spontaneous
/// moments no prepared board covers.
///
/// Words without a symbol still show up, as large text, so the sentence is
/// never silently shortened. A star saves the sentence as a favourite; the
/// favourites list brings it back with one tap.
class SpeakSymbolsScreen extends StatefulWidget {
  /// All parameters are only overridden in tests.
  const SpeakSymbolsScreen({
    super.key,
    this.speechService,
    this.openSettings,
    this.lookupSymbol,
    this.openFavoritesStore,
    this.chooseSymbol,
  });

  final SpeechService? speechService;
  final Future<SpeechSettingsRepository> Function()? openSettings;
  final SymbolLookup? lookupSymbol;

  /// Lets the caregiver pick a picture for a word by hand; returns it saved
  /// under that word, or null if cancelled. Defaults to [pickSymbolForWord].
  final Future<SymbolTile?> Function(BuildContext context, String word)?
  chooseSymbol;
  final Future<FavoritesRepository> Function()? openFavoritesStore;

  @override
  State<SpeakSymbolsScreen> createState() => SpeakSymbolsScreenState();
}

/// One word of the shown sentence and what was found for it.
class _Slot {
  _Slot(this.word);

  final String word;
  SymbolTile? symbol;
  bool searching = true;
}

@visibleForTesting
class SpeakSymbolsScreenState extends State<SpeakSymbolsScreen> {
  late final SpeechService _speech =
      widget.speechService ?? DeviceSpeechService();

  /// Per-session cache, including misses, so a repeated word ("ich",
  /// "und") is not searched in Drive over and over.
  final Map<String, SymbolTile?> _cache = {};

  String _sentence = '';
  List<_Slot> _slots = [];
  List<String> _favorites = [];
  bool _listening = false;
  String? _status;

  /// Increments with every new sentence, so lookups still running for an
  /// older sentence don't write into the new one.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<FavoritesRepository> _favoritesStore() =>
      (widget.openFavoritesStore ?? openFavorites)();

  Future<void> _loadFavorites() async {
    final favorites = await (await _favoritesStore()).load();
    if (!mounted) return;
    setState(() => _favorites = favorites);
  }

  Future<void> _startListening() async {
    if (_listening) return;
    final settings = await (await (widget.openSettings ?? openSpeechSettings)())
        .load();
    final started = await _speech.start(settings);
    if (!mounted) return;
    setState(() {
      _listening = started;
      _status = started ? 'Ich höre zu …' : 'Spracherkennung nicht verfügbar.';
    });
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    final heard = await _speech.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _status = heard.isEmpty ? 'Nichts verstanden — nochmal versuchen.' : null;
    });
    if (heard.isNotEmpty) await showSentence(heard);
  }

  Future<void> _typeSentence() async {
    final controller = TextEditingController();
    final sentence = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Satz eingeben'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'z.B. Wir gehen essen'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Zeigen'),
          ),
        ],
      ),
    );
    if (sentence == null || sentence.trim().isEmpty || !mounted) return;
    await showSentence(sentence.trim());
  }

  /// Shows [sentence] as symbols, filling them in word by word as they are
  /// found. Public so tests (and favourites) can show a sentence directly.
  Future<void> showSentence(String sentence) async {
    final generation = ++_generation;
    final slots = [for (final word in sentenceWords(sentence)) _Slot(word)];
    setState(() {
      _sentence = sentence;
      _slots = slots;
      _status = null;
    });

    final lookup = widget.lookupSymbol ?? resolveSymbol;
    for (final slot in slots) {
      final key = slot.word.toLowerCase();
      final SymbolTile? found;
      if (_cache.containsKey(key)) {
        found = _cache[key];
      } else {
        found = await lookup(slot.word);
        _cache[key] = found;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        slot.symbol = found;
        slot.searching = false;
      });
    }

    if (slots.any((s) => s.symbol == null)) {
      // Default lookup only: a fake in tests has no Drive behind it.
      final problem = widget.lookupSymbol == null
          ? DriveSymbolSource.instance.lastProblem
          : null;
      setState(() {
        _status = [
          ?problem?.message,
          'Tippe auf ein Wort ohne Bild, um eines auszuwählen.',
        ].join('\n');
      });
    }
  }

  /// Lets the caregiver choose a picture for [slot] by hand (e.g. "Schnee"
  /// when no symbol was found automatically, or to replace a wrong one).
  /// The choice is saved under the word, so it is found by itself next
  /// time.
  Future<void> _chooseFor(_Slot slot) async {
    if (slot.searching) return;
    final chosen = await (widget.chooseSymbol ?? pickSymbolForWord)(
      context,
      slot.word,
    );
    if (chosen == null || !mounted) return;
    _cache[slot.word.toLowerCase()] = chosen;
    setState(() {
      for (final s in _slots) {
        if (s.word.toLowerCase() == slot.word.toLowerCase()) s.symbol = chosen;
      }
      if (_slots.every((s) => s.symbol != null)) _status = null;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_sentence.isEmpty) return;
    final updated = toggleFavorite(_favorites, _sentence);
    setState(() => _favorites = updated);
    await (await _favoritesStore()).save(updated);
  }

  Future<void> _openFavorites() async {
    final chosen = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _FavoritesScreen(
          favorites: _favorites,
          onChanged: (updated) async {
            setState(() => _favorites = updated);
            await (await _favoritesStore()).save(updated);
          },
        ),
      ),
    );
    if (chosen != null && mounted) await showSentence(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final favorite = _sentence.isNotEmpty && isFavorite(_favorites, _sentence);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprechen → Symbole'),
        actions: [
          IconButton(
            onPressed: _openFavorites,
            icon: const Icon(Icons.star_outline),
            tooltip: 'Favoriten',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (_sentence.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sentence,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      iconSize: 32,
                      onPressed: _toggleFavorite,
                      icon: Icon(
                        favorite ? Icons.star : Icons.star_border,
                        color: favorite ? Colors.amber.shade800 : null,
                      ),
                      tooltip: favorite
                          ? 'Aus Favoriten entfernen'
                          : 'Als Favorit speichern',
                    ),
                  ],
                ),
              Expanded(
                child: _slots.isEmpty
                    ? Center(
                        child: Text(
                          _status ??
                              'Mikrofon gedrückt halten und einen Satz sagen.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      )
                    : _SymbolSentence(slots: _slots, onTap: _chooseFor),
              ),
              if (_slots.isNotEmpty && _status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_status!),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 112,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _HoldToSpeakButton(
                        listening: _listening,
                        onPressStart: _startListening,
                        onPressEnd: _stopListening,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _listening ? null : _typeSentence,
                          child: const Center(
                            child: Icon(
                              Icons.keyboard_outlined,
                              size: 44,
                              semanticLabel: 'Satz eingeben',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SymbolSentence extends StatelessWidget {
  const _SymbolSentence({required this.slots, required this.onTap});

  final List<_Slot> slots;
  final ValueChanged<_Slot> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Few words -> bigger cards; never smaller than three per row on a
        // phone, so each symbol stays well recognisable.
        final perRow = slots.length <= 2
            ? slots.length
            : slots.length <= 4
            ? 2
            : 3;
        const spacing = 10.0;
        const labelHeight = 32.0;
        final byWidth =
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        // Also fit the height, so a single word on a wide screen (tablet,
        // landscape) does not run off the bottom. Never below 96 px: more
        // words than fit simply scroll.
        final rows = (slots.length / perRow).ceil();
        final byHeight =
            (constraints.maxHeight - spacing * (rows - 1)) / rows - labelHeight;
        final size = byWidth < byHeight
            ? byWidth
            : byHeight < 96
            ? 96.0
            : byHeight;
        return SingleChildScrollView(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final slot in slots)
                SizedBox(
                  width: size,
                  height: size + labelHeight,
                  child: _WordCard(slot: slot, onTap: () => onTap(slot)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.slot, required this.onTap});

  final _Slot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final image = slot.symbol?.imageFile;
    final missing = !slot.searching && image == null;
    return Semantics(
      button: true,
      label: missing ? '${slot.word}, Bild auswählen' : slot.word,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: missing ? colorScheme.primary : colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: slot.searching
                        ? const CircularProgressIndicator()
                        : image != null
                        ? Image.file(
                            image,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          )
                        // No symbol: the word itself, large, so the sentence
                        // stays complete.
                        : FittedBox(
                            child: Text(
                              slot.word,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (missing) ...[
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        slot.word,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldToSpeakButton extends StatelessWidget {
  const _HoldToSpeakButton({
    required this.listening,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final bool listening;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Gedrückt halten und sprechen',
      child: GestureDetector(
        onLongPressStart: (_) => onPressStart(),
        onLongPressEnd: (_) => onPressEnd(),
        child: Material(
          color: listening
              ? colorScheme.errorContainer
              : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(listening ? Icons.mic : Icons.mic_none_outlined, size: 48),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  listening ? 'Ich höre zu …' : 'Halten & sprechen',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Favourite sentences as big buttons; tapping one shows it again.
class _FavoritesScreen extends StatefulWidget {
  const _FavoritesScreen({required this.favorites, required this.onChanged});

  final List<String> favorites;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<_FavoritesScreen> {
  late List<String> _favorites = List.of(widget.favorites);

  void _remove(String sentence) {
    setState(() => _favorites = toggleFavorite(_favorites, sentence));
    widget.onChanged(_favorites);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoriten')),
      body: _favorites.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Favoriten.\nTippe beim Satz auf den Stern, '
                  'um ihn hier zu speichern.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _favorites.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final sentence = _favorites[index];
                return Material(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).pop(sentence),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 72),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(Icons.star, color: Colors.amber.shade800),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              sentence,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _remove(sentence),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Favorit löschen',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
