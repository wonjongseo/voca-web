import assert from 'node:assert/strict';
import test from 'node:test';
import {blankWord, exportCSV, parseCSV, schedule, loadDatabase, DAY, localDate} from '../app/lib/vocabulary.ts';

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
