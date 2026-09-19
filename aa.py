#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import shutil
import sys

MARKER = 'CATEGORY_AUTH_PERSISTENCE_V1'

def fail(msg):
    print('\n[ERROR] ' + msg)
    sys.exit(1)

root = Path.cwd()
page_path = root / 'app' / 'page.tsx'
firebase_path = root / 'app' / 'lib' / 'firebase.ts'

if not (root / 'package.json').exists():
    fail('프로젝트 루트에서 실행해주세요. package.json이 없습니다.')
if not page_path.exists():
    fail('app/page.tsx를 찾지 못했습니다.')
if not firebase_path.exists():
    fail('app/lib/firebase.ts를 찾지 못했습니다.')

page = page_path.read_text(encoding='utf-8')
firebase = firebase_path.read_text(encoding='utf-8')

if MARKER in page:
    print('[INFO] 카테고리 로그인/로그아웃 보존 패치가 이미 적용되어 있습니다.')
    sys.exit(0)

if 'function queueCloudSave(' not in page:
    fail('fix_logged_in_word_persistence가 적용된 코드가 아닙니다.')
if 'function mergeDatabasesForLogin(' not in page:
    fail('fix_offline_words_on_login이 적용된 코드가 아닙니다.')

# 1. constants
const_anchor = "const LOCAL_DIRTY_KEY='leaf-local-dirty-v1';"
if const_anchor not in page:
    fail('LOCAL_DIRTY_KEY를 찾지 못했습니다.')
const_insert = "\nconst CATEGORY_SNAPSHOT_KEY='leaf-category-snapshot-v1'; // " + MARKER + "\nconst CATEGORY_DIRTY_KEY='leaf-category-dirty-v1';"
page = page.replace(const_anchor, const_anchor + const_insert, 1)

# 2. helpers
helper_anchor = 'function rememberQuizWords(mode:Mode,pool:Word[],words:Word[]) {'
helpers = "function normalizedCategories(database:Database){\n  return [...new Set([\n    ...(database.categories??[]),\n    ...database.words.map(word=>(word.category??'').trim()).filter(Boolean),\n  ])].sort((a,b)=>a.localeCompare(b,'ko'));\n}\n\nfunction categoryListKey(database:Database){\n  return JSON.stringify(normalizedCategories(database));\n}\n\nfunction readCategorySnapshot(){\n  try {\n    const raw=localStorage.getItem(CATEGORY_SNAPSHOT_KEY);\n    if(!raw)return null;\n\n    const parsed=JSON.parse(raw) as {\n      ownerUid?:unknown;\n      categories?:unknown;\n    };\n\n    if(\n      !Array.isArray(parsed.categories) ||\n      !parsed.categories.every(item=>typeof item==='string')\n    ){\n      return null;\n    }\n\n    return {\n      ownerUid:typeof parsed.ownerUid==='string'?parsed.ownerUid:null,\n      categories:[...new Set(parsed.categories.map(item=>item.trim()).filter(Boolean))],\n    };\n  } catch {\n    return null;\n  }\n}\n\nfunction writeCategorySnapshot(database:Database,ownerUid:string|null){\n  const snapshot={\n    ownerUid,\n    categories:normalizedCategories(database),\n  };\n  localStorage.setItem(CATEGORY_SNAPSHOT_KEY,JSON.stringify(snapshot));\n}\n\nfunction mergeCategorySnapshot(\n  database:Database,\n  uid:string|null,\n  allowAnyOwner=false,\n){\n  const snapshot=readCategorySnapshot();\n  if(!snapshot)return database;\n\n  if(\n    !allowAnyOwner &&\n    snapshot.ownerUid &&\n    snapshot.ownerUid!==uid\n  ){\n    return database;\n  }\n\n  return {\n    ...database,\n    categories:[...new Set([\n      ...normalizedCategories(database),\n      ...snapshot.categories,\n    ])],\n  };\n}\n\nfunction categoryDirty(){\n  try {\n    return localStorage.getItem(CATEGORY_DIRTY_KEY)==='1';\n  } catch {\n    return false;\n  }\n}\n\nfunction clearCategoryDirtyIfSaved(uid:string,database:Database){\n  try {\n    const snapshot=readCategorySnapshot();\n    if(!snapshot)return;\n\n    const sameOwner=!snapshot.ownerUid||snapshot.ownerUid===uid;\n    const sameCategories=\n      JSON.stringify(snapshot.categories.slice().sort((a,b)=>a.localeCompare(b,'ko')))===\n      categoryListKey(database);\n\n    if(sameOwner&&sameCategories){\n      localStorage.removeItem(CATEGORY_DIRTY_KEY);\n      writeCategorySnapshot(database,uid);\n    }\n  } catch {}\n}\n\n"
if helper_anchor not in page:
    fail('category helper 삽입 위치를 찾지 못했습니다.')
