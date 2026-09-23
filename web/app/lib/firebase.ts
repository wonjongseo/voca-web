import {initializeApp, getApps} from 'firebase/app';
import {
  GoogleAuthProvider,
  createUserWithEmailAndPassword,
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
  type User,
} from 'firebase/auth';

import {
  collection,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  serverTimestamp,
  setDoc,
  writeBatch,
  type DocumentReference,
} from 'firebase/firestore';
import {type Database, type Review, type Word} from './vocabulary';

const config = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
};

export const firebaseConfigured = Boolean(
  config.apiKey &&
  config.authDomain &&
  config.projectId &&
  config.appId,
);

const app = firebaseConfigured ? getApps()[0] ?? initializeApp(config) : null;
export const auth = app ? getAuth(app) : null;
export const firestore = app ? getFirestore(app) : null;

export type CloudScope =
  | {type:'personal'}
  | {type:'group';groupId:string};


export function listenFirebaseUser(callback:(user:User|null)=>void) {
  if(!auth)return ()=>{};
  return onAuthStateChanged(auth,callback);
}

export async function signInEmail(
  email:string,
  password:string,
  createAccount=false,
) {
  if(!auth)throw new Error('Firebase 설정이 필요합니다.');
  return createAccount
    ?createUserWithEmailAndPassword(auth,email,password)
    :signInWithEmailAndPassword(auth,email,password);
}

export async function signInGoogle() {
  if(!auth)throw new Error('Firebase 설정이 필요합니다.');
  return signInWithPopup(auth,new GoogleAuthProvider());
}

export async function signOutFirebase() {
  if(!auth)throw new Error('Firebase 설정이 필요합니다.');
  return signOut(auth);
}

const REVIEW_STORAGE_VERSION=3;
const CHUNK_SCHEMA_VERSION=4;
const CHUNK_COUNT=16;
const groupMembershipCache=new Set<string>();
const chunkVersionCache=new Map<string,Map<string,number>>();

type StoredReview = Review & {id?:string};

function rootPath(uid:string,scope:CloudScope) {
  return scope.type==='personal'
    ?['users',uid] as const
    :['groups',scope.groupId] as const;
}

function normalizeCategories(database:Database) {
  return [...new Set([
    ...(database.categories??[]),
    ...database.words.map(word=>(word.category??'').trim()).filter(Boolean),
  ])].sort((a,b)=>a.localeCompare(b,'ko'));
}

function reviewId(review:StoredReview,index:number){
  return review.id?.trim() ||
    `legacy:${review.date}:${review.correct?'1':'0'}:${index}`;
}

function encodeReviewEvent(review:StoredReview,index:number){
  return JSON.stringify([
    reviewId(review,index),
    review.date,
    review.correct?1:0,
  ]);
}

function decodeReviewEvent(raw:string,wordId:string):StoredReview|null{
  try{
    const parsed=JSON.parse(raw);
    if(!Array.isArray(parsed)||parsed.length<3)return null;
    return {
      id:String(parsed[0]),
      date:String(parsed[1]),
      correct:parsed[2]===1,
      wordId,
    };
  }catch{return null;}
}

function reviewEventsFor(reviews:Database['reviews'],wordId:string){
  return reviews
    .filter(review=>review.wordId===wordId)
    .map((review,index)=>encodeReviewEvent(review as StoredReview,index));
}

function chunkIdForWord(wordId:string){
  let hash=0;
  for(let i=0;i<wordId.length;i++){
    hash=(Math.imul(hash,31)+wordId.charCodeAt(i))>>>0;
  }
  return String(hash%CHUNK_COUNT).padStart(2,'0');
}

function scopeCacheKey(uid:string,scope:CloudScope){
  return `${uid}:${scope.type==='personal'?'personal':`group:${scope.groupId}`}`;
}

function versionStorageKey(uid:string,scope:CloudScope){
  return `leaf-cloud-chunk-versions-v4:${scopeCacheKey(uid,scope)}`;
}

function readStoredVersions(uid:string,scope:CloudScope){
  try{
    const raw=localStorage.getItem(versionStorageKey(uid,scope));
    if(!raw)return new Map<string,number>();
    const parsed=JSON.parse(raw) as Record<string,unknown>;
    return new Map(
      Object.entries(parsed).map(([key,value])=>[key,Number(value)||0] as const),
    );
  }catch{return new Map<string,number>();}
}

