// These recordings are an optional fallback: not every word has a file.
// Audio elements can play them directly without depending on the API server.
export function pronunciationSources(word:string):string[]{
  const normalized=word.trim().toLowerCase();
  const sources:string[]=[];
  if(/^[a-z]+(?:-[a-z]+)*$/.test(normalized)){
    const base=`https://ssl.gstatic.com/dictionary/static/sounds/20200429/${encodeURIComponent(normalized)}`;
    sources.push(`${base}--_us_1.mp3`,`${base}--_gb_1.mp3`);
  }
  sources.push(`/api/pronunciation?word=${encodeURIComponent(normalized)}`);
  return sources;
}
