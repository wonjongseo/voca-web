#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
import sys

MARKER = "BOTTOM_ONLY_PAGINATION_V1"

def fail(message: str):
    print("\n[ERROR] " + message)
    sys.exit(1)

root = Path.cwd()
page_path = root / "app" / "page.tsx"

if not page_path.exists():
    fail("app/page.tsx를 찾지 못했습니다. voca-web 프로젝트 루트에서 실행해주세요.")

page = page_path.read_text(encoding="utf-8")

if MARKER in page:
    print("[INFO] 하단 전용 페이지네이션 패치가 이미 적용되어 있습니다.")
    sys.exit(0)

# 1) 상단 페이지네이션 제거:
#    filtered.length ? <> {renderWordPagination()} <div className="word-grid">
#    ->
#    filtered.length ? <> <div className="word-grid">
top_variants = [
    ':filtered.length?<>{renderWordPagination()}<div className="word-grid">',
    ':filtered.length ? <>{renderWordPagination()}<div className="word-grid">',
]

top_removed = False
for old in top_variants:
    if old in page:
        page = page.replace(
            old,
            old.replace("{renderWordPagination()}", ""),
            1,
        )
        top_removed = True
        break

if not top_removed:
    # 줄바꿈/공백이 있는 경우에도 상단 word-grid 직전 호출 하나만 제거
    word_grid_pos = page.find('<div className="word-grid">')
    if word_grid_pos < 0:
        fail("word-grid를 찾지 못했습니다.")

    call = "{renderWordPagination()}"
    call_pos = page.rfind(call, 0, word_grid_pos)

    if call_pos < 0:
        fail("단어 목록 위의 renderWordPagination() 호출을 찾지 못했습니다.")

    # 너무 멀리 있는 다른 호출을 지우지 않도록 근접성 확인
    if word_grid_pos - call_pos > 200:
        fail("상단 페이지네이션 호출 위치가 예상과 달라 자동 수정하지 않았습니다.")

    page = page[:call_pos] + page[call_pos + len(call):]

# 2) 하단에 남아 있는 구형 V8 호출 제거.
#    최신 renderWordPagination() 하나만 유지.
page = page.replace("{renderWordPaginationV8()}", "")

# 3) marker 추가
marker_anchor = "'use client';"
if marker_anchor not in page:
    fail("page.tsx 시작점을 찾지 못했습니다.")

page = page.replace(
    marker_anchor,
    marker_anchor + f"\n// {MARKER}",
    1,
)

# 4) 최종 검증
if page.count("{renderWordPagination()}") != 1:
    fail(
        "renderWordPagination() 호출이 정확히 1개가 아닙니다. "
        f"현재 {page.count('{renderWordPagination()}')}개입니다."
    )

remaining_call = page.find("{renderWordPagination()}")
word_grid_pos = page.find('<div className="word-grid">')

if remaining_call < word_grid_pos:
    fail("남은 페이지네이션이 아직 단어 목록 위에 있습니다.")

if "{renderWordPaginationV8()}" in page:
    fail("구형 renderWordPaginationV8() 호출이 남아 있습니다.")

page_path.write_text(page, encoding="utf-8", newline="\n")

print("\n[OK] 페이지네이션을 하단 1개만 남겼습니다.")
print("")
print("- 단어 목록 위 페이지네이션 제거")
print("- 하단 구형 renderWordPaginationV8() 호출 제거")
print("- 하단 renderWordPagination() 1개만 유지")
print("- 백업 파일 생성 안 함")
print("")
print("확인:")
print('  Select-String -Path ".\\app\\page.tsx" -Pattern "BOTTOM_ONLY_PAGINATION_V1"')
print('  Select-String -Path ".\\app\\page.tsx" -Pattern "renderWordPagination\\(\\)"')
