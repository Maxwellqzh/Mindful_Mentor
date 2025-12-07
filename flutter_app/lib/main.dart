import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MindfulMentorApp());
}

class MindfulMentorApp extends StatelessWidget {
  const MindfulMentorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mindful Mentor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8B4B8), // 柔和的粉色调
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'IBM Plex Sans SC',
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
      ),
      home: const MentorHomePage(),
    );
  }
}

class MentorHomePage extends StatefulWidget {
  const MentorHomePage({super.key});

  @override
  State<MentorHomePage> createState() => _MentorHomePageState();
}

class _MentorHomePageState extends State<MentorHomePage> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _recordedFilePath;
  // Chat message model: distinguishes bot replies vs user info
  final List<ChatMessage> _messages = <ChatMessage>[
    ChatMessage(text: '欢迎使用 Mindful Mentor，与 AI 心理助手畅聊吧。', isBot: true),
  ];
  // Terminal-like logs for status and prompts (left pane)
  final List<String> _logs = <String>[];
  StreamSubscription<RecordState>? _recordSub;

  @override
  void initState() {
    super.initState();
    _recordSub = _recorder.onStateChanged().listen((RecordState state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = state == RecordState.record;
      });
    });
  }

  @override
  void dispose() {
    _recordSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // Encode a string as UTF-16LE and Base64-encode it for PowerShell -EncodedCommand
  String _toBase64Utf16Le(String s) {
    final List<int> codeUnits = s.codeUnits;
    final Uint8List bytes = Uint8List(codeUnits.length * 2);
    final ByteData bd = bytes.buffer.asByteData();
    for (int i = 0; i < codeUnits.length; i++) {
      bd.setUint16(i * 2, codeUnits[i], Endian.little);
    }
    return base64Encode(bytes);
  }

  // Build a PowerShell command that invokes the given python executable with
  // script and args. Each argument is single-quoted and internal single quotes
  // are doubled (PowerShell single-quote escaping). The returned string is
  // the Base64 UTF-16LE encoded command suitable for -EncodedCommand.
  String _buildPsEncodedCommand(
      String pythonExe, String scriptPath, List<String> args) {
    String escape(String s) => s.replaceAll("'", "''");
    final List<String> parts = <String>[];
    parts.add("& '${escape(pythonExe)}' '${escape(scriptPath)}'");
    for (final String a in args) {
      parts.add("'${escape(a)}'");
    }
    final String cmd = parts.join(' ');
    return _toBase64Utf16Le(cmd);
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (context.mounted) {
          _showSnackBar('无法获取麦克风权限');
        }
        return;
      }

      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory saveDir = Directory('${appDir.path}\\mindful_mentor');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      final String filePath =
          '${saveDir.path}\\mindful_mentor_${DateTime.now().millisecondsSinceEpoch}.wav';

      const RecordConfig config = RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      );

      await _recorder.start(
        config,
        path: filePath,
      );

      setState(() {
        _recordedFilePath = filePath;
        _logs.add('开始录音...');
      });
    } catch (error) {
      _showSnackBar('录音启动失败: $error');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final String? path = await _recorder.stop();
      if (path == null) {
        return;
      }

      setState(() {
        _recordedFilePath = path;
        _logs.add('录音完成，文件已保存。');
      });

      await _simulateModelWorkflow(path);
    } catch (error) {
      _showSnackBar('录音停止失败: $error');
    }
  }

  Future<void> _simulateModelWorkflow(String filePath) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isProcessing = true;
      // _messages.add('正在准备将音频发送给 AI 模型...');
    });

    try {
      // 模拟处理流程：第 1 周无需真正调用后端。
      // await Future<void>.delayed(const Duration(seconds: 2));

      // setState(() {
      //   _messages.add('音频文件路径：$filePath');
      //   _messages.add('AI 模型回复将在后续迭代中接入。');
      // });
      const String wav2txtScriptPath = '..\\core\\wav2txt.py';
      const String wav2emoScriptPath = '..\\core\\wav2emotion.py';
      const String txt2reviewScriptPath = '..\\core\\txt2review.py';
      const String pythonExe = '..\\mm_env\\python.exe';
      // Build PowerShell command using encoded command for proper argument handling
      final String wav2txtEncoded = _buildPsEncodedCommand(
        pythonExe,
        wav2txtScriptPath,
        [filePath, '--language', 'zh'],
      );
      final ProcessResult txtResult = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', wav2txtEncoded],
        runInShell: false,
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
      if (txtResult.exitCode == 0) {
        final String txtOutput = txtResult.stdout as String;
        setState(() {
          _logs.add('音频转文本完成.\n$txtOutput');
        });
        _showSnackBar('音频转文本完成!', isError: false);
        final String txtFilePath = filePath.replaceAll('.wav', '.txt');
        final File txtFile = File(txtFilePath);
        if (await txtFile.exists()) {
          final String transcribedText = await txtFile.readAsString();
          setState(() {
            // add recognized speech as user info (right-side)
            _messages.add(ChatMessage(text: transcribedText, isBot: false));
          });
        } else {
          setState(() {
            _logs.add('转录文本文件不存在! 后端输出: $txtOutput');
          });
          _showSnackBar('转录文本文件不存在! 请检查文件路径。');
        }
      } else {
        final String errorOutput = txtResult.stderr as String;
        final String stdOutput = txtResult.stdout as String;
        setState(() {
          _logs.add('音频转文本失败! 后端输出:\n$errorOutput\n$stdOutput');
        });
        _showSnackBar('音频转文本失败!');
        // 直接返回，不进行后续处理
        return;
      }
      // Build PowerShell command using encoded command for proper argument handling
      final String wav2emoEncoded = _buildPsEncodedCommand(
        pythonExe,
        wav2emoScriptPath,
        [filePath],
      );
      final ProcessResult emoResult = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', wav2emoEncoded],
        runInShell: false,
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
      String emoRecResult = '';
      if (emoResult.exitCode == 0) {
        final String emoOutput = emoResult.stdout as String;
        setState(() {
          _logs.add('情绪识别完成.\n$emoOutput');
        });
        _showSnackBar('情绪识别完成!', isError: false);
        // 抓取控制台输出的最后一行, 格式为'识别到的情绪: xxxxx'
        final List<String> lines = emoOutput.split('\n');
        for (final String line in lines) {
          if (line.startsWith('识别到的情绪:')) {
            emoRecResult = line;
          }
        }
        if (emoRecResult.isNotEmpty) {
          setState(() {
            // treat emotion as user info as well
            _messages.add(ChatMessage(text: emoRecResult, isBot: false));
          });
        } else {
          setState(() {
            _logs.add('情绪识别结果为空! 后端输出:\n$emoOutput');
          });
          _showSnackBar('情绪识别结果为空! 请检查模型输出。');
        }
      } else {
        final String errorOutput = emoResult.stderr as String;
        final String stdOutput = emoResult.stdout as String;
        setState(() {
          _logs.add('情绪识别失败! 后端输出:\n$errorOutput\n$stdOutput');
        });
        _showSnackBar('情绪识别失败!');
        // 直接返回，不进行后续处理
        return;
      }
      final String txtFilePath = filePath.replaceAll('.wav', '.txt');

      // 生成上一次会话上下文（寻找最近的完整三元组：
      // <User Message>\n<User Emotion>\n<Chatbot Reply>）
      // 如果没有找到这样的三元组，则传 'None'
      String convoParam = 'None';
      try {
        int foundBotIdx = -1;
        String u1 = '';
        String u2 = '';
        String bot = '';
        for (int i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].isBot) {
            // 检查前两条是否为用户消息
            if (i - 2 >= 0 &&
                !_messages[i - 1].isBot &&
                !_messages[i - 2].isBot) {
              foundBotIdx = i;
              u1 = _messages[i - 2].text;
              u2 = _messages[i - 1].text;
              bot = _messages[i].text;
              break;
            }
          }
        }
        if (foundBotIdx != -1) {
          // 转义单引号以便在 PowerShell 单引号字符串中安全传递
          final String u1Esc = u1.replaceAll("'", "''");
          final String u2Esc = u2.replaceAll("'", "''");
          final String botEsc = bot.replaceAll("'", "''");
          convoParam = '我说了: $u1Esc.\n$u2Esc.\n你回复: $botEsc';
        }
      } catch (e) {
        convoParam = 'None';
      }
      // Build a safely-quoted PowerShell command so parameters (including
      // paths, spaces, single quotes and newlines) are passed correctly.
      final String reviewEncoded = _buildPsEncodedCommand(
        pythonExe,
        txt2reviewScriptPath,
        [txtFilePath, '-e', emoRecResult, '-p', convoParam],
      );
      final ProcessResult reviewResult = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', reviewEncoded],
        runInShell: false,
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
      if (reviewResult.exitCode == 0) {
        final String reviewOutput = reviewResult.stdout as String;
        // 尝试从 reviewOutput 中提取真实的 review 内容（位于两个 ====== 分隔符之间）。
        String extractedReview = reviewOutput;
        try {
          final List<String> lines = reviewOutput.split(RegExp(r'\r?\n'));
          final String sepLine = List.filled(60, '=').join();
          final List<int> sepIndices = <int>[];
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].trim() == sepLine) sepIndices.add(i);
          }
          if (sepIndices.length >= 3) {
            // review 在第二个分隔符之后、第三个分隔符之前
            final int start = sepIndices[1] + 1;
            final int end = sepIndices[2];
            if (start < end) {
              extractedReview = lines.sublist(start, end).join('\n').trim();
            }
          } else {
            // 兜底策略：根据标题关键字查找并尝试提取
            final int titleIndex =
                lines.indexWhere((l) => l.contains('知心朋友的回应预览'));
            if (titleIndex != -1) {
              int nextSep = -1;
              for (int i = titleIndex + 1; i < lines.length; i++) {
                if (lines[i].trim() == sepLine) {
                  nextSep = i;
                  break;
                }
              }
              if (nextSep != -1) {
                int thirdSep = -1;
                for (int i = nextSep + 1; i < lines.length; i++) {
                  if (lines[i].trim() == sepLine) {
                    thirdSep = i;
                    break;
                  }
                }
                if (thirdSep != -1 && nextSep + 1 < thirdSep) {
                  extractedReview =
                      lines.sublist(nextSep + 1, thirdSep).join('\n').trim();
                } else if (nextSep + 1 < lines.length) {
                  extractedReview =
                      lines.sublist(nextSep + 1).join('\n').trim();
                }
              }
            }
          }
        } catch (e) {
          // 如果解析失败，保留原始输出
          extractedReview = reviewOutput;
        }

        setState(() {
          _logs.add('AI 心理助手已回复: $reviewOutput');
          // add bot reply to chat messages (right-side)
          _messages.add(ChatMessage(text: extractedReview, isBot: true));
        });
        _showSnackBar('AI 心理助手回复已生成!', isError: false);
      } else {
        final String errorOutput = reviewResult.stderr as String;
        final String stdOutput = reviewResult.stdout as String;
        setState(() {
          _logs.add('AI 心理助手回复生成失败! 后端输出： $errorOutput $stdOutput');
        });
        _showSnackBar('AI 心理助手回复生成失败!');
      }
    } catch (error) {
      setState(() {
        _logs.add('音频处理失败: $error');
      });
      _showSnackBar('音频处理失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) {
      return;
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const Color morandiGreen = Color(0xFF8FAF9A);
    final Color backgroundColor =
        isError ? scheme.errorContainer : morandiGreen;
    final Color contentColor = isError ? scheme.onErrorContainer : Colors.white;
    final IconData leadingIcon =
        isError ? Icons.info_outline : Icons.check_circle;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              leadingIcon,
              color: contentColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: contentColor,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0F0), // 柔和的米色背景
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite,
              color: scheme.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'Mindful Mentor',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.3),
                scheme.surfaceContainerHighest.withValues(alpha: 0.2),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surfaceContainerHighest.withValues(alpha: 0.1),
                const Color(0xFFF5F0F0),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                RecordingStatusCard(
                  isRecording: _isRecording,
                  isProcessing: _isProcessing,
                  recordedFilePath: _recordedFilePath,
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: TerminalPanel(
                          logs: _logs,
                          isRecording: _isRecording,
                          isProcessing: _isProcessing,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: MessageList(messages: _messages),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                RecordControlButton(
                  isRecording: _isRecording,
                  isProcessing: _isProcessing,
                  onPressed: _toggleRecording,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RecordingStatusCard extends StatelessWidget {
  const RecordingStatusCard({
    required this.isRecording,
    required this.isProcessing,
    required this.recordedFilePath,
    super.key,
  });

  final bool isRecording;
  final bool isProcessing;
  final String? recordedFilePath;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String statusTitle = isRecording ? '正在录音...' : '准备就绪';
    final String statusSubtitle = isProcessing
        ? '正在处理音频，请稍候'
        : recordedFilePath != null
            ? '已保存录音文件'
            : '点击下方按钮开始录音';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.4),
            scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isRecording
                    ? scheme.errorContainer.withValues(alpha: 0.3)
                    : scheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRecording ? Icons.mic : Icons.mic_none,
                color: isRecording ? scheme.error : scheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    statusTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (isProcessing)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  ChatMessage({required this.text, required this.isBot});
  final String text;
  final bool isBot;
}

class TerminalPanel extends StatelessWidget {
  const TerminalPanel(
      {required this.logs,
      required this.isRecording,
      required this.isProcessing,
      super.key});

  final List<String> logs;
  final bool isRecording;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Use app theme colors instead of pure black for a warmer, cohesive look
        color: scheme.primaryContainer.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isRecording ? Icons.mic : Icons.info_outline,
                color: isRecording ? scheme.error : scheme.onPrimaryContainer,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isRecording
                      ? '状态: 正在录音'
                      : (isProcessing ? '状态: 正在处理音频' : '状态: 准备就绪'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontFamily: 'IBM Plex Sans SC',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: const Color(0xFFF5F0F0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          '终端日志为空',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.8),
                            fontFamily: 'IBM Plex Sans SC',
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: logs.length,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              logs[index],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontFamily: 'IBM Plex Sans SC',
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageList extends StatefulWidget {
  const MessageList({required this.messages, super.key});

  final List<ChatMessage> messages;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll to bottom after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if new messages were added
    if (widget.messages.length > oldWidget.messages.length) {
      // Scroll to bottom after the list is updated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: widget.messages.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 48,
                      color: scheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '开始对话吧',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              )
            : Scrollbar(
                thumbVisibility: true,
                radius: const Radius.circular(10),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  itemCount: widget.messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ChatMessage msg = widget.messages[index];
                    final bool isBot = msg.isBot;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == widget.messages.length - 1 ? 0 : 16,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: isBot
                            ? [
                                // Bot: avatar left, bubble right
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer
                                        .withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.smart_toy,
                                    size: 18,
                                    color: scheme.secondary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.secondaryContainer
                                          .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Text(
                                      msg.text,
                                      style:
                                          theme.textTheme.bodyLarge?.copyWith(
                                        color: scheme.onSurface,
                                        height: 1.5,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ]
                            : [
                                // User: bubble left-aligned to right side, avatar on right
                                Expanded(
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer
                                            .withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        msg.text,
                                        textAlign: TextAlign.right,
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          color: scheme.onSurface,
                                          height: 1.5,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer
                                        .withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    size: 18,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class RecordControlButton extends StatelessWidget {
  const RecordControlButton({
    required this.isRecording,
    required this.isProcessing,
    required this.onPressed,
    super.key,
  });

  final bool isRecording;
  final bool isProcessing;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: (isRecording ? scheme.error : scheme.primary)
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isProcessing ? null : () => onPressed(),
        style: ElevatedButton.styleFrom(
          backgroundColor: isRecording ? scheme.error : scheme.primary,
          foregroundColor: isRecording ? scheme.onError : scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(36),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRecording)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: scheme.onError,
                  shape: BoxShape.circle,
                ),
              )
            else
              const Icon(
                Icons.mic,
                size: 24,
              ),
            const SizedBox(width: 12),
            Text(
              isRecording ? '停止录音' : '开始录音',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
