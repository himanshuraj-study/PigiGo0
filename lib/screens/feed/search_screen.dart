import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/user_avatar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  Set<String> _followingIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchFollowing();
  }

  Future<void> _fetchFollowing() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final result = await supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', user.id);

    setState(() {
      _followingIds = Set<String>.from(
        (result as List).map((f) => f['following_id'].toString()),
      );
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _users = []);
      return;
    }

    setState(() => _isLoading = true);

    final user = supabase.auth.currentUser;
    final result = await supabase
        .from('profiles')
        .select('id, username, bio, avatar_url')
        .ilike('username', '%$query%')
        .neq('id', user?.id ?? '')
        .limit(20);

    setState(() {
      _users = List<Map<String, dynamic>>.from(result);
      _isLoading = false;
    });
  }

  Future<void> _toggleFollow(String targetUserId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final isFollowing = _followingIds.contains(targetUserId);

    setState(() {
      if (isFollowing) {
        _followingIds.remove(targetUserId);
      } else {
        _followingIds.add(targetUserId);
      }
    });

    if (isFollowing) {
      await supabase
          .from('follows')
          .delete()
          .eq('follower_id', user.id)
          .eq('following_id', targetUserId);

      await supabase.rpc('decrement_followers', params: {'user_id': targetUserId});
      await supabase.rpc('decrement_following', params: {'user_id': user.id});
    } else {
      await supabase.from('follows').insert({
        'follower_id': user.id,
        'following_id': targetUserId,
      });

      await supabase.rpc('increment_followers', params: {'user_id': targetUserId});
      await supabase.rpc('increment_following', params: {'user_id': user.id});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text('Search', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: _searchUsers,
              decoration: InputDecoration(
                hintText: 'Search users...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                ? Center(
              child: Text(
                _searchController.text.isEmpty
                    ? 'Search for users to follow'
                    : 'No users found',
                style: const TextStyle(color: Colors.grey),
              ),
            )
                : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final profile = _users[index];
                final isFollowing = _followingIds.contains(profile['id'].toString());

                return ListTile(
                  leading: UserAvatar(
                    avatarUrl: profile['avatar_url'],
                    username: profile['username'],
                    radius: 24,
                  ),
                  title: Text(
                    profile['username'],
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    profile['bio'] ?? '',
                    style: const TextStyle(color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _toggleFollow(profile['id'].toString()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFollowing ? Colors.transparent : Colors.white,
                      foregroundColor: isFollowing ? Colors.white : Colors.black,
                      side: isFollowing
                          ? const BorderSide(color: Colors.grey)
                          : BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(isFollowing ? 'Following' : 'Follow'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}