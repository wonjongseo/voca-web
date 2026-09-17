'use client';

import {Plus, Trash2} from 'lucide-react';
import {useRef} from 'react';
import {getExamples, getSynonyms, withExamples, withSynonyms, type Word} from './lib/vocabulary';

export function WordEntriesEditor({word,onChange}:{word:Word;onChange:(word:Word)=>void}) {
  const examples=getExamples(word);
  const synonyms=getSynonyms(word);
  const pendingFocus=useRef<{kind:'example'|'synonym';index:number}|null>(null);
  function focusAddedField(element:HTMLInputElement|HTMLTextAreaElement|null,kind:'example'|'synonym',index:number) {
    if(element && pendingFocus.current?.kind===kind && pendingFocus.current.index===index) {
      pendingFocus.current=null;
      element.focus();
    }
  }
  return <>
    <fieldset className="entry-group">
      <legend>예문 <span>{examples.length}</span></legend>
      {examples.map((example,index)=><div className="example-entry" key={index}>
        <div className="entry-heading"><span>예문 {index+1}</span><button type="button" className="icon-button" title={`예문 ${index+1} 삭제`} aria-label={`예문 ${index+1} 삭제`} onClick={()=>onChange(withExamples(word,examples.filter((_,i)=>i!==index)))}><Trash2 size={15}/></button></div>
        <label>영어 예문 {index+1}<textarea ref={element=>focusAddedField(element,'example',index)} rows={2} maxLength={2000} value={example.text} onChange={e=>onChange(withExamples(word,examples.map((entry,i)=>i===index?{...entry,text:e.target.value}:entry)))}/></label>
        <label>예문 뜻 {index+1}<textarea rows={2} maxLength={2000} value={example.translation} onChange={e=>onChange(withExamples(word,examples.map((entry,i)=>i===index?{...entry,translation:e.target.value}:entry)))}/></label>
      </div>)}
      <button type="button" className="button entry-add" onClick={()=>{pendingFocus.current={kind:'example',index:examples.length};onChange(withExamples(word,[...examples,{text:'',translation:''}]));}}><Plus size={16}/>예문 추가</button>
    </fieldset>
    <fieldset className="entry-group">
      <legend>유의어 <span>{synonyms.length}</span></legend>
      {synonyms.map((synonym,index)=><div className="synonym-entry" key={index}>
        <label>유의어 {index+1}<input ref={element=>focusAddedField(element,'synonym',index)} maxLength={2000} value={synonym} onChange={e=>onChange(withSynonyms(word,synonyms.map((entry,i)=>i===index?e.target.value:entry)))}/></label>
        <button type="button" className="icon-button" title={`유의어 ${index+1} 삭제`} aria-label={`유의어 ${index+1} 삭제`} onClick={()=>onChange(withSynonyms(word,synonyms.filter((_,i)=>i!==index)))}><Trash2 size={15}/></button>
      </div>)}
      <button type="button" className="button entry-add" onClick={()=>{pendingFocus.current={kind:'synonym',index:synonyms.length};onChange(withSynonyms(word,[...synonyms,'']));}}><Plus size={16}/>유의어 추가</button>
    </fieldset>
  </>;
}

export function ExampleList({word}:{word:Word}) {
  return <div className="example-list">{getExamples(word).map((example,index)=><div key={index}><p>{example.text}</p>{example.translation&&<p className="muted">{example.translation}</p>}</div>)}</div>;
}

export function WordEntriesDetails({word}:{word:Word}) {
  const examples=getExamples(word);
  const synonyms=getSynonyms(word);
  return <dl>
    <div><dt>예문 ({examples.length})</dt><dd>{examples.length?<ExampleList word={word}/>:'등록된 내용이 없습니다.'}</dd></div>
    <div><dt>유의어 ({synonyms.length})</dt><dd>{synonyms.length?<ul className="synonym-list">{synonyms.map((synonym,index)=><li key={index}>{synonym}</li>)}</ul>:'등록된 내용이 없습니다.'}</dd></div>
    <div><dt>메모</dt><dd>{word.memo||'등록된 내용이 없습니다.'}</dd></div>
  </dl>;
}
