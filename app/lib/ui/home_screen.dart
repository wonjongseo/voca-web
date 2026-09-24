import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';

import '../ads/ads_controller.dart';
import '../ads/banner_slot.dart';
import '../domain/quiz_logic.dart';
import '../domain/vocabulary.dart';
import '../services/csv_transfer.dart';
import '../services/pronunciation.dart';
import '../state/leafy_controller.dart';
import '../state/theme_controller.dart';
import 'app_theme.dart';
import 'quiz_screen.dart';
import 'word_editor.dart';

class _HomeUiController extends GetxController {
  int tab = 0;
  String search = '';
  String filter = '전체';
  String category = '전체';
  String studyScope = '오늘 복습';
  final Set<String> studyCategories = <String>{};
  int quizSize = 10;
  bool quizActive = false;
  int wordPage = 1;

  void mutate(VoidCallback action) {
    action();
    update();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.ads});

  final LeafyController controller;
  final AdsController ads;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ui = _HomeUiController();

  int get tab => _ui.tab;
  set tab(int value) => _ui.tab = value;
  String get search => _ui.search;
  set search(String value) => _ui.search = value;
  String get filter => _ui.filter;
  set filter(String value) => _ui.filter = value;
  String get category => _ui.category;
  set category(String value) => _ui.category = value;
  String get studyScope => _ui.studyScope;
  set studyScope(String value) => _ui.studyScope = value;
  int get quizSize => _ui.quizSize;
  set quizSize(int value) => _ui.quizSize = value;
  bool get quizActive => _ui.quizActive;
  set quizActive(bool value) => _ui.quizActive = value;

  // WEB_PARITY_BOTTOM_ONLY_PAGINATION_V5
  static const int wordPageSize = 24;
  int get wordPage => _ui.wordPage;
  set wordPage(int value) => _ui.wordPage = value;

  final speech = Pronunciation();

  LeafyController get c => widget.controller;

  String _studyCategorySummary(Iterable<String> values) {
    final list = values.toList();
    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return '${list.first} 외 ${list.length - 1}개';
  }


  static const titles = ['나의 단어장', '오늘의 학습', '오답노트', '학습 기록', '계정과 설정'];

  static const subtitles = [
    '모은 단어를 검색하고 정리해요.',
    '오늘 기억할 만큼만 가볍게 시작해요.',
    '틀린 단어를 다시 만나 확실히 익혀요.',
    '쌓인 학습 기록을 한눈에 확인해요.',
    '동기화, 발음, 그룹과 단어장을 관리해요.',
  ];

  @override
  void dispose() {
    speech.stop();
    super.dispose();
  }

  Future<void> action(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<String?> prompt(String title) async {
    final input = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = input.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    input.dispose();

    return result;
  }


  Future<void> _selectMultipleStudyCategories(
    List<String> categories,
  ) async {
    final selected = Set<String>.of(_ui.studyCategories);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: AlertDialog(
          title: const Text('학습할 카테고리 선택'),
          content: SizedBox(
            width: 420,
            child: categories.isEmpty
                ? const Text('선택할 카테고리가 없습니다.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final value in categories)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(value),
                            value: selected.contains(value),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selected.add(value);
                                } else {
                                  selected.remove(value);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: Text('선택 완료 (${selected.length})'),
            ),
          ],
                  ),
        ),
      ),
    );

    if (result == null || !mounted) return;

    _ui.mutate(() {
      _ui.studyCategories
        ..clear()
        ..addAll(result);
      studyScope = '복수 카테고리';
    });
  }

  Future<void> edit([VocabWord? word]) async {
    final updated = await editWord(context, word: word);
    if (updated != null) {
      await action(() => c.save(updated));
    }
  }

  Future<void> login() async {
    final result =
        await showDialog<({String email, String password, bool register})>(
          context: context,
          builder: (_) => _LoginDialog(_ui),
        );

    if (result == null) return;

    await action(
      () => c.signIn(result.email, result.password, register: result.register),
    );
  }

  Future<void> detail(VocabWord word) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        word.word,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () =>
                          action(() => speech.speak(word.word, c.accent)),
                      icon: Icon(Icons.volume_up_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final meaning in word.meanings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      meaning,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                if (word.examples.isNotEmpty) ...[
                  const Divider(),
                  const _MiniTitle('예문'),
                  for (final example in word.examples)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((example['text'] ?? '').isNotEmpty)
                            Text(
                              example['text']!,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          if ((example['translation'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              example['translation']!,
                              style: TextStyle(color: LeafyTheme.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
                if (word.synonymEntries.isNotEmpty) ...[
                  const Divider(),
                  const _MiniTitle('유의어'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: word.synonymEntries
                        .map((value) => Chip(label: Text(value)))
                        .toList(),
                  ),
                ],
                if (word.text('memo').trim().isNotEmpty) ...[
                  const Divider(),
                  const _MiniTitle('메모'),
                  Text(word.text('memo')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LeafyController>(
      init: c,
      global: false,
      builder: (_) => GetBuilder<AdsController>(
        init: widget.ads,
        global: false,
        builder: (_) => GetBuilder<_HomeUiController>(
          init: _ui,
          global: false,
          builder: (_) {
            final categories = <String>{
              ...c.book.categories,
              ...c.book.words
                  .map((word) => word.category)
                  .where((value) => value.isNotEmpty),
            }.toList()..sort();

            return Scaffold(
              appBar: AppBar(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.eco_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      'Leafy',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    onPressed: c.busy ? null : c.refreshScope,
                    tooltip: '클라우드에서 새로고침',
                    icon: Icon(Icons.sync_rounded),
                  ),
                  IconButton(
                    onPressed: () => _ui.mutate(() => tab = 4),
                    tooltip: '계정과 설정',
                    icon: Icon(
                      c.user == null
                          ? Icons.person_outline_rounded
                          : Icons.cloud_done_outlined,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
              body: Column(
                children: [
                  if (c.busy) const LinearProgressIndicator(minHeight: 2),
                  if (c.error != null)
                    MaterialBanner(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      content: Text(c.error!),
                      actions: [
                        TextButton(
                          onPressed: c.busy ? null : c.refreshScope,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: RefreshIndicator(
                          onRefresh: c.refreshScope,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 20, 18, 122),
                            children: [
                              _header(),
                              const SizedBox(height: 10),
                              if (tab == 0)
                                ..._words(categories, wrongOnly: false),
                              if (tab == 1) ..._study(categories),
                              if (tab == 2)
                                ..._words(categories, wrongOnly: true),
                              if (tab == 3) ..._statistics(),
                              if (tab == 4) ..._settings(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.ads.ready && !quizActive)
                    BannerSlot(
                      key: ValueKey(widget.ads.bannerId),
                      ads: widget.ads,
                    ),
                ],
              ),
              floatingActionButton: tab == 0 && c.loaded
                  ? FloatingActionButton.extended(
                      onPressed: c.busy ? null : () => edit(),
                      icon: Icon(Icons.add_rounded),
                      label: const Text('단어 추가'),
                    )
                  : null,
              bottomNavigationBar: NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (value) => _ui.mutate(() => tab = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book_rounded),
                    label: '단어장',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.school_outlined),
                    selectedIcon: Icon(Icons.school_rounded),
                    label: '학습',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.replay_outlined),
                    selectedIcon: Icon(Icons.replay_rounded),
                    label: '오답',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart_rounded),
                    label: '기록',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: '설정',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    final cloudLabel = c.user == null
        ? '이 기기에 저장'
        : c.groupId == null
        ? '내 계정 · 로컬 캐시'
        : '그룹 · ${c.groupId}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titles[tab],
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitles[tab], style: TextStyle(color: LeafyTheme.muted)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            cloudLabel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _words(List<String> categories, {required bool wrongOnly}) {
    final words =
        c.book.words.where((word) {
          if (wrongOnly && !c.wrongIds.contains(word.id)) return false;
          if (filter == '즐겨찾기' && !word.favorite) return false;
          if (filter == '복습' && !c.due.any((due) => due.id == word.id))
            return false;
          if (filter == '익숙한 단어' && word.level < 4) return false;
          if (category != '전체' && word.category != category) return false;

          final haystack =
              '${word.word} ${word.meanings.join(' ')} ${word.text('memo')} ${word.synonymEntries.join(' ')}'
                  .toLowerCase();

          return haystack.contains(search.toLowerCase());
        }).toList()..sort(
          (a, b) => ((b.data['created'] as num?) ?? 0).compareTo(
            (a.data['created'] as num?) ?? 0,
          ),
        );

    // 웹과 동일하게 24개씩 표시하고 페이지 이동 UI는 하단에만 둔다.
    final pageCount = words.isEmpty
        ? 1
        : (words.length + wordPageSize - 1) ~/ wordPageSize;
    final effectivePage = wordPage.clamp(1, pageCount).toInt();
    final pageStart = (effectivePage - 1) * wordPageSize;
    final pagedWords = words.skip(pageStart).take(wordPageSize).toList();

    return [
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search_rounded),
          hintText: '단어, 뜻, 메모, 유의어 검색',
        ),
        onChanged: (value) => _ui.mutate(() {
          search = value;
          wordPage = 1;
        }),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final value in ['전체', '즐겨찾기', '복습', '익숙한 단어'])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: FilterChip(
                  label: Text(value),
                  selected: filter == value,
                  onSelected: (_) => _ui.mutate(() {
                    filter = value;
                    wordPage = 1;
                  }),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        initialValue: categories.contains(category) ? category : '전체',
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.folder_open_outlined),
          labelText: '카테고리',
        ),
        items: ['전체', ...categories]
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value == '전체' ? '모든 카테고리' : value),
              ),
            )
            .toList(),
        onChanged: (value) => _ui.mutate(() {
          category = value ?? '전체';
          wordPage = 1;

          if (category != '전체') {
            _ui.studyCategories.clear();
            studyScope = '카테고리:$category';
          } else if (studyScope.startsWith('카테고리:') ||
              studyScope == '복수 카테고리') {
            _ui.studyCategories.clear();
            studyScope = '오늘 복습';
          }
        }),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '${words.length}개의 단어',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                if (wrongOnly)
                  Text(
                    '3연속 정답 시 오답노트 졸업',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (wrongOnly && words.isNotEmpty)
            TextButton.icon(
              onPressed: c.busy ? null : _resetWrongNotebook,
              icon: Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('초기화'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (words.isEmpty)
        _empty(
          wrongOnly
              ? '현재 오답노트에 남아 있는 단어가 없어요.'
              : filter == '즐겨찾기'
              ? '즐겨찾기한 단어가 없어요. 별표를 눌러 중요한 단어를 모아보세요.'
              : filter == '복습'
              ? '지금 복습할 단어가 없어요. 복습 시간이 되면 여기에 표시됩니다.'
              : filter == '익숙한 단어'
              ? '아직 익숙한 단어가 없어요. 학습을 이어가면 여기에 모입니다.'
              : search.trim().isNotEmpty
              ? '검색 결과가 없어요. 다른 검색어를 입력해보세요.'
              : category != '전체'
              ? '선택한 카테고리에 표시할 단어가 없어요.'
              : '아직 단어가 없어요. 새 단어를 추가하거나 CSV를 가져오세요.',
          wrongOnly
              ? Icons.check_circle_outline_rounded
              : filter == '즐겨찾기'
              ? Icons.star_border_rounded
              : filter == '복습'
              ? Icons.schedule_rounded
              : filter == '익숙한 단어'
              ? Icons.workspace_premium_outlined
              : Icons.menu_book_outlined,
        ),
      for (final word in pagedWords) _wordCard(word, wrongOnly: wrongOnly),
      if (words.isNotEmpty && pageCount > 1) ...[
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '이전 페이지',
              onPressed: effectivePage <= 1
                  ? null
                  : () => _ui.mutate(() => wordPage = effectivePage - 1),
              icon: Icon(Icons.chevron_left_rounded),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '$effectivePage / $pageCount',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 페이지',
              onPressed: effectivePage >= pageCount
                  ? null
                  : () => _ui.mutate(() => wordPage = effectivePage + 1),
              icon: Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _wordCard(VocabWord word, {required bool wrongOnly}) {
    final progress = c.wrongProgress(word.id);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => detail(word),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          word.word,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          word.meanings.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        action(() => speech.speak(word.word, c.accent)),
                    icon: Icon(Icons.volume_up_outlined),
                  ),
                  IconButton(
                    onPressed: c.busy
                        ? null
                        : () => action(
                            () =>
                                c.save(word.copy({'favorite': !word.favorite})),
                          ),
                    icon: Icon(
                      word.favorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: word.favorite
                          ? Colors.amber.shade700
                          : LeafyTheme.muted,
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: c.loaded && !c.busy,
                    onSelected: (value) => _wordMenu(word, value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('수정')),
                      PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
                ],
              ),
              if (word.examples.isNotEmpty &&
                  (word.examples.first['text'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  word.examples.first['text']!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (word.category.isNotEmpty)
                    _badge(word.category, Icons.folder_outlined),
                  _badge(
                    word.level >= 4
                        ? '익숙해요'
                        : word.level > 0
                        ? '학습 중'
                        : '새 단어',
                    Icons.spa_outlined,
                  ),
                  if (wrongOnly)
                    _badge(
                      '연속 정답 ${progress.streak}/$relearningStreakTarget',
                      Icons.replay_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: LeafyTheme.primary),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Future<void> _wordMenu(VocabWord word, String value) async {
    if (value == 'edit') {
      await edit(word);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${word.word} 삭제'),
        content: const Text('이 단어를 단어장에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: LeafyTheme.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await action(() => c.delete(word.id));
    }
  }

  List<Widget> _study(List<String> categories) => [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '오늘도 조금씩',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${c.due.length}개 단어가 복습을 기다리고 있어요.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.spa_rounded, color: Colors.white, size: 36),
        ],
      ),
    ),
    const SizedBox(height: 14),
    Card(
      child: SwitchListTile(
        secondary: Icon(Icons.volume_up_outlined),
        title: const Text(
          '정답 확인 후 자동 발음',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        subtitle: const Text(
          '정답을 확인한 뒤 현재 단어를 들려줘요.',
          style: TextStyle(fontSize: 11),
        ),
        value: c.autoSpeak,
        onChanged: (value) => action(() => c.setAutoSpeak(value)),
      ),
    ),
    const SizedBox(height: 10),
    DropdownButtonFormField<String>(
      initialValue:
          [
            '오늘 복습',
            '전체',
            '즐겨찾기',
            '오답',
            '복수 카테고리',
            ...categories.map((value) => '카테고리:$value'),
          ].contains(studyScope)
          ? studyScope
          : '오늘 복습',
      decoration: const InputDecoration(
        labelText: '학습 범위',
        prefixIcon: Icon(Icons.tune_rounded),
      ),
      items:
          [
                '오늘 복습',
                '전체',
                '즐겨찾기',
                '오답',
                ...categories.map((value) => '카테고리:$value'),
                '복수 카테고리',
              ]
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(
                    value.startsWith('카테고리:')
                        ? value.substring('카테고리:'.length)
                        : value == '복수 카테고리'
                        ? _ui.studyCategories.isEmpty
                              ? '복수 카테고리 선택...'
                              : '복수 카테고리 (${_ui.studyCategories.length}개)'
                        : value,
                  ),
                ),
              )
              .toList(),
      onChanged: (value) async {
        if (value == '복수 카테고리') {
          await _selectMultipleStudyCategories(categories);
          return;
        }

        _ui.mutate(() {
          studyScope = value ?? '오늘 복습';
          _ui.studyCategories.clear();
        });
      },
    ),
    if (studyScope == '복수 카테고리' &&
        _ui.studyCategories.isNotEmpty) ...[
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '선택된 카테고리 · ${_studyCategorySummary(_ui.studyCategories)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
    const SizedBox(height: 10),
    DropdownButtonFormField<int>(
      initialValue: quizSize,
      decoration: const InputDecoration(labelText: '문제 수'),
      items: [5, 10, 20, 30, 99999]
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(value == 99999 ? '전체 문제' : '$value문제'),
            ),
          )
          .toList(),
      onChanged: (value) => _ui.mutate(() => quizSize = value ?? 10),
    ),
    const SizedBox(height: 18),
    const _MiniTitle('학습 방식'),
    for (final mode in QuizMode.values) _modeCard(mode),
  ];

  Widget _modeCard(QuizMode mode) {
    final descriptions = {
      QuizMode.flash: '단어를 떠올리고 직접 기억 여부를 체크해요.',
      QuizMode.choice: '네 개의 의미 중 정답을 고르는 퀴즈예요.',
      QuizMode.typing: '의미를 보고 영어 철자를 직접 입력해요.',
      QuizMode.meaning: '의미와 표현을 하나씩 떠올려 모두 완성해요.',
      QuizMode.context: '예문 빈칸에 들어갈 단어를 입력해요.',
    };

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(modeIcons[mode], color: LeafyTheme.primary),
        ),
        title: Text(
          modeNames[mode]!,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(descriptions[mode]!),
        trailing: Icon(Icons.chevron_right_rounded),
        enabled: !c.busy && c.loaded,
        onTap: () => _startQuiz(mode),
      ),
    );
  }

  Future<void> _startQuiz(QuizMode mode) async {
    var words = c.book.words.where((word) {
      return switch (studyScope) {
        '오늘 복습' => c.due.any((due) => due.id == word.id),
        '즐겨찾기' => word.favorite,
        '오답' => c.wrongIds.contains(word.id),
        '복수 카테고리' => _ui.studyCategories.contains(word.category),
        _ =>
          !studyScope.startsWith('카테고리:') ||
              word.category == studyScope.substring('카테고리:'.length),
      };
    }).toList();

    if (mode == QuizMode.context) {
      words = words.where(hasMaskableExample).toList();
    }

    if (words.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 범위에서 학습할 단어가 없습니다.')));
      return;
    }

    final limit = quizSize == 99999 ? words.length : quizSize;
    final selected = c.selectQuizWords(
      words,
      limit,
      mode.name,
      wrongOnly: studyScope == '오답',
    );

    _ui.mutate(() => quizActive = true);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizScreen(controller: c, words: selected, mode: mode),
      ),
    );

    if (mounted) _ui.mutate(() => quizActive = false);
  }

  List<Widget> _statistics() {
    final reviews = c.book.reviews;
    final correct = reviews.where((review) => review['correct'] == true).length;
    final accuracy = reviews.isEmpty
        ? 0
        : (correct / reviews.length * 100).round();

    return [
      Row(
        children: [
          Expanded(child: _stat('${c.book.words.length}', '전체 단어')),
          const SizedBox(width: 8),
          Expanded(child: _stat('${reviews.length}', '학습 횟수')),
          const SizedBox(width: 8),
          Expanded(child: _stat('$accuracy%', '정답률')),
        ],
      ),
      const SizedBox(height: 20),
      const _MiniTitle('최근 7일'),
      for (var i = 6; i >= 0; i--)
        Builder(
          builder: (context) {
            final day = dateKey(DateTime.now().subtract(Duration(days: i)));
            final count = reviews
                .where((review) => review['date'] == day)
                .length;

            return Card(
              child: ListTile(
                title: Text(day),
                trailing: Text(
                  '$count회',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          },
        ),
    ];
  }

  Widget _stat(String value, String label) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _settings() => [
    _section('계정', Icons.person_outline_rounded, [
      if (c.auth == null)
        const ListTile(
          title: Text('게스트 모드'),
          subtitle: Text('Firebase 네이티브 설정이 없어서 이 기기에만 저장됩니다.'),
        ),
      if (c.auth != null && c.user == null) ...[
        ListTile(
          leading: Icon(Icons.mail_outline_rounded),
          title: const Text('이메일 로그인 / 회원가입'),
          onTap: c.busy ? null : login,
        ),
        ListTile(
          leading: Icon(Icons.login_rounded),
          title: const Text('Google 로그인'),
          onTap: c.busy ? null : () => action(c.googleSignIn),
        ),
      ],
      if (c.user != null) ...[
        ListTile(
          leading: CircleAvatar(
            backgroundColor: LeafyTheme.surfaceSoft,
            child: Icon(Icons.person_rounded, color: LeafyTheme.primary),
          ),
          title: Text(c.user!.email ?? '로그인됨'),
          subtitle: const Text('눌러서 UID 복사'),
          onTap: () => Clipboard.setData(ClipboardData(text: c.user!.uid)),
        ),
        ListTile(
          leading: Icon(Icons.logout_rounded),
          title: const Text('로그아웃'),
          onTap: c.busy ? null : () => action(c.signOut),
        ),
      ],
    ]),
    if (c.user != null) ...[
      const SizedBox(height: 14),
      _section('그룹 단어장', Icons.group_outlined, [
        ListTile(
          title: const Text('내 단어장으로 전환'),
          leading: Icon(Icons.person_outline_rounded),
          onTap: c.busy ? null : () => c.selectScope(null),
        ),
        ListTile(
          title: const Text('새 그룹 만들기'),
          leading: Icon(Icons.group_add_outlined),
          onTap: c.busy
              ? null
              : () async {
                  final name = await prompt('새 그룹 이름');
                  if (name != null) await action(() => c.createGroup(name));
                },
        ),
        ListTile(
          title: const Text('그룹 열기'),
          leading: Icon(Icons.folder_open_outlined),
          onTap: c.busy
              ? null
              : () async {
                  final id = await prompt('초대받은 그룹 ID');
                  if (id != null && !id.contains('/')) {
                    await c.selectScope(id, forceRemote: true);
                  }
                },
        ),
        if (c.groupId != null) ...[
          ListTile(
            title: Text(c.groupId!),
            subtitle: const Text('눌러서 그룹 ID 복사'),
            onTap: () => Clipboard.setData(ClipboardData(text: c.groupId!)),
          ),
          ListTile(
            title: const Text('멤버 추가'),
            leading: Icon(Icons.person_add_alt_1_rounded),
            onTap: c.busy
                ? null
                : () async {
                    final uid = await prompt('초대할 사용자의 UID');
                    if (uid != null) await action(() => c.addMember(uid));
                  },
          ),
        ],
      ]),
    ],
    GetBuilder<ThemeController>(
      builder: (themeController) => _section('화면', Icons.palette_outlined, [
        ListTile(
          leading: Icon(themeController.icon),
          title: const Text('테마'),
          subtitle: Text(themeController.label),
        ),
        RadioListTile<LeafyThemePreference>(
          title: const Text('시스템 설정'),
          value: LeafyThemePreference.system,
          groupValue: themeController.preference,
          onChanged: (value) {
            if (value != null) {
              themeController.setPreference(value);
            }
          },
        ),
        RadioListTile<LeafyThemePreference>(
          title: const Text('라이트 모드'),
          value: LeafyThemePreference.light,
          groupValue: themeController.preference,
          onChanged: (value) {
            if (value != null) {
              themeController.setPreference(value);
            }
          },
        ),
        RadioListTile<LeafyThemePreference>(
          title: const Text('다크 모드'),
          value: LeafyThemePreference.dark,
          groupValue: themeController.preference,
          onChanged: (value) {
            if (value != null) {
              themeController.setPreference(value);
            }
          },
        ),
      ]),
    ),
    const SizedBox(height: 14),
    const SizedBox(height: 14),
    _section('발음', Icons.volume_up_outlined, [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: DropdownButtonFormField<String>(
          initialValue: c.accent,
          decoration: const InputDecoration(labelText: '영어 발음'),
          items: const [
            DropdownMenuItem(value: 'en-US', child: Text('미국 영어')),
            DropdownMenuItem(value: 'en-GB', child: Text('영국 영어')),
          ],
          onChanged: (value) {
            if (value != null) action(() => c.setAccent(value));
          },
        ),
      ),
      SwitchListTile(
        title: const Text('정답 확인 후 자동 발음'),
        value: c.autoSpeak,
        onChanged: (value) => action(() => c.setAutoSpeak(value)),
      ),
    ]),
    const SizedBox(height: 14),
    _section('단어장 관리', Icons.inventory_2_outlined, [
      ListTile(
        leading: Icon(Icons.create_new_folder_outlined),
        title: const Text('카테고리 추가'),
        onTap: c.busy || !c.loaded
            ? null
            : () async {
                final name = await prompt('추가할 카테고리');
                if (name != null) {
                  await action(
                    () => c.categories({...c.book.categories, name}.toList()),
                  );
                }
              },
      ),
      ListTile(
        leading: Icon(Icons.upload_file_rounded),
        title: const Text('웹 단어장 CSV 가져오기'),
        onTap: c.busy || !c.loaded ? null : _importCsv,
      ),
      ListTile(
        leading: Icon(Icons.download_rounded),
        title: const Text('CSV 내보내기'),
        onTap: c.book.words.isEmpty
            ? null
            : () => action(() => CsvTransfer().exportWords(c.book.words)),
      ),
      if (widget.ads.privacyRequired)
        ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: const Text('광고 개인정보 설정'),
          onTap: () => action(widget.ads.privacyOptions),
        ),
    ]),
    const SizedBox(height: 26),
    Text(
      'Leafy · 작은 단어가 만드는 큰 변화',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
      ),
    ),
  ];

  Widget _section(String title, IconData icon, List<Widget> children) => Card(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: LeafyTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );

  Future<void> _importCsv() async {
    final proceed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('CSV 파일 가져오기'),
            content: const SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('아래 헤더 형식으로 CSV UTF-8 파일을 준비해주세요.'),
                  SizedBox(height: 12),
                  SelectableText(
                    '카테고리,단어,뜻,예문,예문의 의미,메모',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 10),
                  Text('필수: 단어, 뜻'),
                  Text('선택: 카테고리, 예문, 예문의 의미, 메모'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: Icon(Icons.upload_file_rounded),
                label: const Text('CSV 파일 선택'),
              ),
            ],
          ),
        ) ??
        false;

    if (!proceed || !mounted) return;

    try {
      final words = await CsvTransfer().importWords();
      if (words.isEmpty || !mounted) return;

      final imported = await c.importWords(words);
      if (!mounted) return;

      final skipped = words.length - imported;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$imported개 단어를 가져왔습니다.'
            '${skipped > 0 ? ' $skipped개 중복 단어는 건너뛰었습니다.' : ''}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _resetWrongNotebook() async {
    final count = c.wrongIds.length;

    if (count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('초기화할 오답노트가 없습니다.')));
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('오답노트 초기화'),
            content: Text(
              '현재 오답노트의 $count개 단어를 초기화할까요?\n\n'
              '오답 기록만 삭제하고 단어, 카테고리, 정답 기록, '
              '학습 레벨과 다음 복습일은 유지합니다.\n\n'
              '이 작업은 되돌릴 수 없습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('초기화'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    try {
      final resetCount = await c.resetWrongNotebook();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('오답노트 $resetCount개 단어를 초기화했습니다.')));
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Widget _empty(String text, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 36),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: LeafyTheme.muted),
          ),
        ],
      ),
    ),
  );
}

class _MiniTitle extends StatelessWidget {
  const _MiniTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
    ),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog(this._ui);
  final _HomeUiController _ui;
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final email = TextEditingController();
  final password = TextEditingController();
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
    content: SizedBox(
      width: 420,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '이메일',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) =>
                  value != null && value.contains('@') ? null : '이메일을 입력해주세요.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '비밀번호',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              validator: (value) =>
                  (value?.length ?? 0) >= 6 ? null : '6자 이상 입력해주세요.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('새 계정 만들기'),
              value: register,
              onChanged: (value) => widget._ui.mutate(() => register = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, (
            email: email.text,
            password: password.text,
            register: register,
          ));
        },
        child: Text(register ? '가입하기' : '로그인'),
      ),
    ],
  );
}
