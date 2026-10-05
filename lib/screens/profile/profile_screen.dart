import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../widgets/user_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final posts = await supabase
          .from('posts')
          .select()
          .eq('author_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _profile = profile;
        _posts = List<Map<String, dynamic>>.from(posts);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _changeAvatar() async {
    final picker = ImagePicker();

    // Show bottom sheet to choose source
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Change Profile Photo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Take Photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
              const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_profile?['avatar_url'] != null)
              ListTile(
                leading:
                const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, null),
              ),
          ],
        ),
      ),
    );

    // Remove photo
    if (source == null &&
        _profile?['avatar_url'] != null) {
      await _removeAvatar();
      return;
    }
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final file = File(picked.path);
      final ext = picked.path.split('.').last.toLowerCase();
      final fileName = 'avatar_${user.id}.$ext';

      // Delete old avatar if exists
      try {
        await supabase.storage.from('avatars').remove([fileName]);
      } catch (_) {}

      await supabase.storage.from('avatars').upload(
        fileName,
        file,
        fileOptions:
        const FileOptions(upsert: true),
      );

      final avatarUrl =
      supabase.storage.from('avatars').getPublicUrl(fileName);

      await supabase.from('profiles').upsert({
        'id': user.id,
        'avatar_url': avatarUrl,
        'username': _profile?['username'] ?? '',
      });

      setState(() {
        _profile = {...?_profile, 'avatar_url': avatarUrl};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      await supabase.from('profiles').upsert({
        'id': user.id,
        'avatar_url': null,
        'username': _profile?['username'] ?? '',
      });
      setState(() {
        _profile = {...?_profile, 'avatar_url': null};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _showEditProfile() {
    final usernameController =
    TextEditingController(text: _profile?['username'] ?? '');
    final bioController =
    TextEditingController(text: _profile?['bio'] ?? '');

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
            const Text('Edit Profile',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: usernameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: const TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bioController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Bio',
                labelStyle: const TextStyle(color: Colors.grey),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final user = supabase.auth.currentUser;
                  if (user == null) return;
                  try {
                    await supabase.from('profiles').upsert({
                      'id': user.id,
                      'username': usernameController.text.trim(),
                      'bio': bioController.text.trim(),
                    });
                    if (context.mounted) Navigator.pop(context);
                    _fetchProfile();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to save: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save',
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: Text(
          _profile?['username'] ?? 'Profile',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Avatar with edit button
                  Stack(
                    children: [
                      _isUploadingAvatar
                          ? CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.grey[800],
                        child: const CircularProgressIndicator(
                            color: Colors.white),
                      )
                          : UserAvatar(
                        avatarUrl: _profile?['avatar_url'],
                        username:
                        _profile?['username'] ?? '?',
                        radius: 48,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _isUploadingAvatar
                              ? null
                              : _changeAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.black, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _profile?['username'] ?? 'No username',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_profile?['bio'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _profile!['bio'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat('Posts', '${_posts.length}'),
                      _buildStat('Followers',
                          '${_profile?['followers_count'] ?? 0}'),
                      _buildStat('Following',
                          '${_profile?['following_count'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _showEditProfile,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side:
                        const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.grey, height: 1),
            _posts.isEmpty
                ? const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No posts yet.',
                  style: TextStyle(color: Colors.grey)),
            )
                : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                return Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius:
                    BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        post['content'] ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                              Icons.favorite_border,
                              color: Colors.grey,
                              size: 16),
                          const SizedBox(width: 4),
                          Text(
                              '${post['likes_count'] ?? 0}',
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12)),
                          const SizedBox(width: 16),
                          const Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.grey,
                              size: 16),
                          const SizedBox(width: 4),
                          Text(
                              '${post['comments_count'] ?? 0}',
                              style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style:
            const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }
}