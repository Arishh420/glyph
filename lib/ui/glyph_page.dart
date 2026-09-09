import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/envelope.dart';
import '../core/glyph_codec.dart';
import '../core/glyph_errors.dart';
import '../core/key_rules.dart';
import '../data/key_store.dart';
import '../data/key_store_factory.dart';
import 'labelled_box.dart';
import 'theme.dart';

/// What the single action button is currently for.
enum ActionState {
  /// No usable key yet.
  enterKey,

  /// Key is fine, but there is nothing to work on.
  idle,

  /// Input is ordinary text.
  encrypt,

  /// Input looks like a Glyph message.
  decrypt,

  /// An operation is in flight.
  running,
}

/// Widget keys for the four things a test needs to find.
class GlyphKeys {
  const GlyphKeys._();

  static const Key keyField = Key('glyph.keyField');
  static const Key outputField = Key('glyph.outputField');
  static const Key inputField = Key('glyph.inputField');
  static const Key actionButton = Key('glyph.actionButton');
}

/// The whole application: key, output, input, one button.
class GlyphPage extends StatefulWidget {
  const GlyphPage({
    required this.codec,
    required this.keyStore,
    super.key,
  });

  final GlyphCodec codec;
  final KeyStore keyStore;

  @override
  State<GlyphPage> createState() => _GlyphPageState();
}

