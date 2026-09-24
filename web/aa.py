from pathlib import Path

ROOT = Path.cwd()
for p in [ROOT, *ROOT.parents]:
    if (p / "web/app/page.tsx").exists() and (p / "web/app/globals.css").exists():
        ROOT = p
        break
else:
    raise SystemExit("voca-web 저장소 루트 또는 그 하위에서 실행해주세요.")

page = ROOT / "web/app/page.tsx"
s = page.read_text(encoding="utf-8")

# 필수 state 추가
anchor = "  const [multiCategoryDialogOpen,setMultiCategoryDialogOpen] = useState(false);"
if anchor not in s:
    raise SystemExit("[ERROR] multiCategoryDialogOpen state를 찾지 못했습니다.")

adds = []
if "const [multiCategorySearch,setMultiCategorySearch]" not in s:
    adds.append("  const [multiCategorySearch,setMultiCategorySearch] = useState('');")
if "const [studyCategoryPresets,setStudyCategoryPresets]" not in s:
    adds.append("  const [studyCategoryPresets,setStudyCategoryPresets] = useState<Record<string,string[]>>({});")
if "const [studyPresetName,setStudyPresetName]" not in s:
    adds.append("  const [studyPresetName,setStudyPresetName] = useState('');")
if adds:
    s = s.replace(anchor, anchor + "\n" + "\n".join(adds), 1)

# summary helper
if "const studyCategorySummary=" not in s:
    helper = (
        "  const studyCategorySummary=(values:string[])=>{\n"
        "    if(!values.length)return '';\n"
        "    if(values.length===1)return values[0];\n"
        "    return `${values[0]} 외 ${values.length-1}개`;\n"
        "  };\n\n"
    )
    a = "  const [studyCategories,setStudyCategories] = useState<string[]>([]);"
    i = s.find(a)
    if i == -1:
        raise SystemExit("[ERROR] studyCategories state를 찾지 못했습니다.")
    j = s.find("\n", i) + 1
    s = s[:j] + helper + s[j:]

# 화면 요약 간결화
s = s.replace(
    "{scope==='categories'&&<span className=\"muted\">선택된 카테고리: {studyCategories.join(', ')}</span>}",
    "{scope==='categories'&&studyCategories.length>0&&<span className=\"study-category-summary\">선택된 카테고리 · {studyCategorySummary(studyCategories)}</span>}",
)

# 기존 다이얼로그들 전부 제거: 첫 multiCategoryDialogOpen 렌더부터 footer 직전까지
start_token = "{multiCategoryDialogOpen&&"
footer_token = "    <footer><span>Leafy."
start = s.find(start_token)
footer = s.find(footer_token)
if footer == -1:
    raise SystemExit("[ERROR] footer를 찾지 못했습니다.")
if start != -1 and start < footer:
    s = s[:start] + s[footer:]

dialog = (
"    {multiCategoryDialogOpen&&<div className=\"multi-category-overlay\" role=\"presentation\" onMouseDown={e=>{if(e.target===e.currentTarget){setMultiCategorySearch('');setMultiCategoryDialogOpen(false);}}}>\n"
"      <div className=\"modal multi-category-modal\" role=\"dialog\" aria-modal=\"true\" aria-labelledby=\"multi-category-title\">\n"
"        <h2 id=\"multi-category-title\">학습할 카테고리 선택</h2>\n"
"        <p className=\"muted\">카테고리를 검색하거나 저장한 조합을 불러올 수 있어요.</p>\n"
"\n"
"        <label className=\"multi-category-search\">\n"
"          <Search size={16}/>\n"
"          <input autoFocus placeholder=\"카테고리 검색\" value={multiCategorySearch} onChange={e=>setMultiCategorySearch(e.target.value)}/>\n"
"        </label>\n"
"\n"
"        <div className=\"category-list multi-category-list\">\n"
"          {categoryNames.filter(category=>category.toLowerCase().includes(multiCategorySearch.trim().toLowerCase())).map(category=>{const checked=studyCategories.includes(category);return <label className=\"category-row\" key={category}><span><input type=\"checkbox\" checked={checked} onChange={e=>setStudyCategories(current=>e.target.checked?[...new Set([...current,category])]:current.filter(value=>value!==category))}/>{' '}{category}</span><span>{db.words.filter(w=>(w.category??'')===category).length}개</span></label>})}\n"
"        </div>\n"
"\n"
"        <div className=\"multi-category-presets\">\n"
"          <div className=\"multi-category-presets-head\"><strong>저장한 복수 선택</strong><span>{Object.keys(studyCategoryPresets).length}개</span></div>\n"
"          {Object.entries(studyCategoryPresets).length?<div className=\"multi-category-preset-list\">{Object.entries(studyCategoryPresets).map(([name,categories])=><div className=\"multi-category-preset-row\" key={name}><button type=\"button\" className=\"multi-category-preset-load\" onClick={()=>setStudyCategories(categories)}><strong>{name}</strong><span>{studyCategorySummary(categories)}</span></button><button type=\"button\" className=\"button text-button\" disabled={!studyCategories.length} onClick={()=>setStudyCategoryPresets(current=>({...current,[name]:[...studyCategories]}))}>수정</button><button type=\"button\" className=\"button text-button danger\" onClick={()=>setStudyCategoryPresets(current=>{const next={...current};delete next[name];return next;})}>삭제</button></div>)}</div>:<p className=\"muted\">아직 저장한 복수 선택이 없어요.</p>}\n"
"          <div className=\"multi-category-preset-save\"><input placeholder=\"새 조합 이름 (예: TOEIC 집중)\" value={studyPresetName} onChange={e=>setStudyPresetName(e.target.value)}/><button type=\"button\" className=\"button\" disabled={!studyPresetName.trim()||!studyCategories.length} onClick={()=>{const name=studyPresetName.trim();if(!name)return;setStudyCategoryPresets(current=>({...current,[name]:[...studyCategories]}));setStudyPresetName('');}}>현재 선택 저장</button></div>\n"
"        </div>\n"
"\n"
"        <div className=\"modal-footer\">\n"
"          <button type=\"button\" className=\"button\" onClick={()=>{setMultiCategorySearch('');setMultiCategoryDialogOpen(false);}}>취소</button>\n"
"          <button type=\"button\" className=\"button primary\" disabled={!studyCategories.length} onClick={()=>{setScope('categories');setMultiCategorySearch('');setMultiCategoryDialogOpen(false);}}>선택 완료 ({studyCategories.length})</button>\n"
"        </div>\n"
"      </div>\n"
"    </div>}\n"
)

