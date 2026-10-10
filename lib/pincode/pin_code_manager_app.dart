import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import '../shared/ipc_protocol.dart';
import '../shared/theme.dart';
import '../shared/web_link.dart';
import 'desktop_client.dart';
import 'link_source.dart';
import 'web_client.dart';

typedef DesktopGatewayFactory =
    DesktopGateway Function(LaunchParameters parameters);
typedef WebSessionGatewayFactory =
    WebSessionGateway Function(WebPinRequest request);

void _exitProcess() => exit(0);

/// YesEm Pin Code Manager: collects the signature PIN and reports it to
/// whoever asked for it: the Desktop instance that launched this process, or
/// the server of a web page that opened a `yesem-pcm://` link.
class PinCodeManagerApp extends StatelessWidget {
  const PinCodeManagerApp({
    super.key,
    this.launch,
    this.gatewayFactory = HttpDesktopGateway.new,
    this.links,
    this.webGatewayFactory = HttpWebSessionGateway.new,
    this.linkPolicy = WebLinkPolicy.testBed,
    this.onFinished = _exitProcess,
  });

  /// Connection details handed over on the command line by Desktop; null when
  /// the app was opened by hand or from a browser link.
  final LaunchParameters? launch;
  final DesktopGatewayFactory gatewayFactory;

  /// Browser links (`yesem-pcm://pin?…`), used when [launch] is null.
  final LinkSource? links;
  final WebSessionGatewayFactory webGatewayFactory;
  final WebLinkPolicy linkPolicy;

  /// Called when the helper has nothing more to do. Quits the process by
  /// default.
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YesEm Pin Code Manager',
    theme: yesemTheme(),
    home: PinCodeManagerPage(
      launch: launch,
      gatewayFactory: gatewayFactory,
      links: links,
      webGatewayFactory: webGatewayFactory,
      linkPolicy: linkPolicy,
      onFinished: onFinished,
    ),
  );
}

class PinCodeManagerPage extends StatefulWidget {
  const PinCodeManagerPage({
    super.key,
    required this.launch,
    required this.gatewayFactory,
    required this.onFinished,
    this.links,
    this.webGatewayFactory = HttpWebSessionGateway.new,
    this.linkPolicy = WebLinkPolicy.testBed,
  });

  final LaunchParameters? launch;
  final DesktopGatewayFactory gatewayFactory;
  final LinkSource? links;
  final WebSessionGatewayFactory webGatewayFactory;
  final WebLinkPolicy linkPolicy;
  final VoidCallback onFinished;

  /// PIN2 length is card specific; the PRD only fixes PIN1 at 4 digits.
  static const int minPinLength = 4;
  static const int maxPinLength = 8;

  /// How long the delivery confirmation stays visible before quitting.
  static const Duration closeDelay = Duration(milliseconds: 1500);

  @override
  State<PinCodeManagerPage> createState() => _PinCodeManagerPageState();
}

enum _Connection { none, connecting, connected, failed }

/// Who asked for the PIN, for the texts around the PIN field.
class _Requester {
  const _Requester.desktop(LaunchParameters this.parameters)
    : web = null,
      service = null;

  const _Requester.web(WebPinRequest this.web, {this.service})
    : parameters = null;

  final LaunchParameters? parameters;
  final WebPinRequest? web;

  /// Service name as reported by the web server (after `describe`).
  final String? service;

  bool get isWeb => web != null;
  String get requestId => parameters?.requestId ?? web!.sessionId;
  String get target => isWeb ? (service ?? web!.server.origin) : 'YesEm Desktop';
}

class _PinCodeManagerPageState extends State<PinCodeManagerPage> {
  final TextEditingController _pin = TextEditingController();

  _Requester? _requester;
  DesktopGateway? _gateway;
  StreamSubscription<String>? _linkSubscription;
  _Connection _connection = _Connection.none;
  String? _error;
  bool _submitting = false;
  bool _delivered = false;

  bool get _pinValid => _pin.text.length >= PinCodeManagerPage.minPinLength;
  bool get _canConfirm =>
      _connection == _Connection.connected &&
      _pinValid &&
      !_submitting &&
      !_delivered;

