part of 'lsp_io.dart';

/// This class provides a configuration for Language Server Protocol (LSP) using standard input/output communication.
/// Little bit complex compared to [LspSocketConfig].
///
/// /// Documenation available [here](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/LSPClient.md).
///
/// Example:
///
/// Create an async method to initialize the LSP configuration.
///```dart
///Future<LspConfig?> _initLsp() async {
///    try {
///      final config = await LspStdioConfig.start(
///        executable: '/home/athul/.nvm/versions/node/v20.19.2/bin/pyright-langserver',
///        args: ['--stdio']
///        filePath: '/home/athul/Projects/lsp/example.py',
///        workspacePath: '/home/athul/Projects/lsp',
///        languageId: 'python',
///      );
///
///      return config;
///    } catch (e) {
///      debugPrint('LSP Initialization failed: $e');
///      return null;
///    }
///  }
///  ```
///  Then use a `FutureBuilder` to initialize the LSP configuration and pass it to the `CodeCrafter` widget:
///```dart
///  @override
///  Widget build(BuildContext context) {
///    return MaterialApp(
///      home: Scaffold(
///        body: SafeArea(
///          child: FutureBuilder(
///            future: _initLsp(), // Call the async method to get the LSP config
///            builder: (context, snapshot) {
///              if(snapshot.connectionState == ConnectionState.waiting) {
///                return Center(child: CircularProgressIndicator());
///              }
///              return CodeCrafter(
///                wrapLines: true,
///                editorTheme: anOldHopeTheme,
///                controller: controller,
///                filePath: '/home/athul/Projects/lsp/example.py',
///                textStyle: TextStyle(fontSize: 15, fontFamily: 'monospace'),
///                lspConfig: snapshot.data, // Pass the LSP config here
///              );
///            }
///          ),
///        )
///      ),
///    );
///  }
class LspStdioConfig extends LspConfig {
  /// location of the LSP executable, such as `pyright-langserver`, `rust-analyzer`, etc.
  ///
  /// To get the `executable` path, you can use the `which` command in the terminal. For example, to get the path of the `pyright-langserver`, you can use the following command:
  ///
  ///```bash
  ///which pyright-langserver
  ///```
  final String executable;

  /// Optional arguments to pass to the LSP executable.
  final List<String>? args;
  late Process _process;
  final _buffer = <int>[];

  LspStdioConfig._({
    required this.executable,
    required super.filePath,
    required super.workspacePath,
    required super.languageId,
    this.args = const [],
  });

  static Future<LspStdioConfig> start({
    required String executable,
    required String filePath,
    required String workspacePath,
    required String languageId,
    List<String>? args,
  }) async {
    final config = LspStdioConfig._(
      executable: executable,
      filePath: filePath,
      languageId: languageId,
      workspacePath: workspacePath,
      args: args,
    );
    await config._startProcess();
    return config;
  }

  Future<void> _startProcess() async {
    _process = await Process.start(executable, args ?? []);
    _process.stdout.listen(_handleStdoutData);
    _process.stderr.listen(
      (data) => throw Exception('LSP process error: ${utf8.decode(data)}'),
    );
  }

  void _handleStdoutData(List<int> data) {
    _buffer.addAll(data);
    while (_buffer.isNotEmpty) {
      final headerEnd = _findHeaderEnd();
      if (headerEnd == -1) return;
      final header = utf8.decode(_buffer.sublist(0, headerEnd));
      final contentLength = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(header)?.group(1) ?? '0',
      );
      if (_buffer.length < headerEnd + 4 + contentLength) return;
      final messageStart = headerEnd + 4;
      final messageEnd = messageStart + contentLength;
      final messageBytes = _buffer.sublist(messageStart, messageEnd);
      _buffer.removeRange(0, messageEnd);
      try {
        final json = jsonDecode(utf8.decode(messageBytes));
        _responseController.add(json);
      } catch (e) {
        throw FormatException(
          'Invalid JSON message $e',
          utf8.decode(messageBytes),
        );
      }
    }
  }

  int _findHeaderEnd() {
    final endSequence = [13, 10, 13, 10];
    for (var i = 0; i <= _buffer.length - endSequence.length; i++) {
      if (List.generate(
        endSequence.length,
        (j) => _buffer[i + j],
      ).every((byte) => endSequence.contains(byte))) {
        return i;
      }
    }
    return -1;
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
    await _sendLspMessage(request);

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
    await _sendLspMessage({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  Future<void> _sendLspMessage(Map<String, dynamic> message) async {
    final body = utf8.encode(jsonEncode(message));
    final header = 'Content-Length: ${body.length}\r\n\r\n';
    _process.stdin.add(utf8.encode(header));
    _process.stdin.add(body);
    await _process.stdin.flush();
  }

  @override
  void dispose() {
    _process.kill();
    _responseController.close();
  }
}
