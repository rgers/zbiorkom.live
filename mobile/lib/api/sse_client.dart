import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../core/api_config.dart';

class SseFrame {
  const SseFrame({
    required this.event,
    required this.data,
  });

  final String event;
  final String data;
}

class SseStreamSnapshot<TData, TInitial> {
  const SseStreamSnapshot({
    this.data,
    this.initialData,
    this.isLoading = false,
    this.error,
  });

  final TData? data;
  final TInitial? initialData;
  final bool isLoading;
  final String? error;

  SseStreamSnapshot<TData, TInitial> copyWith({
    TData? data,
    TInitial? initialData,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return SseStreamSnapshot<TData, TInitial>(
      data: data ?? this.data,
      initialData: initialData ?? this.initialData,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SseParser {
  String _event = 'message';
  final List<String> _dataLines = <String>[];

  SseFrame? feedLine(String rawLine) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;

    if (line.isEmpty) {
      if (_dataLines.isEmpty) {
        _event = 'message';
        return null;
      }
      final frame = SseFrame(
        event: _event,
        data: _dataLines.join('\n'),
      );
      _event = 'message';
      _dataLines.clear();
      return frame;
    }

    if (line.startsWith(':')) {
      return null;
    }

    final colonIndex = line.indexOf(':');
    String field;
    String value;
    if (colonIndex == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colonIndex);
      value = line.substring(colonIndex + 1);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
    }

    if (field == 'event') {
      _event = value.isEmpty ? 'message' : value;
    } else if (field == 'data') {
      _dataLines.add(value);
    }

    return null;
  }
}

class SseSubscriptionController<TData, TInitial>
    with WidgetsBindingObserver {
  SseSubscriptionController({
    required this.city,
    required this.endpoint,
    required this.parseData,
    required this.parseInitial,
    required this.onSnapshot,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new {
    WidgetsBinding.instance.addObserver(this);
  }

  final String city;
  final String endpoint;
  final TData Function(dynamic decoded) parseData;
  final TInitial Function(dynamic decoded) parseInitial;
  final void Function(SseStreamSnapshot<TData, TInitial> snapshot) onSnapshot;
  final http.Client Function() _clientFactory;

  static const int maxRetries = 5;
  static const Duration retryDelay = Duration(seconds: 2);
  static const Duration hideGraceDuration = Duration(seconds: 45);
  static const Duration staleAfterDuration = Duration(seconds: 10);

  http.Client? _activeClient;
  StreamSubscription<String>? _lineSubscription;
  Timer? _retryTimer;
  Timer? _hideTimer;
  DateTime? _hiddenAt;
  bool _isBackgrounded = false;
  bool _disposed = false;
  int _retryCount = 0;

  SseStreamSnapshot<TData, TInitial> _snapshot =
      const SseStreamSnapshot(isLoading: true);

  void start() {
    if (_disposed) return;
    _connect();
  }

  void _emit(SseStreamSnapshot<TData, TInitial> next) {
    if (_disposed) return;
    _snapshot = next;
    onSnapshot(next);
  }

  void _connect() {
    if (_disposed || _isBackgrounded || city.isEmpty || endpoint.isEmpty) {
      _closeCurrentStream();
      if (city.isEmpty || endpoint.isEmpty) {
        _emit(_snapshot.copyWith(isLoading: false));
      }
      return;
    }

    _retryTimer?.cancel();
    _closeCurrentStream();

    _emit(_snapshot.copyWith(isLoading: true, clearError: true));

    final uri = Uri.parse('${ApiConfig.baseUrl}/api6/$city/$endpoint');
    final client = _clientFactory();
    _activeClient = client;

    final request = http.Request('GET', uri);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';

    var terminalError = false;
    final parser = SseParser();

    client.send(request).then((response) {
      if (_disposed || _activeClient != client) {
        client.close();
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _handleStreamFailure(client, terminalError: false);
        return;
      }

      _retryCount = 0;
      _lineSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final frame = parser.feedLine(line);
              if (frame == null) return;

              if (frame.event == 'initial') {
                try {
                  final decoded = jsonDecode(frame.data);
                  final initial = parseInitial(decoded);
                  _emit(
                    _snapshot.copyWith(
                      initialData: initial,
                      isLoading: false,
                      clearError: true,
                    ),
                  );
                } catch (_) {
                  terminalError = true;
                  _emit(
                    _snapshot.copyWith(
                      isLoading: false,
                      error: 'PARSE_ERROR',
                    ),
                  );
                  _closeCurrentStream();
                }
              } else if (frame.event == 'message') {
                try {
                  final decoded = jsonDecode(frame.data);
                  final data = parseData(decoded);
                  _emit(
                    _snapshot.copyWith(
                      data: data,
                      isLoading: false,
                      clearError: true,
                    ),
                  );
                } catch (_) {
                  terminalError = true;
                  _emit(
                    _snapshot.copyWith(
                      isLoading: false,
                      error: 'PARSE_ERROR',
                    ),
                  );
                  _closeCurrentStream();
                }
              } else if (frame.event == 'errorCode') {
                terminalError = true;
                _emit(
                  _snapshot.copyWith(
                    isLoading: false,
                    error: _parseErrorData(frame.data),
                  ),
                );
                _closeCurrentStream();
              }
            },
            onError: (_) {
              _handleStreamFailure(client, terminalError: terminalError);
            },
            onDone: () {
              if (!terminalError && !_disposed && _activeClient == client) {
                _handleStreamFailure(client, terminalError: false);
              }
            },
            cancelOnError: true,
          );
    }).catchError((_) {
      _handleStreamFailure(client, terminalError: terminalError);
    });
  }

  String _parseErrorData(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is String ? decoded : jsonEncode(decoded);
    } catch (_) {
      return raw;
    }
  }

  void _handleStreamFailure(http.Client client, {required bool terminalError}) {
    if (_disposed || _activeClient != client) return;
    _closeCurrentStream();

    if (terminalError) return;

    if (_retryCount < maxRetries) {
      _retryCount++;
    } else {
      _emit(_snapshot.copyWith(isLoading: false, error: 'NETWORK_ERROR'));
      return;
    }

    if (!_isBackgrounded && _retryCount <= maxRetries) {
      _retryTimer?.cancel();
      _retryTimer = Timer(retryDelay, () {
        if (!_disposed && !_isBackgrounded && _activeClient == null) {
          _connect();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isBackgrounded = true;
      _hiddenAt = DateTime.now();
      _hideTimer?.cancel();
      _hideTimer = Timer(hideGraceDuration, () {
        if (_isBackgrounded) {
          _closeCurrentStream();
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      _isBackgrounded = false;
      _hideTimer?.cancel();
      _hideTimer = null;

      final hiddenDuration = _hiddenAt == null
          ? Duration.zero
          : DateTime.now().difference(_hiddenAt!);

      if (_activeClient == null || hiddenDuration > staleAfterDuration) {
        _retryCount = 0;
        _connect();
      }
    }
  }

  void _closeCurrentStream() {
    _lineSubscription?.cancel();
    _lineSubscription = null;
    _activeClient?.close();
    _activeClient = null;
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _hideTimer?.cancel();
    _closeCurrentStream();
  }
}