function rememberVersions(uid:string,scope:CloudScope,versions:Map<string,number>){
  chunkVersionCache.set(scopeCacheKey(uid,scope),versions);
  try{
    localStorage.setItem(
      versionStorageKey(uid,scope),
      JSON.stringify(Object.fromEntries(versions)),
    );
  }catch{}
}

function versionsFromRoot(data:Record<string,unknown>|undefined){
  const raw=data?.chunkVersions;
  if(!raw||typeof raw!=='object'||Array.isArray(raw))return new Map<string,number>();
  return new Map(
    Object.entries(raw as Record<string,unknown>)
      .map(([key,value])=>[key,Number(value)||0] as const),
  );
}

function chunkPayload(database:Database,chunkId:string){
  const words:Record<string,unknown>={};
  for(const word of database.words){
    if(chunkIdForWord(word.id)!==chunkId)continue;
    words[word.id]={
      ...JSON.parse(JSON.stringify(word)),
      _reviewEvents:reviewEventsFor(database.reviews,word.id),
    };
  }
  return words;
}

function databaseFromChunkDocs(
  docs:Array<{id:string;data:Record<string,unknown>}>,
  categories:string[],
):Database{
  const words:Word[]=[];
  const reviews:Database['reviews']=[];

  for(const chunk of docs){
    const rawWords=chunk.data.words;
    if(!rawWords||typeof rawWords!=='object'||Array.isArray(rawWords))continue;

    for(const [id,raw] of Object.entries(rawWords as Record<string,unknown>)){
      if(!raw||typeof raw!=='object'||Array.isArray(raw))continue;
      const data={...(raw as Record<string,unknown>)};
      const events=Array.isArray(data._reviewEvents)
        ?data._reviewEvents.filter((item):item is string=>typeof item==='string')
        :[];
      delete data._reviewEvents;
      words.push({...data,id} as Word);
      for(const event of events){
        const review=decodeReviewEvent(event,id);
        if(review)reviews.push(review);
      }
    }
  }

  words.sort((a,b)=>(b.created??0)-(a.created??0));
  return {
    version:1,
    words,
    reviews,
    categories:[...new Set([
      ...categories,
      ...words.map(word=>(word.category??'').trim()).filter(Boolean),
    ])],
  };
}

async function commitWriteChunks(
  writes:((batch:ReturnType<typeof writeBatch>)=>void)[],
){
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  for(let start=0;start<writes.length;start+=450){
    const batch=writeBatch(firestore);
    for(const write of writes.slice(start,start+450))write(batch);
    await batch.commit();
  }
}

async function ensureGroupMember(uid:string,groupId:string,email:string|null){
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  const key=`${uid}:${groupId}`;
  if(groupMembershipCache.has(key))return;

  const groupRef=doc(firestore,'groups',groupId);
  const existing=await getDoc(groupRef);
  if(existing.exists()){
    if(existing.data().memberUids?.[uid]!==true){
      throw new Error('그룹 소유자에게 멤버 초대를 요청해주세요.');
    }
    groupMembershipCache.add(key);
    return;
  }

  await setDoc(groupRef,{
    name:groupId,
    ownerUid:uid,
    memberUids:{[uid]:true},
    memberEmails:{[uid]:email??''},
    createdAt:serverTimestamp(),
    updatedAt:serverTimestamp(),
  },{merge:true});
  groupMembershipCache.add(key);
}