  @override
  void initState() {
    super.initState();
    _pin.addListener(_onPinChanged);
    if (widget.launch case final launch?) {
      _connect(launch);
    } else if (widget.links case final links?) {
      _listenForLinks(links);
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _pin.removeListener(_onPinChanged);
    _pin.dispose();
    _gateway?.close();
    super.dispose();
  }

  Future<void> _listenForLinks(LinkSource links) async {
    _linkSubscription = links.incoming.listen(_openLink);
    final initial = await links.takeInitial();
    if (mounted && initial.isNotEmpty) {
      _openLink(initial.first);
    }
  }

  /// A browser link: validate it, ask its server which service wants the PIN,
  /// then announce ourselves exactly as towards Desktop.
  Future<void> _openLink(String link) async {
    if (!mounted || _submitting || _delivered) {
      return; // Busy with a request; a new one has to wait.
    }
    final WebPinRequest request;
    try {
      request = WebLink.parse(link, policy: widget.linkPolicy);
    } on WebLinkException catch (error) {
      setState(() {
        _connection = _Connection.failed;
        _error = error.message;
      });
      return;
    }
    _gateway?.close();
    final gateway = widget.webGatewayFactory(request);
    setState(() {
      _requester = _Requester.web(request);
      _gateway = gateway;
      _connection = _Connection.connecting;
      _error = null;
    });
    try {
      final info = await gateway.describe();
      await gateway.send(
        PcmEvent(requestId: request.sessionId, type: PcmEventType.opened),
      );
      if (!mounted) return;
      setState(() {
        _requester = _Requester.web(request, service: info.service);
        _connection = _Connection.connected;
      });
    } on DesktopGatewayException catch (error) {
      if (!mounted) return;
      setState(() {
        _connection = _Connection.failed;
        _error = error.message;
      });
    }
  }

  void _onPinChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _connect(LaunchParameters parameters) async {
    _gateway?.close();
    final gateway = widget.gatewayFactory(parameters);
    setState(() {
      _requester = _Requester.desktop(parameters);
      _gateway = gateway;
      _connection = _Connection.connecting;
      _error = null;
    });
    try {
      await gateway.send(
        PcmEvent(requestId: parameters.requestId, type: PcmEventType.opened),
      );
      if (!mounted) return;
      setState(() => _connection = _Connection.connected);
    } on DesktopGatewayException catch (error) {
      if (!mounted) return;
      setState(() {
        _connection = _Connection.failed;
        _error = error.message;
      });
    }
  }

  Future<void> _confirm() async {
    final requester = _requester;
    final gateway = _gateway;
    if (requester == null || gateway == null || !_canConfirm) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await gateway.send(
        PcmEvent(
          requestId: requester.requestId,
          type: PcmEventType.pinEntered,
          pin: _pin.text,
        ),
      );
      if (!mounted) return;
      _pin.clear(); // Do not keep the PIN around longer than needed.
      setState(() {
        _submitting = false;
        _delivered = true;
      });
      await Future<void>.delayed(PinCodeManagerPage.closeDelay);
      if (mounted) {
        widget.onFinished();
      }
    } on DesktopGatewayException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    }
  }

  Future<void> _cancel() async {
    final requester = _requester;
    final gateway = _gateway;
    if (requester != null &&
        gateway != null &&
        _connection == _Connection.connected) {
      try {
        await gateway.send(
          PcmEvent(
            requestId: requester.requestId,
            type: PcmEventType.cancelled,
          ),
        );
      } on DesktopGatewayException {
        // The requester may already be gone; closing regardless.
      }
    }
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = _requester?.isWeb ?? false;
    final showManualForm =
        widget.links == null &&
        (widget.launch == null || _connection == _Connection.failed);
    return Scaffold(
      appBar: AppBar(title: const Text('YesEm Pin Code Manager')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              _RequestCard(
                requester: _requester,
                connection: _connection,
                error: _error,
                onClose: widget.links != null || isWeb ? widget.onFinished : null,
              ),
              if (_connection == _Connection.connected) ...<Widget>[
                const SizedBox(height: 16),
                _buildPinEntry(context),
              ],
              if (showManualForm) ...<Widget>[
                const SizedBox(height: 16),
                _ManualConnectionCard(
                  initial: _requester?.parameters,
                  onConnect: _connect,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry(BuildContext context) {
    final theme = Theme.of(context);
    final requester = _requester;
    final hint = requester != null && requester.isWeb
        ? 'Enter the signature PIN of your ID card. It is sent to '
              '${requester.target} (${requester.web!.server.origin}). Continue '
              'only if you started this on that website.'
        : 'Enter the signature PIN of your ID card. It is sent only to '
              'YesEm Desktop running on this computer.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Signature PIN (PIN2)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(hint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              key: const Key('pin-field'),
              controller: _pin,
              autofocus: true,
              enabled: !_delivered && !_submitting,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(PinCodeManagerPage.maxPinLength),
              ],
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText: 'PIN2',
                helperText:
                    '${PinCodeManagerPage.minPinLength}–'
                    '${PinCodeManagerPage.maxPinLength} digits',
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(letterSpacing: 6, fontSize: 20),
            ),
            const SizedBox(height: 16),
            if (_delivered)
              Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PIN delivered to ${requester?.target}. Closing…',
                      key: const Key('delivered-text'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: <Widget>[
                  FilledButton(
                    key: const Key('confirm-button'),
                    onPressed: _canConfirm ? _confirm : null,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirm'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    key: const Key('cancel-button'),
                    onPressed: _submitting ? null : _cancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            if (_error case final error? when !_delivered) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                error,
                key: const Key('error-text'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.requester,
    required this.connection,
    required this.error,
    this.onClose,
  });

  final _Requester? requester;
  final _Connection connection;
  final String? error;

  /// Offered when the request failed and there's nothing else to do here.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requester = this.requester;
    final web = requester?.web;
    final (IconData icon, String title, String detail) = switch (connection) {
      _Connection.none => (
        Icons.info_outline,
        'No active signing request',
        'This helper is opened by YesEm Desktop when you click Sign, or by a '
            'website. Start it from there, or connect manually below.',
      ),
      _Connection.connecting when web != null => (
        Icons.hourglass_top,
        'Contacting ${web.server.origin}…',
        'Session ${web.sessionId}',
      ),
      _Connection.connecting => (
        Icons.hourglass_top,
        'Connecting to YesEm Desktop…',
        'Request ${requester?.requestId}',
      ),
      _Connection.connected when web != null => (
        Icons.public,
        'Signing request from ${requester?.service}',
        'Website ${web.server.origin} · session ${web.sessionId}',
      ),
      _Connection.connected => (
        Icons.desktop_windows_outlined,
        'Signing request from YesEm Desktop',
        'Request ${requester?.requestId} · '
            '${requester?.parameters?.host}:${requester?.parameters?.port}',
      ),
      _Connection.failed when web != null || requester == null => (
        Icons.error_outline,
        'Could not process the website\'s request',
        error ?? 'Unknown error',
      ),
      _Connection.failed => (
        Icons.error_outline,
        'Could not reach YesEm Desktop',
        error ?? 'Unknown error',
      ),
    };
    final failed = connection == _Connection.failed;
    return Card(
      child: ListTile(
        leading: Icon(
          icon,
          color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
        title: Text(title, key: const Key('request-title')),
        subtitle: Text(detail),
        trailing: failed && onClose != null
            ? TextButton(onPressed: onClose, child: const Text('Close'))
            : null,
      ),
    );
  }
}

/// Development aid: connect to a Desktop instance whose details were read off
/// its "Connection details" panel, e.g. while hot-reloading this app.
class _ManualConnectionCard extends StatefulWidget {
  const _ManualConnectionCard({required this.initial, required this.onConnect});

  final LaunchParameters? initial;
  final ValueChanged<LaunchParameters> onConnect;

  @override
  State<_ManualConnectionCard> createState() => _ManualConnectionCardState();
}

class _ManualConnectionCardState extends State<_ManualConnectionCard> {
  late final TextEditingController _port = TextEditingController(
    text: widget.initial?.port.toString() ?? '',
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.initial?.token ?? '',
  );
  late final TextEditingController _requestId = TextEditingController(
    text: widget.initial?.requestId ?? '',
  );

  @override
  void dispose() {
    _port.dispose();
    _token.dispose();
    _requestId.dispose();
    super.dispose();
  }

  void _submit() {
    final parameters = LaunchParameters.parse(<String>[
      '${IpcProtocol.argPort}=${_port.text.trim()}',
      '${IpcProtocol.argToken}=${_token.text.trim()}',
      '${IpcProtocol.argRequestId}=${_requestId.text.trim()}',
    ]);
    if (parameters == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port, token and request id are required.')),
      );
      return;
    }
    widget.onConnect(parameters);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Manual connection (development)'),
      subtitle: const Text('Values from Desktop → Connection details'),
      initiallyExpanded: widget.initial == null,
      childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      children: <Widget>[
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(labelText: 'Port'),
        ),
        TextField(
          controller: _token,
          decoration: const InputDecoration(labelText: 'Token'),
        ),
        TextField(
          controller: _requestId,
          decoration: const InputDecoration(labelText: 'Request ID'),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _submit, child: const Text('Connect')),
        ),
      ],
    ),
  );
}
