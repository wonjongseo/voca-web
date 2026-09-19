import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ads/ads_controller.dart';
import '../ads/banner_slot.dart';
import '../domain/vocabulary.dart';
import '../services/csv_transfer.dart';
import '../services/pronunciation.dart';
import '../state/leafy_controller.dart';
import 'quiz_screen.dart';
import 'word_editor.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.ads});
  final LeafyController controller;
  final AdsController ads;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  String search = '', filter = '전체', category = '전체', studyScope = '오늘 복습';
  int quizSize = 10;
  bool quizActive = false;
  final speech = Pronunciation();
  LeafyController get c => widget.controller;
  @override
  void dispose() {
    speech.stop();
    super.dispose();
  }

  Future<void> action(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<String?> prompt(
    String title, {
    String initial = '',
    bool secret = false,
  }) async {
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          obscureText: secret,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
    // Dialog close animation can still access its controller; let the widget go first.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    return result;
  }

  Future<void> edit([VocabWord? word]) async {
    final updated = await editWord(context, word: word);
    if (updated != null) await action(() => c.save(updated));
  }

  Future<void> login() async {
    final result =
        await showDialog<({String email, String password, bool register})>(
          context: context,
          builder: (_) => const _LoginDialog(),
        );
    if (result != null) {
      await action(
        () =>
            c.signIn(result.email, result.password, register: result.register),
      );
    }
  }

  Future<void> detail(VocabWord word) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(word.word),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.meanings.join('\n'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              for (final example
                  in (word.data['examples'] as List? ??
                      [
                        {
                          'text': word.text('example'),
                          'translation': word.text('translation'),
                        },
                      ])) ...[
                Text(example['text'] as String),
                Text(
                  example['translation'] as String,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
              ],
              Text('유의어: ${word.text('synonyms')}'),
              Text(word.text('memo')),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => action(() => speech.speak(word.word, c.accent)),
          icon: const Icon(Icons.volume_up),
          tooltip: '발음 듣기',
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, widget.ads]),
    builder: (context, _) {
      final categories = {
        ...c.book.categories,
        ...c.book.words
            .map((w) => w.text('category'))
            .where((s) => s.isNotEmpty),
      }.toList()..sort();
      return Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.eco, color: Color(0xff386b50)),
              SizedBox(width: 8),
              Text('Leafy'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: c.busy ? null : () => c.selectScope(c.groupId),
              icon: const Icon(Icons.refresh),
              tooltip: '단어장 새로고침',
            ),
            IconButton(
              onPressed: () => setState(() => tab = 4),
              icon: Icon(
                c.user == null
                    ? Icons.person_outline
                    : Icons.cloud_done_outlined,
              ),
              tooltip: '계정과 설정',
            ),
          ],
        ),
        body: Column(
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null)
              MaterialBanner(
                content: Text(c.error!),
                actions: [
                  TextButton(
                    onPressed: c.busy ? null : () => c.selectScope(c.groupId),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                    children: [
                      Text(
                        ['나의 단어장', '오늘의 학습', '오답노트', '학습 기록', '계정과 설정'][tab],
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.user == null
                            ? '이 기기에 저장되는 나만의 단어장'
                            : c.groupId == null
                            ? '내 계정의 클라우드 단어장'
                            : '그룹 단어장 · ${c.groupId}',
                      ),
                      const SizedBox(height: 24),
                      if (tab == 0 || tab == 2) ..._words(categories),
                      if (tab == 1) ..._study(categories),
                      if (tab == 3) ..._statistics(),
                      if (tab == 4) ..._settings(),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.ads.ready && !quizActive)
              BannerSlot(key: ValueKey(widget.ads.bannerId), ads: widget.ads),
          ],
        ),
        floatingActionButton: tab == 0 && c.loaded
            ? FloatingActionButton.extended(
                onPressed: c.busy ? null : () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('단어 추가'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (value) => setState(() => tab = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: '단어장',
            ),
            NavigationDestination(
              icon: Icon(Icons.layers_outlined),
              label: '학습',
            ),
            NavigationDestination(icon: Icon(Icons.replay), label: '오답'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: '기록'),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: '설정',
            ),
          ],
        ),
      );
    },
  );
  List<Widget> _words(List<String> categories) {
    final words =
        c.book.words
            .where(
              (w) =>
                  (tab != 2 || c.wrongIds.contains(w.id)) &&
                  (filter != '즐겨찾기' || w.favorite) &&
                  (filter != '복습' || c.due.any((d) => d.id == w.id)) &&
                  (filter != '익숙한 단어' || w.level >= 4) &&
                  (category == '전체' || w.text('category') == category) &&
                  '${w.word} ${w.meaning} ${w.text('memo')}'
                      .toLowerCase()
                      .contains(search.toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.data['created'] as num).compareTo(a.data['created'] as num),
          );
    return [
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '단어, 뜻, 메모 검색',
        ),
        onChanged: (value) => setState(() => search = value),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          for (final value in ['전체', '즐겨찾기', '복습', '익숙한 단어'])
            FilterChip(
              label: Text(value),
              selected: filter == value,
              onSelected: (_) => setState(() => filter = value),
            ),
        ],
      ),
      DropdownButton<String>(
        value: categories.contains(category) ? category : '전체',
        isExpanded: true,
        items: ['전체', ...categories]
            .map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(s == '전체' ? '모든 카테고리' : s),
              ),
            )
            .toList(),
        onChanged: (s) => setState(() => category = s!),
      ),
      Text('${words.length}개의 단어'),
      const SizedBox(height: 12),
      if (words.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '아직 단어가 없어요. 새 단어를 추가하거나 CSV를 가져오세요.',
            textAlign: TextAlign.center,
          ),
        ),
      for (final word in words)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => detail(word),
                        child: Text(
                          word.word,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          action(() => speech.speak(word.word, c.accent)),
                      tooltip: '발음 듣기',
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                    IconButton(
                      onPressed: c.busy || !c.loaded
                          ? null
                          : () => action(
                              () => c.save(
                                word.copy({'favorite': !word.favorite}),
                              ),
                            ),
                      tooltip: '즐겨찾기',
                      icon: Icon(
                        word.favorite ? Icons.star : Icons.star_border,
                        color: word.favorite ? Colors.amber.shade800 : null,
                      ),
                    ),
                    PopupMenuButton<String>(
                      enabled: c.loaded && !c.busy,
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await edit(word);
                        } else {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('${word.word} 삭제'),
                              content: const Text('이 단어를 삭제할까요?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('취소'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('삭제'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await action(() => c.delete(word.id));
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('수정')),
                        PopupMenuItem(value: 'delete', child: Text('삭제')),
                      ],
                    ),
                  ],
                ),
                Text(word.meaning),
                if (word.text('example').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      word.text('example'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${word.text('category')}  ·  ${word.level >= 4
                      ? '익숙해요'
                      : word.level > 0
                      ? '학습 중'
                      : '새 단어'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff386b50),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _study(List<String> categories) => [
    Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('기억이 흐려지기 전에,', style: Theme.of(context).textTheme.titleLarge),
            Text('오늘의 ${c.due.length}개 단어를 만나볼까요?'),
            const SizedBox(height: 12),
            const Text('조금씩, 매일, 꾸준히.'),
          ],
        ),
      ),
    ),
    SwitchListTile(
      title: const Text('정답 확인 후 발음 자동 듣기'),
      value: c.autoSpeak,
      onChanged: (v) => action(() => c.setAutoSpeak(v)),
    ),
    DropdownButton<String>(
      isExpanded: true,
      value:
          [
            '오늘 복습',
            '전체',
            '즐겨찾기',
            '오답',
            ...categories.map((s) => '카테고리:$s'),
          ].contains(studyScope)
          ? studyScope
          : '오늘 복습',
      items: [
        '오늘 복습',
        '전체',
        '즐겨찾기',
        '오답',
        ...categories.map((s) => '카테고리:$s'),
      ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: (s) => setState(() => studyScope = s!),
    ),
    DropdownButton<int>(
      value: quizSize,
      items: [5, 10, 20, 30, 99999]
          .map(
            (n) => DropdownMenuItem(
              value: n,
              child: Text(n == 99999 ? '전체 문제' : '$n문제'),
            ),
          )
          .toList(),
      onChanged: (n) => setState(() => quizSize = n!),
    ),
    for (final mode in QuizMode.values)
      Card(
        child: ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(modeNames[mode]!),
          trailing: const Icon(Icons.chevron_right),
          enabled: !c.busy && c.loaded,
          onTap: () async {
            var words = c.book.words
                .where(
                  (w) => switch (studyScope) {
                    '오늘 복습' => c.due.any((d) => d.id == w.id),
                    '즐겨찾기' => w.favorite,
                    '오답' => c.wrongIds.contains(w.id),
                    _ =>
                      !studyScope.startsWith('카테고리:') ||
                          w.text('category') == studyScope.substring(5),
                  },
                )
                .toList();
            if (mode == QuizMode.context) {
              words = words
                  .where(
                    (w) => w
                        .text('example')
                        .toLowerCase()
                        .contains(w.word.toLowerCase()),
                  )
                  .toList();
            }
            words.shuffle();
            if (words.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('이 범위에서 학습할 단어가 없습니다.')),
              );
              return;
            }
            setState(() => quizActive = true);
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => QuizScreen(
                  controller: c,
                  words: words.take(quizSize).toList(),
                  mode: mode,
                ),
              ),
            );
            if (mounted) setState(() => quizActive = false);
          },
        ),
      ),
  ];
  List<Widget> _statistics() {
    final reviews = c.book.reviews;
    final correct = reviews.where((r) => r['correct'] == true).length;
    return [
      Text(
        '총 ${c.book.words.length}단어 · ${reviews.length}회 복습',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        '정답률 ${reviews.isEmpty ? 0 : (correct / reviews.length * 100).round()}%',
      ),
      const SizedBox(height: 24),
      const Text('최근 7일'),
      for (var i = 6; i >= 0; i--)
        Builder(
          builder: (context) {
            final day = dateKey(DateTime.now().subtract(Duration(days: i)));
            final count = reviews.where((r) => r['date'] == day).length;
            return ListTile(title: Text(day), trailing: Text('$count회'));
          },
        ),
      if (c.user != null) const Text('클라우드 학습 기록은 최근 2,000건을 기준으로 표시합니다.'),
    ];
  }

  List<Widget> _settings() => [
    if (c.auth == null)
      const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('현재 게스트 모드입니다. Firebase 설정 후 로그인과 그룹 공유를 사용할 수 있어요.'),
        ),
      ),
    if (c.auth != null && c.user == null) ...[
      FilledButton(
        onPressed: c.busy ? null : login,
        child: const Text('이메일 로그인 / 회원가입'),
      ),
      OutlinedButton(
        onPressed: c.busy ? null : () => action(c.googleSignIn),
        child: const Text('Google 로그인'),
      ),
    ],
    if (c.user != null) ...[
      ListTile(
        title: Text(c.user!.email ?? '로그인됨'),
        subtitle: const Text('내 UID 복사 · 그룹 초대에 사용'),
        trailing: const Icon(Icons.copy),
        onTap: () => Clipboard.setData(ClipboardData(text: c.user!.uid)),
      ),
      OutlinedButton(
        onPressed: c.busy ? null : () => action(() => c.auth!.signOut()),
        child: const Text('로그아웃'),
      ),
      const Divider(),
      const Text('그룹 단어장'),
      OutlinedButton(
        onPressed: c.busy ? null : () => c.selectScope(),
        child: const Text('내 단어장으로 전환'),
      ),
      OutlinedButton(
        onPressed: c.busy
            ? null
            : () async {
                final name = await prompt('새 그룹 이름');
                if (name != null) {
                  await action(() async {
                    await c.createGroup(name);
                  });
                }
              },
        child: const Text('그룹 만들기'),
      ),
      OutlinedButton(
        onPressed: c.busy
            ? null
            : () async {
                final id = await prompt('초대받은 그룹 ID');
                if (id != null && !id.contains('/')) await c.selectScope(id);
              },
        child: const Text('그룹 열기'),
      ),
      if (c.groupId != null) ...[
        ListTile(
          title: Text(c.groupId!),
          subtitle: const Text('그룹 ID 복사'),
          onTap: () => Clipboard.setData(ClipboardData(text: c.groupId!)),
        ),
        OutlinedButton(
          onPressed: c.busy
              ? null
              : () async {
                  final uid = await prompt('초대할 사용자의 UID');
                  if (uid != null) await action(() => c.addMember(uid));
                },
          child: const Text('멤버 추가 (소유자)'),
        ),
      ],
    ],
    const Divider(),
    const Text('발음'),
    DropdownButton<String>(
      value: c.accent,
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'en-US', child: Text('미국 영어')),
        DropdownMenuItem(value: 'en-GB', child: Text('영국 영어')),
      ],
      onChanged: (value) => action(() => c.setAccent(value!)),
    ),
    SwitchListTile(
      title: const Text('정답 확인 후 발음 자동 듣기'),
      value: c.autoSpeak,
      onChanged: (v) => action(() => c.setAutoSpeak(v)),
    ),
    const Divider(),
    const Text('단어장 관리'),
    OutlinedButton(
      onPressed: c.busy || !c.loaded
          ? null
          : () => action(() async {
              final name = await prompt('추가할 카테고리');
              if (name != null) {
                await c.categories({...c.book.categories, name}.toList());
              }
            }),
      child: const Text('카테고리 추가'),
    ),
    OutlinedButton(
      onPressed: c.busy || !c.loaded
          ? null
          : () => action(() async {
              final words = await CsvTransfer().importWords();
              var count = 0;
              try {
                for (final word in words) {
                  await c.save(word);
                  count++;
                }
              } finally {
                if (mounted && words.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${words.length}개 중 $count개 가져왔습니다.'),
                    ),
                  );
                }
              }
            }),
      child: const Text('웹 단어장 CSV 가져오기'),
    ),
    OutlinedButton(
      onPressed: c.book.words.isEmpty
          ? null
          : () => action(() => CsvTransfer().exportWords(c.book.words)),
      child: const Text('CSV 내보내기'),
    ),
    if (widget.ads.privacyRequired)
      OutlinedButton(
        onPressed: () => action(widget.ads.privacyOptions),
        child: const Text('광고 개인정보 설정'),
      ),
    const SizedBox(height: 24),
    const Text('Leafy · 작은 단어가 만드는 큰 변화', textAlign: TextAlign.center),
  ];
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(register ? '회원가입' : '로그인'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '이메일'),
            validator: (v) =>
                v != null && v.contains('@') ? null : '이메일을 입력해주세요.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
            validator: (v) => (v?.length ?? 0) >= 6 ? null : '6자 이상 입력해주세요.',
          ),
          SwitchListTile(
            title: const Text('새 계정 만들기'),
            value: register,
            onChanged: (v) => setState(() => register = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, (
              email: email.text,
              password: password.text,
              register: register,
            ));
          }
        },
        child: const Text('계속'),
      ),
    ],
  );
}