async function migrateLegacy(
  user:User,
  scope:CloudScope,
  rootRef:DocumentReference,
  rootData:Record<string,unknown>|undefined,
){
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');

  const wordSnap=await getDocs(collection(rootRef,'words'));
  const words:Word[]=[];
  const reviews:Database['reviews']=[];

  for(const item of wordSnap.docs){
    const data={...(item.data() as Record<string,unknown>)};
    if(data.deleted===true)continue;
    const events=Array.isArray(data._reviewEvents)
      ?data._reviewEvents.filter((value):value is string=>typeof value==='string')
      :[];
    delete data._reviewEvents;
    delete data.updatedAt;
    delete data.updatedBy;
    delete data.deleted;
    words.push({...data,id:item.id} as Word);
    for(const event of events){
      const review=decodeReviewEvent(event,item.id);
      if(review)reviews.push(review);
    }
  }

  if(Number(rootData?.reviewStorageVersion)!==REVIEW_STORAGE_VERSION){
    reviews.length=0;
    const legacy=await getDocs(collection(rootRef,'reviews'));
    legacy.docs.forEach((item,index)=>{
      reviews.push({
        ...(item.data() as Review),
        id:`legacy:${item.id}:${index}`,
      });
    });
  }

  const storedCategories=Array.isArray(rootData?.categories)
    ?rootData.categories.filter((x):x is string=>typeof x==='string')
    :[];

  const database:Database={
    version:1,
    words,
    reviews,
    categories:[...new Set([
      ...storedCategories,
      ...words.map(word=>(word.category??'').trim()).filter(Boolean),
    ])],
  };

  const versions=new Map<string,number>();
  const writes:((batch:ReturnType<typeof writeBatch>)=>void)[]=[];

  for(let i=0;i<CHUNK_COUNT;i++){
    const chunkId=String(i).padStart(2,'0');
    const payload=chunkPayload(database,chunkId);
    if(!Object.keys(payload).length)continue;
    versions.set(chunkId,1);
    writes.push(batch=>batch.set(doc(rootRef,'wordChunks',chunkId),{
      version:1,
      words:payload,
      updatedAt:serverTimestamp(),
    }));
  }

  const versionObject=Object.fromEntries(versions);
  writes.push(batch=>batch.set(rootRef,{
    version:1,
    categories:normalizeCategories(database),
    reviewStorageVersion:REVIEW_STORAGE_VERSION,
    storageSchemaVersion:CHUNK_SCHEMA_VERSION,
    chunkCount:CHUNK_COUNT,
    chunkVersions:versionObject,
    updatedAt:serverTimestamp(),
    updatedBy:user.uid,
  },{merge:true}));

  await commitWriteChunks(writes);
  rememberVersions(user.uid,scope,versions);
  return database;
}

export async function loadCloudDatabase(
  user:User,
  scope:CloudScope,
):Promise<Database>{
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  if(scope.type==='group')await ensureGroupMember(user.uid,scope.groupId,user.email);

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);
  const rootSnap=await getDoc(rootRef);
  const rootData=rootSnap.data() as Record<string,unknown>|undefined;

  if(Number(rootData?.storageSchemaVersion)!==CHUNK_SCHEMA_VERSION){
    return migrateLegacy(user,scope,rootRef,rootData);
  }

  const chunkSnap=await getDocs(collection(rootRef,'wordChunks'));
  const docs=chunkSnap.docs.map(item=>({
    id:item.id,
    data:item.data() as Record<string,unknown>,
  }));
  const categories=Array.isArray(rootData?.categories)
    ?rootData.categories.filter((x):x is string=>typeof x==='string')
    :[];

  rememberVersions(
    user.uid,
    scope,
    versionsFromRoot(rootData),
  );
  return databaseFromChunkDocs(docs,categories);
}

export async function loadCloudDatabaseChanges(
  user:User,
  scope:CloudScope,
  base:Database,
):Promise<Database>{
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  if(scope.type==='group')await ensureGroupMember(user.uid,scope.groupId,user.email);

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);
  const rootSnap=await getDoc(rootRef);
  const rootData=rootSnap.data() as Record<string,unknown>|undefined;

  if(Number(rootData?.storageSchemaVersion)!==CHUNK_SCHEMA_VERSION){
    return migrateLegacy(user,scope,rootRef,rootData);
  }

  const key=scopeCacheKey(user.uid,scope);
  const localVersions=chunkVersionCache.get(key)??readStoredVersions(user.uid,scope);
  if(!localVersions.size)return loadCloudDatabase(user,scope);

  const remoteVersions=versionsFromRoot(rootData);
  const changed=[...remoteVersions.entries()]
    .filter(([id,version])=>localVersions.get(id)!==version)
    .map(([id])=>id);

  if(!changed.length){
    rememberVersions(user.uid,scope,remoteVersions);
    return {
      ...base,
      categories:Array.isArray(rootData?.categories)
        ?rootData.categories.filter((x):x is string=>typeof x==='string')
        :base.categories,
    };
  }

  const changedDocs=await Promise.all(
    changed.map(async id=>{
      const snap=await getDoc(doc(rootRef,'wordChunks',id));
      return {id,data:(snap.data()??{}) as Record<string,unknown>};
    }),
  );

  const changedSet=new Set(changed);
  const keptWords=base.words.filter(word=>!changedSet.has(chunkIdForWord(word.id)));
  const keptIds=new Set(keptWords.map(word=>word.id));
  const keptReviews=base.reviews.filter(review=>keptIds.has(review.wordId));
  const categories=Array.isArray(rootData?.categories)
    ?rootData.categories.filter((x):x is string=>typeof x==='string')
    :base.categories;
  const changedDb=databaseFromChunkDocs(changedDocs,categories);

  const merged:Database={
    version:1,
    words:[...changedDb.words,...keptWords].sort((a,b)=>(b.created??0)-(a.created??0)),
    reviews:[...keptReviews,...changedDb.reviews],
    categories:[...new Set([
      ...categories,
      ...keptWords.map(word=>(word.category??'').trim()).filter(Boolean),
      ...changedDb.words.map(word=>(word.category??'').trim()).filter(Boolean),
    ])],
  };

  rememberVersions(user.uid,scope,remoteVersions);
  return merged;
}

