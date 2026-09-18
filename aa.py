#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import shutil
import sys

def fail(msg):
    print(f"[ERROR] {msg}")
    sys.exit(1)

root = Path.cwd()
page = root / "app" / "page.tsx"

if not page.exists():
    fail("app/page.tsx를 찾지 못했습니다. 프로젝트 루트에서 실행해주세요.")

text = page.read_text(encoding="utf-8")

old = """</div>}:quiz.mode==='flash'&&revealed&&<div className="self-grade">"""
new = """</div>:quiz.mode==='flash'&&revealed&&<div className="self-grade">"""

count = text.count(old)
if count != 1:
    fail(f"수정 지점을 찾지 못했습니다. 예상 1개, 실제 {count}개")

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
bak = page.with_name(f"{page.name}.before-jsx-ternary-fix-{stamp}.bak")
shutil.copy2(page, bak)

text = text.replace(old, new, 1)
page.write_text(text, encoding="utf-8", newline="\n")

print("[OK] JSX ternary 문법 오류를 수정했습니다.")
print(f"수정: {page}")
print(f"백업: {bak}")
print("")
print("이제 확인:")
print("  npm run typecheck")
print("  npm run build")
