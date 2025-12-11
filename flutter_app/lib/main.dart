import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http; 

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
  
  // 聊天记录列表
  final List<ChatMessage> _messages = <ChatMessage>[
    ChatMessage(text: '欢迎使用 Mindful Mentor，与 AI 心理助手畅聊吧。', isBot: true),
  ];
  
  // 终端日志列表
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
      final Directory saveDir = Directory('${appDir.path}/mindful_mentor'); // Android 使用正斜杠 /
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      // 使用 .m4a 格式，在 Android 上兼容性更好且体积小（librosa 也能读）
      // 如果你的后端一定要 .wav，也可以改回 .wav
      // 统一使用 / 作为路径分隔符（Windows 和 Android 都支持）
      final String filePath = '${saveDir.path}/audio_record.wav';

      const RecordConfig config = RecordConfig(
        encoder: AudioEncoder.wav, // WAV 格式在 Windows/Android 兼容性最好
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
        _logs.add('录音完成');
      });

      // 录音结束后，直接上传处理
      await _processAudioWithServer(path);
      
    } catch (error) {
      _showSnackBar('录音停止失败: $error');
    }
  }

  // ================= 核心修改：网络请求部分 =================
  Future<void> _processAudioWithServer(String filePath) async {
    if (!mounted) return;
    
    setState(() {
      _isProcessing = true;
      _logs.add('正在上传音频到服务器...');
    });
    

   try {
      String serverIp;
      
      // 智能判断当前运行的平台
      if (Platform.isAndroid) {
        // --- Android 模式 ---
        // 如果你是用【模拟器】，请使用 '10.0.2.2'
        // 如果你是用【真机】，请使用你的电脑局域网 IP，例如 '192.168.1.5'
        serverIp = '192.168.174.210'; 
      } else {
        // --- Windows 模式 ---
        // 电脑自己访问自己，直接用 localhost
        serverIp = '127.0.0.1';
      }

      // 动态构建 URL
      var uri = Uri.parse('http://$serverIp:8000/chat');

      // 构建 Multipart 请求
      var request = http.MultipartRequest('POST', uri);
      
      // 添加文件 (字段名 'file' 必须和 server.py 中的参数名一致)
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      // 设置超时时间 (AI 处理可能比较慢，设长一点)
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // 解析 JSON 结果
        var jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));

        if (jsonResponse.containsKey('error')) {
             throw Exception(jsonResponse['error']);
        }

        String userText = jsonResponse['text'] ?? '';
        String emotion = jsonResponse['emotion'] ?? 'unknown';
        String aiResponse = jsonResponse['response'] ?? '';

        setState(() {
          _logs.add('服务器处理完成。');
          _logs.add('识别文本: $userText');
          _logs.add('识别情绪: $emotion');
          
          // 添加用户消息
          _messages.add(ChatMessage(text: userText, isBot: false));
          
          // 添加 AI 回复
          _messages.add(ChatMessage(text: aiResponse, isBot: true));
        });
        
        _showSnackBar('AI 回复已生成!', isError: false);
        
      } else {
        throw Exception('服务器错误 (${response.statusCode}): ${response.body}');
      }

    } catch (error) {
      String errorMsg = error.toString();
      if (errorMsg.contains('SocketException')) {
         errorMsg = '连接失败。请检查：\n1. 手机和电脑在同一WiFi\n2. 代码中的IP是否正确\n3. 电脑防火墙是否关闭';
      } else if (errorMsg.contains('Timeout')) {
         errorMsg = '请求超时，可能是模型处理太慢。';
      }
      
      setState(() {
        _logs.add('错误: $error');
      });
      _showSnackBar('请求失败', isError: true);
      // 可以在界面上弹窗显示详细错误建议，方便调试
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("连接错误"),
            content: Text(errorMsg),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好的"))],
          ),
        );
      }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > oldWidget.messages.length) {
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