function wordMap(database:Database){
  return new Map(database.words.map(word=>[word.id,word]));
}

function reviewsByWord(database:Database){
  const map=new Map<string,Database['reviews']>();
  for(const review of database.reviews){
    const list=map.get(review.wordId)??[];
    list.push(review);
    map.set(review.wordId,list);
  }
  return map;
}

export async function syncCloudDatabase(
  user:User,
  scope:CloudScope,
  previous:Database,
  next:Database,
){
  if(!firestore)throw new Error('Firebase 설정이 필요합니다.');
  if(scope.type==='group')await ensureGroupMember(user.uid,scope.groupId,user.email);

  const [rootCollection,rootId]=rootPath(user.uid,scope);
  const rootRef=doc(firestore,rootCollection,rootId);
  const key=scopeCacheKey(user.uid,scope);
  let versions=chunkVersionCache.get(key);

  if(!versions){
    const rootSnap=await getDoc(rootRef);
    versions=versionsFromRoot(rootSnap.data() as Record<string,unknown>|undefined);
  }

  const beforeWords=wordMap(previous);
  const afterWords=wordMap(next);
  const beforeReviews=reviewsByWord(previous);
  const afterReviews=reviewsByWord(next);
  const ids=new Set([...beforeWords.keys(),...afterWords.keys()]);
  const dirtyChunks=new Set<string>();

  for(const id of ids){
    if(
      JSON.stringify(beforeWords.get(id))!==JSON.stringify(afterWords.get(id)) ||
      JSON.stringify(beforeReviews.get(id)??[])!==JSON.stringify(afterReviews.get(id)??[])
    ){
      dirtyChunks.add(chunkIdForWord(id));
    }
  }

  const metadataDirty=
    JSON.stringify(normalizeCategories(previous))!==JSON.stringify(normalizeCategories(next));

  if(!dirtyChunks.size&&!metadataDirty)return;

  const nextVersions=new Map(versions);
  const writes:((batch:ReturnType<typeof writeBatch>)=>void)[]=[];

  for(const chunkId of dirtyChunks){
    const version=(nextVersions.get(chunkId)??0)+1;
    nextVersions.set(chunkId,version);
    writes.push(batch=>batch.set(doc(rootRef,'wordChunks',chunkId),{
      version,
      words:chunkPayload(next,chunkId),
      updatedAt:serverTimestamp(),
    }));
  }

  writes.push(batch=>batch.set(rootRef,{
    version:1,
    categories:normalizeCategories(next),
    reviewStorageVersion:REVIEW_STORAGE_VERSION,
    storageSchemaVersion:CHUNK_SCHEMA_VERSION,
    chunkCount:CHUNK_COUNT,
    chunkVersions:Object.fromEntries(nextVersions),
    updatedAt:serverTimestamp(),
    updatedBy:user.uid,
  },{merge:true}));

  await commitWriteChunks(writes);
  rememberVersions(user.uid,scope,nextVersions);
}

export async function saveCloudDatabase(
  user:User,
  scope:CloudScope,
  database:Database,
){
  const previous=await loadCloudDatabase(user,scope);
  await syncCloudDatabase(user,scope,previous,database);
}
