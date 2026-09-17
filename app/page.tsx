'use client';

import {useEffect, useRef, useState} from 'react';
import {createPortal} from 'react-dom';
import {ArrowDownToLine, ArrowLeft, ArrowRight, AudioLines, BookOpen, ChartNoAxesCombined, Check, ChevronRight, CircleHelp, Clock3, FileUp, Flame, Layers, Leaf, Pencil, Plus, RotateCcw, Search, Sprout, Star, Trash2, X} from 'lucide-react';
import {cleanEntries, getExamples, getSynonyms, blankWord, demoWords, exportCSV, loadDatabase, localDate, parseCSV, schedule, shuffle, STORAGE_KEY, type Database, type Word} from './lib/vocabulary';

import {WordEntriesEditor, WordEntriesDetails, ExampleList, MeaningList} from './word-entries';

type Mode = 'flash'|'choice'|'typing'|'context';
type QuizChoice = string|{meaning:string;word:string;example:string;translation?:string};
type Session = {mode: Mode; words: Word[]; index: number; correct: number; incorrectIds?: string[]; choices: QuizChoice[][]};
const QUIZ_HISTORY_KEY = 'leaf-quiz-history-v1';
const modes = [{id:'flash' as const,name:'플래시카드',desc:'단어를 떠올리고, 카드를 뒤집어 확인해요.',icon:Layers},{id:'choice' as const,name:'객관식 퀴즈',desc:'단어에 맞는 의미를 골라보세요.',icon:CircleHelp},{id:'typing' as const,name:'철자 입력',desc:'의미를 보고 영어 단어를 완성해요.',icon:Pencil},{id:'context' as const,name:'예문 퀴즈',desc:'예문 속 빈칸에 들어갈 단어를 골라보세요.',icon:BookOpen}];
const emptyDB: Database = {version:1, words:[], reviews:[]};

const choiceMeaning=(choice:QuizChoice)=>typeof choice==='string'?choice:choice.meaning;
function makeChoices(target:Word,words:Word[]):QuizChoice[] {
  const selected:Word[]=[target];
  const meanings=new Set([target.meaning]);
  for(const word of shuffle(words)){
    if(word.id===target.id||meanings.has(word.meaning))continue;
    selected.push(word);
    meanings.add(word.meaning);
    if(selected.length===4)break;
  }
  return shuffle(selected.map(word=>{const example=getExamples(word)[0];return {meaning:word.meaning,word:word.word,example:example?.text??'',translation:example?.translation??''};}));
}

function ChoiceContent({choice,revealed,wordFirst=false}:{choice:QuizChoice;revealed:boolean;wordFirst?:boolean}) {
  const meaning=choiceMeaning(choice);
  const primary=wordFirst&&typeof choice!=='string'?choice.word:meaning;
  return <span className="choice-copy"><span className="choice-meaning">{primary}</span>{revealed&&typeof choice!=='string'&&<span className="choice-details"><strong>{wordFirst?choice.meaning:choice.word}</strong>{choice.example&&<span>{choice.example}</span>}{choice.translation&&<span className="choice-translation">{choice.translation}</span>}</span>}</span>;
}

function maskedExample(word:Word) {
  const example=getExamples(word)[0]?.text??'';
  const index=example.toLowerCase().indexOf(word.word.toLowerCase());
  return index<0?example:`${example.slice(0,index)}_____${example.slice(index+word.word.length)}`;
}

function preferredEnglishVoice(voices:SpeechSynthesisVoice[]) {
  const preferredNames=['natural','neural','google us english','microsoft aria','microsoft jenny','samantha','ava','zira'];
  return voices.filter(voice=>voice.lang.toLowerCase().startsWith('en')).sort((a,b)=>{
    const score=(voice:SpeechSynthesisVoice)=>{
      const language=voice.lang.toLowerCase();
      const name=voice.name.toLowerCase();
      return (language==='en-us'?100:language.startsWith('en-us')?90:language.startsWith('en-gb')?70:50)+preferredNames.reduce((total,term,index)=>total+(name.includes(term)?30-index:0),0);
    };
    return score(b)-score(a);
  })[0];
}

