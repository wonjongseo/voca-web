#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
voca-web 의미 입력: 쉼표로 나열된 동의 표현 순서 무시 패치

예:
정답: 독점적인, 배타적인
입력: 배타적인, 독점적인
=> 정답

정답: 제공하다
입력: 제공하다, 제안하다
=> 오답

정답: 제공하다, 제안하다
입력: 제안하다, 제공하다
=> 정답

규칙:
- 하나의 의미 항목 내부에서 ',' 또는 '，' 로 나뉜 표현들의 순서는 무시
- 표현 개수와 구성은 모두 같아야 함
- 앞뒤 공백 / 연속 공백 / 영문 대소문자는 무시
- 부분일치/포함관계는 정답 처리하지 않음

실행:
    py allow_reordered_comma_meanings.py
"""

from pathlib import Path
from datetime import datetime
import shutil
import sys

MARKER = "REORDERED_COMMA_MEANINGS_V1"

def fail(msg: str):
    print(f"\n[ERROR] {msg}")
    sys.exit(1)

def backup(path: Path, stamp: str):
    dst = path.with_name(f"{path.name}.before-reordered-meanings-{stamp}.bak")
    shutil.copy2(path, dst)
    return dst

def main():
    root = Path.cwd()
    page_path = root / "app" / "page.tsx"

    if not (root / "package.json").exists():
        fail("package.json이 없습니다. voca-web 프로젝트 루트에서 실행해주세요.")
    if not page_path.exists():
        fail("app/page.tsx를 찾지 못했습니다.")

    page = page_path.read_text(encoding="utf-8")

    if MARKER in page:
        print("[INFO] 이미 적용되어 있습니다.")
        return

    old = """function normalizeMeaningAnswer(value:string) {
  return value.trim().replace(/\\s+/g,' ').toLocaleLowerCase();
}"""

    new = """// REORDERED_COMMA_MEANINGS_V1
function normalizeMeaningAnswer(value:string) {
  // 한 의미 항목 안에서 쉼표로 나열된 표현은 순서가 달라도 같은 답으로 봅니다.
  // 예: "독점적인, 배타적인" === "배타적인, 독점적인"
  // 단, "제공하다" !== "제공하다, 제안하다"
  return value
    .split(/[,，]/)
    .map(part=>part.trim().replace(/\\s+/g,' ').toLocaleLowerCase())
    .filter(Boolean)
    .sort((a,b)=>a.localeCompare(b,'ko'))
    .join('||');
}"""

    count = page.count(old)
    if count != 1:
        fail(
            "normalizeMeaningAnswer 수정 지점을 찾지 못했습니다. "
            f"(예상 1개, 실제 {count}개)\n"
            "이전 quiz_mid_review_upgrade.py가 적용된 코드인지 확인해주세요."
        )

    page = page.replace(old, new, 1)

    required = [
        MARKER,
        ".split(/[,，]/)",
        ".sort((a,b)=>a.localeCompare(b,'ko'))",
        ".join('||')",
        "function answersMatchAllMeanings",
    ]
    missing = [x for x in required if x not in page]
    if missing:
        fail("최종 검증 실패: " + ", ".join(missing))

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = backup(page_path, stamp)
    page_path.write_text(page, encoding="utf-8", newline="\n")

    print("\n[OK] 의미 입력의 쉼표 순서 무시 판정을 적용했습니다.")
    print(f"수정: {page_path}")
    print(f"백업: {bak}")

    print("\n판정 예:")
    print('  "독점적인, 배타적인" ↔ "배타적인, 독점적인" => 정답')
    print('  "제공하다, 제안하다" ↔ "제안하다, 제공하다" => 정답')
    print('  "제공하다" ↔ "제공하다, 제안하다" => 오답')
    print('  "독점적인" ↔ "배타적인" => 오답')

    print("\n확인:")
    print("  npm run typecheck")
    print("  npm run build")
    print("  npm run dev")

if __name__ == "__main__":
    main()
