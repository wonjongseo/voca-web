#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
voca-web 다중 뜻 객관식 정답 판정 버그 수정

현재 문제:
- Session.meanings 에 randomMeaning()으로 출제 뜻을 저장함
- makeChoices() 안에서 target 단어의 뜻을 다시 randomMeaning()으로 뽑음
- 실제 채점은 current.meaning 전체 문자열과 비교함

예:
  access
  meaningEntries = ["접근", "이용 권한"]

세션 출제 뜻: "이용 권한"
보기 표시 뜻: "이용 권한"
채점 기준: current.meaning == "접근; 이용 권한"
=> 사용자가 "이용 권한"을 골라도 오답이 될 수 있음

수정:
1. 출제용 meaning을 한 번만 결정
2. makeChoices()에 그 meaning을 전달
3. 객관식 채점도 currentMeaning 기준
4. 정답 표시도 currentMeaning 기준
5. 철자 문제도 현재 선택된 meaning을 문제로 표시

사용:
    py fix_multi_meaning_quiz.py

확인:
    npm run build
    npm run dev
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
import shutil
import sys


MARKER = "MULTI_MEANING_QUIZ_FIX_V1"


def fail(message: str) -> None:
    print(f"\n[ERROR] {message}")
    sys.exit(1)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        fail(
            f"{label} 수정 지점을 찾지 못했습니다. "
            f"(예상 1개, 실제 {count}개)\n"
            "현재 page.tsx가 이 패치 기준 코드와 다른지 확인해주세요."
        )
    return text.replace(old, new, 1)


def backup(path: Path, stamp: str) -> Path:
    dst = path.with_name(f"{path.name}.before-multi-meaning-fix-{stamp}.bak")
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
        print("[INFO] 다중 뜻 퀴즈 수정이 이미 적용되어 있습니다.")
        return

    # ---------------------------------------------------------------
    # 1. makeChoices:
    #    target의 뜻을 내부에서 다시 랜덤 선택하지 않고
    #    세션에서 이미 고른 targetMeaning을 그대로 사용
    # ---------------------------------------------------------------
    old = """function makeChoices(target:Word,words:Word[]):QuizChoice[] {
  const selected:Word[]=[target];
  const meanings=new Set(getMeanings(target));
  for(const word of shuffle(words)){
    const meaning=randomMeaning(word);
    if(word.id===target.id||meanings.has(meaning))continue;
    selected.push(word);
    meanings.add(meaning);
    if(selected.length===4)break;
  }
  return shuffle(selected.map(word=>{const example=getExamples(word)[0];return {meaning:randomMeaning(word),word:word.word,example:example?.text??'',translation:example?.translation??''};}));
}"""

    new = """function makeChoices(target:Word,words:Word[],targetMeaning=randomMeaning(target)):QuizChoice[] {
  const selected:Word[]=[target];
  const meanings=new Set(getMeanings(target));
  for(const word of shuffle(words)){
    const meaning=randomMeaning(word);
    if(word.id===target.id||meanings.has(meaning))continue;
    selected.push(word);
    meanings.add(meaning);
    if(selected.length===4)break;
  }
  return shuffle(selected.map(word=>{const example=getExamples(word)[0];return {meaning:word.id===target.id?targetMeaning:randomMeaning(word),word:word.word,example:example?.text??'',translation:example?.translation??''};}));
}"""

    page = replace_once(page, old, new, "makeChoices")

    # ---------------------------------------------------------------
    # 2. startQuiz:
    #    meanings와 choices에서 같은 targetMeaning을 사용
    # ---------------------------------------------------------------
    old = """    setQuiz({mode,words,meanings:words.map(randomMeaning),index:0,correct:0,incorrectIds:[],choices:words.map(w=>makeChoices(w,db.words))});"""

    new = """    const meanings=words.map(randomMeaning);
    setQuiz({mode,words,meanings,index:0,correct:0,incorrectIds:[],choices:words.map((w,index)=>makeChoices(w,db.words,meanings[index]))});"""

    page = replace_once(page, old, new, "startQuiz meanings/choices")

    # ---------------------------------------------------------------
    # 3. 철자 입력 문제 역시 선택된 하나의 뜻을 표시
    # ---------------------------------------------------------------
    old = """{quiz.mode==='typing'?current.meaning:quiz.mode==='context'?maskedExample(current):current.word}"""
    new = """{quiz.mode==='typing'?currentMeaning:quiz.mode==='context'?maskedExample(current):current.word}"""
    page = replace_once(page, old, new, "typing currentMeaning")

    # ---------------------------------------------------------------
    # 4. 객관식 정답 표시 + 실제 grade 판정
    #    현재 코드에 같은 비교식이 정확히 2회 있음.
    # ---------------------------------------------------------------
    old_compare = """value===(quiz.mode==='context'?current.word:current.meaning)"""
    count = page.count(old_compare)
    if count != 2:
        fail(
            "객관식 정답 비교식 개수가 예상과 다릅니다. "
            f"(예상 2개, 실제 {count}개)"
        )

    page = page.replace(
        old_compare,
        """value===(quiz.mode==='context'?current.word:currentMeaning)""",
    )

    # ---------------------------------------------------------------
    # 5. 채점 후 정답 안내도 실제 출제된 뜻 표시
    # ---------------------------------------------------------------
    old = """<p>정답: {current.word} · {current.meaning}</p>"""
    new = """<p>정답: {current.word} · {currentMeaning}</p>"""
    page = replace_once(page, old, new, "feedback currentMeaning")

    # Marker
    anchor = """const randomMeaning=(word:Word)=>shuffle(getMeanings(word))[0] ?? word.meaning;"""
    marker_line = anchor + "\n// " + MARKER
    page = replace_once(page, anchor, marker_line, "fix marker")

    # ---------------------------------------------------------------
    # 검증
    # ---------------------------------------------------------------
    checks = [
        MARKER,
        "targetMeaning=randomMeaning(target)",
        "word.id===target.id?targetMeaning:randomMeaning(word)",
        "const meanings=words.map(randomMeaning);",
        "makeChoices(w,db.words,meanings[index])",
        "quiz.mode==='typing'?currentMeaning",
        "quiz.mode==='context'?current.word:currentMeaning",
        "정답: {current.word} · {currentMeaning}",
    ]

    missing = [token for token in checks if token not in page]
    if missing:
        fail("최종 검증 실패: " + ", ".join(missing))

    # 예전 잘못된 채점식이 남아 있으면 실패
    if "quiz.mode==='context'?current.word:current.meaning" in page:
        fail("기존 current.meaning 기반 채점 코드가 아직 남아 있습니다.")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    bak = backup(page_path, stamp)

    page_path.write_text(page, encoding="utf-8", newline="\n")

    print("\n[OK] 다중 뜻 퀴즈 버그를 수정했습니다.")
    print(f"수정: {page_path}")
    print(f"백업: {bak}")
    print("\n변경 사항:")
    print("- 문제마다 출제 뜻을 한 번만 선택")
    print("- 보기의 정답 뜻과 Session.meanings를 일치")
    print("- 객관식 정답 판정을 currentMeaning 기준으로 변경")
    print("- 정답 피드백도 실제 출제된 뜻을 표시")
    print("- 철자 문제도 실제 선택된 뜻 하나만 표시")
    print("\n확인:")
    print("  npm run build")
    print("  npm run dev")


if __name__ == "__main__":
    main()
