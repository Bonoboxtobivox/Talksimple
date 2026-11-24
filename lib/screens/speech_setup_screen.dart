import 'package:flutter/material.dart';

import '../services/speech_service.dart';
import '../services/speech_settings.dart';

/// Guided speech recognition setup for whoever sets the app up:
///
/// 1. pick the German variant (Austria / Germany / Switzerland),
/// 2. pick online or offline recognition,
/// 3. say something to test exactly that combination.
///
/// "Fertig" only unlocks after a successful test, so a saved setup is
/// known to work. Changing step 1 or 2 invalidates an earlier test.
class SpeechSetupScreen extends StatefulWidget {
  /// [openSettings] and [speechService] are only overridden in tests.
  const SpeechSetupScreen({super.key, this.openSettings, this.speechService});

  final Future<SpeechSettingsRepository> Function()? openSettings;
  final SpeechService? speechService;

  @override
  State<SpeechSetupScreen> createState() => _SpeechSetupScreenState();
}

enum _TestState { idle, listening, passed, failed }

class _SpeechSetupScreenState extends State<SpeechSetupScreen> {
  late final SpeechService _speech =
      widget.speechService ?? DeviceSpeechService();

  SpeechSettings? _settings;
  _TestState _test = _TestState.idle;
  String _heard = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<SpeechSettingsRepository> _store() =>
      (widget.openSettings ?? openSpeechSettings)();

  Future<void> _load() async {
    final settings = await (await _store()).load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  void _change(SpeechSettings settings) {
    setState(() {
      _settings = settings;
      _test = _TestState.idle;
      _heard = '';
    });
  }

  Future<void> _toggleTest() async {
    final settings = _settings;
    if (settings == null) return;
    if (_test == _TestState.listening) {
      final heard = await _speech.stop();
      if (!mounted) return;
      setState(() {
        _heard = heard;
        _test = heard.isEmpty ? _TestState.failed : _TestState.passed;
      });
      return;
    }
    final started = await _speech.start(settings);
    if (!mounted) return;
    setState(() {
      _heard = '';
      _test = started ? _TestState.listening : _TestState.failed;
    });
  }

  Future<void> _finish() async {
    final settings = _settings!.copyWith(configured: true);
    await (await _store()).save(settings);
    if (!mounted) return;
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Spracherkennung einrichten')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _Step(
                          number: 1,
                          done: true,
                          title: 'Welche Sprache wird gesprochen?',
                          child: Column(
                            children: [
                              for (final variant in speechVariants)
                                _ChoiceButton(
                                  label: variant.label,
                                  selected:
                                      settings.localeId == variant.localeId,
                                  onTap: () => _change(
                                    settings.copyWith(
                                      localeId: variant.localeId,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _Step(
                          number: 2,
                          done: true,
                          title: 'Mit oder ohne Internet?',
                          child: Column(
                            children: [
                              _ChoiceButton(
                                label: 'Ohne Internet (empfohlen)',
                                description:
                                    'Schneller und überall nutzbar. Braucht das '
                                    'Offline-Sprachpaket am Gerät.',
                                selected: settings.onDevice,
                                onTap: () =>
                                    _change(settings.copyWith(onDevice: true)),
                              ),
                              _ChoiceButton(
                                label: 'Mit Internet',
                                description:
                                    'Geht sofort ohne Einrichtung, braucht aber '
                                    'gutes WLAN oder Mobilfunk.',
                                selected: !settings.onDevice,
                                onTap: () =>
                                    _change(settings.copyWith(onDevice: false)),
                              ),
                            ],
                          ),
                        ),
                        _Step(
                          number: 3,
                          done: _test == _TestState.passed,
                          title: 'Kurz testen',
                          child: _TestArea(
                            state: _test,
                            heard: _heard,
                            onDevice: settings.onDevice,
                            onToggle: _toggleTest,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: FilledButton(
                        onPressed: _test == _TestState.passed ? _finish : null,
                        child: Text(
                          _test == _TestState.passed
                              ? 'Fertig'
                              : 'Bitte zuerst testen',
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.done,
    required this.title,
    required this.child,
  });

  final int number;
  final bool done;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: done && number == 3
                      ? Colors.green.shade700
                      : colorScheme.primary,
                  child: done && number == 3
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : Text(
                          '$number',
                          style: TextStyle(color: colorScheme.onPrimary),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (description != null)
                          Text(
                            description!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TestArea extends StatelessWidget {
  const _TestArea({
    required this.state,
    required this.heard,
    required this.onDevice,
    required this.onToggle,
  });

  final _TestState state;
  final String heard;
  final bool onDevice;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final listening = state == _TestState.listening;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: FilledButton.tonalIcon(
            onPressed: onToggle,
            icon: Icon(listening ? Icons.stop : Icons.mic),
            label: Text(
              listening ? 'Fertig gesprochen' : 'Jetzt testen',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(height: 12),
        switch (state) {
          _TestState.idle => const Text(
            'Tippe auf „Jetzt testen“, sag ein paar Worte und tippe dann '
            'auf „Fertig gesprochen“.',
          ),
          _TestState.listening => const Text('Ich höre zu …'),
          _TestState.passed => _Message(
            icon: Icons.check_circle,
            color: Colors.green.shade800,
            text: 'Funktioniert! Erkannt: „$heard“',
          ),
          _TestState.failed => _Message(
            icon: Icons.warning_amber,
            color: Colors.orange.shade900,
            text: onDevice
                ? 'Das hat nicht geklappt. Vielleicht war es zu leise, oder '
                      'das Offline-Sprachpaket fehlt noch. Installieren: '
                      'Android-Einstellungen → Google → Spracherkennung → '
                      'Offline-Spracherkennung. Oder wähle „Mit Internet“.'
                : 'Das hat nicht geklappt. Vielleicht war es zu leise, das '
                      'Internet fehlt, oder das Mikrofon ist nicht erlaubt.',
          ),
        },
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
