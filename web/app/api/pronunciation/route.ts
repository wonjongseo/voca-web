type DictionaryPronunciation = {
  audio?: string;
};

type DictionaryEntry = {
  phonetics?: DictionaryPronunciation[];
};

function normalizeAudioUrl(url:string) {
  if(url.startsWith('//'))return `https:${url}`;
  if(url.startsWith('http://')){
    return `https://${url.slice('http://'.length)}`;
  }
  return url;
}

function chooseAudio(entries:DictionaryEntry[]) {
  const urls=entries
    .flatMap(entry=>entry.phonetics??[])
    .map(item=>item.audio?.trim()??'')
    .filter(Boolean)
    .map(normalizeAudioUrl);

  const isAmerican=(url:string)=>/(?:[_-]us(?:[_\-.]|$)|\/en-us\/)/i.test(url);
  return [...new Set(urls)].filter(url=>url.startsWith('https://'))
    .sort((a,b)=>Number(isAmerican(b))-Number(isAmerican(a)));
}

async function fetchWithTimeout(url:string,timeoutMs:number) {
  const controller=new AbortController();
  const timeout=setTimeout(()=>controller.abort(),timeoutMs);

  try{
    return await fetch(url,{
      signal:controller.signal,
      headers:{
        'Accept':'application/json,audio/*;q=0.9,*/*;q=0.8',
        'User-Agent':'voca-web-pronunciation/1.0',
      },
    });
  }finally{
    clearTimeout(timeout);
  }
}

// DICTIONARY_MP3_PRONUNCIATION_V2
export async function GET(request:Request) {
  const url=new URL(request.url);
  const word=(url.searchParams.get('word')??'').trim().toLowerCase();

  if(!word||word.length>100){
    return new Response(null,{status:400});
  }

  try{
    const dictionaryResponse=await fetchWithTimeout(
      `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`,
      4500,
    );

    if(!dictionaryResponse.ok){
      return new Response(null,{
        status:dictionaryResponse.status===404?404:502,
        headers:{'Cache-Control':'no-store'},
      });
    }

    const raw=await dictionaryResponse.json();
    const entries=Array.isArray(raw)?raw as DictionaryEntry[]:[];
    const audioUrls=chooseAudio(entries);

    if(!audioUrls.length){
      return new Response(null,{
        status:404,
        headers:{
          'Cache-Control':'public, max-age=3600, s-maxage=3600',
        },
      });
    }

    for(const audioUrl of audioUrls.slice(0,3)){
      try{
        const audioResponse=await fetchWithTimeout(audioUrl,2500);
        const contentType=audioResponse.headers.get('content-type')??'';
        if(!audioResponse.ok||!audioResponse.body||!contentType.startsWith('audio/')){
          await audioResponse.body?.cancel();
          continue;
        }
        return new Response(audioResponse.body,{
          status:200,
          headers:{
            'Content-Type':contentType,
            'Cache-Control':'public, max-age=86400, s-maxage=604800',
          },
        });
      }catch{
        // A missing recording should not prevent trying another dictionary voice.
      }
    }
    return new Response(null,{status:502,headers:{'Cache-Control':'no-store'}});
  }catch{
    return new Response(null,{
      status:502,
      headers:{'Cache-Control':'no-store'},
    });
  }
}
