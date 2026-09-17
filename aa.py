#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
voca-web 카테고리 기능 패치

기능:
- 단어 등록/수정 시 카테고리 선택
- 카테고리 생성 / 이름 변경 / 삭제
- 단어장 카테고리 필터
- 단어 카드 / 상세 화면 카테고리 표시
- 학습 범위에서 특정 카테고리 선택
- CSV category 열 가져오기/내보내기
- 기존 LocalStorage 데이터와 하위 호환

사용:
  py add_categories.py
또는
  python add_categories.py

확인:
  npm run build
  npm run dev
"""

from __future__ import annotations
from datetime import datetime
from pathlib import Path
import shutil
import sys

MARKER = "CATEGORY_FEATURE_V1"


def die(message: str) -> None:
    print(f"\n[ERROR] {message}")
    sys.exit(1)


def replace_once(text: str, old: str, new: str, label: str, required: bool = True):
    count = text.count(old)
    if count == 1:
        return text.replace(old, new, 1), True
    if required:
        die(f"{label} 수정 지점을 찾지 못했습니다. (예상 1개, 실제 {count}개)\n현재 로컬 코드가 최신 main과 많이 달라졌을 수 있습니다.")
    return text, False


def backup(path: Path, stamp: str) -> Path:
    out = path.with_name(f"{path.name}.before-category-{stamp}.bak")
    shutil.copy2(path, out)
    return out


def patch_vocabulary(text: str) -> str:
    if MARKER in text:
        return text

    text, _ = replace_once(
        text,
        """  examples?: Example[]; synonymEntries?: string[]; meaningEntries?: string[];\n};""",
        f"""  examples?: Example[]; synonymEntries?: string[]; meaningEntries?: string[];\n  category?: string; // {MARKER}\n}};""",
        "Word.category",
    )
    text, _ = replace_once(
        text,
        "export type Database = { version: 1; words: Word[]; reviews: Review[] };",
        "export type Database = { version: 1; words: Word[]; reviews: Review[]; categories?: string[] };",
        "Database.categories",
    )
    text, _ = replace_once(
        text,
        "export const blankWord = (): Word => ({id: crypto.randomUUID(), word:'', meaning:'', example:'', translation:'', synonyms:'', memo:'', favorite:false, level:0, due:0, created:Date.now()});",
        "export const blankWord = (): Word => ({id: crypto.randomUUID(), word:'', meaning:'', example:'', translation:'', synonyms:'', memo:'', category:'', favorite:false, level:0, due:0, created:Date.now()});",
        "blankWord category",
    )

    old = "&& (w.examples === undefined || validExamples(w.examples)) && (w.synonymEntries === undefined || validSynonyms(w.synonymEntries)) && (w.meaningEntries === undefined || (validSynonyms(w.meaningEntries) && w.meaningEntries.length > 0 && w.meaningEntries.every(s=>!!s.trim()) && w.meaning === w.meaningEntries.join('; ')));"
    new = "&& (w.category === undefined || typeof w.category === 'string') && (w.examples === undefined || validExamples(w.examples)) && (w.synonymEntries === undefined || validSynonyms(w.synonymEntries)) && (w.meaningEntries === undefined || (validSynonyms(w.meaningEntries) && w.meaningEntries.length > 0 && w.meaningEntries.every(s=>!!s.trim()) && w.meaning === w.meaningEntries.join('; ')));"
    text, _ = replace_once(text, old, new, "validWord category")

    old = """  if(data.version !== 1 || !Array.isArray(data.words) || !data.words.every(validWord) || new Set(data.words.map((w: Word)=>w.id)).size !== data.words.length || !Array.isArray(data.reviews) || !data.reviews.every((r: Review)=>r && typeof r.date === 'string' && typeof r.correct === 'boolean' && typeof r.wordId === 'string')) throw new Error('저장된 데이터를 읽지 못했습니다. 원본 데이터를 보존하기 위해 저장을 중지했습니다.');\n  return data;"""
    new = """  if(data.version !== 1 || !Array.isArray(data.words) || !data.words.every(validWord) || new Set(data.words.map((w: Word)=>w.id)).size !== data.words.length || !Array.isArray(data.reviews) || !data.reviews.every((r: Review)=>r && typeof r.date === 'string' && typeof r.correct === 'boolean' && typeof r.wordId === 'string') || (data.categories !== undefined && (!Array.isArray(data.categories) || !data.categories.every((c: unknown)=>typeof c === 'string')))) throw new Error('저장된 데이터를 읽지 못했습니다. 원본 데이터를 보존하기 위해 저장을 중지했습니다.');\n  const categories=[...new Set([...(data.categories ?? []),...data.words.map((w: Word)=>w.category ?? '').filter(Boolean)])];\n  return {...data,categories};"""
    text, _ = replace_once(text, old, new, "loadDatabase categories")

    text, _ = replace_once(
        text,
        "const fields = ['word','meaning','example','translation','synonyms','memo','favorite','level','due','created'] as const;",
        "const fields = ['word','meaning','example','translation','synonyms','memo','category','favorite','level','due','created'] as const;",
        "CSV fields",
    )
    text, _ = replace_once(
        text,
        "'유의어':'synonyms','메모':'memo','즐겨찾기':'favorite'};",
        "'유의어':'synonyms','메모':'memo','카테고리':'category','분류':'category','즐겨찾기':'favorite'};",
        "CSV aliases",
    )
    text, _ = replace_once(
        text,
        "for(const key of ['word','meaning','example','translation','synonyms','memo'] as const) word[key] = (row[key] || '').trim();",
        "for(const key of ['word','meaning','example','translation','synonyms','memo','category'] as const) word[key] = (row[key] || '').trim();",
        "CSV category parse",
    )
    return text


