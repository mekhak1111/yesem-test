import 'package:flutter/material.dart';

import '../shared/theme.dart';
import 'signing_controller.dart';

/// YesEm Desktop: the document-signing application.
///
/// This test build has a single Sign action that opens the Pin Code Manager
/// and shows whatever PIN it reports back.
class DesktopApp extends StatefulWidget {
  const DesktopApp({super.key, this.controller, this.roleSource = 'default'});

  /// Injected in tests; the app owns its own controller otherwise.
  final SigningController? controller;

  /// How this process learned it is Desktop (flavor, define, argument).
  final String roleSource;

  @override
  State<DesktopApp> createState() => _DesktopAppState();
}

class _DesktopAppState extends State<DesktopApp> {
  late final SigningController _controller =
      widget.controller ?? SigningController();

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YesEm Desktop',
    theme: yesemTheme(),
    home: DesktopHomePage(
      controller: _controller,
      roleSource: widget.roleSource,
    ),
  );
}

class DesktopHomePage extends StatelessWidget {
  const DesktopHomePage({
    super.key,
    required this.controller,
    this.roleSource = 'default',
  });

  final SigningController controller;
  final String roleSource;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('YesEm Desktop'),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Chip(
              label: Text(roleSource),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              _SigningCard(controller: controller),
              if (controller.receivedPin case final pin?) ...<Widget>[
                const SizedBox(height: 16),
                _ReceivedPinCard(pin: pin),
              ],
              const SizedBox(height: 16),
              _ConnectionDetails(controller: controller),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SigningCard extends StatelessWidget {
  const _SigningCard({required this.controller});

  final SigningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _StatusPresentation.of(controller);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Document signing', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Signing with an ID card in a card reader. The signature PIN '
              '(PIN2) is entered in the YesEm Pin Code Manager, never here.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('sign-button'),
                  onPressed: controller.isBusy ? null : controller.startSigning,
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Sign'),
                ),
                const SizedBox(width: 12),
                if (controller.phase != SigningPhase.idle)
                  TextButton(
                    key: const Key('reset-button'),
                    onPressed: controller.reset,
                    child: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (controller.isBusy)
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(status.icon, color: status.color(theme)),
                  ),
                Expanded(
                  child: SelectableText(
                    status.message,
                    key: const Key('status-text'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: status.color(theme),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedPinCard extends StatelessWidget {
  const _ReceivedPinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'PIN received from the Pin Code Manager',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SelectableText(
              pin,
              key: const Key('received-pin'),
              style: theme.textTheme.displaySmall?.copyWith(
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Test build only. The production YesEm Desktop must never '
              'display, store or log a PIN.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({required this.controller});

  final SigningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
          Expanded(
            child: SelectableText(
              value ?? '—',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );

    return Card(
      child: ExpansionTile(
        title: const Text('Connection details'),
        subtitle: const Text(
          'Loopback HTTP channel between Desktop and the Pin Code Manager',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        children: <Widget>[
          row(
            'Listening on',
            controller.port == null
                ? null
                : '127.0.0.1:${controller.port}  (POST /pcm/event)',
          ),
          row('Request ID', controller.requestId),
          row('Token', controller.token),
          row('Pin Code Manager', controller.pinCodeManagerPath),
          const SizedBox(height: 8),
          Text(
            'To develop the Pin Code Manager with hot reload, run '
            '`flutter run -d macos --flavor pincode` and paste these values '
            'into its manual connection form.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation(this.message, this.icon, this._tone);

  final String message;
  final IconData icon;
  final _Tone _tone;

  Color? color(ThemeData theme) => switch (_tone) {
    _Tone.neutral => null,
    _Tone.success => theme.colorScheme.primary,
    _Tone.warning => theme.colorScheme.tertiary,
    _Tone.error => theme.colorScheme.error,
  };

  static _StatusPresentation of(SigningController controller) =>
      switch (controller.phase) {
        SigningPhase.idle => const _StatusPresentation(
          'Ready. Click Sign to open the YesEm Pin Code Manager.',
          Icons.info_outline,
          _Tone.neutral,
        ),
        SigningPhase.launching => const _StatusPresentation(
          'Opening the YesEm Pin Code Manager…',
          Icons.hourglass_top,
          _Tone.neutral,
        ),
        SigningPhase.waitingForPin => const _StatusPresentation(
          'The Pin Code Manager is open. Waiting for the signature PIN…',
          Icons.hourglass_top,
          _Tone.neutral,
        ),
        SigningPhase.pinReceived => const _StatusPresentation(
          'PIN received. In the real product the card would now sign the '
          'document.',
          Icons.check_circle_outline,
          _Tone.success,
        ),
        SigningPhase.cancelled => const _StatusPresentation(
          'Signing was cancelled in the Pin Code Manager.',
          Icons.cancel_outlined,
          _Tone.warning,
        ),
        SigningPhase.closedWithoutPin => const _StatusPresentation(
          'The Pin Code Manager was closed before a PIN was entered.',
          Icons.warning_amber_outlined,
          _Tone.warning,
        ),
        SigningPhase.failed => _StatusPresentation(
          controller.errorMessage ?? 'Signing failed.',
          Icons.error_outline,
          _Tone.error,
        ),
      };
}

enum _Tone { neutral, success, warning, error }
