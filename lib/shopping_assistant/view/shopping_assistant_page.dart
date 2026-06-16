import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:genui_shopping_assistant/shopping_assistant/ai/claude_ai_transport.dart';
import 'package:genui_shopping_assistant/shopping_assistant/ai/firebase_ai_transport.dart';
import 'package:genui_shopping_assistant/shopping_assistant/catalog/shopping_catalog.dart';
import 'package:genui_shopping_assistant/shopping_assistant/view/widgets/chat_input_bar.dart';
import 'package:genui_shopping_assistant/shopping_assistant/view/widgets/message_bubble.dart';
import 'package:genui_shopping_assistant/shopping_assistant/view/widgets/typing_indicator.dart';
import 'package:logging/logging.dart';

final _log = Logger('ShoppingAssistantPage');

sealed class _MessageEntry {
  const _MessageEntry();
}

final class _UserTextEntry extends _MessageEntry {
  const _UserTextEntry(this.text);
  final String text;
}

final class _AssistantTextEntry extends _MessageEntry {
  _AssistantTextEntry(this.text);
  String text;
}

final class _SurfaceEntry extends _MessageEntry {
  const _SurfaceEntry(this.surfaceId);
  final String surfaceId;
}

final class _ErrorEntry extends _MessageEntry {
  const _ErrorEntry(this.message);
  final String message;
}

class ShoppingAssistantPage extends StatefulWidget {
  const ShoppingAssistantPage({super.key});

  @override
  State<ShoppingAssistantPage> createState() => _ShoppingAssistantPageState();
}

class _ShoppingAssistantPageState extends State<ShoppingAssistantPage> {
  late ContentGenerator _contentGenerator;
  late A2uiMessageProcessor _messageProcessor;
  late GenUiConversation _conversation;

  final List<_MessageEntry> _messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initConversation();
  }

  void _initConversation() {
    _contentGenerator = kIsWeb
        ? buildFirebaseAiContentGenerator()
        : buildClaudeContentGenerator();
    _messageProcessor = A2uiMessageProcessor(catalogs: [shoppingCatalog]);
    _conversation = GenUiConversation(
      contentGenerator: _contentGenerator,
      a2uiMessageProcessor: _messageProcessor,
      onSurfaceAdded: (SurfaceAdded event) {
        if (mounted) {
          setState(() => _messages.add(_SurfaceEntry(event.surfaceId)));
          _scheduleScrollToBottom();
        }
      },
      onTextResponse: (String text) {
        if (mounted) {
          setState(() => _messages.add(_AssistantTextEntry(text)));
          _scheduleScrollToBottom();
        }
      },
      onError: (ContentGeneratorError error) {
        _log.warning('Conversation error: $error');
        if (mounted) {
          setState(() {
            _messages.add(const _ErrorEntry(
              'Something went wrong. Please check your connection and try again.',
            ));
          });
          _scheduleScrollToBottom();
        }
      },
    );
  }

  @override
  void dispose() {
    _conversation.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    setState(() => _messages.add(_UserTextEntry(text)));
    _scheduleScrollToBottom();

    try {
      await _conversation.sendRequest(UserMessage.text(text));
    } catch (e, st) {
      _log.severe('Failed to send message', e, st);
      if (mounted) {
        setState(() {
          _messages.add(const _ErrorEntry(
            'Failed to reach the assistant. Please try again.',
          ));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shopping_bag_outlined),
            SizedBox(width: 8),
            Text('Shopping Assistant'),
          ],
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildEntry(_messages[index]),
                  ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _conversation.isProcessing,
            builder: (context, isProcessing, _) {
              if (isProcessing) {
                return const TypingIndicator();
              }
              return const SizedBox.shrink();
            },
          ),
          const Divider(height: 1),
          ValueListenableBuilder<bool>(
            valueListenable: _conversation.isProcessing,
            builder: (context, isProcessing, _) {
              return ChatInputBar(
                isWaiting: isProcessing,
                onSend: _sendMessage,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(_MessageEntry entry) {
    return switch (entry) {
      _UserTextEntry(:final text) => MessageBubble(
          text: text,
          role: BubbleRole.user,
        ),
      _AssistantTextEntry(:final text) => MessageBubble(
          text: text,
          role: BubbleRole.assistant,
        ),
      _ErrorEntry(:final message) => MessageBubble(
          text: message,
          role: BubbleRole.error,
        ),
      _SurfaceEntry(:final surfaceId) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: GenUiSurface(
            // Stable key ensures Flutter reuses the element across rebuilds.
            key: ValueKey(surfaceId),
            host: _conversation.host,
            surfaceId: surfaceId,
            // Fallback while the surface is loading or on parse error.
            defaultBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
    };
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 72,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Your Shopping Assistant',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me to find products, compare options, '
              'or filter by price.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                  label: 'Show me running shoes',
                  onTap: () => _sendMessage('Show me running shoes'),
                ),
                _SuggestionChip(
                  label: 'Best headphones under \$100',
                  onTap: () => _sendMessage('Best headphones under \$100'),
                ),
                _SuggestionChip(
                  label: 'Lightweight backpacks',
                  onTap: () => _sendMessage('Lightweight backpacks'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.chat_bubble_outline, size: 16),
    );
  }
}
