#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
voca-web 오답노트 기능 패치

사용법:
  1) 이 파일을 voca-web 프로젝트 루트(package.json이 있는 위치)에 둡니다.
  2) 실행:
       python add_wrong_note.py
     또는 Windows:
       py add_wrong_note.py
  3) 확인:
       npm run build
       npm run dev

수정 파일:
  - app/page.tsx
  - app/globals.css

기능:
  - 사이드바에 "오답노트" 메뉴 추가
  - 기존 reviews 기록에서 한 번 이상 틀린 단어 자동 집계
  - 단어별 오답 횟수 / 정답 횟수 / 정답률 / 최근 오답일 표시
  - 오답 단어만 다시 학습 가능
  - 오늘의 학습 범위에 "오답노트" 추가

주의:
  - DB 스키마/LocalStorage 형식은 변경하지 않습니다.
  - 실행 전 원본 파일의 timestamp 백업을 자동 생성합니다.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
import shutil
import sys


MARKER = "WRONG_NOTE_FEATURE_V1"


def fail(message: str) -> None:
    print(f"\n[ERROR] {message}")
    sys.exit(1)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        fail(
            f"{label} 수정 지점을 찾지 못했습니다. "
            f"(예상 1개, 실제 {count}개)\n"
            "GitHub 최신 코드와 현재 로컬 코드가 달라졌을 가능성이 있습니다."
        )
    return text.replace(old, new, 1)


def backup_file(path: Path, stamp: str) -> Path:
    backup = path.with_name(f"{path.name}.before-wrong-note-{stamp}.bak")
    shutil.copy2(path, backup)
    return backup


