from pathlib import Path
import re

ROOT = Path.cwd()
for p in [ROOT, *ROOT.parents]:
    if (p / "web/app/page.tsx").exists() and (p / "web/app/globals.css").exists() and (p / "app/lib/ui/home_screen.dart").exists():
        ROOT = p
        break
else:
    raise SystemExit("voca-web 저장소 루트 또는 그 하위에서 실행해주세요.")

page = ROOT / "web/app/page.tsx"
s = page.read_text(encoding="utf-8")

old_open = '''{multiCategoryDialogOpen&&<dialog open className="modal-shell multi-category-dialog" onCancel={()=>setMultiCategoryDialogOpen(false)}>
      <div className="modal">'''
new_open = '''{multiCategoryDialogOpen&&<div className="multi-category-overlay" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)setMultiCategoryDialogOpen(false);}}>
      <div className="modal multi-category-modal" role="dialog" aria-modal="true" aria-labelledby="multi-category-title">
        <h2 id="multi-category-title">학습할 카테고리 선택</h2>'''

if new_open not in s:
    if old_open not in s:
        raise SystemExit("[ERROR] web/app/page.tsx: 복수 카테고리 dialog 시작 부분을 찾지 못했습니다.")
    s = s.replace(old_open, new_open, 1)

s = s.replace(
    '''        <h2>학습할 카테고리 선택</h2>
        <p className="muted">여러 카테고리를 동시에 선택할 수 있어요.</p>''',
    '''        <p className="muted">여러 카테고리를 동시에 선택할 수 있어요.</p>''',
    1,
)

old_close = '''      </div>
    </dialog>}'''
new_close = '''      </div>
    </div>}'''

if new_close not in s:
    if old_close not in s:
        raise SystemExit("[ERROR] web/app/page.tsx: 복수 카테고리 dialog 끝 부분을 찾지 못했습니다.")
    s = s.replace(old_close, new_close, 1)

page.write_text(s, encoding="utf-8", newline="\n")
print("[ok] web/app/page.tsx")

css = ROOT / "web/app/globals.css"
c = css.read_text(encoding="utf-8")

styles = '''
/* MULTI_CATEGORY_CENTERED_DIALOG_V1 */
.multi-category-overlay{
  position:fixed;
  inset:0;
  z-index:1000;
  display:flex;
  align-items:center;
  justify-content:center;
  padding:24px;
  background:rgba(33,52,43,.40);
  backdrop-filter:blur(2px);
}

.multi-category-modal{
  width:min(540px,calc(100vw - 32px));
  max-height:calc(100dvh - 48px);
  overflow:auto;
  margin:0;
  padding:30px;
  border:1px solid #e0e7dd;
  border-radius:8px;
  color:#32412f;
  background:#fff;
  box-shadow:0 22px 85px rgba(21,45,50,.20);
}

.multi-category-modal h2{
  margin:0 0 14px;
}

html[data-theme="dark"] .multi-category-modal{
  background:var(--dark-surface);
  color:var(--dark-text);
  border-color:var(--dark-border);
}

@media(max-width:600px){
  .multi-category-overlay{
    padding:16px;
  }

  .multi-category-modal{
    width:100%;
    max-height:calc(100dvh - 32px);
    padding:24px 20px;
  }
}
'''

if "MULTI_CATEGORY_CENTERED_DIALOG_V1" not in c:
    c += "\n" + styles.strip() + "\n"
    css.write_text(c, encoding="utf-8", newline="\n")
    print("[ok] web/app/globals.css")
else:
    print("[skip] web/app/globals.css 이미 적용됨")

app = ROOT / "app/lib/ui/home_screen.dart"
a = app.read_text(encoding="utf-8")

old_builder = '''      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('학습할 카테고리 선택'),'''

new_builder = '''      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Center(
          child: AlertDialog(
          title: const Text('학습할 카테고리 선택'),'''

if new_builder not in a:
    if old_builder not in a:
        raise SystemExit("[ERROR] app/lib/ui/home_screen.dart: 복수 카테고리 AlertDialog 시작 부분을 찾지 못했습니다.")
    a = a.replace(old_builder, new_builder, 1)

pattern = re.compile(
    r"""(child: Text\('선택 완료 \(\$\{selected\.length\}\)'\),\s*\),\s*\],\s*)\),\s*\),\s*\);""",
    re.MULTILINE,
)
replacement = r"""\1          ),
        ),
      ),
    );"""

a2, count = pattern.subn(replacement, a, count=1)
if count > 0:
    a = a2
elif "builder: (context, setDialogState) => Center(" not in a:
    raise SystemExit("[ERROR] app/lib/ui/home_screen.dart: AlertDialog 닫기 부분을 찾지 못했습니다.")

app.write_text(a, encoding="utf-8", newline="\n")
print("[ok] app/lib/ui/home_screen.dart")

print("\n완료")
print("- Web: 화면 중앙 fixed overlay")
print("- Web: 바깥 영역 클릭 시 닫힘")
print("- App: AlertDialog를 Center로 명시")
print("\n검증:")
print("  cd app")
print("  dart format lib/ui/home_screen.dart")
print("  flutter analyze")
print("")
print("  cd ../web")
print("  npm run build")
