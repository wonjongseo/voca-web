import assert from 'node:assert/strict';
import test from 'node:test';
import {blankWord, exportCSV, parseCSV, schedule, loadDatabase, DAY, localDate, getExamples, getSynonyms, withExamples, withSynonyms, cleanEntries} from '../app/lib/vocabulary.ts';

test('CSV preserves Korean, quoted commas, multiline notes and study progress',()=>{
  const word={...blankWord(),word:'resilient',meaning:'회복력이 있는, 강인한',example:'She said, "Keep going."',translation:'그녀는 "계속해"라고 말했다.',memo:'첫째 줄\n둘째 줄',favorite:true,level:3,due:2000};
  const parsed=parseCSV(exportCSV([word])).words[0];
  for(const key of ['word','meaning','example','translation','memo','favorite','level','due','created']) assert.equal(parsed[key],word[key]);
});
test('CSV accepts Korean aliases and skips rows without required values',()=>{
  const parsed=parseCSV('영단어,의미,예시 뜻\r\nhello,안녕,인사\r\n,비어 있음,');
  assert.equal(parsed.words[0].translation,'인사');assert.equal(parsed.skipped,1);
});
test('CSV rejects missing headers, malformed quotes and empty imports',()=>{
  for(const csv of ['wrong,header\na,b','word,meaning\n"open,안녕','word,meaning\n,'])assert.throws(()=>parseCSV(csv));
});
test('spreadsheet formula payloads are escaped on export',()=>{
  assert.match(exportCSV([{...blankWord(),word:'=HYPERLINK("url")',meaning:'test'}]),/'=HYPERLINK/);
});
test('correct reviews progress at 1, 3, 7, 14, 30 and 60 days; errors reset to 10 minutes',()=>{
  let word=blankWord();
  for(const days of [1,3,7,14,30,60,60]){word=schedule(word,true,1000);assert.equal(word.due,1000+days*DAY);}
  const reset=schedule(word,false,1000);assert.equal(reset.level,0);assert.equal(reset.due,601000);
});
test('saved data round-trips and rejects corruption and duplicate identifiers',()=>{
  const word={...blankWord(),word:'leaf',meaning:'잎'};
  const db={version:1,words:[word],reviews:[{date:localDate(),correct:true,wordId:word.id}]};
  assert.deepEqual(loadDatabase(JSON.stringify(db)),db);
  assert.throws(()=>loadDatabase('{broken'));
  assert.throws(()=>loadDatabase(JSON.stringify({...db,words:[{...word,level:99}]})));
  assert.throws(()=>loadDatabase(JSON.stringify({...db,words:[word,word]})));
});

test('legacy saved entries remain readable without changing stored text',()=>{
  const word={...blankWord(),word:'leaf',meaning:'잎',example:'A green leaf.',translation:'초록 잎.',synonyms:'foliage, greenery; leaves\nplant life'};
  const loaded=loadDatabase(JSON.stringify({version:1,words:[word],reviews:[]})).words[0];
  assert.deepEqual(getExamples(loaded),[{text:'A green leaf.',translation:'초록 잎.'}]);
  assert.deepEqual(getSynonyms(loaded),['foliage','greenery','leaves','plant life']);
  assert.equal(loaded.synonyms,word.synonyms);
});

test('multiple examples and synonyms survive CSV export, reload and review',()=>{
  const examples=[{text:'She said, "Hello."\nThen she left.',translation:'그녀가 "안녕"이라고 했다.\n그리고 떠났다.'},{text:'A second example.',translation:''},{text:'',translation:'번역만 있던 기존 항목'}];
  const synonyms=['hi','hello, there','welcome\nback'];
  const word=withSynonyms(withExamples({...blankWord(),word:'hello',meaning:'안녕'},examples),synonyms);
  const imported=parseCSV(exportCSV([word])).words[0];
  assert.deepEqual(getExamples(imported),examples);
  assert.deepEqual(getSynonyms(imported),synonyms);
  const reviewed=schedule(imported,true,1000);
  const loaded=loadDatabase(JSON.stringify({version:1,words:[reviewed],reviews:[]})).words[0];
  assert.deepEqual(getExamples(loaded),examples);
  assert.deepEqual(getSynonyms(loaded),synonyms);
});

test('editing and deleting entries updates legacy fields and does not mutate original',()=>{
  const original={...blankWord(),word:'hello',meaning:'안녕',example:'Old.',translation:'기존.',synonyms:'hi'};
  const added=withExamples(original,[...getExamples(original),{text:'New.',translation:'신규.'}]);
  const removed=withExamples(added,getExamples(added).slice(1));
  assert.equal(removed.example,'New.');assert.equal(removed.translation,'신규.');
  assert.equal(original.example,'Old.');
  const empty=withSynonyms(withExamples(removed,[]),[]);
  assert.equal(empty.example,'');assert.equal(empty.translation,'');assert.equal(empty.synonyms,'');
  const imported=parseCSV(exportCSV([empty])).words[0];
  assert.deepEqual(getExamples(imported),[]);assert.deepEqual(getSynonyms(imported),[]);
});

test('saving trims entries and drops empty rows without mismatching translations',()=>{
  const word=withSynonyms(withExamples(blankWord(),[{text:' ',translation:' '},{text:' Hello ',translation:' 안녕 '},{text:'',translation:' 번역만 '}]),[' hi ',' ','hello']);
  const cleaned=cleanEntries(word);
  assert.deepEqual(getExamples(cleaned),[{text:'Hello',translation:'안녕'},{text:'',translation:'번역만'}]);
  assert.deepEqual(getSynonyms(cleaned),['hi','hello']);
});

test('corrupt entry arrays are rejected before replacing saved data',()=>{
  const word={...blankWord(),word:'hello',meaning:'안녕'};
  for(const changes of [{examples:[{text:12,translation:''}]},{examples:{}},{synonymEntries:['valid',null]}]) {
    assert.throws(()=>loadDatabase(JSON.stringify({version:1,words:[{...word,...changes}],reviews:[]})));
  }
  for(const csv of ['word,meaning,examples_json\nhello,안녕,not-json','word,meaning,examples_json\nhello,안녕,[1]','word,meaning,synonyms_json\nhello,안녕,[null]'])assert.throws(()=>parseCSV(csv));
});
