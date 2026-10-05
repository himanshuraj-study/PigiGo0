import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'chat_screen.dart';
import '../../widgets/user_avatar.dart';

class DmListScreen extends StatefulWidget {
  const DmListScreen({super.key});

  @override
  State<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends State<DmListScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchConversations();
  }

  Future<void> _fetchConversations() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final result = await supabase
          .from('conversations')
          .select(
          '*, participant1:profiles!conversations_participant1_id_fkey(id, username, avatar_url), participant2:profiles!conversations_participant2_id_fkey(id, username, avatar_url)'
      )
          .or('participant1_id.eq.${user.id},participant2_id.eq.${user.id}')
          .order('last_message_at', ascending: false, nullsFirst: false);

      setState(() {
        _conversations = List<Map<String, dynamic>>.from(result);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startNewConversation() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final usernameController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Message',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: usernameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter username...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final username = usernameController.text.trim();
                  if (username.isEmpty) return;

                  final targetUser = await supabase
                      .from('profiles')
                      .select()
                      .ilike('username', username)
                      .maybeSingle();

                  if (targetUser == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User not found!')),
                      );
                    }
                    return;
                  }

                  if (targetUser['id'] == user.id) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('You cannot message yourself!')),
                      );
                    }
                    return;
                  }

                  final existing = await supabase
                      .from('conversations')
                      .select()
                      .or('and(participant1_id.eq.${user.id},participant2_id.eq.${targetUser['id']}),and(participant1_id.eq.${targetUser['id']},participant2_id.eq.${user.id})')
                      .maybeSingle();

                  Map<String, dynamic> conversation;
                  if (existing != null) {
                    conversation = existing;
                  } else {
                    final created = await supabase
                        .from('conversations')
                        .insert({
                      'participant1_id': user.id,
                      'participant2_id': targetUser['id'],
                      // FIX: set a default last_message_at so it's never null
                      'last_message_at': DateTime.now().toIso8601String(),
                    })
                        .select()
                        .single();
                    conversation = created;
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          conversationId: conversation['id'],
                          otherUsername: targetUser['username'],
                          otherUserId: targetUser['id'],
                        ),
                      ),
                    );
                  }
                  _fetchConversations();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Start Chat',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
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
        title: const Text('Messages',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            onPressed: _startNewConversation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline,
                color: Colors.grey, size: 64),
            const SizedBox(height: 16),
            const Text('No messages yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Start a conversation!',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _startNewConversation,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('New Message'),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conv = _conversations[index];
          final isParticipant1 =
              conv['participant1_id'] == user?.id;
          final otherUser = isParticipant1
              ? conv['participant2']
              : conv['participant1'];
          final otherUsername =
              otherUser?['username'] ?? 'Unknown';
          final lastMessage =
              conv['last_message'] ?? 'Start a conversation';

          // FIX: null-safe parse — fall back to now if missing
          final lastMessageAt = conv['last_message_at'] != null
              ? DateTime.parse(conv['last_message_at'])
              : DateTime.now();

          return ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    conversationId: conv['id'],
                    otherUsername: otherUsername,
                    otherUserId: otherUser?['id'] ?? '',
                  ),
                ),
              ).then((_) => _fetchConversations());
            },
            leading: UserAvatar(
              avatarUrl: otherUser?['avatar_url'],
              username: otherUsername,
              radius: 28,
            ),
            title: Text(otherUsername,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
            subtitle: Text(lastMessage,
                style: const TextStyle(color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            trailing: Text(
              timeago.format(lastMessageAt),
              style: const TextStyle(
                  color: Colors.grey, fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}
