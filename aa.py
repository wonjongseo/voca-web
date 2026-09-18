#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
voca-web 의미 분리 버그 수정
- 괄호 안의 쉼표/가운뎃점은 의미 구분자로 취급하지 않음
- 괄호 밖의 , ， · ㆍ 만 세부 의미 구분자로 처리

예:
  배달하다
  (연설, 강연 등을) 하다

기존 잘못된 분리:
  (연설
  강연 등을) 하다

수정 후:
  (연설, 강연 등을) 하다   ← 하나의 의미

힌트:
  (연설, 강연 등을) 하○

정답 판정:
  "하다" 입력으로 해당 의미 완료 가능
"""

from pathlib import Path
from datetime import datetime
import shutil
import sys

MARKER = "MEANING_SPLIT_OUTSIDE_PARENS_V1"


def fail(message: str):
    print(f"\n[ERROR] {message}")
    sys.exit(1)


def backup(path: Path, stamp: str):
    dst = path.with_name(
        f"{path.name}.before-meaning-paren-split-{stamp}.bak"
    )
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
    print("[INFO] 괄호 내부 구분자 무시 패치가 이미 적용되어 있습니다.")
    sys.exit(0)

if "MEANING_TYPING_FRAGMENTS_V1" not in text:
    fail("MEANING_TYPING_FRAGMENTS_V1을 찾지 못했습니다.")

# ============================================================
# 1. 공통 split helper 추가
# ============================================================
anchor = "function splitMeaningFragments(value:string) {"

pos = text.find(anchor)
if pos < 0:
    fail("splitMeaningFragments()를 찾지 못했습니다.")

helper = r"""// MEANING_SPLIT_OUTSIDE_PARENS_V1
function splitMeaningPartsOutsideParentheses(value:string) {
  const parts:string[]=[];
  let buffer='';
  let roundDepth=0;
  let fullWidthDepth=0;

  const push=()=>{
    const trimmed=buffer.trim();
    if(trimmed)parts.push(trimmed);
    buffer='';
  };

  for(const char of value){
    if(char==='('){
      roundDepth++;
      buffer+=char;
      continue;
    }

    if(char===')'){
      if(roundDepth>0)roundDepth--;
      buffer+=char;
      continue;
    }

    if(char==='（'){
      fullWidthDepth++;
      buffer+=char;
      continue;
    }

    if(char==='）'){
      if(fullWidthDepth>0)fullWidthDepth--;
      buffer+=char;
      continue;
    }

    const isDelimiter=
      char===',' ||
      char==='，' ||
      char==='·' ||
      char==='ㆍ';

    if(
      isDelimiter &&
      roundDepth===0 &&
      fullWidthDepth===0
    ){
      push();
      continue;
    }

    buffer+=char;
  }

  push();
  return parts;
}

"""

text = text[:pos] + helper + text[pos:]

# ============================================================
# 2. splitMeaningFragments 수정
# ============================================================
old_split = r"""function splitMeaningFragments(value:string) {
  return value
    .split(/[,，·ㆍ]/)
    .map(removeMeaningContext)
    .filter(Boolean);
}"""

new_split = r"""function splitMeaningFragments(value:string) {
  return splitMeaningPartsOutsideParentheses(value)
    .map(removeMeaningContext)
    .filter(Boolean);
}"""

if old_split not in text:
    fail("기존 splitMeaningFragments 구현을 찾지 못했습니다.")

text = text.replace(old_split, new_split, 1)

# ============================================================
# 3. 힌트 원문 복원 로직도 동일 helper 사용
# ============================================================
old_hint_split = """  const rawParts=rawMeaning.split(/[,，·ㆍ]/);"""

new_hint_split = """  const rawParts=splitMeaningPartsOutsideParentheses(rawMeaning);"""

if old_hint_split not in text:
    fail("힌트용 rawMeaning split 코드를 찾지 못했습니다.")

text = text.replace(old_hint_split, new_hint_split, 1)

# ============================================================
# 4. 검증
# ============================================================
required = [
    MARKER,
    "function splitMeaningPartsOutsideParentheses",
    "roundDepth===0",
    "fullWidthDepth===0",
    "return splitMeaningPartsOutsideParentheses(value)",
    "const rawParts=splitMeaningPartsOutsideParentheses(rawMeaning);",
]

missing = [token for token in required if token not in text]
if missing:
    fail("최종 검증 실패: " + ", ".join(missing))

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
bak = backup(page_path, stamp)

page_path.write_text(text, encoding="utf-8", newline="\n")

print("\n[OK] 괄호 안의 쉼표/구분자를 의미 분리에서 제외했습니다.")
print(f"수정: {page_path}")
print(f"백업: {bak}")

print("\n이제:")
print("  (연설, 강연 등을) 하다")
print("  -> 하나의 의미로 유지")
print("  -> 힌트: (연설, 강연 등을) 하○")
print("  -> 입력: 하다")
print("  -> 정답")

print("\n괄호 밖 구분자는 기존대로 분리됩니다:")
print("  회의, 총회, 학회")
print("  -> 회의 / 총회 / 학회")

print("\n확인:")
print("  npm run typecheck")
print("  npm run build")
print("  npm run dev")
