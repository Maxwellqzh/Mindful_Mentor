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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
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
  final List<String> _messages = <String>[
    '欢迎使用 Mindful Mentor，与 AI 心理助手畅聊吧。'
  ];
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

      final RecordConfig config = const RecordConfig(
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Mindful Mentor'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RecordingStatusCard(
                isRecording: _isRecording,
                isProcessing: _isProcessing,
                recordedFilePath: _recordedFilePath,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: MessageList(messages: _messages),
              ),
              const SizedBox(height: 16),
              RecordControlButton(
                isRecording: _isRecording,
                isProcessing: _isProcessing,
                onPressed: _toggleRecording,
              ),
            ],
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
    final String statusTitle = isRecording ? '录制中...' : '准备开始录音';
    final String statusSubtitle = isProcessing
        ? '正在处理音频，请稍候'
        : recordedFilePath != null
            ? '最近的录音文件: ${File(recordedFilePath!).uri.pathSegments.last}'
            : '尚未生成录音文件';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              statusTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(statusSubtitle),
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
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Scrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (BuildContext context, int index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                messages[index],
                style: theme.textTheme.bodyLarge,
              ),
            );
          },
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
    final Color backgroundColor =
        isRecording ? scheme.error : scheme.primary;
    final Color foregroundColor =
        isRecording ? scheme.onError : scheme.onPrimary;

    return SizedBox(
      height: 64,
      child: ElevatedButton.icon(
        icon: Icon(isRecording ? Icons.stop : Icons.mic),
        label: Text(isRecording ? '停止录音' : '开始录音'),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: isProcessing ? null : () => onPressed(),
      ),
    );
  }
}


