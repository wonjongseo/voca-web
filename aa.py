#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import json
import re
import shutil
import sys

MARKER = "WEB_IMPORT_CURRENT_MAIN_V7"

def fail(message):
    print("\n[ERROR] " + message)
    sys.exit(1)

def replace_between(text, start_marker, end_marker, replacement, label):
    start = text.find(start_marker)
    if start < 0:
        fail(f"{label}: 시작점을 찾지 못했습니다.")
    end = text.find(end_marker, start)
    if end < 0:
        fail(f"{label}: 끝점을 찾지 못했습니다.")
    return text[:start] + replacement + text[end:]

root = Path.cwd()
page_path = root / "app" / "page.tsx"
package_path = root / "package.json"
css_path = root / "app" / "globals.css"

for path in (page_path, package_path, css_path):
    if not path.exists():
        fail(f"{path}를 찾지 못했습니다. voca-web 프로젝트 루트에서 실행해주세요.")

page = page_path.read_text(encoding="utf-8")
package = json.loads(package_path.read_text(encoding="utf-8"))
css = css_path.read_text(encoding="utf-8")

if MARKER in page:
    print("[INFO] V7이 이미 적용되어 있습니다.")
    sys.exit(0)

# 이 패치는 사용자가 올린 fix_web_direct_excel_import_v5 커밋 상태 전용.
required_current = [
    "async function importFile(file?:File){if(!file)return;try{if(file.size>5*1024*1024)",
    'accept=".csv,text/csv"',
    "<FileUp size={16}/>CSV 가져오기",
    "function acceptImport(){if(!pendingImport)return;",
    "const [pendingImport,setPendingImport] = useState<{words:Word[];skipped:number}|null>(null);",
]

for token in required_current:
    if token not in page:
        fail(
            "현재 page.tsx가 확인한 GitHub 커밋 상태와 다릅니다.\n"
            f"찾지 못한 기준 코드: {token[:90]}"
        )

if "xlsx" not in package.get("dependencies", {}):
    fail(
        "package.json에 xlsx dependency가 없습니다. "
        "현재 GitHub 커밋과 다른 상태입니다."
    )

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup_dir = root / f".web_import_v7_backup_{stamp}"

for path in (page_path, package_path, css_path):
    dst = backup_dir / path.relative_to(root)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dst)

# ------------------------------------------------------------------
# 1) XLSX import
# ------------------------------------------------------------------
user_import = "import type {User} from 'firebase/auth';"
xlsx_import = "import * as XLSX from 'xlsx';"

if xlsx_import not in page:
    if user_import not in page:
        fail("Firebase User import 위치를 찾지 못했습니다.")
    page = page.replace(user_import, user_import + "\n" + xlsx_import, 1)

# ------------------------------------------------------------------
# 2) Excel 셀 직접 파서
#    XLSX -> CSV -> PapaParse 경로는 사용하지 않음.
# ------------------------------------------------------------------
mode_anchor = "type Mode = 'flash'|'choice'|'typing'|'meaningTyping'|'context';"

if mode_anchor not in page:
    fail("Mode 선언 위치를 찾지 못했습니다.")

helpers = r"""// WEB_IMPORT_CURRENT_MAIN_V7
type ExcelImportColumn =
  |'category'
  |'word'