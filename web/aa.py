from pathlib import Path
import sys

ROOT = Path.cwd()

# 이 스크립트는 web 폴더 안에서 실행하거나,
# 저장소 루트(voca-web)에서 실행해도 됩니다.
if (ROOT / "web" / "app" / "page.tsx").exists():
    WEB = ROOT / "web"
elif (ROOT / "app" / "page.tsx").exists():
    WEB = ROOT
else:
    raise SystemExit(
        "web/app/page.tsx 또는 app/page.tsx를 찾지 못했습니다.\n"
        "voca-web 저장소 루트 또는 web 폴더에서 실행해주세요."
    )

page_path = WEB / "app" / "page.tsx"
layout_path = WEB / "app" / "layout.tsx"

page = page_path.read_text(encoding="utf-8")
layout = layout_path.read_text(encoding="utf-8")

changed = []

# 1) Date.now()를 useState 초기 렌더에서 직접 호출하지 않도록 수정
old = "const [now,setNow] = useState(Date.now());"
new = "const [now,setNow] = useState(0); // HYDRATION_STABLE_TIME_V1"
if old in page:
    page = page.replace(old, new, 1)
    changed.append("page.tsx: useState(Date.now()) -> useState(0)")
elif new not in page:
    print("[WARN] now state 패턴을 찾지 못했습니다.")

# 2) mount 이후에만 실제 현재 시간을 넣음
old = """    setReady(true);
    const timer=setInterval(()=>setNow(Date.now()),30000);"""
new = """    setReady(true);
    setNow(Date.now()); // HYDRATION_STABLE_TIME_V1
    const timer=setInterval(()=>setNow(Date.now()),30000);"""
if old in page:
    page = page.replace(old, new, 1)
    changed.append("page.tsx: mount 후 현재 시간 설정")
elif "setNow(Date.now()); // HYDRATION_STABLE_TIME_V1" not in page:
    print("[WARN] setReady(true) 주변 패턴을 찾지 못했습니다.")

# 3) 최초 hydration 중 날짜 텍스트가 서버/클라이언트에서 달라지지 않도록
# ready가 true가 된 뒤에만 날짜를 표시
old = """<span className="date-label">{new Intl.DateTimeFormat('ko-KR',{month:'long',day:'numeric',weekday:'short'}).format(now)}</span>"""
new = """<span className="date-label">{ready?new Intl.DateTimeFormat('ko-KR',{month:'long',day:'numeric',weekday:'short'}).format(now):''}</span>"""
if old in page:
    page = page.replace(old, new, 1)
    changed.append("page.tsx: 날짜 라벨을 mount 후 표시")
elif new not in page:
    print("[WARN] date-label 패턴을 찾지 못했습니다.")

# 4) 브라우저 확장 프로그램이 html/body attribute를 주입하는 경우
# React hydration warning을 줄이기 위한 방어.
# 주의: __endic_crx__ 같이 DOM 노드 자체를 삽입하는 확장 프로그램 문제까지
# 완전히 막는 기능은 아닙니다.
old = '<html lang="ko">'
new = '<html lang="ko" suppressHydrationWarning>'
if old in layout:
    layout = layout.replace(old, new, 1)
    changed.append("layout.tsx: html suppressHydrationWarning 추가")

old = "<body>"
new = "<body suppressHydrationWarning>"
if old in layout:
    layout = layout.replace(old, new, 1)
    changed.append("layout.tsx: body suppressHydrationWarning 추가")

page_path.write_text(page, encoding="utf-8", newline="\n")
layout_path.write_text(layout, encoding="utf-8", newline="\n")

print("수정 완료:")
for item in changed:
    print(f" - {item}")

print()
print("다음 명령으로 확인하세요:")
print("  npm run build")
print("  npm run dev")
print()
print("중요:")
print("에러 로그의 __endic_crx__, data-wxt-integrated, cz-shortcut-listen은")
print("프로젝트 코드가 아니라 Chrome 확장 프로그램이 삽입한 DOM/속성입니다.")
print("수정 후에도 __endic_crx__가 mismatch에 나오면 해당 확장 프로그램을 끄거나")
print("시크릿 모드에서 재현 여부를 확인하세요.")