def patch_page(text: str) -> str:
    if MARKER in text:
        return text

    text, _ = replace_once(text, "const emptyDB: Database = {version:1, words:[], reviews:[]};", "const emptyDB: Database = {version:1, words:[], reviews:[], categories:[]};", "emptyDB")
    text, _ = replace_once(text, "  const [filter,setFilter] = useState('all');\n  const [sort,setSort] = useState('new');", f"  const [filter,setFilter] = useState('all');\n  const [categoryFilter,setCategoryFilter] = useState('all'); // {MARKER}\n  const [sort,setSort] = useState('new');", "categoryFilter state")
    text, _ = replace_once(text, "  const [pendingImport,setPendingImport] = useState<{words:Word[];skipped:number}|null>(null);\n  const [quiz,setQuiz] = useState<Session|null>(null);", "  const [pendingImport,setPendingImport] = useState<{words:Word[];skipped:number}|null>(null);\n  const [categoryManager,setCategoryManager] = useState(false);\n  const [newCategory,setNewCategory] = useState('');\n  const [quiz,setQuiz] = useState<Session|null>(null);", "category manager state")

    text, _ = replace_once(text, "setDeleteId('');setPendingImport(null);setNotice('다른 탭의 변경사항을 불러왔습니다.');", "setDeleteId('');setPendingImport(null);setCategoryManager(false);setNotice('다른 탭의 변경사항을 불러왔습니다.');", "storage listener")
    text, _ = replace_once(text, "  const modalOpen=!!(editor||detail||deleteId||pendingImport);", "  const modalOpen=!!(editor||detail||deleteId||pendingImport||categoryManager);", "modalOpen")

    text, _ = replace_once(text, "  const wrongWords=db.words.filter(w=>latestResults.get(w.id)===false);\n  const today=db.reviews.filter(r=>r.date===localDate());", "  const wrongWords=db.words.filter(w=>latestResults.get(w.id)===false);\n  const categoryNames=[...new Set([...(db.categories??[]),...db.words.map(w=>(w.category??'').trim()).filter(Boolean)])].sort((a,b)=>a.localeCompare(b,'ko'));\n  const today=db.reviews.filter(r=>r.date===localDate());", "categoryNames")

    old_filtered = "  const filtered=db.words.filter(w=>(filter==='all'||filter==='favorite'&&w.favorite||filter==='due'&&w.due<=now||filter==='mastered'&&w.level>=4)&&`${w.word} ${w.meaning} ${getSynonyms(w).join(' ')} ${w.memo}`.toLowerCase().includes(search.toLowerCase())).sort((a,b)=>sort==='az'?a.word.localeCompare(b.word):sort==='due'?a.due-b.due:b.created-a.created);"
    new_filtered = "  const filtered=db.words.filter(w=>(filter==='all'||filter==='favorite'&&w.favorite||filter==='due'&&w.due<=now||filter==='mastered'&&w.level>=4)&&(categoryFilter==='all'||(w.category??'')===categoryFilter)&&`${w.word} ${w.meaning} ${getSynonyms(w).join(' ')} ${w.memo} ${w.category??''}`.toLowerCase().includes(search.toLowerCase())).sort((a,b)=>sort==='az'?a.word.localeCompare(b.word):sort==='due'?a.due-b.due:b.created-a.created);"
    text, _ = replace_once(text, old_filtered, new_filtered, "filtered")

    text, _ = replace_once(text, "  function closeModal(){setEditor(null);setDetail(null);setDeleteId('');setPendingImport(null);}", "  function closeModal(){setEditor(null);setDetail(null);setDeleteId('');setPendingImport(null);setCategoryManager(false);setNewCategory('');}", "closeModal")

    functions = r'''  function addCategory(){
    const name=newCategory.trim();
    if(!name){setNotice('카테고리 이름을 입력해주세요.');return;}
    if(categoryNames.some(category=>category.toLowerCase()===name.toLowerCase())){setNotice('이미 같은 이름의 카테고리가 있습니다.');return;}
    if(commit({...db,categories:[...categoryNames,name]})){setNewCategory('');setNotice(`‘${name}’ 카테고리를 추가했습니다.`);}
  }
  function renameCategory(name:string){
    const next=window.prompt('새 카테고리 이름을 입력해주세요.',name)?.trim();
    if(!next||next===name)return;
    if(categoryNames.some(category=>category!==name&&category.toLowerCase()===next.toLowerCase())){setNotice('이미 같은 이름의 카테고리가 있습니다.');return;}
    if(commit({...db,categories:categoryNames.map(category=>category===name?next:category),words:db.words.map(word=>(word.category??'')===name?{...word,category:next}:word)})){
      if(categoryFilter===name)setCategoryFilter(next);
      if(scope===`category:${name}`)setScope(`category:${next}`);
      setNotice(`카테고리 이름을 ‘${next}’(으)로 변경했습니다.`);
    }
  }
  function deleteCategory(name:string){
    if(!window.confirm(`‘${name}’ 카테고리를 삭제할까요?\n단어는 삭제되지 않고 카테고리만 해제됩니다.`))return;
    if(commit({...db,categories:categoryNames.filter(category=>category!==name),words:db.words.map(word=>(word.category??'')===name?{...word,category:''}:word)})){
      if(categoryFilter===name)setCategoryFilter('all');
      if(scope===`category:${name}`)setScope('all');
      setNotice(`‘${name}’ 카테고리를 삭제했습니다. 단어는 그대로 유지됩니다.`);
    }
  }
'''
    if "  function saveWord(event:React.FormEvent<HTMLFormElement>){" not in text:
        die("카테고리 관리 함수를 삽입할 위치를 찾지 못했습니다.")
    text = text.replace("  function saveWord(event:React.FormEvent<HTMLFormElement>){", functions + "  function saveWord(event:React.FormEvent<HTMLFormElement>){", 1)

    text, _ = replace_once(text, "    const next=cleanEntries({...editor,word:editor.word.trim(),meaning:editor.meaning.trim()});", "    const next=cleanEntries({...editor,word:editor.word.trim(),meaning:editor.meaning.trim(),category:(editor.category??'').trim()});", "saveWord trim")
    text, _ = replace_once(text, "    if(commit({...db,words:exists?db.words.map(w=>w.id===next.id?next:w):[next,...db.words]})){", "    const categories=next.category&&!categoryNames.includes(next.category)?[...categoryNames,next.category]:categoryNames;\n    if(commit({...db,categories,words:exists?db.words.map(w=>w.id===next.id?next:w):[next,...db.words]})){", "saveWord persist")

    old_import = "  function acceptImport(){if(!pendingImport)return;const seen=new Set(db.words.map(w=>w.word.toLowerCase()));const additions=pendingImport.words.filter(w=>{const key=w.word.toLowerCase();if(seen.has(key))return false;seen.add(key);return true;});if(commit({...db,words:[...additions,...db.words]})){setNotice(`${additions.length}개 단어를 가져왔습니다. ${pendingImport.words.length-additions.length+pendingImport.skipped}개 중복·빈 행은 건너뛰었습니다.`);closeModal();}}"
    new_import = "  function acceptImport(){if(!pendingImport)return;const seen=new Set(db.words.map(w=>w.word.toLowerCase()));const additions=pendingImport.words.filter(w=>{const key=w.word.toLowerCase();if(seen.has(key))return false;seen.add(key);return true;});const importedCategories=additions.map(w=>(w.category??'').trim()).filter(Boolean);const categories=[...new Set([...categoryNames,...importedCategories])];if(commit({...db,categories,words:[...additions,...db.words]})){setNotice(`${additions.length}개 단어를 가져왔습니다. ${pendingImport.words.length-additions.length+pendingImport.skipped}개 중복·빈 행은 건너뛰었습니다.`);closeModal();}}"
    text, _ = replace_once(text, old_import, new_import, "acceptImport")

    old_pool = "let pool=retryWords??(scope==='due'?due:scope==='wrong'?wrongWords:scope==='favorite'?db.words.filter(w=>w.favorite):db.words);"
    new_pool = "let pool=retryWords??(scope==='due'?due:scope==='wrong'?wrongWords:scope==='favorite'?db.words.filter(w=>w.favorite):scope.startsWith('category:')?db.words.filter(w=>(w.category??'')===scope.slice('category:'.length)):db.words);"
    if old_pool in text:
        text = text.replace(old_pool, new_pool, 1)
    elif "scope.startsWith('category:')" not in text:
        die("startQuiz 학습 범위 로직을 찾지 못했습니다.")

    old_notice = "scope==='wrong'?'다시 학습할 틀린 단어가 없습니다.':'저장한 단어가 없습니다.'"
    new_notice = "scope==='wrong'?'다시 학습할 틀린 단어가 없습니다.':scope.startsWith('category:')?'선택한 카테고리에 단어가 없습니다.':'저장한 단어가 없습니다.'"
    if old_notice in text:
        text = text.replace(old_notice, new_notice, 1)

    old_actions = "<button className=\"button text-button\" disabled={!ready||!!storageError} onClick={()=>fileRef.current?.click()}><FileUp size={16}/>CSV 가져오기</button><button className=\"button text-button\" disabled={!db.words.length} onClick={download}><ArrowDownToLine size={16}/>내보내기</button>"
    new_actions = "<button className=\"button text-button\" onClick={()=>setCategoryManager(true)} disabled={!ready||!!storageError}><Layers size={16}/>카테고리 관리</button><button className=\"button text-button\" disabled={!ready||!!storageError} onClick={()=>fileRef.current?.click()}><FileUp size={16}/>CSV 가져오기</button><button className=\"button text-button\" disabled={!db.words.length} onClick={download}><ArrowDownToLine size={16}/>내보내기</button>"
    text, _ = replace_once(text, old_actions, new_actions, "manager button")

    text, _ = replace_once(text, "<div className=\"search-sort\"><label className=\"search\">", "<div className=\"search-sort\"><select className=\"category-filter\" aria-label=\"카테고리 필터\" value={categoryFilter} onChange={e=>setCategoryFilter(e.target.value)}><option value=\"all\">모든 카테고리</option>{categoryNames.map(category=><option key={category} value={category}>{category} ({db.words.filter(w=>(w.category??'')===category).length})</option>)}</select><label className=\"search\">", "filter select")

    old_card_top = "<div className=\"word-card-top\"><span className={`status ${w.level>=4?'known':w.level?'learning':''}`}>{w.level>=4?'익숙해요':w.level?'학습 중':'새 단어'}</span><button"
    new_card_top = "<div className=\"word-card-top\"><div className=\"word-card-labels\"><span className={`status ${w.level>=4?'known':w.level?'learning':''}`}>{w.level>=4?'익숙해요':w.level?'학습 중':'새 단어'}</span>{w.category&&<span className=\"category-badge\">{w.category}</span>}</div><button"
    text, _ = replace_once(text, old_card_top, new_card_top, "card badge")

    text, _ = replace_once(text, "<option value=\"wrong\">틀린 단어 ({wrongWords.length})</option></select>", "<option value=\"wrong\">틀린 단어 ({wrongWords.length})</option>{categoryNames.map(category=><option key={category} value={`category:${category}`}>카테고리 · {category} ({db.words.filter(w=>(w.category??'')===category).length})</option>)}</select>", "study scope")

    text, _ = replace_once(text, "<WordEntriesEditor word={editor} onChange={setEditor}/><label>메모", "<WordEntriesEditor word={editor} onChange={setEditor}/><label>카테고리<input list=\"category-options\" placeholder=\"카테고리 선택 또는 새로 입력\" maxLength={60} value={editor.category??''} onChange={e=>setEditor({...editor,category:e.target.value})}/><datalist id=\"category-options\">{categoryNames.map(category=><option key={category} value={category}/>)}</datalist></label><label>메모", "editor category")

    text, _ = replace_once(text, "<h2 id=\"modal-title\" className=\"detail-word\">{detail.word}</h2><MeaningList word={detail}/>", "<h2 id=\"modal-title\" className=\"detail-word\">{detail.word}</h2>{detail.category&&<div className=\"detail-category\"><span className=\"category-badge\">{detail.category}</span></div>}<MeaningList word={detail}/>", "detail category")

    old_branch = ":pendingImport?<><p className=\"eyebrow\">CSV IMPORT</p>"
    new_branch = r''':categoryManager?<><p className="eyebrow">WORD CATEGORIES</p><h2 id="modal-title">카테고리 관리</h2><p className="muted">단어를 주제별로 묶어 관리하고, 카테고리별로 학습할 수 있어요.</p><div className="category-add-row"><input aria-label="새 카테고리 이름" placeholder="예: TOEIC, 회사 영어" maxLength={60} value={newCategory} onChange={e=>setNewCategory(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&!e.nativeEvent.isComposing){e.preventDefault();addCategory();}}}/><button type="button" className="button primary" onClick={addCategory}><Plus size={16}/>추가</button></div>{categoryNames.length?<div className="category-list">{categoryNames.map(category=><div className="category-row" key={category}><div><strong>{category}</strong><span>{db.words.filter(w=>(w.category??'')===category).length}개 단어</span></div><div className="actions"><button type="button" className="icon-button" aria-label={`${category} 이름 변경`} title="이름 변경" onClick={()=>renameCategory(category)}><Pencil size={15}/></button><button type="button" className="icon-button danger" aria-label={`${category} 삭제`} title="카테고리 삭제" onClick={()=>deleteCategory(category)}><Trash2 size={15}/></button></div></div>)}</div>:<div className="category-empty">아직 만든 카테고리가 없어요.</div>}<div className="modal-footer"><button type="button" className="button primary" onClick={closeModal}>완료</button></div></>:pendingImport?<><p className="eyebrow">CSV IMPORT</p>'''
    text, _ = replace_once(text, old_branch, new_branch, "manager modal")
    return text


