import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../profile/profile_screen.dart';
import 'post_detail_screen.dart';
import '../messaging/dm_list_screen.dart';
import 'search_screen.dart';
import 'video_player_screen.dart';
import '../../widgets/user_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _posts = [];
  Set<String> _likedPostIds = {};
  final Set<String> _processingLikes = {};
  bool _isLoading = true;
  int _currentIndex = 0;
  static const int _pageSize = 10;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _fetchMorePosts();
    }
  }

  Future<void> _fetchPosts() async {
    try {
      final user = supabase.auth.currentUser;
      final response = await supabase
          .from('posts')
          .select('*, profiles(username, avatar_url)')
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      Set<String> likedIds = {};
      if (user != null) {
        final likes = await supabase
            .from('likes')
            .select('post_id')
            .eq('user_id', user.id);
        likedIds = Set<String>.from(
            (likes as List).map((l) => l['post_id'].toString()));
      }

      setState(() {
        _posts = List<Map<String, dynamic>>.from(response);
        _likedPostIds = likedIds;
        _isLoading = false;
        _currentPage = 0;
        _hasMore = response.length == _pageSize;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load posts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchMorePosts() async {
    if (_isFetchingMore || !_hasMore) return;
    setState(() => _isFetchingMore = true);

    try {
      final user = supabase.auth.currentUser;
      final nextPage = _currentPage + 1;
      final from = nextPage * _pageSize;
      final to = from + _pageSize - 1;

      final response = await supabase
          .from('posts')
          .select('*, profiles(username, avatar_url)')
          .order('created_at', ascending: false)
          .range(from, to);

      final newPosts = List<Map<String, dynamic>>.from(response);

      if (user != null && newPosts.isNotEmpty) {
        final newPostIds = newPosts.map((p) => p['id'].toString()).toList();
        final likes = await supabase
            .from('likes')
            .select('post_id')
            .eq('user_id', user.id)
            .inFilter('post_id', newPostIds);
        final newLikedIds = Set<String>.from(
            (likes as List).map((l) => l['post_id'].toString()));
        _likedPostIds.addAll(newLikedIds);
      }

      setState(() {
        _posts.addAll(newPosts);
        _currentPage = nextPage;
        _hasMore = response.length == _pageSize;
        _isFetchingMore = false;
      });
    } catch (e) {
      setState(() => _isFetchingMore = false);
    }
  }

  Future<void> _likePost(String postId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (_processingLikes.contains(postId)) return;
    setState(() => _processingLikes.add(postId));

    final isLiked = _likedPostIds.contains(postId);
    final idx = _posts.indexWhere((p) => p['id'].toString() == postId);
    if (idx == -1) {
      setState(() => _processingLikes.remove(postId));
      return;
    }

    final currentLikes = (_posts[idx]['likes_count'] as int?) ?? 0;
    final int newLikes = isLiked
        ? (currentLikes > 0 ? currentLikes - 1 : 0)
        : (currentLikes < 0 ? 0 : currentLikes) + 1;

    setState(() {
      if (isLiked) {
        _likedPostIds.remove(postId);
      } else {
        _likedPostIds.add(postId);
      }
      _posts[idx] = {
        ..._posts[idx],
        'likes_count': newLikes,
      };
    });

    try {
      if (isLiked) {
        await supabase
            .from('likes')
            .delete()
            .eq('user_id', user.id)
            .eq('post_id', postId);
      } else {
        await supabase.from('likes').insert({
          'user_id': user.id,
          'post_id': postId,
        });
      }
      await supabase.from('posts').update({
        'likes_count': newLikes,
      }).eq('id', postId);
    } catch (e) {
      // Revert on failure
      setState(() {
        if (isLiked) {
          _likedPostIds.add(postId);
        } else {
          _likedPostIds.remove(postId);
        }
        _posts[idx] = {
          ..._posts[idx],
          'likes_count': currentLikes,
        };
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update like'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _processingLikes.remove(postId));
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Post',
            style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this post?',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('posts').delete().eq('id', postId);
      setState(() {
        _posts.removeWhere((p) => p['id'].toString() == postId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          '🐦 PigiGo',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
          ? const Center(
        child: Text(
          'No posts yet.\nBe the first to post!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      )
          : RefreshIndicator(
        onRefresh: _fetchPosts,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _posts.length + (_isFetchingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _posts.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final post = _posts[index];
            final profile = post['profiles'];
            final username =
                profile?['username'] ?? 'Unknown';
            final createdAt =
            DateTime.parse(post['created_at']);
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PostDetailScreen(post: post),
                  ),
                ).then((_) => _fetchPosts());
              },
              child: _buildPostCard(
                  post, username, createdAt),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePostDialog(),
        backgroundColor: Colors.white,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            Navigator.push(context,
                MaterialPageRoute(
                    builder: (context) => const SearchScreen()));
          }
          if (index == 2) {
            Navigator.push(context,
                MaterialPageRoute(
                    builder: (context) => const DmListScreen()));
          }
          if (index == 3) {
            Navigator.push(context,
                MaterialPageRoute(
                    builder: (context) => const ProfileScreen()));
          }
        },
        backgroundColor: const Color(0xFF0A0A0A),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(
              icon: Icon(Icons.search), label: ''),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline), label: ''),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: ''),
        ],
      ),
    );
  }

  Widget _buildPostCard(
      Map<String, dynamic> post, String username, DateTime createdAt) {
    final postId = post['id'].toString();
    final isLiked = _likedPostIds.contains(postId);
    final isProcessing = _processingLikes.contains(postId);
    final imageUrl = post['image_url'] as String?;
    final videoUrl = post['video_url'] as String?;
    final isOwner =
        post['author_id'] == supabase.auth.currentUser?.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                UserAvatar(
                  avatarUrl: post['profiles']?['avatar_url'],
                  username: username,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
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
                ),
                if (isOwner)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () => _deletePost(postId),
                  )
                else
                  const Icon(Icons.more_horiz, color: Colors.grey),
              ],
            ),
          ),
          if (post['content'] != null &&
              post['content'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                post['content'],
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, height: 1.5),
              ),
            ),
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 200,
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
          ],
          if (videoUrl != null && videoUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      VideoPlayerScreen(videoUrl: videoUrl),
                ),
              ),
              child: Container(
                height: 200,
                width: double.infinity,
                color: const Color(0xFF2A2A2A),
                child: const Center(
                  child: Icon(Icons.play_circle_filled,
                      color: Colors.white, size: 64),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: isProcessing ? null : () => _likePost(postId),
                  child: Row(
                    children: [
                      isProcessing
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey),
                      )
                          : Icon(
                        isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color:
                        isLiked ? Colors.red : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text('${post['likes_count'] ?? 0}',
                          style: TextStyle(
                              color: isLiked
                                  ? Colors.red
                                  : Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        color: Colors.grey, size: 20),
                    const SizedBox(width: 4),
                    Text('${post['comments_count'] ?? 0}',
                        style:
                        const TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(width: 24),
                const Icon(Icons.share_outlined,
                    color: Colors.grey, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePostDialog() {
    final contentController = TextEditingController();
    File? selectedImage;
    File? selectedVideo;
    bool isPosting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
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
              const Text('Create Post',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                autofocus: true,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 12),
              if (selectedImage != null) ...[
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(selectedImage!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setModalState(
                                () => selectedImage = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (selectedVideo != null) ...[
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.videocam,
                          color: Colors.white, size: 40),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setModalState(
                                  () => selectedVideo = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Text(
                          selectedVideo!.path.split('/').last,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 80,
                        maxWidth: 1080,
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedImage = File(picked.path);
                          selectedVideo = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.image_outlined,
                              color: Colors.grey, size: 20),
                          SizedBox(width: 6),
                          Text('Photo',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickVideo(
                        source: ImageSource.gallery,
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedVideo = File(picked.path);
                          selectedImage = null;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.videocam_outlined,
                              color: Colors.grey, size: 20),
                          SizedBox(width: 6),
                          Text('Video',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: isPosting
                        ? null
                        : () async {
                      final text =
                      contentController.text.trim();
                      if (text.isEmpty &&
                          selectedImage == null &&
                          selectedVideo == null) {
                        return;
                      }

                      final user =
                          supabase.auth.currentUser;
                      if (user == null) return;

                      setModalState(
                              () => isPosting = true);

                      try {
                        String? imageUrl;
                        String? videoUrl;

                        if (selectedImage != null) {
                          final fileExt = selectedImage!
                              .path
                              .split('.')
                              .last
                              .toLowerCase();
                          final fileName =
                              '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                          await supabase.storage
                              .from('post-images')
                              .upload(
                              fileName, selectedImage!);
                          imageUrl = supabase.storage
                              .from('post-images')
                              .getPublicUrl(fileName);
                        }

                        if (selectedVideo != null) {
                          final fileExt = selectedVideo!
                              .path
                              .split('.')
                              .last
                              .toLowerCase();
                          final fileName =
                              'video_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
                          await supabase.storage
                              .from('post-images')
                              .upload(
                              fileName, selectedVideo!);
                          videoUrl = supabase.storage
                              .from('post-images')
                              .getPublicUrl(fileName);
                        }

                        await supabase.from('posts').insert({
                          'author_id': user.id,
                          'content': text,
                          if (imageUrl != null)
                            'image_url': imageUrl,
                          if (videoUrl != null)
                            'video_url': videoUrl,
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                        _fetchPosts();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Failed to post: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                        setModalState(
                                () => isPosting = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isPosting
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black),
                    )
                        : const Text('Post',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}