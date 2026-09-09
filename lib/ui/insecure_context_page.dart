import 'package:flutter/material.dart';

/// Shown instead of the app when a browser withholds Web Crypto.
///
/// Deliberately a dead end rather than a dismissable warning. The alternative
/// is running on the pure-Dart fallback: roughly two seconds per message on a
/// main thread that cannot animate a spinner, using a code path far less
/// exercised than the browser's own. Both failures are quiet ones, and a user
/// who cannot tell the difference is exactly who this screen is for.
class InsecureContextPage extends StatelessWidget {
  const InsecureContextPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.lock_outline, size: 40, color: scheme.error),
                  const SizedBox(height: 18),
                  Text(
                    "Glyph can't run safely on this address",
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This page was opened over an insecure connection, so your '
                    'browser is holding back the encryption tools it normally '
                    'provides.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Glyph could carry on without them, but it would be much '
                    'slower and would no longer be using the encryption built '
                    'into your browser. Rather than quietly do something '
                    'weaker, it stops here.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'What to do',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Open Glyph on an address beginning with https:// '
                          'instead. If you are running it yourself on this '
                          'computer, http://localhost also works.',
                          style: theme.textTheme.bodyMedium,
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
