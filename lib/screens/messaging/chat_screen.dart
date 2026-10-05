import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../feed/video_player_screen.dart';
import '../../services/notification_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUsername;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUsername,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  late final RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    supabase.removeChannel(_channel);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    final result = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: true);

    if (mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(result);
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _subscribeToMessages() {
    _channel = supabase
        .channel('chat:${widget.conversationId}')
        .onBroadcast(
      event: 'new_message',
      callback: (payload) {
        if (!mounted) return;
        final user = supabase.auth.currentUser;
        final senderId = payload['sender_id'] as String?;
        if (senderId != null && senderId != user?.id) {
          setState(() {
            _messages.add(Map<String, dynamic>.from(payload));
          });
          _scrollToBottom();
        }
      },
    )
        .onBroadcast(
      event: 'delete_message',
      callback: (payload) {
        if (!mounted) return;
        final messageId = payload['message_id'] as String?;
        if (messageId != null) {
          setState(() {
            final idx = _messages
                .indexWhere((m) => m['id'].toString() == messageId);
            if (idx != -1) {
              _messages[idx] = {
                ..._messages[idx],
                'deleted': true,
              };
            }
          });
        }
      },
    )
        .subscribe();
  }

  void _scrollToBottom() {
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

  Future<void> _sendMessage({String? mediaUrl, String? mediaType}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && mediaUrl == null) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _messageController.clear();
    final now = DateTime.now().toIso8601String();

    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'conversation_id': widget.conversationId,
      'sender_id': user.id,
      'content': text,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'created_at': now,
      'deleted': false,
    };

    setState(() => _messages.add(tempMessage));
    _scrollToBottom();

    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'content': text,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
      });
      await NotificationService.send(
        type: 'message',
        actorId: user.id,
        targetUserId: widget.otherUserId,
      );

      await _channel.sendBroadcastMessage(
        event: 'new_message',
        payload: {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'conversation_id': widget.conversationId,
          'sender_id': user.id,
          'content': text,
          'media_url': mediaUrl,
          'media_type': mediaType,
          'created_at': now,
          'deleted': false,
        },
      );

      await supabase.from('conversations').update({
        'last_message': mediaUrl != null
            ? (mediaType == 'video' ? '🎥 Video' : '📷 Image')
            : text,
        'last_message_at': now,
      }).eq('id', widget.conversationId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendMedia(String type) async {
    final picker = ImagePicker();
    XFile? picked;

    if (type == 'image') {
      picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
    } else {
      picked = await picker.pickVideo(source: ImageSource.gallery);
    }

    if (picked == null) return;

    setState(() => _isSending = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final file = File(picked.path);
      final ext = picked.path.split('.').last.toLowerCase();
      final fileName =
          '${type}_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('chat-media').upload(fileName, file);
      final mediaUrl =
      supabase.storage.from('chat-media').getPublicUrl(fileName);

      await _sendMessage(mediaUrl: mediaUrl, mediaType: type);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('messages')
          .update({'deleted': true})
          .eq('id', messageId)
          .eq('sender_id', user.id);

      setState(() {
        final idx =
        _messages.indexWhere((m) => m['id'].toString() == messageId);
        if (idx != -1) {
          _messages[idx] = {..._messages[idx], 'deleted': true};
        }
      });

      await _channel.sendBroadcastMessage(
        event: 'delete_message',
        payload: {'message_id': messageId},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMessageBubble(
      Map<String, dynamic> message, bool isMe) {
    final isDeleted = message['deleted'] == true;
    final mediaUrl = message['media_url'] as String?;
    final mediaType = message['media_type'] as String?;
    final createdAt = DateTime.parse(message['created_at']);

    return GestureDetector(
      onLongPress: isMe && !isDeleted
          ? () => _deleteMessage(message['id'].toString())
          : null,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe ? Colors.white : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe ? 18 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 18),
            ),
          ),
          child: isDeleted
              ? Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            child: Text(
              'This message was deleted',
              style: TextStyle(
                color: isMe ? Colors.black38 : Colors.grey,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
              : Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (mediaUrl != null && mediaType == 'image')
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    mediaUrl,
                    width: 220,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: 220,
                        height: 160,
                        color: const Color(0xFF3A3A3A),
                        child: const Center(
                            child: CircularProgressIndicator()),
                      );
                    },
                  ),
                )
              else if (mediaUrl != null && mediaType == 'video')
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          VideoPlayerScreen(videoUrl: mediaUrl),
                    ),
                  ),
                  child: Container(
                    width: 220,
                    height: 140,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Icon(Icons.play_circle_filled,
                          color: Colors.white, size: 52),
                    ),
                  ),
                ),
              if (message['content'] != null &&
                  message['content'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    message['content'],
                    style: TextStyle(
                      color: isMe ? Colors.black : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  timeago.format(createdAt),
                  style: TextStyle(
                    color: isMe ? Colors.black45 : Colors.grey,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[800],
              child: Text(
                widget.otherUsername[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Text(widget.otherUsername,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
              child: Text('No messages yet. Say hi! 👋',
                  style: TextStyle(color: Colors.grey)),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe =
                    message['sender_id'] == user?.id;
                return _buildMessageBubble(message, isMe);
              },
            ),
          ),
          if (_isSending)
            const LinearProgressIndicator(color: Colors.white),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(
                  top: BorderSide(color: Colors.grey, width: 0.3)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined,
                      color: Colors.grey),
                  onPressed:
                  _isSending ? null : () => _pickAndSendMedia('image'),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined,
                      color: Colors.grey),
                  onPressed:
                  _isSending ? null : () => _pickAndSendMedia('video'),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSending ? null : () => _sendMessage(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send,
                        color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}