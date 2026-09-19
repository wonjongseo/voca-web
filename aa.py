#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from datetime import datetime
import shutil
import sys

MARKER = 'CLOUD_SAVE_DURABILITY_V2'

def fail(msg):
    print('\n[ERROR] ' + msg)
    sys.exit(1)

def replace_range(text, start_marker, end_marker, replacement, label):
    start = text.find(start_marker)
    if start < 0:
        fail(label + ': 시작점을 찾지 못했습니다.')
    end = text.find(end_marker, start)
    if end < 0:
        fail(label + ': 종료점을 찾지 못했습니다.')
    return text[:start] + replacement + text[end:]

root = Path.cwd()
page_path = root / 'app' / 'page.tsx'

if not (root / 'package.json').exists():
    fail('프로젝트 루트에서 실행해주세요. package.json이 없습니다.')
if not page_path.exists():
    fail('app/page.tsx를 찾지 못했습니다.')

text = page_path.read_text(encoding='utf-8')

if MARKER in text:
    print('[INFO] 저장 안정화 V2가 이미 적용되어 있습니다.')
    sys.exit(0)

# 1. pending key
const_anchor = "const REUSE_LAST_CATEGORY_KEY = 'leaf-reuse-last-category-v1'; // REUSE_LAST_CATEGORY_V1"
if const_anchor not in text:
    fail('REUSE_LAST_CATEGORY_KEY 위치를 찾지 못했습니다.')
if "CLOUD_PENDING_PREFIX" not in text:
    text = text.replace(const_anchor, const_anchor + "\nconst CLOUD_PENDING_PREFIX='leaf-cloud-pending-v2'; // " + MARKER, 1)

# 2. pending helper
helper_anchor = 'function rememberQuizWords(mode:Mode,pool:Word[],words:Word[]) {'
helpers = "function cloudPendingKey(uid:string,scope:CloudScope){\n  const scopeKey=scope.type==='personal'?'personal':`group:${scope.groupId}`;\n  return `${CLOUD_PENDING_PREFIX}:${uid}:${scopeKey}`;\n}\n\nfunction readPendingCloudDatabase(uid:string,scope:CloudScope):Database|null {\n  try {\n    const raw=localStorage.getItem(cloudPendingKey(uid,scope));\n    return raw?loadDatabase(raw):null;\n  } catch {\n    return null;\n  }\n}\n\nfunction writePendingCloudDatabase(uid:string,scope:CloudScope,database:Database){\n  const serialized=JSON.stringify(database);\n  localStorage.setItem(cloudPendingKey(uid,scope),serialized);\n  return serialized;\n}\n\nfunction clearPendingCloudDatabase(uid:string,scope:CloudScope,expectedSerialized:string){\n  try {\n    const key=cloudPendingKey(uid,scope);\n    if(localStorage.getItem(key)===expectedSerialized){\n      localStorage.removeItem(key);\n    }\n  } catch {}\n}\n\n"
if 'function cloudPendingKey(' not in text:
    if helper_anchor not in text:
        fail('rememberQuizWords 위치를 찾지 못했습니다.')
    text = text.replace(helper_anchor, helpers + helper_anchor, 1)

# 3. queue ref
ref_anchor = '  const firebaseUserRef = useRef<User|null>(null);'
if 'cloudSaveQueueRef' not in text:
    if ref_anchor not in text:
        fail('firebaseUserRef 위치를 찾지 못했습니다.')
    text = text.replace(ref_anchor, ref_anchor + "\n  const cloudSaveQueueRef = useRef<Promise<void>>(Promise.resolve());", 1)

# 4. auth effect 전체를 함수 경계로 교체
auth_block = "  useEffect(()=>listenFirebaseUser(user=>{\n    firebaseUserRef.current=user;\n    setFirebaseUser(user);\n    setQuiz(null);\n    setEditor(null);\n    setDetail(null);\n\n    if(!user){\n      try {\n        const raw=localStorage.getItem(STORAGE_KEY);\n        const data=raw ? loadDatabase(raw) : emptyDB;\n        dbRef.current=data;\n        setDB(data);\n      } catch {}\n      return;\n    }\n\n    const personalScope:CloudScope={type:'personal'};\n    const pending=readPendingCloudDatabase(user.uid,personalScope);\n\n    if(pending){\n      try {\n        localStorage.setItem(STORAGE_KEY,JSON.stringify(pending));\n      } catch {}\n\n      dbRef.current=pending;\n      setDB(pending);\n      setCloudScope(personalScope);\n      queueCloudSave(user,personalScope,pending);\n      setNotice('저장 중이던 단어장을 복구하고 Firebase에 다시 동기화하고 있습니다.');\n      return;\n    }\n\n    void loadCloudDatabase(user,personalScope).then(next=>{\n      try {\n        localStorage.setItem(STORAGE_KEY,JSON.stringify(next));\n      } catch {}\n\n      dbRef.current=next;\n      setDB(next);\n      setCloudScope(personalScope);\n      setNotice('Firebase 단어장을 불러왔습니다.');\n    }).catch(err=>{\n      setNotice(err instanceof Error?err.message:'Firebase 단어장을 불러오지 못했습니다.');\n    });\n  }),[]);"
auth_start = '  useEffect(()=>listenFirebaseUser(user=>{'
auth_end = '  useEffect(()=>()=>stopPronunciation(),[page,quiz?.index,quiz?.mode]);'
text = replace_range(text, auth_start, auth_end, auth_block + '\n', '로그인 초기화')