footer = s.find(footer_token)
s = s[:footer] + dialog + s[footer:]

count = s.count("{multiCategoryDialogOpen&&")
if count != 1:
    raise SystemExit(f"[ERROR] 다이얼로그 렌더 블록이 {count}개 남았습니다.")
if 'placeholder="카테고리 검색"' not in s:
    raise SystemExit("[ERROR] 검색 입력란 삽입 실패")

page.write_text(s, encoding="utf-8", newline="\n")

css = ROOT / "web/app/globals.css"
c = css.read_text(encoding="utf-8")
if "/* MULTI_CATEGORY_CANONICAL_V3 */" not in c:
    styles = (
        "\n/* MULTI_CATEGORY_CANONICAL_V3 */\n"
        ".multi-category-overlay{position:fixed;inset:0;z-index:3000;display:flex;align-items:center;justify-content:center;padding:24px;background:rgba(33,52,43,.42);backdrop-filter:blur(2px)}\n"
        ".multi-category-modal{width:min(560px,calc(100vw - 32px));max-height:calc(100dvh - 48px);overflow:auto;margin:0;padding:30px;border:1px solid #e0e7dd;border-radius:10px;background:#fff;color:#32412f;box-shadow:0 24px 90px rgba(21,45,50,.22);font-family:inherit}\n"
        ".multi-category-modal *{font-family:inherit}\n"
        ".multi-category-search{display:flex;align-items:center;gap:8px;margin:16px 0 12px;padding:0 10px;border:1px solid var(--line);border-radius:6px;background:#fff}\n"
        ".multi-category-search input{width:100%;border:0;outline:0;padding:11px 0;background:transparent;color:inherit}\n"
        ".multi-category-list{max-height:220px;overflow:auto}\n"
        ".multi-category-presets{margin-top:18px;padding-top:16px;border-top:1px solid var(--line)}\n"
        ".multi-category-presets-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;font-size:12px}\n"
        ".multi-category-preset-list{display:grid;gap:7px}\n"
        ".multi-category-preset-row{display:grid;grid-template-columns:minmax(0,1fr) auto auto;align-items:center;gap:6px;padding:7px;border:1px solid var(--line);border-radius:6px}\n"
        ".multi-category-preset-load{min-width:0;display:grid;gap:3px;padding:4px 6px;background:transparent;text-align:left}\n"
        ".multi-category-preset-load span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--muted);font-size:10px}\n"
        ".multi-category-preset-save{display:flex;gap:8px;margin-top:10px}\n"
        ".multi-category-preset-save input{flex:1;min-width:0;border:1px solid var(--line);border-radius:5px;padding:9px 10px}\n"
        ".study-category-summary{display:inline-flex;align-items:center;min-height:38px;padding:0 10px;border:1px solid var(--line);border-radius:5px;background:#fff;color:var(--muted);font-size:11px;font-weight:500;white-space:nowrap;font-family:inherit}\n"
        "html[data-theme=\"dark\"] .multi-category-modal,html[data-theme=\"dark\"] .multi-category-search,html[data-theme=\"dark\"] .multi-category-preset-save input,html[data-theme=\"dark\"] .study-category-summary{background:var(--dark-surface);color:var(--dark-text);border-color:var(--dark-border)}\n"
        "@media(max-width:600px){.multi-category-overlay{padding:16px}.multi-category-modal{width:100%;max-height:calc(100dvh - 32px);padding:24px 20px}.multi-category-preset-save{flex-direction:column}}\n"
    )
    c += styles
    css.write_text(c, encoding="utf-8", newline="\n")

print("[ok] Web 복수 카테고리 다이얼로그를 단일 canonical 블록으로 재작성")
print("[ok] 검색란 확인")
print("[ok] 중앙 overlay 확인")
print("[ok] 선택 요약 a 외 N개 유지")
print("\n검증:")
print("  cd web")
print("  npm run build")
