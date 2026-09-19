#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import shutil
import sys

def fail(msg):
    print('\n[ERROR] ' + msg)
    sys.exit(1)

root = Path.cwd()
page_path = root / 'app' / 'page.tsx'

if not page_path.exists():
    fail('app/page.tsx를 찾지 못했습니다. 프로젝트 루트에서 실행해주세요.')

text = page_path.read_text(encoding='utf-8')

old_start = ':filtered.length?<div className="word-grid">{pagedWords.map(w=>'
new_start = ':filtered.length?<><div className="word-grid">{pagedWords.map(w=>'

old_end = '      </button>\n    </div>}:<div className="empty-state"><BookOpen size={34}/>'
new_end = '      </button>\n    </div>}</>:<div className="empty-state"><BookOpen size={34}/>'

already_start = ':filtered.length?<><div className="word-grid">{pagedWords.map(w=>'
already_end = '</div>}</>:<div className="empty-state"><BookOpen size={34}/>'

if already_start in text and already_end in text:
    print('[INFO] JSX Fragment 수정이 이미 적용되어 있습니다.')
    sys.exit(0)

start_count = text.count(old_start)
end_count = text.count(old_end)

if start_count != 1:
    fail(f'목록 시작점을 찾지 못했습니다. 예상 1개, 실제 {start_count}개')

if end_count != 1:
    fail(f'pagination 종료점을 찾지 못했습니다. 예상 1개, 실제 {end_count}개')

text = text.replace(old_start, new_start, 1)
text = text.replace(old_end, new_end, 1)

if new_start not in text:
    fail('Fragment 시작 검증 실패')

if new_end not in text:
    fail('Fragment 종료 검증 실패')

stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
bak = page_path.with_name(f'{page_path.name}.before-pagination-fragment-fix-{stamp}.bak')
shutil.copy2(page_path, bak)

page_path.write_text(text, encoding='utf-8', newline='\n')

print('\n[OK] pagination JSX Fragment 수정 완료')
print(f'백업: {bak}')
print('\n다음 실행:')
print('  npm run typecheck')
print('  npm run build')
print('  npm run dev')