def patch_css(css: str) -> str:
    if f"/* {MARKER} */" in css:
        return css
    addition = r"""
/* CATEGORY_FEATURE_V1 */
.word-card-labels{display:flex;align-items:center;gap:6px;min-width:0;flex-wrap:wrap}
.category-badge{display:inline-flex;align-items:center;max-width:170px;padding:4px 8px;border-radius:999px;background:#edf3ef;color:#55705d;border:1px solid #dbe7de;font-size:9px;font-weight:700;line-height:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.category-filter{max-width:190px}
.detail-category{margin:-5px 0 15px}
.category-add-row{display:flex;gap:8px;margin:20px 0 14px}
.category-add-row input{flex:1;min-width:0}
.category-add-row .button{flex:none}
.category-list{display:flex;flex-direction:column;border:1px solid var(--line);border-radius:9px;overflow:hidden;max-height:330px;overflow-y:auto}
.category-row{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:13px 14px;background:#fff;border-bottom:1px solid var(--line)}
.category-row:last-child{border-bottom:0}
.category-row>div:first-child{display:flex;flex-direction:column;gap:4px;min-width:0}
.category-row strong{font-size:13px;overflow-wrap:anywhere}
.category-row span{font-size:9px;color:#89938c}
.category-empty{padding:30px 16px;border:1px dashed #d9e1db;border-radius:9px;text-align:center;color:#8b958e;font-size:11px}
@media(max-width:760px){.category-filter{max-width:none;width:100%}.category-add-row{align-items:stretch}}
"""
    return css.rstrip() + "\n\n" + addition.strip() + "\n"


