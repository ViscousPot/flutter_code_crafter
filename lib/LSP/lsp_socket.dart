part of 'lsp.dart';

/// A configuration class for Language Server Protocol (LSP) using WebSocket communication.
///
/// Documenation available [here](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/LSPClient.md).
///
///Example:
/// create a [LspSocketConfig] object and pass it to the [CodeCrafter] widget.
///
///```dart
///final lspConfig = LspSocketConfig(
///    filePath: '/home/athul/Projects/lsp/example.py',
///    workspacePath: "/home/athul/Projects/lsp",
///    languageId: "python",
///    serverUrl: "ws://localhost:5656"
///),
///```
///Then pass the `lspConfig` instance to the `CodeCrafter` widget:
///
///```dart
///CodeCrafter(
///    controller: controller,
///    theme: anOldHopeTheme,
///    lspConfig: lspConfig, // Pass the LSP config here
///),
///```
class LspSocketConfig extends LspConfig {
  /// The URL of the LSP server to connect to via WebSocket.
  final String serverUrl;
  final WebSocketChannel _channel;

  LspSocketConfig({
    required super.filePath,
    required super.workspacePath,
    required super.languageId,
    required this.serverUrl,
  }) : _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

  /// This method is used to initialize the LSP server. and it's used internally by the [CodeCrafter] widget.
  /// Calling it directly is not recommended and may crash the LSP server if called multiple times.
  Future<void> connect() async {
    _channel.stream.listen((data) {
      try {
        final json = jsonDecode(data as String);
        _responseController.add(json);
      } catch (e) {
        throw FormatException('Invalid JSON response: $data', e);
      }
    });
  }

  @override
  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final id = _nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    _channel.sink.add(jsonEncode(request));

    return await _responseController.stream.firstWhere(
      (response) => response['id'] == id,
      orElse: () => throw TimeoutException('No response for request $id'),
    );
  }

  @override
  Future<void> _sendNotification({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    _channel.sink.add(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
  }

  @override
  void dispose() {
    _channel.sink.close();
    _responseController.close();
  }
}
