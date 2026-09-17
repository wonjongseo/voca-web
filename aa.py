#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
voca-web 철자 입력 대체 정답 허용 패치

예:
정답 단어:
  provide
  의미1: 제공하다
  의미2: 주다

입력 단어:
  offer
  의미1: 제공하다
  의미2: 제안하다

이번 문제의 currentMeaning == "제공하다" 이면:
  offer => 정답 인정

하지만 offer가:
  의미1: 제공하다, 제안하다
처럼 "하나의 의미 항목"으로 저장되어 있다면:
  "제공하다"와 정확히 같지 않으므로 오답

규칙:
- 입력 단어가 나만의 단어장에 실제로 존재해야 함
- 이번 문제의 currentMeaning과 의미 항목 전체가 정확히 일치해야 함
- 부분 문자열 포함은 사용하지 않음
- 기존 작은 철자 오타 허용 기능은 유지
- 대체 정답으로 인정된 경우 피드백에도 표시

실행:
    py allow_typing_synonym_answer.py

확인:
    npm run build
    npm run dev
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
import shutil
import sys


MARKER = "TYPING_EQUIVALENT_MEANING_ANSWER_V1"


def fail(message: str) -> None:
    print(f"\n[ERROR] {message}")
    sys.exit(1)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        fail(
            f"{label} 수정 지점을 찾지 못했습니다. "
            f"(예상 1개, 실제 {count}개)\n"
            "현재 app/page.tsx가 최신 GitHub 코드와 다른지 확인해주세요."
        )
    return text.replace(old, new, 1)


def backup(path: Path, stamp: str) -> Path:
    dst = path.with_name(f"{path.name}.before-typing-equivalent-answer-{stamp}.bak")
    shutil.copy2(path, dst)
    return dst