def validate(vocab: str, page: str, css: str) -> None:
    checks = [
        ("Word category", "category?: string"),
        ("Database categories", "categories?: string[]"),
        ("categoryNames", "const categoryNames="),
        ("filter", 'aria-label="카테고리 필터"'),
        ("manager", "카테고리 관리"),
        ("study scope", "카테고리 · {category}"),
        ("editor", "editor.category??''"),
        ("css", ".category-badge{"),
    ]
    merged = vocab + "\n" + page + "\n" + css
    missing = [label for label, token in checks if token not in merged]
    if missing:
        die("최종 검증 실패: " + ", ".join(missing))
    if page.count("const categoryNames=") != 1:
        die("categoryNames 선언 개수가 비정상입니다.")
    if page.count("function addCategory()") != 1:
        die("addCategory 함수 개수가 비정상입니다.")


def main() -> None:
    root = Path.cwd()
    package = root / "package.json"
    page_path = root / "app" / "page.tsx"
    vocab_path = root / "app" / "lib" / "vocabulary.ts"
    css_path = root / "app" / "globals.css"

    if not package.exists():
        die("package.json이 없습니다. voca-web 프로젝트 루트에서 실행해주세요.")
    for path in (page_path, vocab_path, css_path):
        if not path.exists():
            die(f"필수 파일을 찾지 못했습니다: {path}")

    page = page_path.read_text(encoding="utf-8")
    vocab = vocab_path.read_text(encoding="utf-8")
    css = css_path.read_text(encoding="utf-8")

    if MARKER in page and MARKER in vocab:
        print("[INFO] 카테고리 패치가 이미 적용되어 있습니다.")
        return

    vocab = patch_vocabulary(vocab)
    page = patch_page(page)
    css = patch_css(css)
    validate(vocab, page, css)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backups = [backup(page_path, stamp), backup(vocab_path, stamp), backup(css_path, stamp)]

    page_path.write_text(page, encoding="utf-8", newline="\n")
    vocab_path.write_text(vocab, encoding="utf-8", newline="\n")
    css_path.write_text(css, encoding="utf-8", newline="\n")

    print("\n[OK] 카테고리 기능을 적용했습니다.")
    print(f"수정: {page_path}")
    print(f"수정: {vocab_path}")
    print(f"수정: {css_path}")
    for item in backups:
        print(f"백업: {item}")
    print("\n추가된 기능")
    print("- 단어 등록/수정 시 카테고리 선택")
    print("- 카테고리 추가 / 이름 변경 / 삭제")
    print("- 단어 목록 카테고리 필터")
    print("- 단어 카드와 상세 화면 카테고리 표시")
    print("- 카테고리별 퀴즈 학습")
    print("- CSV category 열 가져오기/내보내기")
    print("- 기존 저장 데이터 자동 호환")
    print("\n확인:")
    print("  npm run build")
    print("  npm run dev")


if __name__ == "__main__":
    main()