def main() -> None:
    root = Path.cwd()
    page_path = root / "app" / "page.tsx"
    css_path = root / "app" / "globals.css"

    if not (root / "package.json").exists():
        fail("프로젝트 루트에서 실행해주세요. package.json을 찾을 수 없습니다.")

    for path in (page_path, css_path):
        if not path.exists():
            fail(f"필수 파일을 찾을 수 없습니다: {path}")

    page = page_path.read_text(encoding="utf-8")
    css = css_path.read_text(encoding="utf-8")

    if MARKER in page:
        print("오답노트 패치가 이미 적용되어 있습니다. 변경하지 않습니다.")
        return

    # ------------------------------------------------------------------
    # 1. 기존 reviews를 기반으로 오답 통계 계산
    # ------------------------------------------------------------------
    old = """  const mastered=db.words.filter(w=>w.level>=4).length;
  let streak=0;"""
    new = f"""  const mastered=db.words.filter(w=>w.level>=4).length;

  // {MARKER}
  // 별도 DB 필드를 추가하지 않고 기존 reviews 기록으로 오답노트를 계산합니다.
  const wrongStats=db.words.flatMap(word=>{{
    const reviews=db.reviews.filter(r=>r.wordId===word.id);
    const wrongReviews=reviews.filter(r=>!r.correct);
    if(!wrongReviews.length)return [];
    const correct=reviews.length-wrongReviews.length;
    return [{{
      word,
      wrong:wrongReviews.length,
      correct,
      total:reviews.length,
      accuracy:Math.round(correct/reviews.length*100),
      lastWrong:wrongReviews[wrongReviews.length-1]?.date??'',
    }}];
  }}).sort((a,b)=>b.wrong-a.wrong||a.accuracy-b.accuracy||a.word.word.localeCompare(b.word.word));
  const wrongWords=wrongStats.map(item=>item.word);

  let streak=0;"""
    page = replace_once(page, old, new, "오답 통계")

    # ------------------------------------------------------------------
    # 2. 페이지 메타데이터: 오답노트 제목/설명
    # ------------------------------------------------------------------
    old = """  const week=Array.from({length:7},(_,i)=>{const d=new Date();d.setDate(d.getDate()-6+i);const key=localDate(d);return{day:['일','월','화','수','목','금','토'][d.getDay()],count:db.reviews.filter(r=>r.date===key).length,key};});
  return <div className="app-shell">"""
    new = """  const week=Array.from({length:7},(_,i)=>{const d=new Date();d.setDate(d.getDate()-6+i);const key=localDate(d);return{day:['일','월','화','수','목','금','토'][d.getDay()],count:db.reviews.filter(r=>r.date===key).length,key};});
  const pageMeta:Record<string,{eyebrow:string;title:string;desc:string}>={
    words:{eyebrow:'WORDS THAT STAY WITH YOU',title:'나의 단어장',desc:'발견한 단어를 모아, 나만의 언어로 만들어보세요.'},
    study:{eyebrow:'A LITTLE PRACTICE, EVERY DAY',title:'오늘의 학습',desc:'한 번 더 떠올리는 순간, 단어가 오래 남아요.'},
    wrong:{eyebrow:'WORDS TO MEET AGAIN',title:'오답노트',desc:'헷갈렸던 단어를 모아, 다시 확실하게 기억해보세요.'},
    stats:{eyebrow:'YOUR GROWTH, ONE WORD AT A TIME',title:'학습 기록',desc:'작은 반복이 쌓여, 더 넓은 어휘가 됩니다.'},
  };
  const currentPageMeta=pageMeta[page]??pageMeta.words;
  return <div className="app-shell">"""
    page = replace_once(page, old, new, "페이지 메타데이터")

    # ------------------------------------------------------------------
    # 3. 사이드바 메뉴에 오답노트 추가
    # ------------------------------------------------------------------
    old = """<aside className="sidebar"><a className="brand" href="/" aria-label="LEAF 홈"><span className="brand-symbol"><Leaf size={24}/></span>leaf<span className="brand-dot">.</span></a><span className="workspace-label">MY LEARNING SPACE</span><nav aria-label="주 메뉴">{[{id:'words',label:'나의 단어장',icon:BookOpen},{id:'study',label:'오늘의 학습',icon:Layers},{id:'stats',label:'학습 기록',icon:ChartNoAxesCombined}].map(({id,label,icon:Icon})=><button key={id} className={page===id?'nav-item active':'nav-item'} onClick={()=>{setPage(id);setQuiz(null);}}><Icon size={19}/><span>{label}</span>{id==='study'&&due.length>0&&<span className="nav-count">{due.length}</span>}</button>)}</nav>"""
    new = """<aside className="sidebar"><a className="brand" href="/" aria-label="LEAF 홈"><span className="brand-symbol"><Leaf size={24}/></span>leaf<span className="brand-dot">.</span></a><span className="workspace-label">MY LEARNING SPACE</span><nav aria-label="주 메뉴">{[{id:'words',label:'나의 단어장',icon:BookOpen},{id:'study',label:'오늘의 학습',icon:Layers},{id:'wrong',label:'오답노트',icon:RotateCcw},{id:'stats',label:'학습 기록',icon:ChartNoAxesCombined}].map(({id,label,icon:Icon})=><button key={id} className={page===id?'nav-item active':'nav-item'} onClick={()=>{setPage(id);setQuiz(null);}}><Icon size={19}/><span>{label}</span>{id==='study'&&due.length>0&&<span className="nav-count">{due.length}</span>}{id==='wrong'&&wrongWords.length>0&&<span className="nav-count wrong-count">{wrongWords.length}</span>}</button>)}</nav>"""
    page = replace_once(page, old, new, "사이드바 오답노트 메뉴")

    # ------------------------------------------------------------------
    # 4. 상단 breadcrumb / 페이지 헤딩을 공통 pageMeta로 변경
    # ------------------------------------------------------------------
    old = """<div className="main-area"><header className="topbar"><div><span className="muted">나의 학습 공간</span><ChevronRight size={14}/><span>{page==='words'?'나의 단어장':page==='study'?'오늘의 학습':'학습 기록'}</span></div>"""
    new = """<div className="main-area"><header className="topbar"><div><span className="muted">나의 학습 공간</span><ChevronRight size={14}/><span>{currentPageMeta.title}</span></div>"""
    page = replace_once(page, old, new, "상단 breadcrumb")

    old = """<main><section className="page-heading"><div><p className="eyebrow">{page==='words'?'WORDS THAT STAY WITH YOU':page==='study'?'A LITTLE PRACTICE, EVERY DAY':'YOUR GROWTH, ONE WORD AT A TIME'}</p><h1>{page==='words'?'나의 단어장':page==='study'?'오늘의 학습':'학습 기록'}</h1><p>{page==='words'?'발견한 단어를 모아, 나만의 언어로 만들어보세요.':page==='study'?'한 번 더 떠올리는 순간, 단어가 오래 남아요.':'작은 반복이 쌓여, 더 넓은 어휘가 됩니다.'}</p></div>{page==='words'&&"""
    new = """<main><section className="page-heading"><div><p className="eyebrow">{currentPageMeta.eyebrow}</p><h1>{currentPageMeta.title}</h1><p>{currentPageMeta.desc}</p></div>{page==='words'&&"""
    page = replace_once(page, old, new, "페이지 헤딩")

    # ------------------------------------------------------------------
    # 5. 오답만 학습할 수 있도록 startQuiz 범위 추가
    # ------------------------------------------------------------------
    old = """function startQuiz(mode:Mode){const pool=scope==='due'?due:scope==='favorite'?db.words.filter(w=>w.favorite):db.words;"""
    new = """function startQuiz(mode:Mode){const pool=scope==='due'?due:scope==='favorite'?db.words.filter(w=>w.favorite):scope==='wrong'?wrongWords:db.words;"""
    page = replace_once(page, old, new, "오답 학습 범위")

    # ------------------------------------------------------------------
    # 6. 오늘의 학습 select에 "오답노트" 추가
    # ------------------------------------------------------------------
    old = """<option value="favorite">즐겨찾기 ({db.words.filter(w=>w.favorite).length})</option></select>"""
    new = """<option value="favorite">즐겨찾기 ({db.words.filter(w=>w.favorite).length})</option><option value="wrong">오답노트 ({wrongWords.length})</option></select>"""
    page = replace_once(page, old, new, "학습 범위 select")

    # ------------------------------------------------------------------
    # 7. 오답노트 페이지 UI 추가
    # ------------------------------------------------------------------
    anchor = """    {page==='stats'&&<section className="stats-section">"""
    wrong_section = """    {page==='wrong'&&<section className="wrong-section"><div className="section-title wrong-title"><div><h2>다시 볼 단어 <span>{wrongStats.length}</span></h2><p className="muted">한 번 이상 틀린 단어를 오답 횟수가 많은 순서로 모았어요.</p></div><button className="button primary" disabled={!wrongWords.length} onClick={()=>{setPage('study');setScope('wrong');setQuiz(null);}}>오답만 다시 학습<ArrowRight size={17}/></button></div>{wrongStats.length?<div className="wrong-list">{wrongStats.map(({word,wrong,correct,total,accuracy,lastWrong})=><article className="wrong-row" key={word.id}><div className="wrong-word"><button className="word-link" onClick={()=>setDetail(word)}>{word.word}</button><button className="icon-button" aria-label={`${word.word} 발음 듣기`} title="발음 듣기" onClick={()=>speak(word.word)}><AudioLines size={16}/></button><p>{word.meaning}</p></div><div className="wrong-metrics"><div><span>오답</span><strong className="wrong-number">{wrong}<small>회</small></strong></div><div><span>정답</span><strong>{correct}<small>회</small></strong></div><div><span>정답률</span><strong>{accuracy}<small>%</small></strong></div><div><span>최근 오답</span><strong className="wrong-date">{lastWrong||'-'}</strong></div></div><div className="wrong-bar" aria-label={`${word.word} 정답률 ${accuracy}%`}><div style={{width:`${accuracy}%`}}/></div><div className="wrong-row-footer"><span>총 {total}회 학습</span><button className="button text-button" onClick={()=>setDetail(word)}>단어 보기<ChevronRight size={14}/></button></div></article>)}</div>:<div className="empty-state wrong-empty"><Check size={34}/><h3>아직 오답이 없어요.</h3><p>학습 중 틀린 단어가 생기면 여기에 자동으로 모입니다.</p><button className="button primary" onClick={()=>setPage('study')}>학습 시작<ArrowRight size={16}/></button></div>}</section>}
"""
    if anchor not in page:
        fail("오답노트 페이지를 삽입할 위치를 찾지 못했습니다.")
    page = page.replace(anchor, wrong_section + anchor, 1)

    # ------------------------------------------------------------------
    # 8. CSS 추가
    # ------------------------------------------------------------------
    css_addition = r"""
/* WRONG_NOTE_FEATURE_V1 */
.wrong-count{background:#f4e3dc!important;color:#9d6657!important}
.wrong-section{padding:12px 0 30px}
.wrong-title{align-items:flex-end}
.wrong-title>div>p{font-size:11px;margin-top:8px}
.wrong-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:15px}
.wrong-row{position:relative;background:#fff;border:1px solid #e3e7e2;border-radius:7px;padding:19px 20px 14px;overflow:hidden}
.wrong-row:hover{border-color:#c8d3c8;box-shadow:0 4px 16px #244d3710}
.wrong-word{display:grid;grid-template-columns:auto 30px 1fr;align-items:center;column-gap:6px;min-width:0}
.wrong-word .word-link{font-size:24px}
.wrong-word>p{grid-column:1/-1;font-size:12px;color:#69766d;margin-top:8px;overflow-wrap:anywhere}
.wrong-metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;border-top:1px solid #edf0ec;margin-top:15px;padding-top:15px}
.wrong-metrics>div{min-width:0}
.wrong-metrics span{display:block;font-size:9px;color:#929b93;margin-bottom:5px}
.wrong-metrics strong{font-size:18px;font-weight:600;overflow-wrap:anywhere}
.wrong-metrics .wrong-number{color:#b56f5e}
.wrong-metrics .wrong-date{font-size:11px;line-height:1.4}
.wrong-metrics small{font-size:9px;margin-left:3px}
.wrong-bar{height:4px;border-radius:999px;background:#f0e3de;margin-top:15px;overflow:hidden}
.wrong-bar>div{height:100%;background:#709477;min-width:0;transition:width .2s}
.wrong-row-footer{display:flex;align-items:center;justify-content:space-between;margin-top:8px;font-size:9px;color:#98a098}
.wrong-row-footer .button{min-height:28px}
.wrong-empty{margin-top:10px}

@media(max-width:900px){
  .wrong-list{grid-template-columns:1fr}
}
@media(max-width:600px){
  .wrong-title{align-items:flex-start}
  .wrong-title>div{width:100%}
  .wrong-title>.button{width:100%}
  .wrong-metrics{grid-template-columns:repeat(2,1fr);row-gap:14px}
  .wrong-word{grid-template-columns:auto 30px}
  .wrong-word>p{grid-column:1/-1}
}
"""
    css = css.rstrip() + "\n" + css_addition.strip() + "\n"

    # ------------------------------------------------------------------
    # 9. 최종 검증 후 백업 + 저장
    # ------------------------------------------------------------------
    required_checks = [
        ("오답노트 메뉴", "label:'오답노트'"),
        ("오답 통계", "const wrongStats="),
        ("오답 학습 범위", "scope==='wrong'?wrongWords"),
        ("오답 페이지", "page==='wrong'&&<section className=\"wrong-section\">"),
        ("CSS", ".wrong-list{"),
    ]
    combined = page + "\n" + css
    for label, token in required_checks:
        if token not in combined:
            fail(f"최종 검증 실패: {label}")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    page_backup = backup_file(page_path, stamp)
    css_backup = backup_file(css_path, stamp)

    page_path.write_text(page, encoding="utf-8", newline="\n")
    css_path.write_text(css, encoding="utf-8", newline="\n")

    print("\n[OK] 오답노트 기능을 적용했습니다.")
    print(f"  수정: {page_path}")
    print(f"  수정: {css_path}")
    print(f"  백업: {page_backup}")
    print(f"  백업: {css_backup}")
    print("\n다음 명령으로 확인하세요:")
    print("  npm run build")
    print("  npm run dev")
    print("\n추가된 기능:")
    print("  - 사이드바 오답노트")
    print("  - 오답 횟수 / 정답 횟수 / 정답률 / 최근 오답일")
    print("  - 오답 많은 순 자동 정렬")
    print("  - 오답 단어만 다시 학습")
    print("  - 기존 LocalStorage/DB 형식 변경 없음")


if __name__ == "__main__":
    main()
