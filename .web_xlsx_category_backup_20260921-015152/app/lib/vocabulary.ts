import Papa from 'papaparse';

export type Example = { text: string; translation: string };
export type Word = {
  id: string; word: string; meaning: string; example: string; translation: string;
  synonyms: string; memo: string; favorite: boolean; level: number; due: number; created: number;
  examples?: Example[]; synonymEntries?: string[]; meaningEntries?: string[];
  category?: string; // CATEGORY_FEATURE_V3
};
export type Review = { id?: string; date: string; correct: boolean; wordId: string };
export type Database = { version: 1; words: Word[]; reviews: Review[]; categories?: string[] };
export const STORAGE_KEY = 'leaf-vocabulary-v1';
export const DAY = 86400000;
export const localDate = (date = new Date()) => `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
export const blankWord = (): Word => ({id: crypto.randomUUID(), word:'', meaning:'', example:'', translation:'', synonyms:'', memo:'', category:'', favorite:false, level:0, due:0, created:Date.now()});
// Old notebooks keep their original fields until the word is edited.
export const getMeanings = (word: Word): string[] => word.meaningEntries ?? (word.meaning ? [word.meaning] : []);
export function withMeanings(word: Word, meaningEntries: string[]): Word {
  return {...word, meaningEntries, meaning:meaningEntries.join('; ')};
}
export const getExamples = (word: Word): Example[] => word.examples ?? (word.example || word.translation ? [{text:word.example,translation:word.translation}] : []);
export const getSynonyms = (word: Word): string[] => word.synonymEntries ?? word.synonyms.split(/[,;\n]/).map(s=>s.trim()).filter(Boolean);
export function withExamples(word: Word, examples: Example[]): Word {
  return {...word, examples, example:examples[0]?.text ?? '', translation:examples[0]?.translation ?? ''};
}
export function withSynonyms(word: Word, synonymEntries: string[]): Word {
  return {...word, synonymEntries, synonyms:synonymEntries.join(', ')};
}
export function cleanEntries(word: Word): Word {
  return withMeanings(withSynonyms(withExamples(word,getExamples(word).map(e=>({text:e.text.trim(),translation:e.translation.trim()})).filter(e=>e.text || e.translation)), getSynonyms(word).map(s=>s.trim()).filter(Boolean)),getMeanings(word).map(s=>s.trim()).filter(Boolean));
}
const validExamples = (value: unknown): value is Example[] => Array.isArray(value) && value.every(e=>e && typeof e.text === 'string' && typeof e.translation === 'string');
const validSynonyms = (value: unknown): value is string[] => Array.isArray(value) && value.every(s=>typeof s === 'string');
export function schedule(word: Word, correct: boolean, now = Date.now()): Word {
  const level = correct ? Math.min(word.level + 1, 6) : 0;
  return {...word, level, due: now + (correct ? [0,1,3,7,14,30,60][level] * DAY : 10 * 60000)};
}
export function validWord(value: unknown): value is Word {
  if (!value || typeof value !== 'object') return false;
  const w = value as Word;
  return ['id','word','meaning','example','translation','synonyms','memo'].every(k => typeof w[k as keyof Word] === 'string') && !!w.word.trim() && !!w.meaning.trim() && (w.category === undefined || typeof w.category === 'string') && typeof w.favorite === 'boolean' && Number.isInteger(w.level) && w.level >= 0 && w.level <= 6 && Number.isFinite(w.due) && Number.isFinite(w.created) && (w.examples === undefined || validExamples(w.examples)) && (w.synonymEntries === undefined || validSynonyms(w.synonymEntries)) && (w.meaningEntries === undefined || (validSynonyms(w.meaningEntries) && w.meaningEntries.length > 0 && w.meaningEntries.every(s=>!!s.trim()) && w.meaning === w.meaningEntries.join('; ')));
}
export function loadDatabase(raw: string): Database {
  const data = JSON.parse(raw);
  if(data.version !== 1 || !Array.isArray(data.words) || !data.words.every(validWord) || new Set(data.words.map((w: Word)=>w.id)).size !== data.words.length || !Array.isArray(data.reviews) || !data.reviews.every((r: Review)=>r && (r.id === undefined || typeof r.id === 'string') && typeof r.date === 'string' && typeof r.correct === 'boolean' && typeof r.wordId === 'string') || (data.categories !== undefined && (!Array.isArray(data.categories) || !data.categories.every((c: unknown)=>typeof c === 'string')))) throw new Error('저장된 데이터를 읽지 못했습니다. 원본 데이터를 보존하기 위해 저장을 중지했습니다.');
  const storedCategories:string[]=Array.isArray(data.categories)?data.categories:[];
  const categories=[...new Set([...storedCategories,...data.words.map((w: Word)=>(w.category??'').trim()).filter(Boolean)])];
  return {...data,categories};
}
const fields = ['word','meaning','example','translation','synonyms','memo','category','favorite','level','due','created'] as const;
const aliases: Record<string,string> = {'영단어':'word','단어':'word','의미':'meaning','뜻':'meaning','예시':'example','예문':'example','예시 뜻':'translation','예문 뜻':'translation','유의어':'synonyms','메모':'memo','카테고리':'category','분류':'category','즐겨찾기':'favorite'};
export function parseCSV(csv: string): {words: Word[]; skipped: number} {
  const parsed = Papa.parse<Record<string,string>>(csv.replace(/^\uFEFF/,''), {header:true, skipEmptyLines:'greedy', transformHeader: h => aliases[h.trim()] || h.trim().toLowerCase()});
  if(parsed.errors.length) throw new Error(`CSV 형식을 확인해주세요: ${parsed.errors[0].message}`);
  if(!parsed.meta.fields?.includes('word') || !parsed.meta.fields.includes('meaning')) throw new Error('CSV에 word(영단어), meaning(의미) 열이 필요합니다.');
  let skipped = 0;
  const words = parsed.data.flatMap(row => {
    if(!row.word?.trim() || !row.meaning?.trim()){skipped++; return [];}
    const word = blankWord();
    for(const key of ['word','meaning','example','translation','synonyms','memo','category'] as const) word[key] = (row[key] || '').trim();
    if(row.examples_json?.trim()) {
      let entries: unknown;
      try {entries=JSON.parse(row.examples_json);} catch {throw new Error(`${word.word}: 예문 목록의 JSON 형식이 올바르지 않습니다.`);}
      if(!validExamples(entries)) throw new Error(`${word.word}: 예문에는 text와 translation 문자열이 필요합니다.`);
      Object.assign(word,withExamples(word,entries));
    }
    if(row.synonyms_json?.trim()) {
      let entries: unknown;
      try {entries=JSON.parse(row.synonyms_json);} catch {throw new Error(`${word.word}: 유의어 목록의 JSON 형식이 올바르지 않습니다.`);}
      if(!validSynonyms(entries)) throw new Error(`${word.word}: 유의어 목록에는 문자열만 사용할 수 있습니다.`);
      Object.assign(word,withSynonyms(word,entries));
    }
    if(row.meanings_json?.trim()) {
      let entries: unknown;
      try {entries=JSON.parse(row.meanings_json);} catch {throw new Error(`${word.word}: 의미 목록의 JSON 형식이 올바르지 않습니다.`);}
      if(!validSynonyms(entries) || !entries.length || entries.some(s=>!s.trim())) throw new Error(`${word.word}: 비어 있지 않은 의미가 하나 이상 필요합니다.`);
      Object.assign(word,withMeanings(word,entries));
    }
    word.favorite = row.favorite === 'true';
    const level = Number(row.level);
    word.level = Number.isInteger(level) && level >= 0 && level <= 6 ? level : 0;
    word.due = row.due && Number.isFinite(Number(row.due)) ? Number(row.due) : 0;
    word.created = row.created && Number.isFinite(Number(row.created)) ? Number(row.created) : Date.now();
    return [word];
  });
  if(!words.length) throw new Error('가져올 단어가 없습니다. 단어와 의미를 확인해주세요.');
  return {words, skipped};
}
export const exportCSV = (words: Word[]) => '\uFEFF' + Papa.unparse(words.map(w => ({...Object.fromEntries(fields.map(f => [f,w[f]])), examples_json:JSON.stringify(getExamples(w)), synonyms_json:JSON.stringify(getSynonyms(w)), meanings_json:JSON.stringify(getMeanings(w))})), {columns:[...fields,'examples_json','synonyms_json','meanings_json'], escapeFormulae:true});
export function shuffle<T>(items: T[]): T[] {
  const result = [...items];
  for(let i=result.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1)); [result[i],result[j]]=[result[j],result[i]];}
  return result;
}
export function demoWords(): Word[] {
  return [
    ['serendipity','뜻밖의 행운, 우연한 발견','Finding this book was pure serendipity.','이 책을 발견한 것은 순전히 뜻밖의 행운이었다.','chance, good fortune','좋아하는 단어. 우연이 가져다주는 좋은 일.'],
    ['resilient','회복력이 있는, 쉽게 좌절하지 않는','She remained resilient in difficult times.','그녀는 힘든 시기에도 쉽게 좌절하지 않았다.','strong, adaptable',''],
    ['embrace','받아들이다, 포용하다','Learn to embrace change.','변화를 받아들이는 법을 배워라.','accept, welcome',''],
    ['perspective','관점, 시각','Travel gives us a new perspective.','여행은 우리에게 새로운 관점을 준다.','viewpoint, outlook',''],
    ['consistent','꾸준한, 일관된','Consistent practice makes a difference.','꾸준한 연습이 차이를 만든다.','steady, regular',''],
    ['flourish','번창하다, 잘 자라다','Ideas flourish when we share them.','아이디어는 나눌 때 꽃핀다.','thrive, prosper',''],
  ].map((values,i)=>({...blankWord(),word:values[0],meaning:values[1],example:values[2],translation:values[3],synonyms:values[4],memo:values[5],favorite:i===0}));
}
