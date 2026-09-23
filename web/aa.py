from pathlib import Path

ROOT = Path.cwd()

def find_root(start: Path) -> Path:
    for p in [start, *start.parents]:
        if (p / "web/app/page.tsx").exists():
            return p
    raise SystemExit("voca-web 저장소 루트 또는 그 하위에서 실행해주세요.")

ROOT = find_root(ROOT)
page = ROOT / "web/app/page.tsx"
s = page.read_text(encoding="utf-8")

def replace_once(old: str, new: str, label: str):
    global s
    if new in s:
        print(f"[skip] {label} (이미 적용됨)")
        return
    if old not in s:
        raise SystemExit(f"[ERROR] {label} 패턴을 찾지 못했습니다.")
    s = s.replace(old, new, 1)
    print(f"[ok] {label}")

replace_once(
    "  const typingInputRef = useRef<HTMLInputElement>(null);\n",
    "  const typingInputRef = useRef<HTMLInputElement>(null);\n  const meaningHintBoxRef = useRef<HTMLDivElement>(null);\n",
    "meaningHintBoxRef 추가",
)

replace_once(
    '        {visibleMeaningHints.length>0&&<div className="meaning-hint-box">\n',
    '        {visibleMeaningHints.length>0&&<div ref={meaningHintBoxRef} className="meaning-hint-box">\n',
    "힌트 박스 ref 연결",
)

replace_once(
    """              requestAnimationFrame(()=>
                typingInputRef.current?.focus()
              );
""",
    """              requestAnimationFrame(()=>{
                meaningHintBoxRef.current?.scrollIntoView({
                  behavior:'smooth',
                  block:'center',
                });

                typingInputRef.current?.focus();
              });
""",
    "힌트 클릭 시 부드러운 스크롤",
)

page.write_text(s, encoding="utf-8", newline="\n")

print("\n완료.")
print("확인:")
print("  cd web")
print("  npm run build")