class _GlyphPageState extends State<GlyphPage> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  final FocusNode _keyFocus = FocusNode(debugLabel: 'key');
  final FocusNode _inputFocus = FocusNode(debugLabel: 'input');

  bool _obscureKey = true;
  bool _running = false;
  String? _error;

  /// Set while a brief "Copied" acknowledgement is showing.
  bool _outputCopied = false;
  bool _keyCopied = false;
  Timer? _outputCopyTimer;
  Timer? _keyCopyTimer;

  /// The short-key hint is shown once and then latched off, so it informs
  /// without turning into a recurring scold.
  bool _shortHintSpent = false;

  /// Last key written to storage, to avoid rewriting on every keystroke.
  String? _savedKey;

  @override
  void initState() {
    super.initState();
    _key.addListener(_onKeyChanged);
    _input.addListener(_onInputChanged);
    _loadStoredKey();
  }

  @override
  void dispose() {
    _outputCopyTimer?.cancel();
    _keyCopyTimer?.cancel();
    _key.removeListener(_onKeyChanged);
    _input.removeListener(_onInputChanged);
    _key.dispose();
    _input.dispose();
    _output.dispose();
    _keyFocus.dispose();
    _inputFocus.dispose();
    widget.codec.dispose();
    super.dispose();
  }

  Future<void> _loadStoredKey() async {
    String? stored;
    try {
      stored = await widget.keyStore.read();
    } catch (_) {
      // A key store that cannot be read is not fatal: the user can type the
      // key again. Nothing about the failure is worth showing them.
      stored = null;
    }
    if (!mounted) {
      return;
    }
    if (stored != null && stored.isNotEmpty) {
      _savedKey = stored;
      _key.text = stored;
    }
    setState(() {});
    _focusOnLaunch();
  }

  /// Puts focus in the right field and makes sure the keyboard actually opens.
  ///
  /// With no usable key there is nothing the input can be used for, so the key
  /// field wins; otherwise the input does.
  ///
  /// The delay and the explicit show are not superstition. Requesting focus
  /// while the platform view is still being attached to Android's input method
  /// manager leaves the field focused but the keyboard closed: logcat shows
  /// "Ignoring showSoftInput() as view ... is not served". Focus alone is
  /// therefore not enough, and neither is `autofocus`, which runs during the
  /// very first build. Re-asserting the request once the view is attached is
  /// what actually raises the keyboard.
  void _focusOnLaunch() {
    final target = KeyRules.isValid(_key.text) ? _inputFocus : _keyFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      target.requestFocus();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || !target.hasFocus) {
        return;
      }
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  // ---------------------------------------------------------------- reactions

  void _onKeyChanged() {
    // Latch the short-key hint off once the key has grown past the threshold,
    // so it informs once rather than reappearing on every later edit.
    if (KeyRules.isValid(_key.text) && !KeyRules.isShort(_key.text)) {
      _shortHintSpent = true;
    }
    final normalised = KeyRules.normalise(_key.text);
    if (normalised != _savedKey) {
      // A different key invalidates every cached derived key.
      widget.codec.clearCache();
      if (KeyRules.isValid(normalised)) {
        _savedKey = normalised;
        widget.keyStore.write(normalised).catchError((Object _) {
          // Failing to persist is not worth interrupting the user for; the
          // key still works for this session.
        });
      } else {
        _savedKey = null;
      }
    }
    setState(() {});
  }

  void _onInputChanged() {
    // The error refers to the previous input, so it goes as soon as the input
    // changes.
    setState(() => _error = null);
  }

  // -------------------------------------------------------------- derived state
  // Direction is read off the input text, live.

  bool get _looksLikeGlyph {
    final trimmed = _input.text.trimLeft();
    if (trimmed.length < Envelope.prefix.length) {
      return false;
    }
    // Case-insensitive purely to choose the button label. The decoder itself
    // stays strict, so 'gly1...' still fails as NotGlyphMessage.
    return trimmed
        .substring(0, Envelope.prefix.length)
        .toUpperCase()
        .startsWith(Envelope.prefix);
  }

  bool get _keyIsValid => KeyRules.isValid(_key.text);

  ActionState get _actionState {
    if (_running) {
      return ActionState.running;
    }
    if (!_keyIsValid) {
      return ActionState.enterKey;
    }
    if (_input.text.trim().isEmpty) {
      return ActionState.idle;
    }
    return _looksLikeGlyph ? ActionState.decrypt : ActionState.encrypt;
  }

  /// On macOS the "Enter Key" state is inert and the key field is focused at
  /// launch instead; on touch platforms tapping it raises the keyboard.
  bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  bool get _buttonEnabled {
    switch (_actionState) {
      case ActionState.enterKey:
        return !_isMacOS;
      case ActionState.encrypt:
      case ActionState.decrypt:
        return true;
      case ActionState.idle:
      case ActionState.running:
        return false;
    }
  }

  String get _buttonLabel {
    switch (_actionState) {
      case ActionState.enterKey:
        return 'Enter Key';
      case ActionState.idle:
        return 'Encrypt / Decrypt';
      case ActionState.encrypt:
        return 'Encrypt';
      case ActionState.decrypt:
        return 'Decrypt';
      case ActionState.running:
        return '';
    }
  }

  // --------------------------------------------------------------- operations

  Future<void> _run() async {
    if (_running) {
      return;
    }
    if (!_keyIsValid) {
      if (!_isMacOS) {
        _keyFocus.requestFocus();
      }
      return;
    }
    final input = _input.text;
    if (input.trim().isEmpty) {
      return;
    }

    final decrypting = _looksLikeGlyph;
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      final result = decrypting
          ? await widget.codec.decrypt(key: _key.text, armoured: input)
          : await widget.codec.encrypt(key: _key.text, plaintext: input);
      if (!mounted) {
        return;
      }
      setState(() {
        _output.text = result;
        _running = false;
      });
    } on GlyphError catch (error) {
      if (!mounted) {
        return;
      }
      // Input and output are left exactly as they were.
      setState(() {
        _error = error.message;
        _running = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Something went wrong while handling this message.';
        _running = false;
      });
    }
  }

  Future<void> _copyOutput() async {
    await Clipboard.setData(ClipboardData(text: _output.text));
    if (!mounted) {
      return;
    }
    setState(() => _outputCopied = true);
    _outputCopyTimer?.cancel();
    _outputCopyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _outputCopied = false);
      }
    });
  }

  Future<void> _copyKey() async {
    await Clipboard.setData(ClipboardData(text: _key.text));
    if (!mounted) {
      return;
    }
    setState(() => _keyCopied = true);
    _keyCopyTimer?.cancel();
    _keyCopyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _keyCopied = false);
      }
    });
  }

  Future<void> _pasteInput() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  void _generateKey() {
    _key.text = KeyRules.generate();
    // Reveal it: a generated key is no use unless it can be read and passed
    // to the other person.
    setState(() => _obscureKey = false);
  }

  /// Wipes the key from storage, from the field, and every derived key from
  /// the cache.
  Future<void> _forgetKey() async {
    _key.clear();
    _savedKey = null;
    setState(() {
      _obscureKey = true;
      _error = null;
    });
    await widget.codec.clearCache();
    try {
      await widget.keyStore.delete();
    } catch (_) {
      // Nothing useful to say if the store refuses.
    }
    if (mounted) {
      _keyFocus.requestFocus();
    }
  }

  // ------------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        // Android 16 enforces edge-to-edge, so the insets are honoured on
        // every side rather than relying on a system-drawn bar.
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            // macOS uses Cmd+Enter; the control variant covers a hardware
            // keyboard attached to a phone or tablet.
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _run,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _run,
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildKeyBox(scheme),
                if (!kKeyStorePersists) _buildNoPersistenceNotice(scheme),
                const SizedBox(height: 18),
                Expanded(child: _buildOutputBox(scheme)),
                const SizedBox(height: 18),
                Expanded(child: _buildInputBox(scheme)),
                const SizedBox(height: 18),
                _buildActionButton(scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Permanent, non-dismissable line shown only where the key cannot be saved.
  ///
  /// That is the web build, and it is the one difference in behaviour a friend
  /// will actually trip over: they type a key, refresh, and it is gone. Saying
  /// so once, always, in the interface is cheaper than the confusion. Driven by
  /// [kKeyStorePersists] rather than a `kIsWeb` check, so it stays true to what
  /// the key store actually does rather than to a guess about the platform.
  Widget _buildNoPersistenceNotice(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 15,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              "Key is not saved in the browser — you'll need to re-enter it "
              'after a refresh.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(ColorScheme scheme, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    );
  }

  Widget _buildKeyBox(ColorScheme scheme) {
    final hasKey = _key.text.isNotEmpty;
    final showShortHint = KeyRules.isShort(_key.text) && !_shortHintSpent;

    return LabelledBox(
      label: 'KEY',
      actions: <Widget>[
        if (hasKey && !_obscureKey)
          BoxAction(
            icon: _keyCopied ? Icons.check : Icons.copy_all_outlined,
            tooltip: _keyCopied ? 'Copied' : 'Copy key',
            colour: _keyCopied ? GlyphTheme.actionColour(context) : null,
            onPressed: _copyKey,
          ),
        if (hasKey)
          BoxAction(
            icon: Icons.backspace_outlined,
            tooltip: 'Forget key',
            onPressed: _forgetKey,
          ),
      ],
      footer: showShortHint
          ? Text(
              'Short key — fine for casual use.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
            )
          : null,
      child: TextField(
        key: GlyphKeys.keyField,
        controller: _key,
        focusNode: _keyFocus,
        obscureText: _obscureKey,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        textInputAction: TextInputAction.done,
        // The action key on the key field runs the operation when there is
        // something to act on, and otherwise moves to the input.
        onSubmitted: (_) {
          if (_input.text.trim().isNotEmpty && _keyIsValid) {
            _run();
          } else {
            _inputFocus.requestFocus();
          }
        },
        style: GlyphTheme.monoStyle(context),
        decoration: _fieldDecoration(scheme, 'Shared key').copyWith(
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_keyIsValid)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.check_circle,
                    size: 19,
                    color: GlyphTheme.actionColour(context),
                    semanticLabel: 'Key is valid',
                  ),
                ),
              BoxAction(
                icon: _obscureKey
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                tooltip: _obscureKey ? 'Reveal key' : 'Hide key',
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
              BoxAction(
                icon: Icons.casino_outlined,
                tooltip: 'Generate a random key',
                onPressed: _generateKey,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutputBox(ColorScheme scheme) {
    final hasOutput = _output.text.isNotEmpty;

    return LabelledBox(
      label: 'OUTPUT',
      expand: true,
      actions: <Widget>[
        if (hasOutput) ...<Widget>[
          BoxAction(
            icon: _outputCopied ? Icons.check : Icons.copy_all_outlined,
            tooltip: _outputCopied ? 'Copied' : 'Copy',
            colour: _outputCopied ? GlyphTheme.actionColour(context) : null,
            onPressed: _copyOutput,
          ),
          BoxAction(
            icon: Icons.close,
            tooltip: 'Clear output',
            onPressed: () => setState(_output.clear),
          ),
        ],
      ],
      footer: _error == null
          ? null
          : Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w500,
                  ),
            ),
      child: TextField(
        key: GlyphKeys.outputField,
        controller: _output,
        // Read-only, and no caret: this box is a result, not somewhere to
        // type. Selection stays on so the text can be copied by hand.
        readOnly: true,
        showCursor: false,
        enableInteractiveSelection: true,
        maxLines: null,
        minLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: GlyphTheme.monoStyle(context),
        decoration: _fieldDecoration(scheme, 'Your result appears here'),
      ),
    );
  }

  Widget _buildInputBox(ColorScheme scheme) {
    final hasInput = _input.text.isNotEmpty;

    return LabelledBox(
      label: 'INPUT',
      expand: true,
      actions: <Widget>[
        if (hasInput)
          BoxAction(
            icon: Icons.close,
            tooltip: 'Clear input',
            onPressed: () => setState(_input.clear),
          ),
        BoxAction(
          icon: Icons.content_paste_go_outlined,
          tooltip: 'Paste',
          onPressed: _pasteInput,
        ),
      ],
      child: TextField(
        key: GlyphKeys.inputField,
        controller: _input,
        focusNode: _inputFocus,
        maxLines: null,
        minLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        // Enter inserts a newline: a message being encrypted may well contain
        // line breaks. Cmd/Ctrl+Enter runs the operation instead.
        textInputAction: TextInputAction.newline,
        // Autocorrect silently rewriting a pasted ciphertext would look like
        // an unfixable bug, so every helpful text behaviour is off.
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        style: GlyphTheme.monoStyle(context),
        decoration: _fieldDecoration(
          scheme,
          'Type a message, or paste an encrypted one',
        ),
      ),
    );
  }

  Widget _buildActionButton(ColorScheme scheme) {
    final enabled = _buttonEnabled;
    final isAction = _actionState == ActionState.encrypt ||
        _actionState == ActionState.decrypt;

    return SizedBox(
      height: 52,
      child: FilledButton(
        key: GlyphKeys.actionButton,
        onPressed: enabled ? _run : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              isAction ? GlyphTheme.actionColour(context) : scheme.secondary,
          foregroundColor: isAction ? Colors.white : scheme.onSecondary,
          disabledBackgroundColor:
              scheme.onSurface.withValues(alpha: 0.10),
          disabledForegroundColor:
              scheme.onSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        child: _actionState == ActionState.running
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              )
            : Text(_buttonLabel),
      ),
    );
  }
}
