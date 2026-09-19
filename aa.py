#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import shutil
import sys

MARKER = 'QUIZ_SPACING_CLEANUP_V1'

def fail(msg):
    print('\n[ERROR] ' + msg)
    sys.exit(1)

root = Path.cwd()
page_path = root / 'app' / 'page.tsx'
css_path = root / 'app' / 'globals.css'

if not (root / 'package.json').exists():
    fail('voca-web 프로젝트 루트에서 실행해주세요.')
if not page_path.exists():
    fail('app/page.tsx를 찾지 못했습니다.')
if not css_path.exists():
    fail('app/globals.css를 찾지 못했습니다.')

page = page_path.read_text(encoding='utf-8')
css = css_path.read_text(encoding='utf-8')

if MARKER in css:
    print('[INFO] 퀴즈 여백 정리 패치가 이미 적용되어 있습니다.')
    sys.exit(0)

# 1. 전체 의미 카드와 중복되는 '등록된 의미' 제거
registered_line = "          <p>등록된 의미: {currentMeanings.join(' · ')}</p>\n"
registered_count = page.count(registered_line)
if registered_count == 1:
    page = page.replace(registered_line, '', 1)
elif registered_count > 1:
    fail(f'등록된 의미 문구가 여러 개 있습니다: {registered_count}개')
else:
    # 이미 제거된 경우는 통과
    if '등록된 의미: {currentMeanings.join' in page:
        fail('등록된 의미 문구 구조가 예상과 달라 자동 수정하지 않았습니다.')

# 2. 이전 요청대로 정답 후 정보 카드의 카테고리도 제거
category_block = '        {current.category?.trim()&&<div className="quiz-word-detail-row">\n          <span className="quiz-word-detail-label">카테고리</span>\n          <span className="quiz-word-category">{current.category}</span>\n        </div>}\n'
if category_block in page:
    page = page.replace(category_block, '', 1)
else:
    # 이미 제거되었으면 통과. 단, 퀴즈 정보 카드 안에 남아 있으면 중단.
    details_start = page.find('className="quiz-word-details"')
    if details_start >= 0:
        details_end = page.find('      </div>}', details_start)
        if details_end >= 0:
            details_slice = page[details_start:details_end+14]
            if '>카테고리</span>' in details_slice:
                fail('퀴즈 단어 정보 카드의 카테고리 구조가 예상과 다릅니다.')

# 3. 과도한 세로 중앙 정렬을 CSS override로 무효화
css_override = '\n/* QUIZ_SPACING_CLEANUP_V1 */\n\n/*\n  이전 viewport 전체 세로 중앙 정렬을 무효화합니다.\n  진행바 아래에 적당한 간격만 두고 문제 영역을 시작합니다.\n*/\n.quiz-wrap{\n  min-height:0!important;\n  display:block!important;\n}\n\n.question-area.quiz-question-centered{\n  flex:none!important;\n  display:block!important;\n  justify-content:initial!important;\n  padding:76px 20px 35px!important;\n}\n\n@media(max-width:600px){\n  .question-area.quiz-question-centered{\n    padding:42px 0 24px!important;\n  }\n}\n'
css += css_override

# 4. 검증
if '등록된 의미: {currentMeanings.join' in page:
    fail('등록된 의미 줄이 아직 남아 있습니다.')

if 'className="quiz-word-details"' in page:
    details_start = page.find('className="quiz-word-details"')
    next_button = page.find('onClick={nextQuestion}', details_start)
    if next_button > details_start:
        details_slice = page[details_start:next_button]
        if '>카테고리</span>' in details_slice:
            fail('정답 후 단어 정보 카드에 카테고리가 아직 남아 있습니다.')

if MARKER not in css:
    fail('CSS override 검증 실패')
if 'padding:76px 20px 35px!important;' not in css:
    fail('데스크톱 문제 영역 여백 검증 실패')

stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
page_bak = page_path.with_name(f'{page_path.name}.before-quiz-spacing-cleanup-{stamp}.bak')
css_bak = css_path.with_name(f'{css_path.name}.before-quiz-spacing-cleanup-{stamp}.bak')
shutil.copy2(page_path, page_bak)
shutil.copy2(css_path, css_bak)

page_path.write_text(page, encoding='utf-8', newline='\n')
css_path.write_text(css, encoding='utf-8', newline='\n')

print('\n[OK] 퀴즈 UI 여백/중복 문구 정리 완료')
print('- viewport 전체 강제 세로 중앙 정렬 무효화')
print('- 진행바 아래 약 76px 후 문제 시작')
print('- 모바일은 약 42px 여백')
print('- 등록된 의미: ... 문구 제거')
print('- 정답 후 단어 정보 카드의 카테고리 제거')
print(f'\n백업: {page_bak}')
print(f'백업: {css_bak}')
print('\n다음 실행:')
print('  npm run typecheck')
print('  npm run build')
print('  npm run dev')