function acceptsSpelling(answer:string, expected:string) {
  const a=answer.trim().toLowerCase();
  const b=expected.trim().toLowerCase();
  if(a===b)return true;
  if(Math.abs(a.length-b.length)>1)return false;
  if(a.length===b.length){
    const differences:number[]=[];
    for(let i=0;i<a.length;i++)if(a[i]!==b[i])differences.push(i);
    return differences.length===1 || (differences.length===2 && differences[1]===differences[0]+1 && a[differences[0]]===b[differences[1]] && a[differences[1]]===b[differences[0]]);
  }
  const [shorter,longer]=a.length<b.length?[a,b]:[b,a];
  let shortIndex=0;
  let longIndex=0;
  let skipped=false;
  while(shortIndex<shorter.length&&longIndex<longer.length){
    if(shorter[shortIndex]===longer[longIndex]){shortIndex++;longIndex++;continue;}
    if(skipped)return false;
    skipped=true;
    longIndex++;
  }
  return true;
}

function readQuizHistory(): Record<string,string[]> {
  try {
    const parsed=JSON.parse(localStorage.getItem(QUIZ_HISTORY_KEY) || '{}');
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function writeQuizHistory(history: Record<string,string[]>) {
  try {localStorage.setItem(QUIZ_HISTORY_KEY,JSON.stringify(history));} catch {}
}

function selectBalancedWords(mode:Mode,pool:Word[],limit:number) {
  const history=readQuizHistory();
  const poolIds=new Set(pool.map(word=>word.id));
  const seen=(history[mode] || []).filter(id=>poolIds.has(id));
  const unseen=shuffle(pool.filter(word=>!seen.includes(word.id)));
  const seenWords=shuffle(seen.flatMap(id=>pool.find(word=>word.id===id) ?? []));
  const words=[...unseen,...seenWords].slice(0,limit);
  const pickedIds=words.map(word=>word.id);
  history[mode]=[...seen.filter(id=>!pickedIds.includes(id)),...pickedIds].filter(id=>poolIds.has(id)).slice(-pool.length);
  writeQuizHistory(history);
  return words;
}

export default function Home() {
  const [db,setDB] = useState<Database>(emptyDB);
  const dbRef = useRef(db);
  const [ready,setReady] = useState(false);
  const [storageError,setStorageError] = useState('');
  const [page,setPage] = useState('words');
  const [search,setSearch] = useState('');
  const [filter,setFilter] = useState('all');
  const [sort,setSort] = useState('new');
  const [editor,setEditor] = useState<Word|null>(null);
  const [detail,setDetail] = useState<Word|null>(null);
  const [deleteId,setDeleteId] = useState('');
  const [notice,setNotice] = useState('');
  const [pendingImport,setPendingImport] = useState<{words:Word[];skipped:number}|null>(null);
  const [quiz,setQuiz] = useState<Session|null>(null);
  const [scope,setScope] = useState('due');
  const [quizSize,setQuizSize] = useState('10');
  const [answer,setAnswer] = useState('');
  const [acceptedTypo,setAcceptedTypo] = useState(false);
  const [revealed,setRevealed] = useState(false);
  const [graded,setGraded] = useState<boolean|null>(null);
  const [now,setNow] = useState(Date.now());
  const fileRef = useRef<HTMLInputElement>(null);
  const modalRef = useRef<HTMLDialogElement>(null);
  const wordInputRef = useRef<HTMLInputElement>(null);
  const typingInputRef = useRef<HTMLInputElement>(null);
  const busyGrade = useRef(false);
  useEffect(()=>{
    try {const raw=localStorage.getItem(STORAGE_KEY); const data=raw ? loadDatabase(raw) : emptyDB; dbRef.current=data; setDB(data);}
    catch(err){setStorageError(err instanceof Error ? err.message : '브라우저 저장소에 접근할 수 없습니다.');}
    setReady(true);
    const timer=setInterval(()=>setNow(Date.now()),30000);
    const listener=(event:StorageEvent)=>{if(event.key===STORAGE_KEY){try{const data=event.newValue ? loadDatabase(event.newValue) : emptyDB; dbRef.current=data;setDB(data);setQuiz(null);setEditor(null);setDetail(null);setDeleteId('');setPendingImport(null);setNotice('다른 탭의 변경사항을 불러왔습니다.');}catch{setStorageError('다른 탭에서 변경된 데이터를 읽지 못했습니다.');}}};
    window.addEventListener('storage',listener);
    return ()=>{clearInterval(timer);window.removeEventListener('storage',listener);};
  },[]);
  useEffect(()=>{if(!notice)return; const id=setTimeout(()=>setNotice(''),5500);return ()=>clearTimeout(id);},[notice]);
  const modalOpen=!!(editor||detail||deleteId||pendingImport);
  useEffect(()=>{if(modalOpen)modalRef.current?.showModal();else modalRef.current?.close();},[modalOpen]);
  useEffect(()=>{
    if(!editor)return;
    const frame=requestAnimationFrame(()=>wordInputRef.current?.focus());
    return ()=>cancelAnimationFrame(frame);
  },[editor?.id]);
  useEffect(()=>{
    if(quiz?.mode!=='typing'||graded!==null)return;
    const frame=requestAnimationFrame(()=>typingInputRef.current?.focus());
    return ()=>cancelAnimationFrame(frame);
  },[quiz?.index,quiz?.mode,graded]);
  function commit(next: Database) {
    if(storageError){setNotice('저장소 오류를 해결한 후 다시 시도해주세요.');return false;}
    try {localStorage.setItem(STORAGE_KEY,JSON.stringify(next));dbRef.current=next;setDB(next);return true;}
    catch{setNotice('저장하지 못했습니다. 브라우저 저장 공간이나 설정을 확인해주세요.');return false;}
  }
  const due=db.words.filter(w=>w.due<=now);
  const latestResults=new Map<string,boolean>();
  for(let i=db.reviews.length-1;i>=0;i--){const review=db.reviews[i];if(!latestResults.has(review.wordId))latestResults.set(review.wordId,review.correct);}
  const wrongWords=db.words.filter(w=>latestResults.get(w.id)===false);
  const today=db.reviews.filter(r=>r.date===localDate());
  const mastered=db.words.filter(w=>w.level>=4).length;
  let streak=0;
  const dateSet=new Set(db.reviews.map(r=>r.date));
  const cursor=new Date();
  if(!dateSet.has(localDate(cursor)))cursor.setDate(cursor.getDate()-1);
  while(dateSet.has(localDate(cursor))){streak++;cursor.setDate(cursor.getDate()-1);}
  const filtered=db.words.filter(w=>(filter==='all'||filter==='favorite'&&w.favorite||filter==='due'&&w.due<=now||filter==='mastered'&&w.level>=4)&&`${w.word} ${w.meaning} ${getSynonyms(w).join(' ')} ${w.memo}`.toLowerCase().includes(search.toLowerCase())).sort((a,b)=>sort==='az'?a.word.localeCompare(b.word):sort==='due'?a.due-b.due:b.created-a.created);
  function closeModal(){setEditor(null);setDetail(null);setDeleteId('');setPendingImport(null);}
  function saveWord(event:React.FormEvent<HTMLFormElement>){
    event.preventDefault(); if(!editor)return;
    const next=cleanEntries({...editor,word:editor.word.trim(),meaning:editor.meaning.trim()});
    if(!next.word||!next.meaning){setNotice('영단어와 의미를 하나 이상 입력해주세요.');return;}
    if(db.words.some(w=>w.id!==next.id&&w.word.toLowerCase()===next.word.toLowerCase())){setNotice('이미 저장한 단어입니다. 기존 단어를 수정해주세요.');return;}
    const exists=db.words.some(w=>w.id===next.id);
    if(commit({...db,words:exists?db.words.map(w=>w.id===next.id?next:w):[next,...db.words]})){
      if(exists) closeModal();
      else setEditor(blankWord());
      setNotice(exists?'단어를 수정했습니다.':'새로운 단어를 저장했습니다. 계속해서 다음 단어를 추가할 수 있어요.');
    }
  }
  function download(){const blob=new Blob([exportCSV(db.words)],{type:'text/csv;charset=utf-8;'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`leaf-vocabulary-${localDate()}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);setNotice('단어장 CSV를 내보냈습니다.');}
  async function importFile(file?:File){if(!file)return;try{if(file.size>5*1024*1024)throw new Error('5MB 이하의 CSV 파일을 선택해주세요.');setPendingImport(parseCSV(await file.text()));}catch(err){setNotice(err instanceof Error?err.message:'파일을 읽지 못했습니다.');}finally{if(fileRef.current)fileRef.current.value='';}}
  function acceptImport(){if(!pendingImport)return;const seen=new Set(db.words.map(w=>w.word.toLowerCase()));const additions=pendingImport.words.filter(w=>{const key=w.word.toLowerCase();if(seen.has(key))return false;seen.add(key);return true;});if(commit({...db,words:[...additions,...db.words]})){setNotice(`${additions.length}개 단어를 가져왔습니다. ${pendingImport.words.length-additions.length+pendingImport.skipped}개 중복·빈 행은 건너뛰었습니다.`);closeModal();}}
  function speak(word:string){
    if(!('speechSynthesis' in window)){setNotice('이 브라우저는 발음을 지원하지 않습니다.');return;}
    const synthesis=window.speechSynthesis;
    synthesis.cancel();
    let played=false;
    let fallback=0;
    const play=()=>{
      if(played)return;
      played=true;
      window.clearTimeout(fallback);
      synthesis.removeEventListener('voiceschanged',play);
      const utterance=new SpeechSynthesisUtterance(word);
      const voice=preferredEnglishVoice(synthesis.getVoices());
      if(voice){utterance.voice=voice;utterance.lang=voice.lang;}
      else utterance.lang='en-US';
      utterance.rate=.92;
      utterance.pitch=1;
      synthesis.speak(utterance);
    };
    if(synthesis.getVoices().length)play();
    else{synthesis.addEventListener('voiceschanged',play,{once:true});fallback=window.setTimeout(play,600);}
  }
  function startQuiz(mode:Mode,retryWords?:Word[]){
    let pool=retryWords??(scope==='due'?due:scope==='wrong'?wrongWords:scope==='favorite'?db.words.filter(w=>w.favorite):db.words);
    if(!retryWords&&scope==='due'&&!pool.length&&db.words.length){pool=db.words;setScope('all');setNotice('오늘 복습을 완료해서 모든 단어로 다시 학습합니다.');}
    if(mode==='context')pool=pool.filter(word=>getExamples(word).some(example=>example.text.trim()));
    if(!pool.length){setNotice(mode==='context'?'선택한 범위에 예문이 등록된 단어가 없습니다.':scope==='favorite'?'즐겨찾기한 단어가 없습니다.':scope==='wrong'?'다시 학습할 틀린 단어가 없습니다.':'저장한 단어가 없습니다.');return;}
    const limit=retryWords?.length??(quizSize==='all'?pool.length:Number(quizSize));
    const words=mode==='typing'&&!retryWords?selectBalancedWords(mode,pool,limit):shuffle(pool).slice(0,limit);
    if(mode==='choice'&&new Set(db.words.map(w=>w.meaning)).size<2){setNotice('객관식 퀴즈에는 서로 다른 의미의 단어가 2개 이상 필요합니다.');return;}
    if(mode==='context'&&db.words.length<2){setNotice('예문 퀴즈에는 단어가 2개 이상 필요합니다.');return;}
    setQuiz({mode,words,index:0,correct:0,incorrectIds:[],choices:words.map(w=>makeChoices(w,db.words))});
    setAnswer('');setAcceptedTypo(false);setRevealed(false);setGraded(null);busyGrade.current=false;
  }
  function grade(correct:boolean){if(!quiz||graded!==null||busyGrade.current)return;busyGrade.current=true;const word=quiz.words[quiz.index];const current=dbRef.current;const latest=current.words.find(w=>w.id===word.id);if(!latest){setQuiz(null);busyGrade.current=false;return;}if(commit({...current,words:current.words.map(w=>w.id===word.id?schedule(w,correct):w),reviews:[...current.reviews,{date:localDate(),correct,wordId:word.id}]})){setGraded(correct);setRevealed(true);setQuiz({...quiz,correct:quiz.correct+(correct?1:0),incorrectIds:correct?(quiz.incorrectIds??[]):[...(quiz.incorrectIds??[]),word.id]});}else busyGrade.current=false;}
  function nextQuestion(){if(!quiz)return;setQuiz({...quiz,index:quiz.index+1});setGraded(null);setAnswer('');setAcceptedTypo(false);setRevealed(false);busyGrade.current=false;}
  const current=quiz?.words[quiz.index];
  const week=Array.from({length:7},(_,i)=>{const d=new Date();d.setDate(d.getDate()-6+i);const key=localDate(d);return{day:['일','월','화','수','목','금','토'][d.getDay()],count:db.reviews.filter(r=>r.date===key).length,key};});
  return <div className="app-shell">
    <aside className="sidebar"><a className="brand" href="/" aria-label="LEAF 홈"><span className="brand-symbol"><Leaf size={24}/></span>leaf<span className="brand-dot">.</span></a><span className="workspace-label">MY LEARNING SPACE</span><nav aria-label="주 메뉴">{[{id:'words',label:'나의 단어장',icon:BookOpen},{id:'study',label:'오늘의 학습',icon:Layers},{id:'stats',label:'학습 기록',icon:ChartNoAxesCombined}].map(({id,label,icon:Icon})=><button key={id} className={page===id?'nav-item active':'nav-item'} onClick={()=>{setPage(id);setQuiz(null);}}><Icon size={19}/><span>{label}</span>{id==='study'&&due.length>0&&<span className="nav-count">{due.length}</span>}</button>)}</nav><div className="sidebar-bottom"><div className="little-sprout"><Sprout size={29}/></div><strong>조금씩, 매일, 꾸준히.</strong><p>오늘의 단어가<br/>내일의 나를 넓혀줘요.</p><div className="local-indicator"><span/>이 브라우저에 저장됨</div></div></aside>
    <div className="main-area"><header className="topbar"><div><span className="muted">나의 학습 공간</span><ChevronRight size={14}/><span>{page==='words'?'나의 단어장':page==='study'?'오늘의 학습':'학습 기록'}</span></div><span className="date-label">{new Intl.DateTimeFormat('ko-KR',{month:'long',day:'numeric',weekday:'short'}).format(now)}</span><div className="avatar">L</div></header>
    <main><section className="page-heading"><div><p className="eyebrow">{page==='words'?'WORDS THAT STAY WITH YOU':page==='study'?'A LITTLE PRACTICE, EVERY DAY':'YOUR GROWTH, ONE WORD AT A TIME'}</p><h1>{page==='words'?'나의 단어장':page==='study'?'오늘의 학습':'학습 기록'}</h1><p>{page==='words'?'발견한 단어를 모아, 나만의 언어로 만들어보세요.':page==='study'?'한 번 더 떠올리는 순간, 단어가 오래 남아요.':'작은 반복이 쌓여, 더 넓은 어휘가 됩니다.'}</p></div>{page==='words'&&<button className="button primary" onClick={()=>setEditor(blankWord())} disabled={!ready||!!storageError}><Plus size={18}/>단어 추가</button>}</section>
    {storageError&&<div role="alert" className="error-banner">{storageError}</div>}
    <section className="summary-strip" aria-label="학습 요약"><div><span className="stat-icon green"><BookOpen size={20}/></span><div><span>저장한 단어</span><strong>{db.words.length}<small>개</small></strong></div></div><div><span className="stat-icon coral"><RotateCcw size={20}/></span><div><span>오늘 복습할 단어</span><strong>{due.length}<small>개</small></strong></div></div><div><span className="stat-icon violet"><Check size={20}/></span><div><span>익숙해진 단어</span><strong>{mastered}<small>개</small></strong></div></div><div><span className="stat-icon yellow"><Flame size={20}/></span><div><span>연속 학습</span><strong>{streak}<small>일</small></strong></div></div></section>
    {page==='words'&&<><section className="review-band"><div className="review-copy"><span className="tiny-label"><span className="live-dot"/>DAILY REVIEW</span><h2>{due.length?<>기억이 흐려지기 전에,<br/>오늘의 {due.length}개 단어를 만나볼까요?</>:<>단어 하나에서 시작하는<br/>오늘의 작은 성장.</>}</h2><p>{due.length?'짧은 복습으로 어제의 단어를 오래 기억하세요.':'새로운 단어를 모으거나, 저장한 단어를 다시 만나보세요.'}</p><button className="button dark" onClick={()=>{setPage('study');setScope(due.length?'due':'all');}}>오늘의 학습 시작<ArrowRight size={17}/></button></div><div className="review-visual"><img src="https://images.unsplash.com/photo-1455390582262-044cdead277a?auto=format&fit=crop&w=850&q=85" alt="펼친 노트에 펜으로 기록하는 모습"/><div className="image-caption"><span>GROW YOUR VOCABULARY</span><strong>Make every word<br/>a little more yours.</strong></div></div></section>
    <section className="word-section"><div className="section-title"><h2>모든 단어 <span>{db.words.length}</span></h2><div className="actions"><input ref={fileRef} type="file" accept=".csv,text/csv" hidden onChange={e=>void importFile(e.target.files?.[0])}/><button className="button text-button" disabled={!ready||!!storageError} onClick={()=>fileRef.current?.click()}><FileUp size={16}/>CSV 가져오기</button><button className="button text-button" disabled={!db.words.length} onClick={download}><ArrowDownToLine size={16}/>내보내기</button></div></div><div className="filter-row"><div className="tabs" role="tablist" aria-label="단어 필터">{[{id:'all',label:'전체'},{id:'due',label:'복습할 단어'},{id:'favorite',label:'즐겨찾기'},{id:'mastered',label:'익숙한 단어'}].map(t=><button role="tab" aria-selected={filter===t.id} key={t.id} onClick={()=>setFilter(t.id)} className={filter===t.id?'selected':''}>{t.label}</button>)}</div><div className="search-sort"><label className="search"><Search size={17}/><input aria-label="단어 검색" placeholder="단어, 의미 검색" value={search} onChange={e=>setSearch(e.target.value)}/></label><select aria-label="정렬 순서" value={sort} onChange={e=>setSort(e.target.value)}><option value="new">최근 추가순</option><option value="az">알파벳순</option><option value="due">복습 날짜순</option></select></div></div>
    {!ready?<div className="empty-state">단어장을 불러오는 중...</div>:filtered.length?<div className="word-grid">{filtered.map(w=><article className="word-card" key={w.id}><div className="word-card-top"><span className={`status ${w.level>=4?'known':w.level?'learning':''}`}>{w.level>=4?'익숙해요':w.level?'학습 중':'새 단어'}</span><button className={`icon-button favorite ${w.favorite?'is-favorite':''}`} aria-label={`${w.word} 즐겨찾기 ${w.favorite?'해제':'추가'}`} aria-pressed={w.favorite} title="즐겨찾기" onClick={()=>commit({...db,words:db.words.map(item=>item.id===w.id?{...item,favorite:!item.favorite}:item)})}><Star size={17}/></button></div><div className="word-line"><button className="word-link" onClick={()=>setDetail(w)}>{w.word}</button><button className="icon-button" aria-label={`${w.word} 발음 듣기`} title="발음 듣기" onClick={()=>speak(w.word)}><AudioLines size={17}/></button></div><p className="meaning">{w.meaning}</p><p className="example">{getExamples(w)[0]?.text||'아직 등록된 예문이 없어요.'}</p><div className="word-footer"><span><Clock3 size={13}/>{w.due<=now?'오늘 복습':`${new Intl.DateTimeFormat('ko-KR',{month:'short',day:'numeric'}).format(w.due)} 복습`}</span><div className="actions"><button className="icon-button" aria-label={`${w.word} 수정`} title="단어 수정" onClick={()=>setEditor({...w})}><Pencil size={15}/></button><button className="icon-button danger" aria-label={`${w.word} 삭제`} title="단어 삭제" onClick={()=>setDeleteId(w.id)}><Trash2 size={15}/></button></div></div></article>)}</div>:<div className="empty-state"><BookOpen size={34}/><h3>{db.words.length?'조건에 맞는 단어가 없어요.':'첫 번째 단어를 기록해보세요.'}</h3><p>{db.words.length?'검색어나 필터를 바꿔보세요.':'어떤 단어와 함께 시작할까요?'}</p>{!db.words.length&&<div className="actions"><button className="button primary" onClick={()=>setEditor(blankWord())}><Plus size={17}/>단어 추가</button><button className="button" onClick={()=>{if(commit({...db,words:demoWords()}))setNotice('예시 단어 6개를 추가했습니다.');}}>예시 단어로 시작</button></div>}</div>}<div className="list-bottom"><span>{filtered.length}개의 단어</span><span><Leaf size={13}/>오늘도 한 단어만큼 자라는 중</span></div></section></>}
    {page==='study'&&<section className="study-section">{!quiz?<><div className="section-title"><h2>어떻게 학습할까요?</h2><div className="study-options"><label>학습 범위<select aria-label="학습 범위" value={scope} onChange={e=>setScope(e.target.value)}><option value="due">오늘 복습할 단어 ({due.length})</option><option value="all">모든 단어 ({db.words.length})</option><option value="favorite">즐겨찾기 ({db.words.filter(w=>w.favorite).length})</option><option value="wrong">틀린 단어 ({wrongWords.length})</option></select></label><label>문제 수<select aria-label="문제 수" value={quizSize} onChange={e=>setQuizSize(e.target.value)}><option value="5">5개</option><option value="10">10개</option><option value="20">20개</option><option value="30">30개</option><option value="all">전체</option></select></label></div></div><div className="mode-grid">{modes.map(({id,name,desc,icon:Icon})=><button key={id} className="mode-card" onClick={()=>startQuiz(id)} disabled={!ready||!!storageError}><span className="mode-icon"><Icon size={28}/></span><h3>{name}</h3><p>{desc}</p><span className="mode-start">학습 시작<ArrowRight size={18}/></span></button>)}</div><div className="study-note"><Sprout size={22}/><span>오늘 {today.length}번 복습했어요. 작은 반복을 이어가세요.</span></div></>:!current?<div className="quiz-result"><span className="result-icon"><Check size={38}/></span><p className="eyebrow">SESSION COMPLETE</p><h2>오늘도 한 걸음 자랐어요.</h2><p>{quiz.words.length}개 중 {quiz.correct}개를 기억했어요.</p><strong>{Math.round(quiz.correct/quiz.words.length*100)}<small>%</small></strong><div className="result-actions">{(quiz.incorrectIds?.length??0)>0&&<button className="button" onClick={()=>startQuiz(quiz.mode,db.words.filter(w=>(quiz.incorrectIds??[]).includes(w.id)))}><RotateCcw size={17}/>틀린 단어 다시 학습</button>}<button className="button primary" onClick={()=>setQuiz(null)}>학습 목록으로<ArrowRight size={17}/></button></div></div>:<div className="quiz-wrap"><div className="quiz-top"><button className="button text-button" onClick={()=>setQuiz(null)}><ArrowLeft size={17}/>학습 종료</button><span>{modes.find(m=>m.id===quiz.mode)?.name} · {quiz.index+1} / {quiz.words.length}</span></div><div className="progress-track"><div style={{width:`${quiz.index/quiz.words.length*100}%`}}/></div><div className="question-area"><p className="eyebrow">{quiz.mode==='typing'?'이 의미의 영어 단어는?':quiz.mode==='context'?'빈칸에 들어갈 단어는?':'이 단어의 의미는?'}</p><h2 className={quiz.mode==='context'?'context-question':''}>{quiz.mode==='typing'?current.meaning:quiz.mode==='context'?maskedExample(current):current.word}</h2>{quiz.mode==='context'&&graded!==null&&getExamples(current)[0]?.translation&&<p className="context-translation">{getExamples(current)[0].translation}</p>}{(quiz.mode!=='typing'&&quiz.mode!=='context'||quiz.mode==='context'&&graded!==null)&&<button className="icon-button" aria-label="발음 듣기" title="발음 듣기" onClick={()=>speak(current.word)}><AudioLines size={23}/></button>}{quiz.mode==='flash'&&(revealed?<div className="revealed-answer"><MeaningList word={current}/><ExampleList word={current}/></div>:<button className="button" onClick={()=>setRevealed(true)}><RotateCcw size={17}/>정답 보기</button>)}{(quiz.mode==='choice'||quiz.mode==='context')&&<div className="choices">{quiz.choices[quiz.index].map((choice,i)=>{const meaning=choiceMeaning(choice);const value=quiz.mode==='context'&&typeof choice!=='string'?choice.word:meaning;return <button key={`${meaning}-${i}`} className={`choice ${graded!==null&&value===(quiz.mode==='context'?current.word:current.meaning)?'correct':''} ${graded===false&&value===answer?'incorrect':''}`} disabled={graded!==null} onClick={()=>{setAnswer(value);grade(value===(quiz.mode==='context'?current.word:current.meaning));}}><span className="choice-number">{i+1}</span><ChoiceContent choice={choice} revealed={graded!==null} wordFirst={quiz.mode==='context'}/></button>;})}</div>}{quiz.mode==='typing'&&<form className="typing-form" onSubmit={e=>{e.preventDefault();if(answer.trim()){const exact=answer.trim().toLowerCase()===current.word.trim().toLowerCase();const accepted=acceptsSpelling(answer,current.word);setAcceptedTypo(accepted&&!exact);grade(accepted);}}}><input ref={typingInputRef} aria-label="영어 단어 정답" autoComplete="off" autoCapitalize="none" spellCheck={false} placeholder="영어 단어를 입력하세요" value={answer} disabled={graded!==null} onChange={e=>setAnswer(e.target.value)}/><button className="button primary" disabled={!answer.trim()||graded!==null}>정답 확인</button></form>}{graded!==null?<div className={`feedback ${graded?'positive':'negative'}`}><strong>{graded?(acceptedTypo?'작은 오타가 있지만 정답이에요!':'잘 기억했어요!'):'다음에 한 번 더 만나봐요.'}</strong><p>정답: {current.word} · {current.meaning}</p><button className="button primary" onClick={nextQuestion}>{quiz.index+1===quiz.words.length?'결과 보기':'다음 단어'}<ArrowRight size={17}/></button></div>:quiz.mode==='flash'&&revealed&&<div className="self-grade"><button className="button" onClick={()=>grade(false)}><RotateCcw size={17}/>다시 볼게요</button><button className="button primary" onClick={()=>grade(true)}><Check size={17}/>기억했어요</button></div>}</div></div>}</section>}
    {page==='stats'&&<section className="stats-section"><div className="section-title"><h2>이번 주의 꾸준함</h2><span className="muted">최근 7일</span></div><div className="chart" role="img" aria-label={week.map(d=>`${d.day}요일 ${d.count}회`).join(', ')}>{week.map(d=><div className="bar-column" key={d.key}><span>{d.count}</span><div className="bar-track"><div className={d.key===localDate()?'bar today':'bar'} style={{height:`${d.count?Math.max(4,d.count/Math.max(1,...week.map(x=>x.count))*100):0}%`}}/></div><span>{d.day}</span></div>)}</div><div className="history-summary"><div><span>누적 복습</span><strong>{db.reviews.length}<small>회</small></strong></div><div><span>전체 정답률</span><strong>{db.reviews.length?Math.round(db.reviews.filter(r=>r.correct).length/db.reviews.length*100):0}<small>%</small></strong></div><div><span>오늘의 복습</span><strong>{today.length}<small>회</small></strong></div></div><h2 className="history-title">최근 학습</h2>{db.reviews.length?<div className="history-list">{db.reviews.slice(-12).reverse().map((r,i)=><div key={`${r.wordId}-${i}`}><span className={`history-dot ${r.correct?'success':''}`}>{r.correct?<Check size={16}/>:<RotateCcw size={16}/>}</span><strong>{db.words.find(w=>w.id===r.wordId)?.word||'삭제된 단어'}</strong><span>{r.correct?'기억했어요':'다시 학습'}</span><time>{r.date}</time></div>)}</div>:<div className="empty-state"><ChartNoAxesCombined size={32}/><h3>아직 학습 기록이 없어요.</h3><button className="button primary" onClick={()=>setPage('study')}>첫 학습 시작<ArrowRight size={16}/></button></div>}</section>}
    <footer><span>leaf. 작은 단어가 만드는 큰 변화</span><span>나만의 어휘, 나만의 속도로.</span></footer></main></div>
    <dialog ref={modalRef} onCancel={closeModal} onClick={e=>{if(e.target===e.currentTarget)closeModal();}} aria-labelledby="modal-title"><div className="modal"><button className="icon-button modal-close" onClick={closeModal} aria-label="닫기" title="닫기"><X size={21}/></button>{editor?<><p className="eyebrow">MY VOCABULARY</p><h2 id="modal-title">{db.words.some(w=>w.id===editor.id)?'단어 수정':'새로운 단어'}</h2><form onSubmit={saveWord} onKeyDown={event=>{if(event.ctrlKey&&event.key==='Enter'&&!event.nativeEvent.isComposing){event.preventDefault();event.currentTarget.requestSubmit();}}} className="word-form">{[{key:'word',label:'영단어',required:true}].map(({key,label,required})=><label key={key}>{label}{required&&<span className="required"> *</span>}<input ref={wordInputRef} autoFocus={key==='word'} required={required} maxLength={key==='word'?120:2000} value={String(editor[key as keyof Word])} onChange={e=>setEditor({...editor,[key]:e.target.value})}/></label>)}<WordEntriesEditor word={editor} onChange={setEditor}/><label>메모<textarea rows={3} maxLength={5000} value={editor.memo} onChange={e=>setEditor({...editor,memo:e.target.value})}/></label><div className="modal-footer"><button type="button" className="button" onClick={closeModal}>취소</button><button type="submit" className="button primary"><Check size={17}/>단어 저장</button></div></form></>:detail?<><p className="eyebrow">WORD DETAILS</p><h2 id="modal-title" className="detail-word">{detail.word}</h2><MeaningList word={detail}/><WordEntriesDetails word={detail}/><div className="modal-footer split"><button className="button danger" onClick={()=>{setDeleteId(detail.id);setDetail(null);}}><Trash2 size={16}/>삭제</button><button className="button primary" onClick={()=>{setEditor({...detail});setDetail(null);}}><Pencil size={16}/>수정</button></div></>:deleteId?<><h2 id="modal-title">단어를 삭제할까요?</h2><p>‘{db.words.find(w=>w.id===deleteId)?.word}’ 단어가 단어장에서 삭제됩니다.</p><div className="modal-footer"><button className="button" onClick={closeModal}>취소</button><button className="button danger" onClick={()=>{if(commit({...db,words:db.words.filter(w=>w.id!==deleteId)})){closeModal();setNotice('단어를 삭제했습니다.');}}}>삭제</button></div></>:pendingImport?<><p className="eyebrow">CSV IMPORT</p><h2 id="modal-title">단어 가져오기</h2><p>{pendingImport.words.length}개 단어를 찾았습니다.</p><p className="muted">중복 단어와 단어·의미가 비어 있는 행은 건너뜁니다. 기존 단어는 유지됩니다.</p><div className="import-preview">{pendingImport.words.slice(0,5).map(w=><div key={w.id}><strong>{w.word}</strong><span>{w.meaning}</span></div>)}</div><div className="modal-footer"><button className="button" onClick={closeModal}>취소</button><button className="button primary" onClick={acceptImport}><FileUp size={16}/>가져오기</button></div></>:null}</div></dialog>
    {notice&&createPortal(<div className="toast" role="status">{notice}<button className="icon-button" aria-label="알림 닫기" onClick={()=>setNotice('')}><X size={17}/></button></div>,modalOpen&&modalRef.current?modalRef.current:document.body)}
  </div>;
}