page = page.replace(helper_anchor, helpers + helper_anchor, 1)

# 3. 초기 localStorage load에서 미동기화 카테고리 복구
initial_old = "    try {const raw=localStorage.getItem(STORAGE_KEY); const data=raw ? loadDatabase(raw) : emptyDB; dbRef.current=data; setDB(data);}"
initial_new = "    try {const raw=localStorage.getItem(STORAGE_KEY); let data=raw ? loadDatabase(raw) : emptyDB; const lastUid=localStorage.getItem(LAST_CLOUD_UID_KEY); if(categoryDirty())data=mergeCategorySnapshot(data,lastUid||null,true); if(!readCategorySnapshot()&&normalizedCategories(data).length)writeCategorySnapshot(data,lastUid||null); dbRef.current=data; setDB(data);}"
if initial_old not in page:
    fail('초기 localStorage 로드 코드를 찾지 못했습니다.')
page = page.replace(initial_old, initial_new, 1)

# 4. logout branch에서 카테고리 dirty snapshot 복구
logout_old = "        const data=raw ? loadDatabase(raw) : emptyDB;\n        dbRef.current=data;\n        setDB(data);"
logout_new = "        let data=raw ? loadDatabase(raw) : emptyDB;\n        if(categoryDirty()){\n          const lastUid=localStorage.getItem(LAST_CLOUD_UID_KEY);\n          data=mergeCategorySnapshot(data,lastUid||null,true);\n          localStorage.setItem(STORAGE_KEY,JSON.stringify(data));\n        }\n        dbRef.current=data;\n        setDB(data);"
if logout_old not in page:
    fail('로그아웃 DB 복구 지점을 찾지 못했습니다.')
page = page.replace(logout_old, logout_new, 1)

# 5. 로그인 merge에서 category dirty snapshot까지 병합
auth_merge_old = "      if(canMergeLocal){\n        next=mergeDatabasesForLogin(next,localDatabase);\n      }\n\n      try {"
auth_merge_new = "      if(canMergeLocal){\n        next=mergeDatabasesForLogin(next,localDatabase);\n      }\n\n      const hasCategoryDirty=categoryDirty();\n      if(hasCategoryDirty){\n        next=mergeCategorySnapshot(next,user.uid);\n      }\n\n      try {"
if auth_merge_old not in page:
    fail('로그인 DB 병합 지점을 찾지 못했습니다.')
page = page.replace(auth_merge_old, auth_merge_new, 1)

auth_queue_old = '      if(pending||canMergeLocal){'
auth_queue_new = '      if(pending||canMergeLocal||hasCategoryDirty){'
if auth_queue_old not in page:
    fail('로그인 후 재동기화 조건을 찾지 못했습니다.')
page = page.replace(auth_queue_old, auth_queue_new, 1)

# 6. commit에서 categories 변경을 별도 dirty snapshot으로 기록
commit_start = page.find('  function commit(next: Database) {')
commit_end = page.find('  function selectedCloudScope():CloudScope|null {', commit_start)
if commit_start < 0 or commit_end < 0:
    fail('commit 함수 범위를 찾지 못했습니다.')
commit_block = page[commit_start:commit_end]

commit_scope_anchor = '    if(user&&!scope){\n      setNotice(\'그룹 이름을 입력해주세요.\');\n      return false;\n    }'
commit_scope_insert = "    if(user&&!scope){\n      setNotice('그룹 이름을 입력해주세요.');\n      return false;\n    }\n\n    const trackCategoryPersistence=!user||scope?.type==='personal';\n    const categoriesChanged=\n      trackCategoryPersistence&&\n      categoryListKey(dbRef.current)!==categoryListKey(next);"
if commit_scope_anchor not in commit_block:
    fail('commit scope 검사 위치를 찾지 못했습니다.')
commit_block = commit_block.replace(commit_scope_anchor, commit_scope_insert, 1)

commit_store_old = "      localStorage.setItem(STORAGE_KEY,JSON.stringify(next));\n      if(!user)localStorage.setItem(LOCAL_DIRTY_KEY,'1');"
commit_store_new = "      localStorage.setItem(STORAGE_KEY,JSON.stringify(next));\n      if(categoriesChanged){\n        writeCategorySnapshot(next,user?.uid??null);\n        localStorage.setItem(CATEGORY_DIRTY_KEY,'1');\n      }\n      if(!user)localStorage.setItem(LOCAL_DIRTY_KEY,'1');"
if commit_store_old not in commit_block:
    fail('commit localStorage 저장 위치를 찾지 못했습니다.')
commit_block = commit_block.replace(commit_store_old, commit_store_new, 1)