def main() -> None:
    root = Path.cwd()
    page_path = root / "app" / "page.tsx"

    if not (root / "package.json").exists():
        fail("package.json이 없습니다. voca-web 프로젝트 루트에서 실행해주세요.")
    if not page_path.exists():
        fail("app/page.tsx를 찾지 못했습니다.")

    page = page_path.read_text(encoding="utf-8")

    if MARKER in page:
        print("[INFO] 철자 입력 대체 정답 기능이 이미 적용되어 있습니다.")
        return

    # ---------------------------------------------------------------
    # 1) 의미 항목 완전 일치 helper
    # ---------------------------------------------------------------
    anchor = """function acceptsSpelling(answer:string, expected:string) {
  const a=answer.trim().toLowerCase();
  const b=expected.trim().toLowerCase();
  if(a===b)return true;
  if(Math.abs(a.length-b.length)>1)return false;
  if(a.length===b.length){
    const differences:number[]=[];
    for(let i=0;i<a.length;i++)if(a[i]!==b[i])differences.push(i);
    return differences.length===1 || (differences.length===2 && differences[1]===differences[0]+1 && a[differences[0]]===b[differences[1]] && a[differences[1]]===b[differences[0]]);
  }
  const [shorter,longer]=a.length<b.length?[a,b]:[b,a];
  let shortIndex=0;
  let longIndex=0;
  let skipped=false;
  while(shortIndex<shorter.length&&longIndex<longer.length){
    if(shorter[shortIndex]===longer[longIndex]){shortIndex++;longIndex++;continue;}
    if(skipped)return false;
    skipped=true;
    longIndex++;
  }
  return true;
}"""

    replacement = anchor + """

// TYPING_EQUIVALENT_MEANING_ANSWER_V1
function findEquivalentMeaningAnswer(answer:string,currentWord:Word,currentMeaning:string,words:Word[]):Word|null {
  const normalizedAnswer=answer.trim().toLowerCase();
  const normalizedMeaning=currentMeaning.trim();

  if(!normalizedAnswer||!normalizedMeaning)return null;

  const candidate=words.find(word=>
    word.id!==currentWord.id &&
    word.word.trim().toLowerCase()===normalizedAnswer
  );

  if(!candidate)return null;

  // 중요:
  // "제공하다" === "제공하다" 만 인정합니다.
  // "제공하다, 제안하다".includes("제공하다") 같은 부분 일치는 사용하지 않습니다.
  return getMeanings(candidate).some(meaning=>meaning.trim()===normalizedMeaning)
    ? candidate
    : null;
}"""

    page = replace_once(page, anchor, replacement, "대체 정답 helper")

    # ---------------------------------------------------------------
    # 2) 어떤 대체 단어가 인정됐는지 저장
    # ---------------------------------------------------------------
    page = replace_once(
        page,
        """  const [acceptedTypo,setAcceptedTypo] = useState(false);
  const [revealed,setRevealed] = useState(false);""",
        """  const [acceptedTypo,setAcceptedTypo] = useState(false);
  const [acceptedAlternative,setAcceptedAlternative] = useState<Word|null>(null);
  const [revealed,setRevealed] = useState(false);""",
        "acceptedAlternative state",
    )

    # ---------------------------------------------------------------
    # 3) startQuiz의 초기화에 대체 정답 상태 초기화
    # 현재 코드 변형에 대응하기 위해 공통 reset sequence를 전부 교체
    # ---------------------------------------------------------------
    reset_old = """setAnswer('');setAcceptedTypo(false);setRevealed(false);setGraded(null);busyGrade.current=false;"""
    reset_new = """setAnswer('');setAcceptedTypo(false);setAcceptedAlternative(null);setRevealed(false);setGraded(null);busyGrade.current=false;"""

    reset_count = page.count(reset_old)
    if reset_count < 1:
        fail("퀴즈 초기화 코드를 찾지 못했습니다.")
    page = page.replace(reset_old, reset_new)

    # ---------------------------------------------------------------
    # 4) 철자 입력 submit 채점 변경
    #
    # 기존:
    # exact / acceptsSpelling만 확인
    #
    # 변경:
    # exact -> typo -> 단어장의 동일 의미 항목 순서
    # ---------------------------------------------------------------
    old_submit = """onSubmit={e=>{e.preventDefault();if(answer.trim()){const exact=answer.trim().toLowerCase()===current.word.trim().toLowerCase();const accepted=acceptsSpelling(answer,current.word);setAcceptedTypo(accepted&&!exact);grade(accepted);}}}"""

    new_submit = """onSubmit={e=>{e.preventDefault();if(answer.trim()){const exact=answer.trim().toLowerCase()===current.word.trim().toLowerCase();const spellingAccepted=acceptsSpelling(answer,current.word);const alternative=spellingAccepted?null:findEquivalentMeaningAnswer(answer,current,currentMeaning,db.words);setAcceptedTypo(spellingAccepted&&!exact);setAcceptedAlternative(alternative);grade(spellingAccepted||!!alternative);}}}"""

    page = replace_once(page, old_submit, new_submit, "철자 입력 채점")

    # ---------------------------------------------------------------
    # 5) 피드백 문구
    #
    # 대체 정답이면 어떤 단어가 인정됐는지 명확히 표시
    # ---------------------------------------------------------------
    old_feedback = """<strong>{graded?(acceptedTypo?'작은 오타가 있지만 정답이에요!':'잘 기억했어요!'):'다음에 한 번 더 만나봐요.'}</strong><p>정답: {current.word} · {currentMeaning}</p>"""

    new_feedback = """<strong>{graded?(acceptedAlternative?`‘${acceptedAlternative.word}’도 같은 의미로 저장되어 있어 정답으로 인정했어요!`:acceptedTypo?'작은 오타가 있지만 정답이에요!':'잘 기억했어요!'):'다음에 한 번 더 만나봐요.'}</strong><p>정답: {current.word} · {currentMeaning}</p>{graded&&acceptedAlternative&&<p>인정된 답: {acceptedAlternative.word} · {currentMeaning}</p>}"""

    page = replace_once(page, old_feedback, new_feedback, "대체 정답 피드백")

    # ---------------------------------------------------------------
    # 6) 검증
    # ---------------------------------------------------------------
    required = [
        MARKER,
        "function findEquivalentMeaningAnswer",
        "meaning.trim()===normalizedMeaning",
        "acceptedAlternative",
        "findEquivalentMeaningAnswer(answer,current,currentMeaning,db.words)",
        "grade(spellingAccepted||!!alternative)",
        "같은 의미로 저장되어 있어 정답으로 인정했어요",
        "인정된 답:",
    ]
    missing = [token for token in required if token not in page]
    if missing:
        fail("최종 검증 실패: " + ", ".join(missing))

    # 부분 일치 판정을 실수로 넣지 않았는지 검증
    forbidden = [
        "meaning.includes(normalizedMeaning)",
        "normalizedMeaning.includes(meaning)",
    ]
    leftovers = [token for token in forbidden if token in page]
    if leftovers:
        fail("부분 문자열 의미 비교 코드가 발견되었습니다: " + ", ".join(leftovers))

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = backup(page_path, stamp)
    page_path.write_text(page, encoding="utf-8", newline="\n")

    print("\n[OK] 철자 입력 대체 정답 기능을 적용했습니다.")
    print(f"수정: {page_path}")
    print(f"백업: {bak}")

    print("\n판정 예:")
    print("provide: [제공하다, 주다]")
    print("offer:   [제공하다, 제안하다]")
    print("문제 뜻: 제공하다 / 입력: offer")
    print("=> 정답 인정")
    print("")
    print("provide: [제공하다, 주다]")
    print("offer:   [제공하다, 제안하다]  <- 이 전체가 하나의 의미 항목")
    print("문제 뜻: 제공하다 / 입력: offer")
    print("=> 오답")
    print("")
    print("※ 위 두 예시는 화면상 쉼표 표현이 같아 보일 수 있으므로")
    print("   실제 기준은 meaningEntries의 '의미 항목 단위'입니다.")

    print("\n확인:")
    print("  npm run build")
    print("  npm run dev")


if __name__ == "__main__":
    main()
