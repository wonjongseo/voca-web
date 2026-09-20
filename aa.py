#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import json
import shutil
import sys

MARKER = "WEB_XLSX_IMPORT_WITH_CATEGORY_V3"

def fail(message):
    print("\n[ERROR] " + message)
    sys.exit(1)

def replace_range(text, start_marker, end_marker, replacement, label):
    start = text.find(start_marker)
    if start < 0:
        fail(f"{label}: 시작점을 찾지 못했습니다: {start_marker}")
    end = text.find(end_marker, start)
    if end < 0:
        fail(f"{label}: 종료점을 찾지 못했습니다: {end_marker}")
    return text[:start] + replacement + text[end:]

root = Path.cwd()
page_path = root / "app" / "page.tsx"
vocab_path = root / "app" / "lib" / "vocabulary.ts"
package_path = root / "package.json"

for path in (page_path, vocab_path, package_path):
    if not path.exists():
        fail(f"{path}를 찾지 못했습니다. voca-web 프로젝트 루트에서 실행해주세요.")

page = page_path.read_text(encoding="utf-8")
vocab = vocab_path.read_text(encoding="utf-8")
package = json.loads(package_path.read_text(encoding="utf-8"))

if MARKER in page:
    print("[INFO] 웹 XLSX + 카테고리 가져오기 V3가 이미 적용되어 있습니다.")
    sys.exit(0)

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup_dir = root / f".web_xlsx_category_v3_backup_{stamp}"

for path in (page_path, vocab_path, package_path):
    dst = backup_dir / path.relative_to(root)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dst)

# ------------------------------------------------------------
# 1) SheetJS XLSX dependency
# 실패했던 이전 V2가 package.json까지만 수정했어도 안전하게 재실행 가능.
# ------------------------------------------------------------
dependencies = package.setdefault("dependencies", {})
dependencies["xlsx"] = "https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz"

package_path.write_text(
    json.dumps(package, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

# ------------------------------------------------------------
# 2) CSV parser aliases
# Day -> category / 대소문자 무관 alias.
# 이전 실패 패치가 vocabulary.ts까지만 바꾼 경우에도 no-op.
# ------------------------------------------------------------
if "'day':'category'" not in vocab and "'day': 'category'" not in vocab:
    alias_start = vocab.find("const aliases: Record<string,string> = ")
    if alias_start < 0:
        fail("vocabulary.ts aliases 선언을 찾지 못했습니다.")
    alias_end = vocab.find(";\n", alias_start)
    if alias_end < 0:
        fail("vocabulary.ts aliases 선언 끝을 찾지 못했습니다.")
    alias_end += 1

    aliases = """const aliases: Record<string,string> = {
  '영단어':'word',
  '영어단어':'word',
  '단어':'word',
  '의미':'meaning',
  '뜻':'meaning',
  '예시':'example',
  '예문':'example',
  '예시 뜻':'translation',
  '예문 뜻':'translation',
  '유의어':'synonyms',
  '메모':'memo',
  '카테고리':'category',
  '분류':'category',
  'day':'category',
  '즐겨찾기':'favorite',
}"""
    vocab = vocab[:alias_start] + aliases + vocab[alias_end:]

if "aliases[key.toLowerCase()]" not in vocab:
    old = "transformHeader: h => aliases[h.trim()] || h.trim().toLowerCase()"