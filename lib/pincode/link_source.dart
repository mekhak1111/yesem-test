import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../shared/web_link.dart';

/// Where links opened from a browser reach this process.
abstract interface class LinkSource {
  /// Links that started the app (cold start); empty when there were none.
  Future<List<String>> takeInitial();

  /// Links arriving while the app runs.
  Stream<String> get incoming;
}

/// Per-OS delivery:
///
/// * macOS sends links as Apple Events to the running app (also on a cold
///   start); AppDelegate.swift buffers them and hands them over on the
///   `yesem/links` channel.
/// * Windows and Linux start the registered executable with the link as a
///   command-line argument. A second link starts a second process (no
///   single-instance forwarding in this test bed).
LinkSource platformLinkSource(List<String> args) =>
    Platform.isMacOS ? MethodChannelLinkSource() : ArgsLinkSource(args);

class ArgsLinkSource implements LinkSource {
  ArgsLinkSource(this.args);

  final List<String> args;

  @override
  Future<List<String>> takeInitial() async => <String>[
    ?WebLink.findInArgs(args),
  ];

  @override
  Stream<String> get incoming => const Stream<String>.empty();
}

class MethodChannelLinkSource implements LinkSource {
  MethodChannelLinkSource([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        _incoming.add(call.arguments as String);
      }
    });
  }

  static const String channelName = 'yesem/links';

  final MethodChannel _channel;
  final StreamController<String> _incoming = StreamController<String>.broadcast();

  @override
  Future<List<String>> takeInitial() async {
    try {
      final links = await _channel.invokeListMethod<String>('takePending');
      return links ?? const <String>[];
    } on MissingPluginException {
      return const <String>[]; // Runner without the native handler.
    }
  }

  @override
  Stream<String> get incoming => _incoming.stream;
}
