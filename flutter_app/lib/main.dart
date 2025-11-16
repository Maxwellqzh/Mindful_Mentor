import 'dart:async';
import 'dart:io';

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
        fontFamily: 'Roboto',
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
  final List<String> _messages = <String>['欢迎使用 Mindful Mentor，与 AI 心理助手畅聊吧。'];
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
      final String filePath =
          '${appDir.path}/mindful_mentor_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const RecordConfig config = RecordConfig(
        encoder: AudioEncoder.aacLc,
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
        _messages.add('开始录音...');
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
        _messages.add('录音完成，文件已保存。');
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
      _messages.add('正在准备将音频发送给 AI 模型...');
    });

    try {
      // 模拟处理流程：第 1 周无需真正调用后端。
      await Future<void>.delayed(const Duration(seconds: 2));

      setState(() {
        _messages.add('音频文件路径：$filePath');
        _messages.add('AI 模型回复将在后续迭代中接入。');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: scheme.errorContainer,
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
                  child: MessageList(messages: _messages),
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

class MessageList extends StatelessWidget {
  const MessageList({required this.messages, super.key});

  final List<String> messages;

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
        child: messages.isEmpty
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final bool isFirstMessage = index == 0;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == messages.length - 1 ? 0 : 16,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isFirstMessage)
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer
                                    .withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.smart_toy,
                                size: 18,
                                color: scheme.primary,
                              ),
                            )
                          else
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer
                                    .withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.waving_hand,
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
                                color: isFirstMessage
                                    ? scheme.secondaryContainer
                                        .withValues(alpha: 0.4)
                                    : scheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                messages[index],
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurface,
                                  height: 1.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
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
