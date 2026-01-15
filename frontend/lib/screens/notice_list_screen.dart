import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';
import '../models/notice_model.dart';
import '../services/auth_service.dart';

class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  List<NoticeModel> _notices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotices();
  }

  Future<void> _fetchNotices() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/notices/'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _notices = data.map((item) => NoticeModel.fromJson(item)).toList();
          _isLoading = false;
        });

        // [New] Update last seen notice ID (find max ID in the list)
        if (_notices.isNotEmpty) {
          final maxId = _notices.map((n) => n.id).reduce((a, b) => a > b ? a : b);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_seen_notice_id', maxId);
          print("[NOTICE] Updated last_seen_notice_id to: $maxId");
        }
      } else {
        throw Exception("Failed to load notices");
      }
    } catch (e) {
      print("Error fetching notices: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("공지사항을 불러오는 데 실패했습니다.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6),
      appBar: AppBar(
        title: Text(
          "공지사항",
          style: GoogleFonts.jua(
            color: const Color(0xFF4E342E),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF4E342E)),
      ),
      body: Stack(
        children: [
          // Background Pattern
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/login_bg.png'),
                fit: BoxFit.cover,
                opacity: 0.1,
              ),
            ),
          ),
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4E342E)))
              : _notices.isEmpty
                  ? Center(
                      child: Text(
                        "등록된 공지사항이 없습니다.",
                        style: GoogleFonts.jua(fontSize: 18, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notices.length,
                      itemBuilder: (context, index) {
                        final notice = _notices[index];
                        return _buildNoticeCard(notice);
                      },
                    ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard(NoticeModel notice) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF5D4037), width: 1),
      ),
      elevation: 2,
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        collapsedShape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
        backgroundColor: Colors.white,
        collapsedBackgroundColor: Colors.white,
        title: Text(
          notice.title,
          style: GoogleFonts.jua(
            fontSize: 18,
            color: const Color(0xFF4E342E),
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          DateFormat('yyyy.MM.dd').format(notice.createdAt),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                notice.content,
                style: GoogleFonts.jua(
                  fontSize: 16,
                  color: const Color(0xFF5D4037),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