# 5. commit 전체 교체
commit_block = "  function queueCloudSave(user:User,scope:CloudScope,next:Database){\n    let serialized:string;\n\n    try {\n      serialized=writePendingCloudDatabase(user.uid,scope,next);\n    } catch {\n      setNotice('브라우저에 클라우드 저장 대기 데이터를 기록하지 못했습니다.');\n      return;\n    }\n\n    cloudSaveQueueRef.current=cloudSaveQueueRef.current\n      .catch(()=>{})\n      .then(async()=>{\n        try {\n          await saveCloudDatabase(user,scope,next);\n          clearPendingCloudDatabase(user.uid,scope,serialized);\n        } catch(err) {\n          setNotice(\n            err instanceof Error\n              ?`Firebase 저장 실패: ${err.message} · 로컬에는 보관되어 있습니다.`\n              :'Firebase 저장에 실패했습니다. 로컬에는 보관되어 있습니다.'\n          );\n        }\n      });\n  }\n\n  function commit(next: Database) {\n    if(storageError){\n      setNotice('저장소 오류를 해결한 후 다시 시도해주세요.');\n      return false;\n    }\n\n    const user=firebaseUserRef.current;\n    const scope=user?selectedCloudScope():null;\n\n    if(user&&!scope){\n      setNotice('그룹 이름을 입력해주세요.');\n      return false;\n    }\n\n    try {\n      localStorage.setItem(STORAGE_KEY,JSON.stringify(next));\n    } catch {\n      setNotice('저장하지 못했습니다. 브라우저 저장 공간이나 설정을 확인해주세요.');\n      return false;\n    }\n\n    dbRef.current=next;\n    setDB(next);\n\n    if(user&&scope){\n      queueCloudSave(user,scope,next);\n    }\n\n    return true;\n  }\n"
commit_start = '  function commit(next: Database) {'
commit_end = '  function selectedCloudScope():CloudScope|null {'
text = replace_range(text, commit_start, commit_end, commit_block, 'commit 저장 로직')

# 6. saveToCloud 전체 교체
save_block = "  async function saveToCloud() {\n    const scope=selectedCloudScope();\n    if(!firebaseUser){setNotice('먼저 로그인해주세요.');return;}\n    if(!scope){setNotice('그룹 이름을 입력해주세요.');return;}\n\n    setCloudBusy(true);\n    try {\n      await cloudSaveQueueRef.current.catch(()=>{});\n\n      const current=dbRef.current;\n      const serialized=writePendingCloudDatabase(firebaseUser.uid,scope,current);\n\n      await saveCloudDatabase(firebaseUser,scope,current);\n      clearPendingCloudDatabase(firebaseUser.uid,scope,serialized);\n\n      setCloudScope(scope);\n      setNotice(scope.type==='personal'?'내 단어장을 클라우드에 저장했습니다.':'그룹 단어장을 클라우드에 저장했습니다.');\n    } catch(err) {\n      setNotice(err instanceof Error?err.message:'클라우드 저장에 실패했습니다.');\n    } finally {\n      setCloudBusy(false);\n    }\n  }\n"
save_start = '  async function saveToCloud() {'
save_end = '  async function loadFromCloud() {'
text = replace_range(text, save_start, save_end, save_block, 'saveToCloud')

# 7. loadFromCloud는 pending save queue가 끝난 뒤 cloud read
load_start = text.find('  async function loadFromCloud() {')
load_end = text.find('  const due=', load_start)
if load_start < 0 or load_end < 0:
    fail('loadFromCloud 범위를 찾지 못했습니다.')
load_block = text[load_start:load_end]
needle = "    setCloudBusy(true);\n    try {\n      const next=await loadCloudDatabase(firebaseUser,scope);"
replacement = "    setCloudBusy(true);\n    try {\n      await cloudSaveQueueRef.current.catch(()=>{});\n      const next=await loadCloudDatabase(firebaseUser,scope);"
if 'await cloudSaveQueueRef.current.catch(()=>{});' not in load_block:
    if needle not in load_block:
        fail('loadFromCloud 내부 cloud read 지점을 찾지 못했습니다.')
    load_block = load_block.replace(needle, replacement, 1)
    text = text[:load_start] + load_block + text[load_end:]

# 8. 검증
required = [
    MARKER,
    "const CLOUD_PENDING_PREFIX='leaf-cloud-pending-v2';",
    'function cloudPendingKey(',