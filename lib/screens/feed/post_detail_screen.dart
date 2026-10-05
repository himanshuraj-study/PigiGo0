import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final supabase = Supabase.instance.client;
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _comments = [];
  bool _isLiked = false;
  int _likesCount = 0;
  bool _isLoading = false;
  bool _isProcessingLike = false;

  @override
  void initState() {
    super.initState();
    _likesCount = widget.post['likes_count'] ?? 0;
    _fetchComments();
    _checkIfLiked();
  }

  Future<void> _checkIfLiked() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final result = await supabase
        .from('likes')
        .select()
        .eq('user_id', user.id)
        .eq('post_id', widget.post['id'])
        .maybeSingle();
    if (mounted) setState(() => _isLiked = result != null);
  }

  Future<void> _toggleLike() async {
    if (_isProcessingLike) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isProcessingLike = true);

    try {
      final existing = await supabase
          .from('likes')
          .select()
          .eq('user_id', user.id)
          .eq('post_id', widget.post['id'])
          .maybeSingle();

      if (existing != null) {
        await supabase
            .from('likes')
            .delete()
            .eq('user_id', user.id)
            .eq('post_id', widget.post['id']);
        await supabase
            .from('posts')
            .update({'likes_count': _likesCount - 1}).eq('id', widget.post['id']);
        if (mounted) setState(() { _isLiked = false; _likesCount--; });
      } else {
        await supabase.from('likes').insert({
          'user_id': user.id,
          'post_id': widget.post['id'],
        });
        await supabase
            .from('posts')
            .update({'likes_count': _likesCount + 1}).eq('id', widget.post['id']);
        if (mounted) setState(() { _isLiked = true; _likesCount++; });
      }
    } catch (e) {
      if (mounted) setState(() { _isLiked = true; });
    } finally {
      if (mounted) setState(() => _isProcessingLike = false);
    }
  }

  Future<void> _fetchComments() async {
    final result = await supabase
        .from('comments')
        .select('*, profiles(username)')
        .eq('post_id', widget.post['id'])
        .order('created_at', ascending: true);
    if (mounted) {
      setState(() {
        _comments = List<Map<String, dynamic>>.from(result);
      });
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      await supabase.from('comments').insert({
        'post_id': widget.post['id'],
        'author_id': user.id,
        'content': _commentController.text.trim(),
      });
      await supabase.from('posts').update({
        'comments_count': _comments.length + 1,
      }).eq('id', widget.post['id']);
      _commentController.clear();
      await _fetchComments();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sharePost() {
    final content = widget.post['content'];
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Post copied to clipboard!'),
          backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final profile = post['profiles'];
    final username = profile?['username'] ?? 'Unknown';
    final createdAt = DateTime.parse(post['created_at']);
    final imageUrl = post['image_url'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Post', style: TextStyle(color: Colors.white)),
      ),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Post header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[800],
                      child: Text(username[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(username,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        Text(timeago.format(createdAt),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Post text
                if (post['content'] != null &&
                    post['content'].toString().isNotEmpty)
                  Text(post['content'],
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, height: 1.5)),

                // Post image
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _showFullScreenImage(context, imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 250,
                            color: const Color(0xFF2A2A2A),
                            child: const Center(
                                child: CircularProgressIndicator()),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          height: 200,
                          color: const Color(0xFF2A2A2A),
                          child: const Icon(Icons.broken_image,
                              color: Colors.grey, size: 48),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Actions
                Row(
                  children: [
                    GestureDetector(
                      onTap: _isProcessingLike ? null : _toggleLike,
                      child: Row(
                        children: [
                          _isProcessingLike
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.grey),
                          )
                              : Icon(
                            _isLiked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color:
                            _isLiked ? Colors.red : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(width: 6),
                          Text('$_likesCount',
                              style: TextStyle(
                                  color:
                                  _isLiked ? Colors.red : Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            color: Colors.grey, size: 24),
                        const SizedBox(width: 6),
                        Text('${_comments.length}',
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(width: 24),
                    GestureDetector(
                      onTap: _sharePost,
                      child: const Icon(Icons.share_outlined,
                          color: Colors.grey, size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.grey),
                const SizedBox(height: 8),

                // Comments
                if (_comments.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No comments yet. Be the first!',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  ..._comments.map((comment) {
                    final commentUsername =
                        comment['profiles']?['username'] ?? 'Unknown';
                    final commentTime =
                    DateTime.parse(comment['created_at']);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.grey[800],
                            child: Text(commentUsername[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(commentUsername,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    const SizedBox(width: 8),
                                    Text(timeago.format(commentTime),
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(comment['content'],
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),

          // Comment input
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border:
              Border(top: BorderSide(color: Colors.grey, width: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
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
                  ),
                ),
                const SizedBox(width: 8),
                _isLoading
                    ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                    CircularProgressIndicator(strokeWidth: 2))
                    : GestureDetector(
                  onTap: _addComment,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle),
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

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
