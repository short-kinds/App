import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// === 데모/디버그 토글(나중에 주석처리 or false로 변경) ======================
const bool kShowDevButtons = false; // 디버그 버튼 노출 여부

// === 데모용: 로컬 '시청 보상 완료' 캐시 초기화 ===============================
// - SharedPreferences에 저장된 키
//   'watch_rewarded:<uid>:<itemUuid>:YYYY-MM-DD' 를 찾아 제거합니다.
// - itemUuid를 주면 해당 아이템만, 생략하면 오늘 전체를 삭제합니다.
// - KST 기준으로 날짜를 맞추고 싶으면 useKst=true로 호출하세요.
Future<int> resetLocalWatchCache({String? itemUuid, bool useKst = false}) async {
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return 0;

  // 오늘 날짜 문자열
  String dayNow() {
    DateTime now = DateTime.now();
    if (useKst) {
      now = DateTime.now().toUtc().add(const Duration(hours: 9));
    }
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  final prefs = await SharedPreferences.getInstance();
  final keys = prefs.getKeys();
  final today = dayNow();
  final prefix = 'watch_rewarded:$uid:';

  final targets = <String>[];
  for (final k in keys) {
    if (!k.startsWith(prefix)) continue;
    if (!k.endsWith(':$today')) continue;              // 오늘자만
    if (itemUuid != null && !k.contains(':$itemUuid:')) continue; // 특정 아이템만
    targets.add(k);
  }

  for (final k in targets) {
    await prefs.remove(k);
  }
  return targets.length;
}
// =========================================================================

final supabaseUrl = dotenv.env['SUPABASE_URL']!;
final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

SupabaseClient get sb => Supabase.instance.client;

// [추가] 문자열형 아이템 ID를 DB용 UUID로 변환하는 헬퍼 (전역에)
final _uuid = Uuid();
String _dbItemId(String logicalId) =>
    _uuid.v5(Uuid.NAMESPACE_URL, 'shortkinds:$logicalId');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    // authFlowType: AuthFlowType.pkce, // 미지원
  );
  runApp(const ShortKindsApp());
}

class ShortKindsApp extends StatefulWidget {
  const ShortKindsApp({super.key});
  @override
  State<ShortKindsApp> createState() => _ShortKindsAppState();
}

class _ShortKindsAppState extends State<ShortKindsApp> {
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _sub;
  late final AppLinks _links = AppLinks();

  @override
  void initState() {
    super.initState();

    // ✅ 첫 프레임이 나온 다음에 딥링크 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // (1) 앱이 링크로 시작된 경우
      _links.getInitialLink().then((uri) {
        if (mounted && uri != null) _handleDeepLink(uri);
      }).catchError((_) {});

      // (2) 실행 중 새 링크가 들어오는 경우
      _sub = _links.uriLinkStream.listen((uri) {
        if (!mounted || uri == null) return;
        _handleDeepLink(uri);
      }, onError: (_) {});
    });
  }

  void _handleDeepLink(Uri uri) {
    if (uri.host != 'item') return; // scheme은 Android/iOS 설정대로
    final id = uri.queryParameters['id'];
    final cat = uri.queryParameters['cat'];
    if (id == null || cat == null) return;

    _navKey.currentState?.push(
      _fadeSlideRoute(NewsFeedScreen(selectedCategory: cat, jumpToItemId: id)),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'Short Kinds',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A56F6)),
      ),
      home: const AuthGate(child: SplashScreen()), // ✅ 반드시 지정
    );
  }
}

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 세션 변화에 반응
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (_, __) {
        final hasSession = sb.auth.currentSession != null;
        return hasSession ? child : const SignInScreen();
      },
    );
  }
}

//카테고리 고정 리스트 (API 연동 시 교체?)
const List<String> kCategories = <String>[
  '정치', '경제', '사회', '문화', '국제', '지역', '스포츠', 'IT_과학',
];

