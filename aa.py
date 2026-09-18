#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
aaab 로컬 코드용 의미 입력 안정화 패치 V2

목적:
- "직장, 일자리"에서
    직장 -> 부분 정답
    일자리 -> 최종 정답
  이 되어야 하는데 마지막 입력 시 오답으로 끝나는 문제 보강

수정:
1) 의미 비교 문자열 Unicode NFKC 정규화
2) zero-width/BOM 제거
3) 한글 IME 조합 중 Enter submit 차단
4) submit 시 React state보다 실제 input DOM 값을 우선 사용

이 스크립트는 줄바꿈/포맷 전체 문자열 일치에 의존하지 않습니다.

실행:
    py fix_meaning_input_match_v2.py
"""

from pathlib import Path
from datetime import datetime
import re
import shutil
import sys

MARKER = "MEANING_INPUT_MATCH_STABILITY_V2"


def fail(msg: str):
    print(f"\n[ERROR] {msg}")
    sys.exit(1)


def backup(path: Path, stamp: str):
    dst = path.with_name(f"{path.name}.before-meaning-match-v2-{stamp}.bak")
    shutil.copy2(path, dst)
    return dst


root = Path.cwd()
page_path = root / "app" / "page.tsx"

if not (root / "package.json").exists():
    fail("package.json이 없습니다. voca-web 프로젝트 루트에서 실행해주세요.")

if not page_path.exists():
    fail("app/page.tsx를 찾지 못했습니다.")

text = page_path.read_text(encoding="utf-8")

if MARKER in text:
    print("[INFO] 이미 V2 패치가 적용되어 있습니다.")
    sys.exit(0)

if "MEANING_TYPING_FRAGMENTS_V1" not in text:
    fail(
        "MEANING_TYPING_FRAGMENTS_V1을 찾지 못했습니다.\n"
        "meaning_typing_fragments.py가 적용된 코드에서 실행해주세요."
    )

# ------------------------------------------------------------
# 1) removeMeaningContext 함수만 구조적으로 교체
# ------------------------------------------------------------
start = text.find("function removeMeaningContext(value:string)")
if start < 0:
    fail("removeMeaningContext 함수를 찾지 못했습니다.")

next_func = text.find("function normalizeMeaningFragment", start)
if next_func < 0:
    fail("normalizeMeaningFragment 함수를 찾지 못했습니다.")

new_remove = r"""// MEANING_INPUT_MATCH_STABILITY_V2
function removeMeaningContext(value:string) {
  return value
    .normalize('NFKC')
    .replace(/[\u200B-\u200D\u2060\uFEFF]/g,'')
    .replace(/\([^)]*\)/g,' ')
    .replace(/（[^）]*）/g,' ')
    .replace(/\s+/g,' ')
    .trim();
}