/// 공용: 페이드 + 아래에서 살짝 슬라이드 전환
Route _fadeSlideRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation) {
      return page;
    },
    transitionsBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation, Widget child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.10),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// 1) 스플래시
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..forward();

 @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final hasSession = sb.auth.currentSession != null;

      Navigator.of(context).pushReplacement(
        _fadeSlideRoute(
          hasSession
            ? const OnboardingScreen()
            : const SignInScreen(showSplashAfterLogin: true), // ⬅️ 앱 첫 로그인 경로
        ),
      );
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.primary,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic),
            child: Text(
              'Short Kinds',
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 2) 온보딩 (시작하기 → 카테고리 선택)
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.86,
                      height: 360,
                      child: ClipPath(
                        clipper: _BlobClipper(),
                        child: Container(color: const Color(0xFFF59BEA)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        '빅카인즈의 새로운\n뉴스 숏폼 서비스\nShort kinds',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
                    );
                  },
                  child: const Text('시작하기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2.5) 카테고리 선택 화면
class CategorySelectScreen extends StatefulWidget {
  final List<String> categories;
  const CategorySelectScreen({super.key, required this.categories});

  @override
  State<CategorySelectScreen> createState() => _CategorySelectScreenState();
}

class _CategorySelectScreenState extends State<CategorySelectScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            // 아이콘 배지
            Icon(Icons.done_rounded,  // 또는 Icons.check_rounded / Icons.task_alt_rounded
                color: Colors.black, size: 26),
            const SizedBox(width: 8),
            const Text(
              '관심 카테고리 선택',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.4,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '원하는 카테고리를 선택하세요.\n선택한 카테고리의 뉴스 쇼츠만 보여드려요.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 30),

              GridView.builder(
                itemCount: widget.categories.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,          // 2열
                  mainAxisSpacing: 25,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.35,      // 셀 가로/세로 비 (값 줄이면 더 높아짐)
                ),
                itemBuilder: (context, i) {
                  final c = widget.categories[i];
                  final selected = _selected == c;
                  return _CategoryTile(
                    label: c,
                    selected: selected,
                    onTap: () => setState(() => _selected = c),
                  );
                },
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('선택 완료'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _selected == null
                      ? null
                      : () {
                          // ★ 디버그 로그(원인 추적에 도움)
                          // debugPrint('go -> ${_selected!}');
                          Navigator.of(context).pushReplacement(
                            _fadeSlideRoute(NewsFeedScreen(selectedCategory: _selected!)),
                          );
                        },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}


class _CategoryTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: selected ? cs.primary : cs.primary.withValues(alpha: 0.08),
      shape: StadiumBorder(side: BorderSide(color: cs.primary, width: 1.5)),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56), // 높이 업(필요시 60~64로)
          child: Padding(
            // 좌우 패딩도 살짝 줄여 여백 타이트하게
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 항상 정확히 중앙 정렬되는 라벨 텍스트
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24, // 더 키우고 싶으면 19~20
                    fontWeight: FontWeight.w800,
                    color: selected ? cs.onPrimary : cs.primary,
                  ),
                ),
                // 선택 시에만 왼쪽에 '겹쳐서' 아이콘 표시 → 텍스트 폭에 영향 없음
                if (selected)
                  const Positioned(
                    left: 8, // 아이콘 왼쪽 여백(더 붙이고 싶으면 8~10)
                    child: Icon(Icons.check_rounded, size: 30, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 퀴즈 데이터
class QuizData {
  final String question;
  final List<String> options;   // 보기 4개
  final int answerIndex;        // 0..3
  final bool ctaTop;
  final int secondsBeforeEnd;

  QuizData({
    required this.question,
    required this.options,
    required this.answerIndex,
    this.ctaTop = false,
    this.secondsBeforeEnd = 5,
  }) : assert(options.length == 4, 'options는 4개여야 합니다.');
}

/// 데이터 모델
class NewsItem {
  final String id;
  final String outletName;
  final int trustScore;     // %
  final String videoUrl;    // TODO: video_player로 사용
  final String title;
  final String reporter;
  final String publishedAt;
  final String playbackPolicy;
  final String? articleUrl;

  /// ✅ 카테고리(필터용)
  final String category;

  // ★ 추가: 퀴즈(없으면 null)
  final QuizData? quiz;

  const NewsItem({
    required this.id,
    required this.outletName,
    required this.trustScore,
    required this.videoUrl,
    required this.title,
    required this.reporter,
    required this.publishedAt,
    required this.category,
    this.quiz, 
    required this.playbackPolicy,
    this.articleUrl,
  });
}

extension NewsFactories on NewsItem {
  static String muxUrl(String playbackId) =>
      'https://stream.mux.com/$playbackId.m3u8';

  static NewsItem fromRow(Map<String, dynamic> r) {
    final muxPlaybackId = (r['mux_playback_id'] as String?) ?? '';
    final policy = ((r['playback_policy'] as String?) ?? 'public').toLowerCase();

    QuizData? q;
    final quizzes = r['quizzes'];
    if (quizzes is Map && quizzes.isNotEmpty) {
      q = QuizData(
        question: quizzes['question'] as String,
        options: (quizzes['options'] as List).cast<String>(),
        answerIndex: quizzes['answer_index'] as int,
        ctaTop: (quizzes['cta_top'] as bool?) ?? false,
        secondsBeforeEnd: (quizzes['seconds_before_end'] as int?) ?? 5,
      );
    } else if (quizzes is List && quizzes.isNotEmpty) {
      final m = quizzes.first as Map<String, dynamic>;
      q = QuizData(
        question: m['question'] as String,
        options: (m['options'] as List).cast<String>(),
        answerIndex: m['answer_index'] as int,
        ctaTop: (m['cta_top'] as bool?) ?? false,
        secondsBeforeEnd: (m['seconds_before_end'] as int?) ?? 5,
      );
    }

    final url = muxPlaybackId.isNotEmpty ? muxUrl(muxPlaybackId) : '';

    return NewsItem(
      id: r['logical_id'] as String,
      outletName: (r['outlet_name'] as String?) ?? '',
      trustScore: (r['trust_score'] as int?) ?? 0,
      videoUrl: url,
      title: r['title'] as String,
      reporter: (r['reporter'] as String?) ?? '',
      publishedAt: (r['published_at'] as String?) ?? '',
      category: r['category'] as String,
      quiz: q,
      playbackPolicy: policy,
      articleUrl: (r['url'] as String?),
    );
  }
}

/// 3) 세로 피드 화면 (선택한 카테고리만 표시)
class NewsFeedScreen extends StatefulWidget {
  final String? selectedCategory;
  final String? jumpToItemId; // 이 ID가 있으면 해당 기사부터 시작

  const NewsFeedScreen({
    super.key,
    this.selectedCategory,
    this.jumpToItemId,
  });

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  late final PageController _pc;
  int _current = 0;
  bool _isAtEnd = false;

  // ✅ 서버 데이터
  final List<NewsItem> _items = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _pc = PageController(initialPage: 0);
    _fetchItems(); // Supabase에서 로드
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  /// Supabase에서 선택 카테고리의 숏츠(+퀴즈) 조회
  Future<void> _fetchItems() async {
    final cat = widget.selectedCategory;
    if (cat == null || cat.isEmpty) {
      setState(() { _loading = false; _err = '카테고리가 지정되지 않았습니다.'; });
      return;
    }

    try {
      // 1) shorts만 먼저 (임베드 제거!)
      final shortsRows = await sb
          .from('shorts')
          .select('''
            id, logical_id, title, outlet_name, reporter, category,
            trust_score, published_at, mux_playback_id, playback_policy, duration_seconds, url
          ''')
          .eq('category', cat)
          .order('published_at', ascending: false);

      final base = (shortsRows as List).cast<Map<String, dynamic>>();
      debugPrint('[shorts] cat=$cat -> ${base.length} rows');

      // 2) quizzes는 id 목록으로 한 번 더 가져오기 (버전 무관)
      List<Map<String, dynamic>> qrows = const [];
      if (base.isNotEmpty) {
        final ids = base.map((r) => r['id'] as String).toList();

        // PostgREST in 연산자: in.(id1,id2,...)  — uuid는 따옴표 없어도 동작합니다.
        final inArg = '(${ids.join(',')})';

        final qRes = await sb
            .from('quizzes')
            .select('item_id, question, options, answer_index, cta_top, seconds_before_end')
            .filter('item_id', 'in', inArg);

        qrows = (qRes as List).cast<Map<String, dynamic>>();
        debugPrint('[quizzes] fetched=${qrows.length}');
      }

      // 3) item_id -> 퀴즈 맵핑 후 주입
      final byId = <String, Map<String, dynamic>>{
        for (final q in qrows) q['item_id'] as String: q,
      };

      final list = base.map((r) {
        r['quizzes'] = byId[r['id'] as String]; // Map 또는 null — fromRow가 둘 다 처리
        return NewsFactories.fromRow(r);
      }).toList();

      // 4) jumpTo 처리
      int initial = 0;
      if (widget.jumpToItemId != null) {
        final idx = list.indexWhere((e) => e.id == widget.jumpToItemId);
        if (idx >= 0) initial = idx;
      }

      if (!mounted) return;
      setState(() {
        _items..clear()..addAll(list);
        _loading = false;
        _err = null;
        _current = initial; // 현재 인덱스만 먼저 기억
      });

      // PageView가 attach된 "다음 프레임"에 점프
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pc.hasClients) {
          _pc.jumpToPage(_current);
        }
      });
    } catch (e, st) {
      debugPrint('[fetch error] $e\n$st');  // ← 실제 에러 꼭 확인
      if (!mounted) return;
      setState(() { _loading = false; _err = '$e'; });
    }
  }
  
  // _NewsFeedScreenState 클래스 안에(예: build 위쪽 아무 곳) 추가
  Future<void> _openOriginalUrl(NewsItem item) async {
    final raw = item.articleUrl?.trim();
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('원문 URL이 없습니다.')),
        );
      }
      return;
    }

    // 잘못된 스킴(예: "https:///") 보정 시도
    final fixed = raw.startsWith('http') ? raw : 'https://$raw';
    final uri = Uri.tryParse(fixed);

    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL 형식이 올바르지 않습니다: $raw')),
        );
      }
      return;
    }

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('브라우저를 열 수 없습니다.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('원문 열기 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selected = widget.selectedCategory ?? '';
    final hasItems = _items.isNotEmpty;
    final selectedLabel = selected.isEmpty ? '미지정' : selected;
    final appBarTitle = hasItems && !_isAtEnd ? _items[_current].outletName : 'Short Kinds';

    final canPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          leadingWidth: 40,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacement(
                  _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
                );
              }
            },
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.article, color: cs.onPrimary, size: 16),
              ),
              Flexible(
                child: Text(
                  appBarTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (hasItems && !_isAtEnd)
              IconButton(
                tooltip: '원문 열기',
                icon: const Icon(Icons.link_rounded, color: Colors.white, size: 28),
                onPressed: () => _openOriginalUrl(_items[_current]),   // ★ 원문 열기
              ),
            if (hasItems && !_isAtEnd)
              IconButton(
                tooltip: '더보기',
                icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
                onPressed: () => _showMetaDialog(context, _items[_current]),
              ),
            // 로그인/로그아웃 버튼 상태 반영(기존 코드 유지)
            StreamBuilder<AuthState>(
              stream: sb.auth.onAuthStateChange,
              builder: (context, _) {
                final loggedIn = sb.auth.currentSession != null;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loggedIn)
                      IconButton(
                        tooltip: '내 활동',
                        icon: const Icon(Icons.person_outline, color: Colors.white, size: 24),
                        onPressed: () {
                          // ✅ 소스는 DB에서 로드된 _items로 변경
                          Navigator.of(context).push(
                            _fadeSlideRoute(MyActivityScreen(source: _items)),
                          );
                        },
                      ),
                    loggedIn
                        ? IconButton(
                            tooltip: '로그아웃',
                            icon: const Icon(Icons.logout, color: Colors.white, size: 24),
                            onPressed: _confirmAndLogout, // 아래 헬퍼
                          )
                        : IconButton(
                            tooltip: '로그인',
                            icon: const Icon(Icons.login, color: Colors.white, size: 24),
                            onPressed: _goLogin, // 아래 헬퍼
                          ),
                  ],
                );
              },
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_err != null)
                ? _EmptyCategory(
                    category: selectedLabel,
                    onChangeCategory: () {
                      Navigator.of(context).pushReplacement(
                        _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
                      );
                    },
                  )
                : hasItems
                    ? PageView.builder(
                        controller: _pc,
                        scrollDirection: Axis.vertical,
                        // 실제 아이템 + 엔드 페이지 1장
                        itemCount: _items.length + 1,
                        onPageChanged: (i) {
                          setState(() {
                            _isAtEnd = (i == _items.length);
                            if (!_isAtEnd) _current = i;
                          });
                        },
                        itemBuilder: (context, index) {
                          // 마지막 인덱스면 ‘끝 페이지’
                          if (index == _items.length) {
                            return _EndOfCategoryPage(
                              category: selectedLabel,
                              onChangeCategory: () {
                                Navigator.of(context).pushReplacement(
                                  _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
                                );
                              },
                            );
                          }
                          // 동영상+메타 페이지
                          return _NewsPage(key: ValueKey('news_$index'), item: _items[index]);
                        },
                      )
                    : _EmptyCategory(
                        category: selectedLabel,
                        onChangeCategory: () {
                          Navigator.of(context).pushReplacement(
                            _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
                          );
                        },
                      ),
      ),
    );
  }

  Future<void> _goLogin() async {
    final ok = await Navigator.of(context).push(
      _fadeSlideRoute(const SignInScreen(showSplashAfterLogin: false)),
    );
    if (!mounted) return;
    if (ok == true) setState(() {}); // 돌아오자마자 UI 갱신
  }

  Future<void> _confirmAndLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('예')),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    try {
      await sb.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃 실패: $e')),
      );
    }
  }

  /// 더보기(⋮) → 제목/기자/날짜 팝업
  void _showMetaDialog(BuildContext context, NewsItem item) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'meta',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: size.width * 0.92,
              constraints: BoxConstraints(
                minHeight: 180,
                maxHeight: size.height * 0.55,
              ),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black45, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8)),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('제목: ${item.title}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                    const SizedBox(height: 10),
                    Text('기자: ${item.reporter}', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    const SizedBox(height: 8),
                    Text('날짜: ${item.publishedAt}', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size(108, 40),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('CLOSE'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class BadgeDef {
  final String code;
  final String title;
  final String criteria; // 달성 기준 설명
  const BadgeDef(this.code, this.title, this.criteria);
}

const List<BadgeDef> kBadgeCatalog = [
  BadgeDef('achv_news_explorer', '뉴스 탐험가', '30일 연속 서로 다른 3개 카테고리에서 각 1개 이상 시청'),
  BadgeDef('achv_daily_running', '데일리 러닝', '30일 연속 시청 5개'),
  BadgeDef('achv_night_hunter',  '심야 뉴스 헌터', '30일 연속 밤 12시~새벽 5시 사이 뉴스 시청 5개'),
  BadgeDef('achv_news_maniac',   '뉴스 마니아', '누적 시청 100개'),
  BadgeDef('achv_quiz_master',   '퀴즈 마스터', '퀴즈 정답 누적 100회 (테스트=1회)'),
  BadgeDef('achv_like_100',      '공감의 달인', '좋아요 누적 100회 (테스트=1회)'),
  BadgeDef('achv_bookmark_100',  '컬렉터',     '찜 누적 100개'),
];

// 배지 포인트(서버 트리거와 동일하게 유지)
const Map<String, int> kBadgePointMap = {
  'achv_like_100':      50,
  'achv_bookmark_100':  50,
  'achv_quiz_master':   150,
  'achv_news_maniac':   150,
  'achv_news_explorer': 100,
  'achv_daily_running': 50,
  'achv_night_hunter':  50,
};

int badgePoints(String code) => kBadgePointMap[code] ?? 0;

String badgeName(String code) {
  switch (code) {
    case 'achv_news_explorer': return '뉴스 탐험가';
    case 'achv_daily_running': return '데일리 러닝';
    case 'achv_night_hunter':  return '심야 뉴스 헌터';
    case 'achv_news_maniac':   return '뉴스 마니아';
    case 'achv_quiz_master':   return '퀴즈 마스터';
    case 'achv_like_100':      return '공감의 달인';
    case 'achv_bookmark_100':  return '컬렉터';
    default: return '새 배지';
  }
}

class MyActivityScreen extends StatefulWidget {
  final List<NewsItem> source; // 전체 기사(로컬 allItems)
  const MyActivityScreen({super.key, required this.source});

  @override
  State<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends State<MyActivityScreen> {
  bool _loading = true;
  String? _err;
  List<NewsItem> _bookmarks = [];
  List<NewsItem> _likes = [];

  int _totalPoints = 0;
  int _todayWatch = 0;
  int _todayLikeAwards = 0;
  int _todayQuizCorrect = 0;
  List<Map<String, dynamic>> _badges = [];

  NewsItem _newsFromItemRow(Map<String, dynamic> r) {
    return NewsItem(
      id: '', // logical_id 모를 수 있음(네비는 카테고리만 사용)
      outletName: (r['outlet_name'] as String?) ?? '',
      trustScore: 0,
      videoUrl: '',
      title: (r['title'] as String?) ?? '',
      reporter: (r['reporter'] as String?) ?? '',
      publishedAt: '',
      category: (r['category'] as String?) ?? '',
      playbackPolicy: 'public',
      quiz: null,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadRewards();
  }

  Future<void> _load() async {
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _loading = false;
          _err = '로그인이 필요합니다.';
        });
        return;
      }

      final bmRows = await sb
          .from('my_bookmarks')
          .select('item_id, created_at')
          .order('created_at', ascending: false);

      final likeRows = await sb
          .from('my_likes')
          .select('item_id, created_at')
          .order('created_at', ascending: false);

      final bmIds = (bmRows as List).map((r) => (r['item_id'] as String)).toList();
      final likeIds = (likeRows as List).map((r) => (r['item_id'] as String)).toList();

      // 1) 현재 화면에 로드된 기사(source)로 1차 매칭
      final known = <String, NewsItem>{
        for (final n in widget.source) _dbItemId(n.id): n,
      };

      final bmItems = <NewsItem>[];
      final likeItems = <NewsItem>[];

      for (final id in bmIds) {
        final hit = known[id];
        if (hit != null) bmItems.add(hit);
      }
      for (final id in likeIds) {
        final hit = known[id];
        if (hit != null) likeItems.add(hit);
      }

      // 2) 남은 UUID는 DB 'items'에서 보강 조회(타 카테고리에서도 보이게)
      final missing = {...bmIds, ...likeIds}..removeWhere(known.containsKey);
      if (missing.isNotEmpty) {
        final inArg = '(${missing.join(',')})';
        final rows = await sb
            .from('items')
            .select('id, title, outlet_name, reporter, category')
            .filter('id', 'in', inArg);

        final mapped = {
          for (final r in (rows as List).cast<Map<String, dynamic>>())
            (r['id'] as String): _newsFromItemRow(r),
        };

        for (final id in bmIds) {
          if (!known.containsKey(id) && mapped[id] != null) bmItems.add(mapped[id]!);
        }
        for (final id in likeIds) {
          if (!known.containsKey(id) && mapped[id] != null) likeItems.add(mapped[id]!);
        }
      }

      if (!mounted) return;
      setState(() {
        _bookmarks = bmItems;
        _likes = likeItems;
        _loading = false;
        _err = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
    }
  }

  /// 항목 탭 시 해당 카테고리 피드로 이동 + 해당 기사 위치로 초기 진입
  void _goToItem(NewsItem item) {
    Navigator.of(context).push(
      _fadeSlideRoute(
        NewsFeedScreen(
          selectedCategory: item.category,
          jumpToItemId: (item.id.isNotEmpty) ? item.id : null, // id 없으면 카테고리 피드로만
        ),
      ),
    );
  }

  Future<void> _loadRewards() async {
    try {
      final m = await sb.rpc('get_rewards_summary') as Map?;
      if (!mounted || m == null) return;
      setState(() {
        _totalPoints = (m['total_points'] ?? 0) as int;
        _todayWatch = (m['today_watch'] ?? 0) as int;
        _todayLikeAwards = (m['today_like_awards'] ?? 0) as int;
        _todayQuizCorrect = (m['today_quiz_correct'] ?? 0) as int;
        _badges = (m['badges'] as List?)?.cast<Map<String,dynamic>>() ?? [];
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leadingWidth: 40,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pushReplacement(
                  _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
                );
              }
            },
          ),
          title: const Text('내 활동',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          bottom: TabBar(
            tabs: [Tab(text: '찜'), Tab(text: '좋아요'), Tab(text: '보상')],
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            labelColor: Colors.white,          // 선택된 탭 글씨 (불투명)
            unselectedLabelColor: Colors.white60, // 비선택 탭 글씨 (투명도↓)
          ),
          // ################ test용 ##################
          actions: [
            if (kShowDevButtons)
              IconButton(
                tooltip: '시청 캐시 초기화(오늘 전체)',
                icon: const Icon(Icons.cleaning_services_rounded, color: Colors.white),
                onPressed: () async {
                  final removed = await resetLocalWatchCache(); // 오늘 전체
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('오늘 로컬 시청 캐시 삭제: $removed개')),
                  );
                  // 포인트/진행상황 갱신(선택)
                  try {
                    // ignore: use_build_context_synchronously
                    final state = context.findAncestorStateOfType<_MyActivityScreenState>();
                    await state?._loadRewards();
                  } catch (_) {}
                },
              ),
          ],
          // ##################################
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_err != null)
                ? Center(
                    child: Text(_err!,
                        style: const TextStyle(color: Colors.white70)),
                  )
                : TabBarView(
                    children: [
                      _buildList(_bookmarks, emptyLabel: '찜한 기사가 없어요.'),
                      _buildList(_likes, emptyLabel: '좋아요한 기사가 없어요.'),
                      _buildRewardsTab(),
                    ],
                  ),
        floatingActionButton: (_loading || _err != null)
            ? null
            : FloatingActionButton.extended(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                onPressed: () async {
                  await _load();         
                  await _loadRewards();  
                },
                label: const Text('새로고침',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                icon: const Icon(Icons.refresh),
              ),
      ),
    );
  }

  /// 리스트 형태 UI
  Widget _buildList(List<NewsItem> items, {required String emptyLabel}) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: const TextStyle(color: Colors.white70)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final it = items[i];
        return Card(
          color: Colors.white.withValues(alpha: 0.06),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            leading:
                const Icon(Icons.play_circle_fill, color: Colors.white70),
            title: Text(
              it.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              '${it.outletName} · ${it.category}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            trailing:
                const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () => _goToItem(it),
          ),
        );
      },
    );
  }

  String _badgeTitle(String code) {
    switch (code) {
      case 'achv_news_explorer': return '뉴스 탐험가';
      case 'achv_daily_running': return '데일리 러닝';
      case 'achv_night_hunter':  return '심야 뉴스 헌터';
      case 'achv_news_maniac':   return '뉴스 마니아';
      case 'achv_quiz_master':   return '퀴즈 마스터';
      case 'achv_like_100':      return '공감의 달인';
      case 'achv_bookmark_100':  return '컬렉터';
      default: return code;
    }
  }

  String _badgeDescription(String code) {
    switch (code) {
      case 'achv_news_explorer': return '30일 연속 서로 다른 3개 카테고리에서 각 1개 이상 시청';
      case 'achv_daily_running': return '30일 연속 시청 5개 달성';
      case 'achv_night_hunter':  return '30일 연속 밤 12시~새벽 5시 사이 뉴스 시청 5개';
      case 'achv_news_maniac':   return '누적 시청 100회';
      case 'achv_quiz_master':   return '퀴즈 정답 누적 100회 (테스트=1회)';
      case 'achv_like_100':      return '좋아요 누적 100개 (테스트=1회)';
      case 'achv_bookmark_100':  return '찜 누적 100개';
      default: return '';
    }
  }

  IconData _badgeIcon(String code) {
    switch (code) {
      case 'achv_news_explorer': return Icons.public;
      case 'achv_daily_running': return Icons.calendar_today;
      case 'achv_night_hunter':  return Icons.nightlight_round;
      case 'achv_news_maniac':   return Icons.local_fire_department;
      case 'achv_quiz_master':   return Icons.school;
      case 'achv_like_100':      return Icons.thumb_up;
      case 'achv_bookmark_100':  return Icons.bookmark;
      default: return Icons.star_border;
    }
  }

  Widget _buildBadgeSection() {
    final cs = Theme.of(context).colorScheme;

    // 보유 배지 맵(code -> awardedAt)
    final owned = <String, DateTime>{};
    for (final b in _badges) {
      final c = (b['code'] as String?) ?? '';
      final atStr = (b['awarded_at'] as String?) ?? '';
      if (c.isEmpty) continue;
      DateTime? at;
      try { at = DateTime.tryParse(atStr); } catch (_) {}
      owned[c] = at ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    // 정렬: 보유 배지(최근순) → 미보유(카탈로그 순)
    final earned = kBadgeCatalog.where((d) => owned.containsKey(d.code)).toList()
      ..sort((a, b) => (owned[b.code]!).compareTo(owned[a.code]!));
    final locked = kBadgeCatalog.where((d) => !owned.containsKey(d.code)).toList();
    final all = [...earned, ...locked];

    Widget tile(BadgeDef def, {required bool active}) {
      final pts = badgePoints(def.code);
      final dt = owned[def.code];
      final dateStr = (active && dt != null)
          ? dt.toIso8601String().split('T').first
          : '';

      final card = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.10 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? cs.primary : Colors.white12,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _badgeIcon(def.code),
              size: 28,
              color: active ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 12),
            // 본문(제목/설명/포인트) — 여러 줄 허용
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.title,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white60,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    def.criteria,
                    // 잘림 방지: wrap 허용
                    softWrap: true,
                    style: TextStyle(
                      color: active ? Colors.white70 : Colors.white38,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '획득 시 +${pts}P',
                    style: TextStyle(
                      color: active ? Colors.white70 : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 우측 날짜
            if (active && dateStr.isNotEmpty)
              Text(
                dateStr,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
          ],
        ),
      );

      return active ? card : Opacity(opacity: 0.55, child: card);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('배지',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),

        if (all.isEmpty)
          const Text('표시할 배지가 없습니다.', style: TextStyle(color: Colors.white54))
        else
          Column(
            children: [
              for (final def in all) ...[
                tile(def, active: owned.containsKey(def.code)),
                const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }


  Widget _buildRewardsTab() {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        // (기존) 포인트 카드
        Card(
          color: Colors.white.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('내 포인트', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('$_totalPoints P', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                const Text('오늘 진행 상황', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _kv('시청 보상', '$_todayWatch / 5'),
                _kv('좋아요 보너스', '$_todayLikeAwards / 3'),
                _kv('퀴즈 정답', '$_todayQuizCorrect / 3'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // (기존) 상점 버튼
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.store_mall_directory_rounded),
            label: const Text('상점 가기'),
            onPressed: () async {
              await Navigator.of(context).push(
                _fadeSlideRoute(ShopScreen(initialPoints: _totalPoints)),
              );
              await _loadRewards();
              if (mounted) setState(() {});
            },
          ),
        ),

        const SizedBox(height: 16),

        // ✅ 새 배지 섹션
        _buildBadgeSection(),
      ],
    );
  }


  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(k, style: const TextStyle(color: Colors.white70)),
        const Spacer(),
        Text(v, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );

}

/// 빈 상태 위젯
class _EmptyCategory extends StatelessWidget {
  final String category;
  final VoidCallback onChangeCategory;
  const _EmptyCategory({required this.category, required this.onChangeCategory});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              '‘$category’ 카테고리의 쇼츠가 아직 없어요.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onChangeCategory,
              icon: const Icon(Icons.category_outlined),
              label: const Text('카테고리 다시 선택'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onPrimary,
                side: BorderSide(color: cs.primary),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4) 개별 페이지(동영상+메타)
class _NewsPage extends StatefulWidget {
  final NewsItem item;
  const _NewsPage({super.key, required this.item});

  @override
  State<_NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<_NewsPage> with SingleTickerProviderStateMixin {
  VideoPlayerController? _vc;           // ← nullable 로 변경
  Duration _dur = Duration.zero;
  Duration _pos = Duration.zero;

  bool get _ready => _vc != null && _vc!.value.isInitialized;

  double get progress {
    if (_dur.inMilliseconds == 0) return 0.0;
    return _pos.inMilliseconds / _dur.inMilliseconds;
  }

  bool _ctaVisible = false;  // 5초 전 CTA
  bool _quizOpened = false;
  bool _isScrubbing = false;
  bool _rewarded = false;

  bool _liked = false;
  bool _bookmarked = false;
  int _likeCountRemote = 0;
  int _shareCount = 0;

  bool _completedOnce = false;   // ✅ 이번 재생에서 '완료' 처리 1회만
  bool _rewardedToday = false;   // ✅ 오늘(로컬 날짜) 이 영상 보상 여부 캐시
  bool _snackShownOnce = false;  // ✅ 스낵바 1회만

  String _dailyKey(String uid, String itemUuid, DateTime nowLocal) {
    final y = nowLocal.year.toString().padLeft(4,'0');
    final m = nowLocal.month.toString().padLeft(2,'0');
    final d = nowLocal.day.toString().padLeft(2,'0');
    return 'watch_rewarded:$uid:$itemUuid:$y-$m-$d';
  }

  String _badgeLabel(String code) {
    switch (code) {
      case 'achv_like_100':     return '공감의 달인';
      case 'achv_bookmark_100': return '컬렉터';
      case 'achv_quiz_master':  return '퀴즈 마스터';
      case 'achv_news_explorer':return '뉴스 탐험가';
      case 'achv_daily_running':return '데일리 러닝';
      case 'achv_night_hunter': return '심야 뉴스 헌터';
      case 'achv_news_maniac':  return '뉴스 마니아';
      default:                  return code;
    }
  }

  // ── 2) 초기화/교체 로직 헬퍼 ───────────────────────────────────────────────
  void _onPlaybackCompletedOnce() {
    // 오늘 이미 보상 받았으면 아예 끝
    if (_rewardedToday) return;
    _awardWatchIfNeeded(); // 보상 시도 (성공 시에만 로컬 캐시 갱신)
  }

  Future<void> _initController(String url) async {
    final old = _vc;       // 이전 컨트롤러 보관
    _vc = null;            // 먼저 끊고
    await old?.dispose();  // 안전하게 해제

    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )
      ..setLooping(false)
      ..setVolume(1.0);

    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }

    // 리스너는 새 컨트롤러(c)에 부착
    c.addListener(() {
      if (!mounted) return;
      final v = c.value;
      _pos = v.position;
      _dur = v.duration;
      if (!_isScrubbing) {
        setState(() {}); // 진행바 등 갱신
        final remaining = (_dur - _pos).inSeconds;
        _maybeShowCTA(remainingSec: remaining);

        // 완료 시 포인트
        if (v.isInitialized && !v.isPlaying && _dur > Duration.zero && _pos >= _dur) {
          if (!_completedOnce) {
            _completedOnce = true;
            _onPlaybackCompletedOnce();
          }
        }
      }
    });

    setState(() {
      _vc = c;
      _dur = c.value.duration;
    });

    try {
      await c.play();
    } catch (_) {}
  }

  // ── 3) 라이프사이클에서 호출 ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (widget.item.videoUrl.isNotEmpty) {
      _initController(widget.item.videoUrl);
    }
    _loadMeta();
    _refreshShareCount();
    _loadRewardedToday(); // ✅ 추가
  }

  Future<void> _loadRewardedToday() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    final itemUuid = _dbItemId(widget.item.id);

    final prefs = await SharedPreferences.getInstance();
    final key = _dailyKey(uid, itemUuid, DateTime.now());
    final rewarded = prefs.getBool(key) ?? false;

    if (!mounted) return;
    setState(() {
      _rewardedToday = rewarded;   // ✅ 오늘 이미 보상 받았으면 true
    });
  }

  @override
  void didUpdateWidget(covariant _NewsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.videoUrl != widget.item.videoUrl) {
      // 새 영상으로 교체되면 재생 관련 1회성 플래그 리셋
      _completedOnce = false;
      _snackShownOnce = false;

      if (widget.item.videoUrl.isNotEmpty) {
        _initController(widget.item.videoUrl);
      } else {
        final old = _vc; _vc = null;
        old?.dispose();
        setState(() { _dur = Duration.zero; _pos = Duration.zero; });
      }

      // 새 영상의 '오늘 보상 받았는지' 상태도 로드
      _loadRewardedToday(); // ✅ 추가
    }
  }

  @override
  void dispose() {
    _vc?.dispose(); // ✅ null-safe
    super.dispose();
  }

  Future<void> _refreshShareCount() async {
    try {
      final id = _dbItemId(widget.item.id);     // ← UUID 변환
      final res = await sb.rpc('get_share_counts', params: {
        'p_item_ids': [id],
      });
      if (!mounted) return;
      if (res is List && res.isNotEmpty) {
        setState(() => _shareCount = (res.first['share_count'] as int?) ?? 0);
      } else {
        setState(() => _shareCount = 0);
      }
    } catch (_) {}
  }

  Future<bool> _ensureItemExists(String itemUuid) async {
    try {
      final exists = await sb
          .from('items')
          .select('id')
          .eq('id', itemUuid)
          .maybeSingle();

      if (exists != null) return true;

      await sb.from('items').insert({
        'id': itemUuid,
        'title': widget.item.title,
        'outlet_name': widget.item.outletName,
        'reporter': widget.item.reporter,
        'category': widget.item.category,
      });

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('items 등록 실패: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _loadMeta() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    final itemId = _dbItemId(widget.item.id);   // ← UUID 변환

    try {
      final likeRow = await sb
          .from('my_likes')
          .select('item_id')
          .eq('item_id', itemId)
          .maybeSingle();

      final bmRow = await sb
          .from('my_bookmarks')
          .select('item_id')
          .eq('item_id', itemId)
          .maybeSingle();

      final countRow = await sb
          .from('like_counts')
          .select('like_count')
          .eq('item_id', itemId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _liked = likeRow != null;
        _bookmarked = bmRow != null;
        _likeCountRemote = (countRow?['like_count'] as int?) ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) { return; }

    final itemUuid = _dbItemId(widget.item.id);
    if (!await _ensureItemExists(itemUuid)) return;

    final next = !_liked;
    setState(() {
      _liked = next;
      _likeCountRemote += next ? 1 : -1;
      if (_likeCountRemote < 0) _likeCountRemote = 0;
    });

    try {
      if (next) {
        await sb
            .from('likes')
            .upsert(
              {'user_id': uid, 'item_id': itemUuid},
              onConflict: 'user_id,item_id',
              ignoreDuplicates: true,
            )
            .select();
      } else {
        await sb.from('likes').delete().eq('user_id', uid).eq('item_id', itemUuid);
      }

      final countRow = await sb
          .from('like_counts')
          .select('like_count')
          .eq('item_id', itemUuid)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _likeCountRemote = (countRow?['like_count'] as int?) ?? 0);

      if (next) {
        try {
          final res = await sb.rpc('award_like_bonus', params: {'p_item_id': itemUuid}) as Map?;
          final gained = (res?['new_points'] ?? 0) as int;
          final badge  = (res?['badge_awarded'] as String?) ?? '';

          if (gained > 0 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('+1P 좋아요 보너스')),
            );
          }

          if (badge.isNotEmpty && mounted) {
            final label = _badgeLabel(badge);
            final pts = badgePoints(badge);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('🎖 $label 배지 획득! +${pts}P')),
            );
          }
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !next;
        _likeCountRemote += next ? -1 : 1;
        if (_likeCountRemote < 0) _likeCountRemote = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('좋아요 처리 실패: $e')),
      );
    }
  }

  Future<void> _toggleBookmark() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    final itemUuid = _dbItemId(widget.item.id);
    if (!await _ensureItemExists(itemUuid)) return;

    final next = !_bookmarked;
    setState(() => _bookmarked = next);

    try {
      if (next) {
        await sb.from('bookmarks').upsert(
          {'user_id': uid, 'item_id': itemUuid},
          onConflict: 'user_id,item_id',
          ignoreDuplicates: true,
        );
        try {
          final r = await sb.rpc('check_bookmark_badge') as Map?;
          final badge = (r?['badge_awarded'] as String?) ?? '';
          if (badge.isNotEmpty && mounted) {
            final label = _badgeLabel(badge);
            final pts = badgePoints(badge);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('🎖 $label 배지 획득! +${pts}P')),
            );
          }
        } catch (_) {}
      } else {
        await sb.from('bookmarks')
            .delete()
            .eq('user_id', uid)
            .eq('item_id', itemUuid);
      }
    } catch (e) {
      setState(() => _bookmarked = !next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('북마크 처리 실패: $e')),
      );
    }
  }

  Future<void> _shareNews() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final item = widget.item;
    final deepLink = 'shortkinds://item'
        '?id=${Uri.encodeComponent(item.id)}'
        '&cat=${Uri.encodeComponent(item.category)}';

    final shareText = '${item.title}\n$deepLink';

    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: shareText, subject: 'Short Kinds'),
      );

      if (result.status == ShareResultStatus.success) {
        final itemUuid = _dbItemId(item.id);
        if (!await _ensureItemExists(itemUuid)) return;

        await sb.from('shares').insert({
          'user_id': uid,
          'item_id': itemUuid,
          'channel': _shareChannelLabel(result),
        });
        await _refreshShareCount();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공유 완료!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유 실패: $e')),
      );
    }
  }

  Future<void> _awardWatchIfNeeded() async {
    // ① 오늘 이미 보상 받았으면 종료
    if (_rewardedToday) return;

    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    final itemUuid = _dbItemId(widget.item.id);
    if (!await _ensureItemExists(itemUuid)) return;

    try {
      final res = await sb.rpc('award_watch_complete', params: {
        'p_item_id': itemUuid,
      }) as Map?;

      final gained = (res?['new_points'] ?? 0) as int;

      // ② 서버가 보상 안 줬으면(=하루 한도/중복 등) 로컬 캐시만 맞춰주고 끝
      if (gained <= 0) {
        _rewardedToday = true;        // 서버상 이미 처리된 상태로 동기화
        return;
      }

      // ③ 여기로 왔다는 건 '오늘 처음' 보상 성공
      _rewardedToday = true;

      // 로컬에 '오늘 이 영상 보상 완료' 기록
      final prefs = await SharedPreferences.getInstance();
      final key = _dailyKey(uid, itemUuid, DateTime.now());
      await prefs.setBool(key, true);

      if (!mounted || _snackShownOnce) return;

      final w = (res?['watch'] ?? 0) as int;
      final s = (res?['streak5'] ?? 0) as int;

      final parts = <String>[];
      if (w > 0) parts.add('+${w}P 시청');
      if (s > 0) parts.add('+${s}P 연속 보너스');

      // ④ 스낵바도 1번만
      if (parts.isNotEmpty) {
        _snackShownOnce = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parts.join(' · '))),
        );
      }

      final badges = (res?['badges_awarded'] as List?)?.cast<String>() ?? const [];
      for (final b in badges) {
        if (!mounted) break;
        final pts = badgePoints(b);     // 위 맵에서 포인트 조회
        final label = _badgeLabel(b);   // 이미 있는 배지 한글명 매핑 함수 사용

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎖 $label 배지 획득! +${pts}P')),
        );
      }
    } catch (_) {}
  }


  String _shareChannelLabel(ShareResult result) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
        return 'android-share-sheet';
      case TargetPlatform.iOS:
        return 'ios-share-sheet';
      default:
        return 'system-share';
    }
  }

  // === 재생 제어 헬퍼들 (가드 추가) ===
  void _pausePlayback() async {
    _isScrubbing = true;
    if (_vc == null) return;
    await _vc!.pause();
  }

  Future<void> _seekToFraction(double v) async {
    if (_vc == null) return;
    final clamped = v.clamp(0.0, 1.0);
    if (_dur.inMilliseconds > 0) {
      final target = Duration(milliseconds: (_dur.inMilliseconds * clamped).round());
      await _vc!.seekTo(target);
      setState(() { /* _pos는 listener에서 갱신 */ });
      _maybeShowCTA(remainingSec: (_dur - target).inSeconds);
    }
  }

  void _resumePlayback() async {
    _isScrubbing = false;
    if (_vc == null) return;
    if (_pos >= _dur && _dur > Duration.zero) {
      await _vc!.seekTo(Duration.zero);
    }
    await _vc!.play();
  }

  void _maybeShowCTA({required int remainingSec}) {
    final q = widget.item.quiz;
    if (q == null || _quizOpened) return;
    if (remainingSec <= q.secondsBeforeEnd && !_ctaVisible) {
      setState(() => _ctaVisible = true);
    }
  }

  void _openQuiz() {
    final q = widget.item.quiz;
    if (q == null) return;

    setState(() {
      _ctaVisible = false;
      _quizOpened = true;
    });

    _showQuizDialog(context, q).then((_) {
      // 팝업 닫힘 후 다시 퀴즈를 열지 않도록 유지(필요하면 리셋 가능)
    });
  }

  Widget _clampTextScale(Widget child) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: const TextScaler.linear(1.0)),
      child: child,
    );
  }

  // ── 4) 빌드 가드 적용 ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: true,
      // 안전영역 + 최소 16px 더 띄우기
      minimum: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: _ready ? _vc!.value.aspectRatio : (9 / 16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_ready)
                    VideoPlayer(_vc!)
                  else
                    const ColoredBox(color: Colors.black),

                  if (!_ready || (_vc?.value.isBuffering ?? false))
                    const Positioned(child: CircularProgressIndicator()),

                  if (!_ready && widget.item.videoUrl.isEmpty)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: _clampTextScale(
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320), // ⬅️ 너무 넓지 않게
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Text(
                                '재생 URL이 없어 영상 미표시',           // or '서명된 스트림(토큰 필요) – 목록만 표시'
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,      // ⬅️ 두 줄로 자르고 말줄임
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // === 안내 배지 ②: 서명된 스트림(토큰 필요) ===
                  // CTA 배지보다 앞에 둡니다. (겹치지 않게 bottom 값을 조금 더 위로)
                  // NewsItem.playbackPolicy 를 추가했다면 아래 주석 해제
                  if (!_ready && widget.item.videoUrl.isNotEmpty && widget.item.playbackPolicy != 'public')
                    Positioned(
                      bottom: 44,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Text(
                          '서명된 스트림(토큰 필요) – 목록만 표시',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),

                  if (_ctaVisible && widget.item.quiz != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: (widget.item.quiz!.ctaTop ? null : 20),
                      top: (widget.item.quiz!.ctaTop ? 20 : null),
                      child: GestureDetector(
                        onTap: _openQuiz,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.quiz_outlined, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '퀴즈 풀러가시겠어요? (영상 종료 5초 전)',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                  maxLines: 2,
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _InteractiveSeekBar(
              progress: progress,
              height: 12,
              thumbRadius: 6,
              onChangeStart: _pausePlayback,
              onChanged: (v) => _seekToFraction(v),
              onChangeEnd: (v) => _resumePlayback(),
            ),
          ),

          const SizedBox(height: 6.0),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _toggleLike,
                  icon: Icon(_liked ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                      size: 22, color: Colors.white),
                ),
                const SizedBox(width: 2),
                Text('$_likeCountRemote',
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _toggleBookmark,
                  icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      size: 26, color: Colors.white),
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: _shareNews,
                  icon: const Icon(Icons.share, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 2),
                Text('$_shareCount',
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const Spacer(),
                Text(
                  '유사도 : ${widget.item.trustScore}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== 퀴즈 팝업 =====
  Future<void> _showQuizDialog(BuildContext context, QuizData quiz) {
    final cs = Theme.of(context).colorScheme;
    int? selected;
    bool submitted = false;

    return showGeneralDialog(
      context: context,
      barrierDismissible: !submitted,
      barrierLabel: 'quiz',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) {
        final size = MediaQuery.of(context).size;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setSt) {
                return Container(
                  width: size.width * 0.92,
                  constraints: BoxConstraints(
                    minHeight: 220,
                    maxHeight: size.height * 0.70,
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black26, width: 1.2),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          quiz.question,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                        ),
                        const SizedBox(height: 14),
                        for (int i = 0; i < quiz.options.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              onTap: submitted ? null : () => setSt(() => selected = i),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _choiceBorderColor(i, selected, submitted, quiz),
                                    width: 1.6,
                                  ),
                                  color: _choiceBgColor(i, selected, submitted, quiz),
                                ),
                                child: Row(
                                  children: [
                                    _ChoiceIndexBadge(
                                      indexLabel: '${i + 1}',
                                      activeColor: _choiceMarkerColor(i, selected, submitted, quiz, cs),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        quiz.options[i],
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: _choiceTextColor(i, selected, submitted, quiz),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: selected == null || submitted
                                    ? null
                                    : () async {
                                        setSt(() => submitted = true);
                                        if (selected == quiz.answerIndex) {
                                          try {
                                            final r = await sb.rpc('mark_quiz_correct') as Map?;
                                            final gained = (r?['new_points'] ?? 0) as int;
                                            final today = (r?['today_quiz_correct'] ?? 0) as int;
                                            final bonus = (r?['bonus_awarded'] ?? false) as bool;
                                            final badge = (r?['badge_awarded'] as String?) ?? '';

                                            if (mounted) {
                                              if (gained > 0) {
                                                final msg = bonus
                                                    ? '+${gained}P 퀴즈 정답(+5 보너스) · 오늘 $today/3'
                                                    : '+${gained}P 퀴즈 정답 · 오늘 $today/3';
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('오늘 퀴즈 보상(3회) 한도에 도달했습니다.')),
                                                );
                                              }
                                              if (badge.isNotEmpty) {
                                                final pts   = badgePoints(badge);     // 예: achv_quiz_master -> 150 등
                                                final label = badgeName(badge);       // '퀴즈 마스터' 등
                                                final text  = pts > 0
                                                    ? '🎖 $label 배지 획득! +${pts}P'
                                                    : '🎖 $label 배지 획득!';
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
                                              }
                                            }
                                          } catch (_) {}
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                child: const Text('제출'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.black87,
                                  side: const BorderSide(color: Colors.black26),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                child: Text(submitted ? '닫기' : '취소'),
                              ),
                            ),
                          ],
                        ),
                        if (submitted) ...[
                          const SizedBox(height: 12),
                          Text(
                            selected == quiz.answerIndex ? '정답입니다! 🎉' : '오답입니다. 정답은 ${quiz.answerIndex + 1}번이에요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected == quiz.answerIndex ? Colors.green[700] : Colors.red[700],
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  // === 보기 색상 헬퍼들 ===
  Color _choiceBorderColor(int i, int? selected, bool submitted, QuizData q) {
    if (!submitted) {
      return (selected == i) ? Colors.black87 : Colors.black26;
    }
    if (i == q.answerIndex) return Colors.green;
    if (selected == i && i != q.answerIndex) return Colors.red;
    return Colors.black26;
  }

  Color _choiceBgColor(int i, int? selected, bool submitted, QuizData q) {
    if (!submitted) return Colors.white;
    if (i == q.answerIndex) return Colors.green.withValues(alpha: 0.08);
    if (selected == i && i != q.answerIndex) return Colors.red.withValues(alpha: 0.08);
    return Colors.white;
  }

  Color _choiceTextColor(int i, int? selected, bool submitted, QuizData q) {
    if (!submitted) return Colors.black87;
    if (i == q.answerIndex) return Colors.green[800]!;
    if (selected == i && i != q.answerIndex) return Colors.red[800]!;
    return Colors.black87;
  }
}



class _InteractiveSeekBar extends StatelessWidget {
  final double progress;                     // 0.0 ~ 1.0
  final VoidCallback? onChangeStart;         // 제스처 시작(일시정지)
  final ValueChanged<double>? onChanged;     // 이동 중(실시간 위치)
  final ValueChanged<double>? onChangeEnd;   // 손 뗌/취소(자동재생 확정)
  final double height;
  final double thumbRadius;

  const _InteractiveSeekBar({
    super.key,
    required this.progress,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
    this.height = 14,
    this.thumbRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final p = progress.clamp(0.0, 1.0);
        final w = constraints.maxWidth;
        final filledW = w * p;

        double _toValue(Offset localPos) =>
            (localPos.dx / w).clamp(0.0, 1.0).toDouble();

        double? lastV;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,

          // 단일 흐름: Pan 계열만 사용 (탭/드래그 모두 커버)
          onPanDown: (d) {
            onChangeStart?.call();                 // 일시정지
            final v = _toValue(d.localPosition);   // 즉시 위치 반영
            lastV = v;
            onChanged?.call(v);
          },
          onPanUpdate: (d) {
            final v = _toValue(d.localPosition);
            lastV = v;
            onChanged?.call(v);                    // 실시간 위치 갱신
          },
          onPanEnd: (_) {
            onChangeEnd?.call(lastV ?? p);         // 손 뗌 → 자동재생
          },
          onPanCancel: () {
            onChangeEnd?.call(lastV ?? p);         // 취소돼도 자동재생
          },

          child: SizedBox(
            height: height,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 트랙 배경
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                // 진행된 구간
                Container(
                  width: filledW,
                  height: height,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                // 손잡이(thumb)
                Positioned(
                  left: (filledW - thumbRadius)
                      .clamp(0.0, w - thumbRadius * 2)
                      .toDouble(),
                  child: Container(
                    width: thumbRadius * 2,
                    height: thumbRadius * 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class _ChoiceIndexBadge extends StatelessWidget {
  final String indexLabel;
  final Color activeColor;
  const _ChoiceIndexBadge({required this.indexLabel, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: activeColor, width: 1.5),
      ),
      child: Text(
        indexLabel,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: activeColor,
        ),
      ),
    );
  }
}

Color _choiceMarkerColor(int i, int? selected, bool submitted, QuizData q, ColorScheme cs) {
  if (!submitted) return (selected == i) ? cs.primary : Colors.black54;
  if (i == q.answerIndex) return Colors.green[700]!;
  if (selected == i && i != q.answerIndex) return Colors.red[700]!;
  return Colors.black54;
}

class _EndOfCategoryPage extends StatelessWidget {
  final String category;
  final VoidCallback onChangeCategory;
  const _EndOfCategoryPage({
    required this.category,
    required this.onChangeCategory,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 56, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                '‘$category’ 카테고리의 쇼츠를 모두 보셨어요!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '다른 카테고리를 선택해 보실래요?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  icon: const Icon(Icons.category_rounded),
                  label: const Text('카테고리 다시 선택'),
                  onPressed: onChangeCategory,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class SignInScreen extends StatefulWidget {
  final bool showSplashAfterLogin;
  const SignInScreen({super.key, this.showSplashAfterLogin = true});
  
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _loading = false;
  String? _err;

  Future<void> _run(Future<void> Function() f) async {
    setState(() { _loading = true; _err = null; });
    try { await f(); }
    catch (e) { setState(() => _err = '$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              color: Colors.white,
              margin: const EdgeInsets.all(20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('로그인', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '이메일'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pw,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '비밀번호'),
                    ),
                    const SizedBox(height: 16),
                    if (_err != null)
                      Text(_err!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _loading ? null : () => _run(() async {
                              await sb.auth.signInWithPassword(
                                email: _email.text.trim(),
                                password: _pw.text,
                              );
                              if (!mounted) return;
                              if (widget.showSplashAfterLogin) {
                                Navigator.of(context).pushReplacement(_fadeSlideRoute(const SplashScreen()));
                              } else {
                                Navigator.of(context).pop(true); // ⬅️ 호출한 화면(기사)로 복귀
                              }
                            }),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
                            child: _loading ? const SizedBox(height:20, width:20, child:CircularProgressIndicator(strokeWidth:2))
                                           : const Text('로그인'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : () => _run(() async {
                              await sb.auth.signUp(
                                email: _email.text.trim(),
                                password: _pw.text,
                              );
                              if (!mounted) return;
                              if (widget.showSplashAfterLogin) {
                                Navigator.of(context).pushReplacement(_fadeSlideRoute(const SplashScreen()));
                              } else {
                                Navigator.of(context).pop(true);
                              }
                            }),
                            child: const Text('회원가입'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// 블롭 클리퍼 (온보딩용)
class _BlobClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(0.05 * w, 0.45 * h)
      ..cubicTo(0.00 * w, 0.10 * h, 0.40 * w, -0.05 * h, 0.62 * w, 0.10 * h)
      ..cubicTo(0.85 * w, 0.25 * h, 1.05 * w, 0.20 * h, 0.98 * w, 0.46 * h)
      ..cubicTo(0.92 * w, 0.72 * h, 0.72 * w, 0.95 * h, 0.48 * w, 0.90 * h)
      ..cubicTo(0.28 * w, 0.86 * h, 0.10 * w, 0.72 * h, 0.05 * w, 0.45 * h)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// ─────────────────────────────────────────────────────────────
/// 상점 화면: 포인트로 아이템 구매
/// - 서버에 Supabase RPC 'purchase_shop_item' 필요
///   기대 파라미터: { p_item_code: text, p_price: int }
///   기대 반환: { new_points: int, purchased_id: uuid? } 형태의 Map
/// ─────────────────────────────────────────────────────────────

class ShopItem {
  final String code;
  final String name;
  final int price;
  final String? imageAsset; // 나중에 네트워크 이미지 연결 시 사용
  const ShopItem({required this.code, required this.name, required this.price, this.imageAsset,});
}

class ShopScreen extends StatefulWidget {
  final int initialPoints;
  const ShopScreen({super.key, required this.initialPoints});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _points = 0;
  bool _busy = false;

  // 요청된 두 가지 항목
  final List<ShopItem> _items = const [
    ShopItem(code:'ice_ame',              name:'아이스 아메리카노', price:2000,  imageAsset:'assets/shop/ice_americano.jpg'),
    ShopItem(code:'gift_culture_10000',   name:'문화상품권 5000원권', price:5000,  imageAsset:'assets/shop/culture_land.jpg'),
    ShopItem(code:'burger_set_7000',      name:'햄버거 세트',     price:7000,  imageAsset:'assets/shop/hamburger.jpg'),
    ShopItem(code:'movie_ticket_15000',   name:'영화 관람권',     price:15000, imageAsset:'assets/shop/cinema.jpg'),
    ShopItem(code:'donation_child_1000',  name:'아동복지재단 후원', price:1000,  imageAsset:'assets/shop/kid.png'),
    ShopItem(code:'test_1p',              name:'test',           price:1,     imageAsset:'assets/shop/exam.png'),
  ];

  @override
  void initState() {
    super.initState();
    _points = widget.initialPoints;
    _refreshPoints(); // 최신값 동기화
  }

  Future<void> _refreshPoints() async {
    try {
      final m = await sb.rpc('get_rewards_summary') as Map?;
      if (!mounted || m == null) return;
      setState(() => _points = (m['total_points'] ?? _points) as int);
    } catch (_) {
      // 무시: 초기 접속 시에도 상점은 동작해야 하므로 조용히 패스
    }
  }

  Future<void> _confirmAndBuy(ShopItem it) async {
    final cs = Theme.of(context).colorScheme;
    if (_busy) return;

    if (_points < it.price) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('포인트가 부족합니다.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('구매 확인'),
        content: Text('‘${it.name}’을(를) ${it.price}P로 구매하시겠습니까?\n보유 포인트: $_points P'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('구매'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await _buy(it);
  }

  Future<void> _buy(ShopItem it) async {
    setState(() => _busy = true);
    try {
      // ★ 서버 RPC 호출 (미구현 시 서버에서 생성 필요)
      final res = await sb.rpc('purchase_shop_item', params: {
        'p_item_code': it.code,
        'p_price': it.price,
      }) as Map?;

      // 기대: { new_points: int, purchased_id: uuid? }
      final newPoints = (res?['new_points'] as int?) ?? -1;
      if (newPoints >= 0) {
        if (!mounted) return;
        setState(() => _points = newPoints);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('구매 완료! -${it.price}P  (잔여: $newPoints P)')),
        );
      } else {
        // RPC 반환형이 다르거나 null인 경우 → 포인트만 재조회
        await _refreshPoints();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매 처리 완료(포인트 갱신됨)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('구매 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _fallbackThumb() => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24, width: 1),
    ),
    alignment: Alignment.center,
    child: const Icon(Icons.image, color: Colors.white54),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(
                _fadeSlideRoute(CategorySelectScreen(categories: kCategories)),
              );
            }
          },
        ),
        title: const Text('상점', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // 보유 포인트 카드
          Card(
            color: Colors.white.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: cs.primary, size: 28),
                  const SizedBox(width: 12),
                  const Text('보유 포인트', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$_points P',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 상점 아이템들
          for (final it in _items) ...[
            Card(
              color: Colors.white.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: (it.imageAsset == null)
                        ? _fallbackThumb()
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              it.imageAsset!,            // 예: 'assets/shop/ice_americano.jpg'
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _fallbackThumb(),
                            ),
                          ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text('${it.price} P',
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: (_busy || _points < it.price) ? null : () => _confirmAndBuy(it),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                          return states.contains(WidgetState.disabled)
                              ? Colors.grey.shade700    // 비활성화 배경
                              : cs.primary;             // 활성화 배경
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                          return states.contains(WidgetState.disabled)
                              ? Colors.white54          // ⬅️ 비활성화일 때 '구매' 글씨 흐리게
                              : cs.onPrimary;           // 활성화 글씨
                        }),
                        shape: const WidgetStatePropertyAll(
                          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        ),
                        textStyle: const WidgetStatePropertyAll(
                          TextStyle(fontWeight: FontWeight.w800),
                        ),
                        minimumSize: const WidgetStatePropertyAll(Size(84, 40)),
                      ),
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('구매'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