"""

text = text[:start] + new_remove + text[next_func:]

# normalizeMeaningFragment도 locale + NFKC를 확실히 적용
pattern = re.compile(
    r"""function normalizeMeaningFragment\(value:string\)\s*\{\s*return\s+removeMeaningContext\(value\)(?:\.normalize\('NFKC'\))?\.toLocaleLowerCase(?:\([^)]*\))?\s*;\s*\}""",
    re.S,
)

replacement = """function normalizeMeaningFragment(value:string) {
  return removeMeaningContext(value)
    .normalize('NFKC')
    .toLocaleLowerCase('ko-KR');
}"""

text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    fail(f"normalizeMeaningFragment 교체 실패 (실제 {count}개)")

# ------------------------------------------------------------
# 2) IME ref 추가
# ------------------------------------------------------------
if "const meaningComposingRef = useRef(false);" not in text:
    anchor = "const typingInputRef = useRef<HTMLInputElement>(null);"
    idx = text.find(anchor)
    if idx < 0:
        fail("typingInputRef를 찾지 못했습니다.")

    insert_at = idx + len(anchor)
    text = (
        text[:insert_at]
        + "\n  const meaningComposingRef = useRef(false);"
        + text[insert_at:]
    )

# ------------------------------------------------------------
# 3) 의미 입력 form 범위 찾기
# ------------------------------------------------------------
form_marker = 'className="meaning-typing-form meaning-step-form"'
form_pos = text.find(form_marker)
if form_pos < 0:
    fail("meaning-step-form을 찾지 못했습니다.")

# form의 onSubmit 시작점
submit_pos = text.rfind("onSubmit={e=>{", max(0, form_pos - 300), form_pos + 200)
if submit_pos < 0:
    # 포맷이 다를 경우 앞으로도 탐색
    submit_pos = text.find("onSubmit={e=>{", form_pos)
if submit_pos < 0:
    fail("의미 form의 onSubmit을 찾지 못했습니다.")

# 해당 form의 닫힘 지점까지만 작업
form_end = text.find("</form>", submit_pos)
if form_end < 0:
    fail("의미 form의 </form>을 찾지 못했습니다.")

segment = text[submit_pos:form_end]

# e.preventDefault() 뒤에 IME guard 삽입
if "meaningComposingRef.current" not in segment:
    prevent_match = re.search(r"e\.preventDefault\(\)\s*;", segment)
    if not prevent_match:
        fail("의미 form 안의 e.preventDefault()를 찾지 못했습니다.")

    pos = prevent_match.end()
    segment = (
        segment[:pos]
        + "\n        if(meaningComposingRef.current||graded!==null)return;"
        + segment[pos:]
    )

# 기존 const value = meaningInput... 형태를 DOM 우선 읽기로 변경
value_pattern = re.compile(
    r"""const\s+value\s*=\s*meaningInput\.trim\(\)\s*;"""
)

segment, value_count = value_pattern.subn(
    "const value=(typingInputRef.current?.value??meaningInput).trim();",
    segment,
    count=1,
)

if value_count == 0:
    # 이미 비슷하게 수정되어 있으면 통과
    if "typingInputRef.current?.value??meaningInput" not in segment:
        fail("의미 form 안의 const value=meaningInput.trim()을 찾지 못했습니다.")

text = text[:submit_pos] + segment + text[form_end:]

# ------------------------------------------------------------
# 4) 의미 input에 composition 이벤트 추가
# ------------------------------------------------------------
input_marker = 'aria-label="기억나는 의미 또는 표현 입력"'
input_pos = text.find(input_marker)
if input_pos < 0:
    # 이전 버전 라벨도 지원
    input_marker = 'aria-label="기억나는 의미 입력"'
    input_pos = text.find(input_marker)

if input_pos < 0:
    fail("의미 입력 input의 aria-label을 찾지 못했습니다.")

# 해당 input 태그의 끝 ' />' 또는 '/>' 찾기
tag_start = text.rfind("<input", max(0, input_pos - 500), input_pos)
tag_end = text.find("/>", input_pos)
if tag_start < 0 or tag_end < 0:
    fail("의미 입력 <input /> 태그 범위를 찾지 못했습니다.")

tag_end += 2
input_tag = text[tag_start:tag_end]

if "onCompositionStart" not in input_tag:
    on_change = re.search(
        r"""onChange=\{e=>setMeaningInput\(e\.target\.value\)\}""",
        input_tag,
    )
    if not on_change:
        fail("의미 입력 input의 onChange를 찾지 못했습니다.")

    insert = """onCompositionStart={()=>{meaningComposingRef.current=true;}}
            onCompositionEnd={e=>{
              meaningComposingRef.current=false;
              setMeaningInput(e.currentTarget.value);
            }}
            onKeyDown={e=>{
              if(e.key==='Enter'&&(e.nativeEvent.isComposing||meaningComposingRef.current)){
                e.preventDefault();
              }
            }}
            """

    input_tag = (
        input_tag[:on_change.start()]
        + insert
        + input_tag[on_change.start():]
    )

text = text[:tag_start] + input_tag + text[tag_end:]

# ------------------------------------------------------------
# 5) 최종 검증
# ------------------------------------------------------------
required = [
    MARKER,
    ".normalize('NFKC')",
    r".replace(/[\u200B-\u200D\u2060\uFEFF]/g,'')",
    "const meaningComposingRef = useRef(false);",
    "if(meaningComposingRef.current||graded!==null)return;",
    "typingInputRef.current?.value??meaningInput",
    "onCompositionStart",
    "onCompositionEnd",
    "e.nativeEvent.isComposing",
]

missing = [token for token in required if token not in text]
if missing:
    fail("최종 검증 실패: " + ", ".join(missing))

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
bak = backup(page_path, stamp)

page_path.write_text(text, encoding="utf-8", newline="\n")

print("\n[OK] 의미 입력 안정화 V2 패치를 적용했습니다.")
print(f"수정: {page_path}")
print(f"백업: {bak}")
print()
print("테스트:")
print("  저장: 직장, 일자리")
print("  1) 직장 입력 -> 부분 정답")
print("  2) 일자리 입력 -> 전체 완료 / 정답")
print()
print("확인:")
print("  npm run typecheck")
print("  npm run build")
print("  npm run dev")
